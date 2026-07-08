//
//  NorthernLightsApp.swift
//  NorthernLights
//
//  Created by Dharanitharan R on 08/07/26.
//

import SwiftUI

@main
struct NorthernLightsApp: App {
    var body: some Scene {
        MenuBarExtra("Northern Lights", systemImage: "bag.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
