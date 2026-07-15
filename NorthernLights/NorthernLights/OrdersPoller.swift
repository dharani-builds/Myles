import Foundation

/// The timer that keeps `OrdersState` fresh.
///
/// Runs a loop while active:
///   1. Ask `MCPClient` for the latest orders
///   2. Update `OrdersState` with the result (or error)
///   3. Sleep for `interval` seconds (or Swiggy's suggested cadence)
///   4. Repeat until `stop()` is called
///
/// The poller does NOT decide when it should be running — that's the caller's
/// job. `NorthernLightsApp` watches `AuthState` and calls `start()` / `stop()`
/// on auth transitions.
///
/// **On a 401 (dead token):** the poller calls the `onUnauthorized` handler
/// once and stops. The handler is expected to log the user out, which will
/// bounce the UI back to the sign-in screen — no further polls, no error
/// screen. See the project memory: Swiggy doesn't currently issue refresh
/// tokens, so silent token refresh isn't an option yet.
@MainActor
final class OrdersPoller {

    // MARK: - Configuration

    /// Fallback interval when Swiggy doesn't give us a `pollIntervalSec`
    /// (e.g. Instamart-only, or no active orders at all). 30s is a decent
    /// baseline: live enough to feel current, gentle enough to not spam.
    private let defaultInterval: Duration = .seconds(30)

    /// Guardrails around whatever Swiggy suggests. Values under 10s risk
    /// rate-limits; values over 5min make the app feel stale.
    private let minInterval: TimeInterval = 10
    private let maxInterval: TimeInterval = 300

    // MARK: - Dependencies

    private let client: MCPClient
    private let state: OrdersState
    /// Called if a poll fails with a 401. Expected to sign the user out.
    private let onUnauthorized: @MainActor () -> Void

    // MARK: - Loop state

    private var task: Task<Void, Never>?
    var isRunning: Bool { task != nil }

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

    /// Begin polling. Immediately fires one fetch, then sleeps and repeats.
    /// Safe to call multiple times — any existing loop is cancelled before a
    /// new one starts.
    func start() {
        stop()
        state.setLoading()
        task = Task { [weak self] in
            await self?.loop()
        }
    }

    /// Stop polling. Idempotent — safe to call when already stopped.
    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - The loop

    private func loop() async {
        while !Task.isCancelled {
            let nextDelay = await pollOnce()

            // Cancellable sleep — if stop() is called during the wait, we
            // break out immediately instead of blocking for the full interval.
            do {
                try await Task.sleep(for: nextDelay)
            } catch {
                break  // task cancelled
            }
        }
    }

    /// One iteration. Returns how long to sleep before the next iteration.
    private func pollOnce() async -> Duration {
        do {
            let result = try await client.fetchActiveOrders()
            state.setLoaded(result.orders)
            return clampedInterval(result.suggestedPollInterval)
        } catch MCPError.unauthorized {
            // Token is dead and we have no refresh path — send the user
            // back to sign in. Stop the loop so we don't keep hammering.
            onUnauthorized()
            stop()
            return defaultInterval  // unreachable — loop is cancelled
        } catch {
            state.setError(error.localizedDescription)
            return defaultInterval
        }
    }

    /// Clamp Swiggy's suggested interval to `[minInterval, maxInterval]`, or
    /// fall back to the default if there wasn't a suggestion.
    private func clampedInterval(_ suggested: TimeInterval?) -> Duration {
        guard let suggested else { return defaultInterval }
        let clamped = max(minInterval, min(maxInterval, suggested))
        return .seconds(clamped)
    }
}
