import SwiftUI

@main
struct ProximaApp: App {
    @StateObject private var appState = AppState(discovery: NearbyService(), microphone: SystemMicrophonePermission())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .privacyShield() // M3-11 : aperçu multitâche masqué
        }
    }
}
