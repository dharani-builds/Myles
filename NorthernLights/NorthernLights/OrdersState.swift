import Foundation

/// The single source of truth for what the orders popover should show.
///
/// Views read `status` to decide which screen to render. `OrdersPoller` writes
/// to `status` via `setLoaded` / `setError` / `setLoading` — no one else does.
///
/// Mental model: same pattern as `AuthState`, just for orders.
///   • AuthState answers "is the user signed in?"
///   • OrdersState answers "what do we know about active orders right now?"
///
/// **Error handling policy (matches Figma):**
///   • First-ever poll fails (from `.loading`) → immediate `.error`
///   • Poll fails while we have data (`.loaded` or `.empty`) → SILENT stale for
///     the first N-1 failures, then escalate to `.error` on the Nth. Prevents
///     a single flaky poll from wiping the screen.
///   • The view layer distinguishes "was showing an order → 'Something went
///     wrong'" from "wasn't → 'Couldn't fetch orders'" via `hadOrdersAtErrorStart`.
///   • Any successful poll resets the failure counter and clears the flag.
@MainActor
@Observable
final class OrdersState {

    enum Status: Equatable {
        /// First-ever load in progress — no data yet.
        /// (After we have data once, we keep showing it during refreshes
        /// instead of flashing back to loading. Prevents flicker.)
        case loading
        /// Fetch succeeded, but the user has no active orders right now.
        case empty
        /// One or more active orders, freshest data we have.
        case loaded([Order])
        /// Last fetch failed hard enough that we've given up showing stale data.
        case error(String)
    }

    private(set) var status: Status

    /// Timestamp of the most recent successful fetch. `nil` until first success.
    private(set) var lastUpdated: Date?

    /// When we escalate to `.error`, this tells the view which copy to render:
    ///   • `true`  → mid-order error ("Something went wrong" + Twitter link)
    ///   • `false` → cold error ("Couldn't fetch orders" + Twitter link)
    /// Read-only for views; internally maintained by `setError` / `setLoaded`.
    private(set) var hadOrdersAtErrorStart: Bool = false

    // MARK: - Escalation config

    /// Consecutive failures required before we swap the visible state to `.error`.
    /// Chosen so a single blip doesn't wipe the screen. 3 × ~45s ≈ 2.25 min of
    /// no response before we escalate. Tune with the design if it feels off.
    private let errorEscalationThreshold: Int = 3

    /// Failure counter. Reset on any successful poll.
    private var consecutiveErrorCount: Int = 0

    // MARK: - Init

    init(initial: Status = .loading) {
        self.status = initial
    }

    // MARK: - Mutation (called by the poller, or by fixtures during dev)

    func setLoaded(_ orders: [Order]) {
        status = orders.isEmpty ? .empty : .loaded(orders)
        lastUpdated = Date()
        consecutiveErrorCount = 0
        hadOrdersAtErrorStart = false
    }

    func setError(_ message: String) {
        // First-poll failure (from .loading) — no threshold, show error now.
        // "hadOrdersAtErrorStart = false" since we never had orders to lose.
        if case .loading = status {
            consecutiveErrorCount = 1
            hadOrdersAtErrorStart = false
            status = .error(message)
            return
        }

        consecutiveErrorCount += 1

        // On the FIRST error of a run, snapshot whether we were mid-order.
        // Later errors in the same run keep this flag as-is.
        if consecutiveErrorCount == 1 {
            hadOrdersAtErrorStart = isCurrentlyLoaded
        }

        // Threshold: silent stale for the first N-1 failures, keeping the last
        // successful state visible. Escalate to `.error` on the Nth.
        guard consecutiveErrorCount >= errorEscalationThreshold else {
            return
        }

        status = .error(message)
    }

    func setLoading() {
        status = .loading
        consecutiveErrorCount = 0
        hadOrdersAtErrorStart = false
    }

    // MARK: - Helpers

    private var isCurrentlyLoaded: Bool {
        if case .loaded = status { return true }
        return false
    }

    // MARK: - Preview helpers
    //
    // Xcode Previews can't run the poller, so we expose factories that
    // pre-seed the state exactly. Do not use in the app.

    /// A preview instance already in the `.error` state, with the mid-order
    /// flag set as requested. Lets Previews render both error variants.
    static func previewError(_ message: String = "Preview error", midOrder: Bool) -> OrdersState {
        let s = OrdersState(initial: .error(message))
        s.hadOrdersAtErrorStart = midOrder
        return s
    }
}
