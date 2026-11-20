import SwiftUI

@main
struct ProximaApp: App {
    @StateObject private var appState = AppState(discovery: NearbyService())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
