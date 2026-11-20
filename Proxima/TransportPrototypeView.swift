import SwiftUI

struct TransportPrototypeView: View {
    @StateObject private var transport = TransportPrototype()

    var body: some View {
        NavigationStack {
            List {
                Section("Moi") { Text(transport.pseudonym).monospaced() }
                Section("Pairs connectés") {
                    if transport.connectedPeers.isEmpty {
                        Text("Aucun pour l'instant…").foregroundStyle(.secondary)
                    }
                    ForEach(transport.connectedPeers, id: \.self) { Text($0).monospaced() }
                }
                Section {
                    Button("Envoyer un message de test", action: transport.sendTestMessage)
                        .disabled(transport.connectedPeers.isEmpty)
                }
                Section("Journal") {
                    ForEach(Array(transport.events.enumerated()), id: \.offset) { Text($0.element).font(.footnote) }
                }
            }
            .navigationTitle("Prototype M2-02")
        }
        .onAppear { transport.start() }
        .onDisappear { transport.stop() }
    }
}
