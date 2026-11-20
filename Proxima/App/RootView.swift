import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        NearbyListView()
            .fullScreenCover(isPresented: Binding(get: { appState.showCallScreen },
                                                  set: { if !$0 { appState.dismissCall() } })) {
                CallView().environmentObject(appState)
                    .privacyShield() // M3-11 : la présentation plein écran n'hérite pas de l'overlay racine
            }
            .alert("Micro désactivé", isPresented: $appState.showMicrophoneDeniedAlert) {
                Button("Ouvrir les Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Proxima a besoin du micro pour passer un appel. Autorisez-le dans Réglages > Proxima > Micro. Le son n'est jamais enregistré.")
            }
            .onChange(of: scenePhase) { _, phase in
                // Découverte uniquement au premier plan (M2-03), et seulement après le tap de l'utilisateur (M3-02).
                if phase == .active { appState.resumeDiscoveryIfRequested() }
                else if phase == .background { appState.enterBackground() }
            }
    }
}
