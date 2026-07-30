import Foundation

/// Which Swiggy vertical the order belongs to. Drives badge color + progress hue.
enum OrderPlatform: Equatable, Hashable, CaseIterable {
    case food
    case instamart
}

/// A single active order shown in the menu bar popover.
///
/// This is intentionally the smallest shape the UI cares about — restaurant
/// name, one line of status copy, an ETA, and a progress percentage. The
/// mapping from Swiggy's MCP response (`orderStatus`, `currentStatus`, etc.)
/// to this shape happens in the data layer, not here.
struct Order: Identifiable, Equatable {
    let id: String
    let platform: OrderPlatform
    /// What was ordered — store/restaurant name + items, joined with " • ".
    /// e.g. "Truffles • Grilled Fish in Lemon Butter Sauce". This identifies
    /// the order; it never changes over the order's life.
    let context: String
    /// Human-friendly status headline. e.g. "Order Received", "Out for delivery"
    let status: String
    /// Delivery-partner detail from Swiggy, when there is one — e.g.
    /// "SIDDANNA GOWDA has reached your location". Instamart only today
    /// (`track_order`'s `subStatusMessage`); Food's MCP exposes no partner
    /// info at all, so it's always nil there.
    let partnerDetail: String?
    /// True once the order has left the store and is en route to the user.
    /// Views use this to decide whether `context` or `partnerDetail` is the
    /// more useful thing to surface in the row's secondary line.
    let isEnRoute: Bool
    /// ETA in minutes. Nil if the order has no meaningful ETA.
    let eta: Int?
    /// Progress fraction, 0.0 – 1.0, interpolated from remaining ETA on both
    /// platforms. The bar is spring-animated so any change slides smoothly.
    let progress: Double

    init(
        id: String,
        platform: OrderPlatform,
        context: String,
        status: String,
        partnerDetail: String? = nil,
        isEnRoute: Bool = false,
        eta: Int?,
        progress: Double
    ) {
        self.id = id
        self.platform = platform
        self.context = context
        self.status = status
        self.partnerDetail = partnerDetail
        self.isEnRoute = isEnRoute
        self.eta = eta
        self.progress = progress
    }
}

/// Milestone anchors kept as an enum for referenceability in code + fixtures.
/// Nothing forces the runtime progress to snap to these — Food interpolates
/// between them based on ETA. Ordered lowest → highest, values are percentages.
enum ProgressStage: Int, CaseIterable {
    case placed      = 10
    case preparing   = 25
    case packed      = 50
    case inTransit   = 75
    case nearby      = 95
    case delivered   = 100

    var fraction: Double { Double(rawValue) / 100.0 }
}
