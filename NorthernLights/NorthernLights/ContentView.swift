//
//  ContentView.swift
//  NorthernLights
//
//  Created by Dharanitharan R on 08/07/26.
//

import SwiftUI

/// Root view for the menu bar popover. Branches on auth state.
///
/// TEMPORARY note: the `.authenticated` case still uses hardcoded sample
/// orders. Next step is the data layer — polling Swiggy MCP endpoints
/// with the token we just acquired via `SwiggyOAuth`.
struct ContentView: View {
    @Environment(AuthState.self) private var authState

    var body: some View {
        switch authState.status {
        case .idle:
            ConnectView()
        case .authorizing:
            LoadingView()
        case .authenticated:
            OrderCardView(orders: sampleOrders)
        case .error(let message):
            ErrorView(message: message)
        }
    }
}

// MARK: - Connect (not signed in)
//
// Functional-but-not-designed placeholder. Uses the design tokens so it feels
// on-brand, but the exact layout will be re-done in the Phase 4 polish pass.

private struct ConnectView: View {
    @Environment(AuthState.self) private var authState

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Connect Swiggy")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text("Sign in to see your active orders here")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await authState.signIn() }
            } label: {
                Text("Sign in with Swiggy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.swiggy500)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(width: 350)
        .background(Color.surfaceBackground)
    }
}

// MARK: - Loading (auth in progress)

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Waiting for Swiggy sign-in…")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(32)
        .frame(width: 350)
        .background(Color.surfaceBackground)
    }
}

// MARK: - Error (last attempt failed)

private struct ErrorView: View {
    let message: String
    @Environment(AuthState.self) private var authState

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Sign-in failed")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await authState.signIn() }
            } label: {
                Text("Try again")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.swiggy500)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(width: 350)
        .background(Color.surfaceBackground)
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
        .environment(AuthState())
}
