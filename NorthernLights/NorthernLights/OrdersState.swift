import Foundation

/// The single source of truth for what the orders popover should show.
///
/// Views read `status` to decide which screen to render. The poller (added in
/// a later step) writes to `status`. Until then, `NorthernLightsApp` seeds it
/// with fixture data so the UI can be built and reviewed without any network.
///
/// Mental model: this is the same pattern as `AuthState`, just for orders.
///   • AuthState answers "is the user signed in?"
///   • OrdersState answers "what do we know about active orders right now?"
@MainActor
@Observable
final class OrdersState {

    /// The four screens the popover can show, in the order they matter for the UI.
    enum Status: Equatable {
        /// First-ever load in progress — no data yet.
        /// (After we have data once, we keep showing it during refreshes
        /// instead of flashing back to loading. Prevents flicker.)
        case loading
        /// Fetch succeeded, but the user has no active orders right now.
        case empty
        /// One or more active orders, freshest data we have.
        case loaded([Order])
        /// Last fetch failed. Message is user-facing; keep it short.
        case error(String)
    }

    private(set) var status: Status

    /// Timestamp of the most recent successful fetch. `nil` until first success.
    /// Useful later for showing "updated 12s ago" copy, and for deciding whether
    /// to keep showing stale data vs. flip to `.error`.
    private(set) var lastUpdated: Date?

    init(initial: Status = .loading) {
        self.status = initial
    }

    // MARK: - Mutation (called by the poller, or by fixtures during dev)

    func setLoaded(_ orders: [Order]) {
        status = orders.isEmpty ? .empty : .loaded(orders)
        lastUpdated = Date()
    }

    func setError(_ message: String) {
        // If we already have data, keep showing it — don't wipe the screen on
        // a single flaky poll. The poller can decide when to escalate to an
        // actual error screen (e.g. after N consecutive failures).
        if case .loaded = status { return }
        if case .empty = status { return }
        status = .error(message)
    }

    func setLoading() {
        status = .loading
    }
}
