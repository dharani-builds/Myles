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

    // MARK: - Secondary-line comparison
    //
    // Both taken verbatim from the live 2026-07-27 Instamart capture, so the
    // layout comparison uses real string lengths rather than invented ones.

    /// Before the order leaves the store — no partner attached yet, so there's
    /// nothing to swap in and both treatments should look identical.
    static let instamartBeforeDispatch = Order(
        id: "fixture-im-pre-dispatch",
        platform: .instamart,
        context: "Instamart • NOICE Chocolate Nougat Barks, Minimalist Vitamin B5 10% Oil Free Moisturizer",
        status: "Order Confirmed!",
        partnerDetail: nil,
        isEnRoute: false,
        eta: 8,
        progress: 0.35
    )

    /// En route with a partner detail — this is the case the two treatments
    /// actually differ on.
    static let instamartEnRoute = Order(
        id: "fixture-im-en-route",
        platform: .instamart,
        context: "Instamart • NOICE Chocolate Nougat Barks, Minimalist Vitamin B5 10% Oil Free Moisturizer",
        status: "Arrived at location",
        partnerDetail: "SIDDANNA GOWDA has reached your location",
        isEnRoute: true,
        eta: 1,
        progress: 0.95
    )

    /// Both stages together, so one preview shows the before/after transition.
    static let instamartStages: [Order] = [instamartBeforeDispatch, instamartEnRoute]

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
