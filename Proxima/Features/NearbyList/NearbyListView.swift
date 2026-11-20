import SwiftUI

struct NearbyListView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @State private var showLocalNetworkHelp = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.searchRequested { list.refreshable { appState.refreshNearby() } } else { welcome }
            }
            .navigationTitle("Proxima")
        }
    }

    /// Accueil : explique le besoin du réseau local avant la popup iOS.
    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 64)).foregroundStyle(.tint)
            Text("Appelez les personnes proches").font(.title2.bold())
            VStack(alignment: .leading, spacing: 12) {
                Label("Proxima utilise le réseau local et le Wi-Fi pair-à-pair pour trouver les iPhones autour de vous.", systemImage: "wifi")
                Label("Rien ne passe par Internet ni par un serveur.", systemImage: "icloud.slash")
                Label("Vous apparaissez sous un pseudonyme éphémère, renouvelé toutes les 10 minutes.", systemImage: "theatermasks")
            }
            .font(.callout).foregroundStyle(.secondary)
            Text("iOS va vous demander l'accès au réseau local.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button {
                appState.userRequestedSearch()
            } label: {
                Text("Rechercher les personnes proches").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding()
    }

    private var list: some View {
        List {
            Section("Moi") {
                Label(appState.myAlias, systemImage: "person.crop.circle.dashed")
            }
            Section {
                if appState.nearby.peers.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Recherche d'utilisateurs proches… (tirez pour actualiser)").foregroundStyle(.secondary)
                    }
                }
                ForEach(appState.nearby.peers) { peer in
                    Button { Task { await appState.requestCall(with: peer) } } label: {
                        HStack {
                            Label(peer.alias, systemImage: "person.wave.2")
                            Spacer()
                            Image(systemName: "phone.fill").foregroundStyle(.green)
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button("Bloquer pour la session", systemImage: "hand.raised", role: .destructive) {
                            appState.blockPeer(peer)
                        }
                    }
                }
            } header: {
                Text("À proximité")
            } footer: {
                // iOS n'expose pas l'état de la permission réseau local : aide discrète si personne n'apparaît.
                if showLocalNetworkHelp && appState.nearby.peers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personne n'apparaît ? Vérifiez Réglages > Proxima > Réseau local.")
                        Button("Ouvrir les Réglages") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.footnote)
                    }
                }
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(10))
            showLocalNetworkHelp = true
        }
    }
}
