import Foundation
import Combine

/// État racine de l'app : liste des proches + appel en cours (maquette).
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var nearby = NearbyPeerList()
    @Published var activeCall: NearbyPeer?

    let discovery: PeerDiscovering

    init(discovery: PeerDiscovering) {
        self.discovery = discovery
        discovery.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .found(let peer): self.nearby.add(peer)
            case .lost(let id): self.nearby.remove(id: id)
            }
        }
    }

    var myAlias: String { discovery.localPseudonym.alias }

    func startDiscovery() { discovery.start() }
    func stopDiscovery() {
        discovery.stop()
        nearby.removeAll()
    }

    // TODO M3-05 : envoyer une demande d'appel, attendre l'acceptation explicite du pair.
    // TODO M3-07 : démarrer l'audio chiffré une fois la poignée de main (M2-05) terminée.
    func startMockCall(with peer: NearbyPeer) { activeCall = peer }
    func hangUp() { activeCall = nil }
}
