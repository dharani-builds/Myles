//
//  ContentView.swift
//  NorthernLights
//
//  Created by Dharanitharan R on 08/07/26.
//

import SwiftUI

/// Root view for the menu bar popover.
///
/// Two-level branching:
///   1. `AuthState` — is the user signed in?
///   2. `OrdersState` — if signed in, what's the order fetch showing?
///
/// Each branch is a tiny view below, so we can iterate on any single state
/// (empty, loading, one order, many orders, error) from Xcode Previews
/// without needing a live Swiggy feed.
struct ContentView: View {
    @Environment(AuthState.self) private var authState
    @Environment(OrdersState.self) private var ordersState

    var body: some View {
        switch authState.status {
        case .idle:
            ConnectView()
        case .authorizing:
            AuthLoadingView()
        case .authenticated:
            ordersScreen
        case .error(let message):
            AuthErrorView(message: message)
        }
    }

    /// Which orders-screen to show, once we know the user is signed in.
    @ViewBuilder
    private var ordersScreen: some View {
        switch ordersState.status {
        case .loading:
            OrdersLoadingView()
        case .empty:
            EmptyOrdersView()
        case .loaded(let orders):
            OrderCardView(orders: orders)
        case .error(let message):
            OrdersErrorView(message: message)
        }
    }
}

// MARK: - Connect (not signed in)

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

// MARK: - Auth loading / auth error

private struct AuthLoadingView: View {
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

private struct AuthErrorView: View {
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

// MARK: - Orders: loading / empty / error
//
// Functional placeholders. Layout + copy will be re-designed in the Phase 4
// polish pass — right now the goal is just to have every state renderable
// with fixtures so nothing breaks the layout during dev.

private struct OrdersLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Checking for orders…")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(32)
        .frame(width: 350)
        .background(Color.surfaceBackground)
    }
}

private struct EmptyOrdersView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("No active orders")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Text("You'll see live updates here when you place an order on Swiggy.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 350)
        .background(Color.surfaceBackground)
    }
}

private struct OrdersErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text("Couldn't fetch orders")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 350)
        .background(Color.surfaceBackground)
    }
}

// MARK: - Previews (one per state, all fixture-driven)

#Preview("Auth · signed out") {
    ContentView()
        .environment(AuthState())
        .environment(OrdersState())
}

#Preview("Orders · loading") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState(initial: .loading))
}

#Preview("Orders · empty") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState(initial: .empty))
}

#Preview("Orders · one order") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState(initial: .loaded(Fixtures.singleOrder)))
}

#Preview("Orders · many orders") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState(initial: .loaded(Fixtures.mixedOrders)))
}

#Preview("Orders · error") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState(initial: .error("Swiggy is taking longer than usual to respond.")))
}
