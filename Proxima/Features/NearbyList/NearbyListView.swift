import SwiftUI

struct NearbyListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Moi") {
                    Label(appState.myAlias, systemImage: "person.crop.circle.dashed")
                }
                Section("À proximité") {
                    if appState.nearby.peers.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Recherche d'utilisateurs proches…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(appState.nearby.peers) { peer in
                        Button { appState.startMockCall(with: peer) } label: {
                            HStack {
                                Label(peer.alias, systemImage: "person.wave.2")
                                Spacer()
                                Image(systemName: "phone.fill").foregroundStyle(.green)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Proxima")
        }
    }
}
