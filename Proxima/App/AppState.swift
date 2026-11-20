import Foundation
import Combine

/// État racine de l'app : liste des proches + appel en cours (maquette).
/// Aucune permission n'est demandée à l'init : réseau local au tap « Rechercher », micro au premier appel (M3-02).
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var nearby = NearbyPeerList()
    @Published var activeCall: NearbyPeer?
    /// L'utilisateur a demandé la recherche pendant cette session (non persisté, volontairement).
    @Published private(set) var searchRequested = false
    /// Alerte affichée quand le micro est refusé.
    @Published var showMicrophoneDeniedAlert = false

    let discovery: PeerDiscovering
    let microphone: MicrophonePermission

    init(discovery: PeerDiscovering, microphone: MicrophonePermission) {
        self.discovery = discovery
        self.microphone = microphone
        discovery.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .found(let peer): self.nearby.add(peer)
            case .lost(let id): self.nearby.remove(id: id)
            }
        }
    }

    var myAlias: String { discovery.localPseudonym.alias }

    /// Action explicite de l'utilisateur : déclenche la popup iOS « Réseau local » au premier usage.
    func userRequestedSearch() {
        searchRequested = true
        discovery.start()
    }

    /// Reprise au premier plan : seulement si l'utilisateur avait déjà lancé la recherche.
    func resumeDiscoveryIfRequested() {
        if searchRequested { discovery.start() }
    }

    func stopDiscovery() {
        discovery.stop()
        nearby.removeAll()
    }

    /// Lancement d'un appel : le micro est demandé ici (premier usage), jamais au lancement.
    // TODO M3-05 : envoyer une demande d'appel, attendre l'acceptation explicite du pair.
    // TODO M3-07 : démarrer l'audio chiffré une fois la poignée de main (M2-05) terminée.
    func requestCall(with peer: NearbyPeer) async {
        switch microphone.status {
        case .granted:
            activeCall = peer
        case .denied:
            showMicrophoneDeniedAlert = true
        case .undetermined:
            if await microphone.request() {
                activeCall = peer
            } else {
                showMicrophoneDeniedAlert = true
            }
        }
    }

    func hangUp() { activeCall = nil }
}
