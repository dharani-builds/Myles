//
//  MylesApp.swift
//  Myles
//
//  Created by Dharanitharan R on 08/07/26.
//

import SwiftUI
import AppKit

@main
struct MylesApp: App {

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
            // On 401, mark the session as expired (drops to .idle with a
            // "session expired" preamble in LoginView) rather than a silent
            // sign-out. Gives the user context about why they're looking at
            // the login screen.
            onUnauthorized: { auth.markSessionExpired() }
        )

        _authState = State(initialValue: auth)
        _ordersState = State(initialValue: orders)
        _ordersPoller = State(initialValue: poller)
    }

    // MARK: - Scene

    var body: some Scene {
        // "MenuBarIcon" is a template image (Assets.xcassets), so macOS
        // recolors it automatically for light/dark menu bars.
        MenuBarExtra("Myles", image: "MenuBarIcon") {
            ContentView()
                .environment(authState)
                .environment(ordersState)
                .environment(ordersPoller)
                // React to auth transitions:
                //   • sign in  → start polling
                //   • sign out → stop polling
                // `initial: true` also fires on launch, so an already-signed-in
                // user starts polling immediately.
                .onChange(of: authState.status, initial: true) { _, newValue in
                    guard !Self.USE_FIXTURES else { return }
                    if newValue == .authenticated {
                        // Only start on the true "just became authenticated"
                        // transition — NOT on every popover open. MenuBarExtra
                        // re-mounts ContentView each time the popover shows,
                        // which re-fires this handler with `initial: true`.
                        // Without this guard, we'd call start() (which resets
                        // state to .loading) on every open → visible flicker.
                        if !ordersPoller.isRunning {
                            ordersPoller.start()
                        }
                    } else {
                        ordersPoller.stop()
                    }
                }
                // Popover-opened trigger: when the user clicks the menu bar
                // icon, the app becomes active. If our last poll is stale
                // (>15s old), fire a fresh one immediately so what they see
                // reflects reality, not the last idle-backoff snapshot.
                //
                // We use `didBecomeActiveNotification` because MenuBarExtra
                // doesn't expose a first-class "popover opened" event, and
                // `.onAppear` on the content view doesn't reliably fire on
                // every open with the `.window` style. For a menu-bar-only
                // app (accessory activation policy), this notification only
                // fires on popover open — nothing else brings the app to
                // the foreground.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    guard !Self.USE_FIXTURES else { return }
                    ordersPoller.refreshNowIfStale()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
