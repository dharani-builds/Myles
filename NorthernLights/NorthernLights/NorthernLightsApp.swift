//
//  NorthernLightsApp.swift
//  NorthernLights
//
//  Created by Dharanitharan R on 08/07/26.
//

import SwiftUI

@main
struct NorthernLightsApp: App {

    // MARK: - Fixtures escape hatch
    //
    // Flip to `true` to show canned orders from `Fixtures.swift` in the running
    // app, skipping the network entirely. Handy for design/UI iteration —
    // saves you from having to keep an order in flight on Swiggy just to see
    // the loaded state. Flip back to `false` for real use.
    private static let USE_FIXTURES = false

    // MARK: - Shared state

    @State private var authState: AuthState
    @State private var ordersState: OrdersState
    @State private var ordersPoller: OrdersPoller

    // MARK: - Init
    //
    // Assembles the object graph: AuthState, OrdersState, MCPClient, OrdersPoller.
    // The poller holds references to the client and state; the `onUnauthorized`
    // closure captures AuthState so a dead token bounces the user cleanly back
    // to the sign-in screen.

    @MainActor
    init() {
        let auth = AuthState()

        let orders: OrdersState = Self.USE_FIXTURES
            ? OrdersState(initial: .loaded(Fixtures.mixedOrders))
            : OrdersState(initial: .loading)

        let client = MCPClient()
        let poller = OrdersPoller(
            client: client,
            state: orders,
            onUnauthorized: { auth.signOut() }
        )

        _authState = State(initialValue: auth)
        _ordersState = State(initialValue: orders)
        _ordersPoller = State(initialValue: poller)
    }

    // MARK: - Scene

    var body: some Scene {
        MenuBarExtra("Northern Lights", systemImage: "bag.fill") {
            ContentView()
                .environment(authState)
                .environment(ordersState)
                // React to auth transitions:
                //   • sign in  → start polling
                //   • sign out → stop polling (and OrdersState will reset next start)
                // `initial: true` fires on launch too, so a user who's already
                // authenticated from a prior session starts polling immediately.
                .onChange(of: authState.status, initial: true) { _, newValue in
                    guard !Self.USE_FIXTURES else { return }
                    if newValue == .authenticated {
                        ordersPoller.start()
                    } else {
                        ordersPoller.stop()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
