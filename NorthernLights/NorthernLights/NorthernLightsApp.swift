//
//  NorthernLightsApp.swift
//  NorthernLights
//
//  Created by Dharanitharan R on 08/07/26.
//

import SwiftUI

@main
struct NorthernLightsApp: App {
    // The single AuthState instance for the app's lifetime.
    // Injected into the SwiftUI view hierarchy via .environment(...) so any
    // view can read it with @Environment(AuthState.self).
    @State private var authState = AuthState()

    var body: some Scene {
        MenuBarExtra("Northern Lights", systemImage: "bag.fill") {
            ContentView()
                .environment(authState)
        }
        .menuBarExtraStyle(.window)
    }
}
