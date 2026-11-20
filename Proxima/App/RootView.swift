import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NearbyListView()
            .fullScreenCover(item: $appState.activeCall) { peer in
                CallView(peer: peer, onHangUp: appState.hangUp)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                // Découverte uniquement au premier plan (M2-03 : rien n'est annoncé en arrière-plan).
                if phase == .active { appState.startDiscovery() }
                else if phase == .background { appState.stopDiscovery() }
            }
    }
}
