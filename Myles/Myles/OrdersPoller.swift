import Foundation

/// The timer that keeps `OrdersState` fresh.
///
/// Runs a loop while active:
///   1. Ask `MCPClient` for the latest orders
///   2. Update `OrdersState` with the result (or error)
///   3. Sleep for the interval decided by the ladder / Swiggy suggestion
///   4. Repeat until `stop()` is called
///
/// The poller does NOT decide when it should be running — that's the caller's
/// job. `MylesApp` watches `AuthState` and calls `start()` / `stop()`
/// on auth transitions, and calls `refreshNowIfStale()` when the popover opens.
///
/// **Polling ladder (empty state):**
///   • Fresh empty (first 10 min)  → 60s
///   • Empty 10–30 min             → 2 min
///   • Empty 30+ min               → 5 min
///
/// **Active order:** whatever Swiggy suggests via `pollIntervalSec`, clamped
/// to `[10s, 300s]`. Falls back to 30s for Instamart-only (no suggestion).
///
/// **On a 401 (dead token):** call `onUnauthorized`, stop the loop.
@MainActor
@Observable
final class OrdersPoller {

    // MARK: - Public observable state (read by the footer view)

    /// Absolute Date when the next scheduled poll will fire.
    /// Nil before the first poll starts or after `stop()`.
    private(set) var nextPollAt: Date?

    /// True while a poll request is in flight (network call running).
    private(set) var isPolling: Bool = false

    /// True after at least one poll has completed. Used to pick copy:
    /// "Checking…" before first completion vs. "Updating…" after.
    private(set) var hasEverPolled: Bool = false

    /// Seconds of the current sleep. Used by the footer to decide whether to
    /// show the minutes-format copy at all (only when > 60).
    private(set) var currentIntervalSeconds: TimeInterval = 60

    // MARK: - Configuration

    /// Guardrails around any interval we schedule.
    private let minInterval: TimeInterval = 10
    private let maxInterval: TimeInterval = 300

    /// Empty-state ladder — how long to wait between polls when nothing is active.
    private let emptyFast: TimeInterval = 60      // 60s → row 1
    private let emptyMid:  TimeInterval = 120     // 2 min → row 2
    private let emptySlow: TimeInterval = 300     // 5 min → row 3

    /// How long we have to be empty before stepping down the ladder.
    private let ladderStepMid:  TimeInterval = 600    // 10 min → row 2 kicks in
    private let ladderStepSlow: TimeInterval = 1800   // 30 min → row 3 kicks in

    /// Active-order fallback when Swiggy doesn't suggest an interval
    /// (typical for Instamart-only). Faster than empty since orders move.
    private let activeOrderFallback: TimeInterval = 30

    /// User opening the popover triggers a fresh poll, but only if the last
    /// completed poll was more than this long ago. Prevents rapid open/close
    /// from spamming Swiggy.
    private let openTriggerMinAge: TimeInterval = 15

    // MARK: - Dependencies

    private let client: MCPClient
    private let state: OrdersState
    private let onUnauthorized: @MainActor () -> Void

    // MARK: - Loop internals

    private var loopTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?

    /// When did the current empty-state stretch begin? Used to pick the ladder
    /// row. Set on empty→loaded→empty transitions, cleared while loaded.
    private var emptyStateStartedAt: Date?

    /// Timestamp of the most recent poll completion (success or error).
    /// Used by `refreshNowIfStale()` to skip pointless double-polls.
    private var lastPollCompletedAt: Date?

    var isRunning: Bool { loopTask != nil }

    // MARK: - Init

    init(
        client: MCPClient,
        state: OrdersState,
        onUnauthorized: @escaping @MainActor () -> Void
    ) {
        self.client = client
        self.state = state
        self.onUnauthorized = onUnauthorized
    }

    // MARK: - Public API

    /// Begin polling. Fires an immediate first poll, then follows the ladder.
    /// Safe to call multiple times — any existing loop is cancelled first.
    func start() {
        stop()
        state.setLoading()
        hasEverPolled = false
        emptyStateStartedAt = nil
        lastPollCompletedAt = nil
        loopTask = Task { [weak self] in await self?.loop() }
    }

