import Foundation

/// The timer that keeps `OrdersState` fresh.
///
/// Runs a loop while active:
///   1. Ask `MCPClient` for the latest orders
///   2. Update `OrdersState` with the result (or error)
///   3. Sleep for `interval` seconds
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

    /// Time between polls, in seconds. 30s is a decent starting point:
    /// live enough to feel current, gentle enough to not spam Swiggy.
    /// If Swiggy ever rate-limits us, this is the first knob to turn.
    private let interval: Duration = .seconds(30)

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

    /// Begin polling. Immediately fires one fetch, then sleeps `interval` and
    /// repeats. Safe to call multiple times — any existing loop is cancelled
    /// before a new one starts.
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
            await pollOnce()

            // Cancellable sleep — if stop() is called during the wait, we
            // break out immediately instead of blocking for the full interval.
            do {
                try await Task.sleep(for: interval)
            } catch {
                break  // task cancelled
            }
        }
    }

    private func pollOnce() async {
        do {
            let orders = try await client.fetchActiveOrders()
            state.setLoaded(orders)
        } catch MCPError.unauthorized {
            // Token is dead and we have no refresh path — send the user
            // back to sign in. Stop the loop so we don't keep hammering.
            onUnauthorized()
            stop()
        } catch {
            state.setError(error.localizedDescription)
        }
    }
}
