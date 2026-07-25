import Foundation

/// Canned `Order` data for building and reviewing UI without a live Swiggy feed.
///
/// **These are permanent.** They stay in the project even after real data is
/// wired up, because SwiftUI Previews (and the occasional "let me see the
/// error screen") need instant, reliable inputs. Real-order testing happens
/// separately — see the roadmap Phase 5.
///
/// Every fixture is grounded in the actual captured MCP responses in
/// `data/food-observation-*.jsonl` and `data/instamart-observation-*.jsonl`.
/// If Swiggy's response shape changes, refresh from those captures, not from
/// imagination.
enum Fixtures {

    // MARK: - Individual orders

    /// Food order in transit, short status line.
    static let foodInTransit = Order(
        id: "fixture-food-transit",
        platform: .food,
        context: "Truffles • Grilled Fish in Lemon Butter Sauce",
        status: "Out for delivery",
        eta: 10,
        progress: ProgressStage.inTransit.fraction
    )

    /// Instamart order packed, long context that should truncate.
    static let instamartLongContext = Order(
        id: "fixture-instamart-long",
        platform: .instamart,
        context: "Modern 100% Whole Wheat Bread • Yogabar Dark Chocolate Oats • Robusta Bananas",
        status: "Order Packed",
        eta: 5,
        progress: ProgressStage.packed.fraction
    )

    /// Food order with a long status line that should wrap to two lines.
    static let foodLongStatus = Order(
        id: "fixture-food-long-status",
        platform: .food,
        context: "Theobroma • Chicken Tikka Sandwich",
        status: "Delivery partner is at the restaurant",
        eta: 15,
        progress: ProgressStage.preparing.fraction
    )

    /// Instamart nearby, close ETA, real status copy from the captures.
    static let instamartNearby = Order(
        id: "fixture-instamart-nearby",
        platform: .instamart,
        context: "Khadi Natural Coconut Milk & Honey Soap",
        status: "Your delivery partner is 2 minutes away",
        eta: 2,
        progress: ProgressStage.nearby.fraction
    )

    // MARK: - Named states (drop-in for OrdersState during dev + previews)

    /// Four orders across both platforms, exercising short/long status + context.
    static let mixedOrders: [Order] = [
        foodInTransit,
        instamartLongContext,
        foodLongStatus,
        instamartNearby
    ]

    /// A single order — the common everyday case.
    static let singleOrder: [Order] = [foodInTransit]
}