    /// Stop polling. Idempotent.
    func stop() {
        loopTask?.cancel()
        loopTask = nil
        sleepTask?.cancel()
        sleepTask = nil
        nextPollAt = nil
        isPolling = false
    }

    /// Called when the user opens the popover. Cuts short the current sleep
    /// to fire an immediate poll — UNLESS the last poll completed less than
    /// `openTriggerMinAge` seconds ago (no point re-polling immediately).
    func refreshNowIfStale() {
        guard loopTask != nil else { return }
        if let last = lastPollCompletedAt,
           Date().timeIntervalSince(last) < openTriggerMinAge {
            return
        }
        // Kick the sleep. The loop's `_ = await sleep.value` returns, the
        // outer `while !Task.isCancelled` continues, pollOnce fires.
        sleepTask?.cancel()
    }

    // MARK: - The loop

    private func loop() async {
        while !Task.isCancelled {
            let suggested = await pollOnce()
            let nextDelay = decideNextInterval(suggested: suggested)

            currentIntervalSeconds = nextDelay
            nextPollAt = Date().addingTimeInterval(nextDelay)

            let sleep = Task<Void, Never> {
                do {
                    try await Task.sleep(for: .seconds(nextDelay))
                } catch {
                    // sleep cancelled → just return so the loop iterates
                }
            }
            sleepTask = sleep
            _ = await sleep.value
            sleepTask = nil
        }
    }

    /// One iteration. Returns Swiggy's suggested `pollIntervalSec` if we got
    /// one from `get_food_delivery_status` (only present when a Food order is
    /// active). Also updates `OrdersState` and internal empty-state tracking.
    private func pollOnce() async -> TimeInterval? {
        isPolling = true
        defer { isPolling = false }

        do {
            let result = try await client.fetchActiveOrders()
            state.setLoaded(result.orders)
            hasEverPolled = true
            lastPollCompletedAt = Date()

            // Empty-state stopwatch: start it when we first observe empty
            // AFTER having had orders (or on first poll). Clear it while loaded.
            if result.orders.isEmpty {
                if emptyStateStartedAt == nil {
                    emptyStateStartedAt = Date()
                }
            } else {
                emptyStateStartedAt = nil
            }

            return result.suggestedPollInterval
        } catch MCPError.unauthorized {
            onUnauthorized()
            stop()
            return nil
        } catch {
            state.setError(error.localizedDescription)
            hasEverPolled = true
            lastPollCompletedAt = Date()
            return nil
        }
    }

    /// Decide next sleep duration.
    private func decideNextInterval(suggested: TimeInterval?) -> TimeInterval {
        // Active order — use Swiggy's suggestion, or fallback for Instamart-only.
        if case .loaded = state.status {
            let base = suggested ?? activeOrderFallback
            return clamped(base)
        }

        // Empty state (or error while never-loaded) — walk the ladder.
        guard let startedAt = emptyStateStartedAt else {
            return emptyFast
        }
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed >= ladderStepSlow {
            return emptySlow
        } else if elapsed >= ladderStepMid {
            return emptyMid
        } else {
            return emptyFast
        }
    }

    private func clamped(_ interval: TimeInterval) -> TimeInterval {
        max(minInterval, min(maxInterval, interval))
    }

    // MARK: - Preview helpers
    //
    // Xcode Previews inject a poller that isn't actually running but has
    // plausible timing state, so the footer renders realistic "Next update
    // in Xs" copy in the canvas.

    /// An idle, non-running instance seeded with plausible timing state.
    /// Do not use in the app.
    static func previewIdle(intervalSeconds: TimeInterval = 60) -> OrdersPoller {
        let p = OrdersPoller(
            client: MCPClient(),
            state: OrdersState(),
            onUnauthorized: {}
        )
        p.currentIntervalSeconds = intervalSeconds
        p.nextPollAt = Date().addingTimeInterval(max(1, intervalSeconds - 15))
        p.hasEverPolled = true
        return p
    }
}
