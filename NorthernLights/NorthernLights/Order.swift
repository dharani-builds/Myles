import Foundation

/// Which Swiggy vertical the order belongs to. Drives badge color + progress hue.
enum OrderPlatform: Equatable {
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
    /// Context line — restaurant/store name + primary item, joined with " • ".
    /// e.g. "Truffles • Grilled Fish in Lemon Butter Sauce"
    let context: String
    /// Human-friendly status headline. e.g. "Order Received", "Out for delivery"
    let status: String
    /// ETA in minutes. Nil if the order has no meaningful ETA.
    let eta: Int?
    /// Progress percentage, matches the 6 discrete Figma variants.
    let progress: ProgressStage
}

/// The six discrete progress stages from the Figma progress bar component.
enum ProgressStage: Int, CaseIterable {
    case placed      = 10
    case preparing   = 25
    case packed      = 50
    case inTransit   = 75
    case nearby      = 95
    case delivered   = 100

    var fraction: Double { Double(rawValue) / 100.0 }
}
