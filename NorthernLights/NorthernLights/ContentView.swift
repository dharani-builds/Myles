//
//  ContentView.swift
//  NorthernLights
//
//  Created by Dharanitharan R on 08/07/26.
//

import SwiftUI

/// The popover content shown when the user clicks the menu bar icon.
///
/// TEMPORARY: uses hardcoded sample orders. The real data layer (OAuth +
/// Swiggy MCP calls + polling) will feed this view once we wire it up.
struct ContentView: View {
    var body: some View {
        OrderCardView(orders: sampleOrders)
    }
}

// MARK: - Sample data (remove once real data is wired)

private let sampleOrders: [Order] = [
    // Short status, short-ish context
    Order(
        id: "sample-1",
        platform: .food,
        context: "Truffles • Grilled Fish in Lemon Butter Sauce",
        status: "Out for delivery",
        eta: 10,
        progress: .inTransit
    ),
    // Short status, long context (should truncate with ellipsis)
    Order(
        id: "sample-2",
        platform: .instamart,
        context: "Modern 100% Whole Wheat Bread • Yogabar Dark Chocolate Oats • Robusta Bananas",
        status: "Order Packed",
        eta: 5,
        progress: .packed
    ),
    // LONG status (should wrap to 2 lines)
    Order(
        id: "sample-3",
        platform: .food,
        context: "Theobroma • Chicken Tikka Sandwich",
        status: "Delivery partner is at the restaurant",
        eta: 15,
        progress: .preparing
    ),
    // LONG status (should wrap to 2 lines) + short ETA
    Order(
        id: "sample-4",
        platform: .instamart,
        context: "Khadi Natural Coconut Milk & Honey Soap",
        status: "Your delivery partner is 2 minutes away",
        eta: 2,
        progress: .nearby
    )
]

#Preview {
    ContentView()
}
