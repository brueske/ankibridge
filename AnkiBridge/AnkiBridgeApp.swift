import SwiftUI

@main
struct AnkiBridgeApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .environmentObject(state.settings)
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(state.settings)
        }
    }
}
