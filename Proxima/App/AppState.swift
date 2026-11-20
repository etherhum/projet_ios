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

    /// Alias local affiché (change à chaque rotation).
    @Published private(set) var myAlias: String

    let discovery: PeerDiscovering
    let microphone: MicrophonePermission
    private let rotationTimer: RotationTimer
    private let rotationInterval: TimeInterval
    /// Rotation échue pendant un appel : effectuée à la fin de l'appel (M2-03).
    private(set) var rotationPending = false
    private var discovering = false

    init(discovery: PeerDiscovering, microphone: MicrophonePermission,
         rotationTimer: RotationTimer? = nil,
         rotationInterval: TimeInterval = RotationPolicy.interval) {
        self.discovery = discovery
        self.microphone = microphone
        self.rotationTimer = rotationTimer ?? SystemRotationTimer()
        self.rotationInterval = rotationInterval
        self.myAlias = discovery.localPseudonym.alias
        discovery.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .found(let peer):
                // Défense en profondeur : jamais soi-même dans la liste.
                guard peer.id != self.discovery.localPseudonym.value else { return }
                self.nearby.add(peer)
            case .lost(let id): self.nearby.remove(id: id)
            }
        }
    }

    /// Hook M3-05 : un appel est en cours (aucune rotation pendant un appel).
    var isInCall: Bool { activeCall != nil }

    /// Action explicite de l'utilisateur : déclenche la popup iOS « Réseau local » au premier usage.
    func userRequestedSearch() {
        searchRequested = true
        startDiscovery()
    }

    /// Reprise au premier plan : seulement si l'utilisateur avait déjà lancé la recherche.
    func resumeDiscoveryIfRequested() {
        if searchRequested { startDiscovery() }
    }

    func stopDiscovery() {
        rotationTimer.stop()
        discovering = false
        discovery.stop()
        nearby.removeAll()
    }

    private func startDiscovery() {
        guard !discovering else { return }
        discovering = true
        discovery.start() // nouveau pseudonyme à chaque démarrage (retour au premier plan inclus)
        myAlias = discovery.localPseudonym.alias
        rotationTimer.start(interval: rotationInterval) { [weak self] in self?.rotationTick() }
    }

    /// Échéance de la minuterie : rotation, sauf pendant un appel (reportée à la fin de l'appel).
    func rotationTick() {
        guard discovering else { return }
        if isInCall { rotationPending = true } else { rotatePseudonym() }
    }

    private func rotatePseudonym() {
        rotationPending = false
        // Les anciens pairs ont été vus par l'ancien browser : la liste repart de zéro (pas d'entrée périmée).
        nearby.removeAll()
        discovery.rotate()
        myAlias = discovery.localPseudonym.alias
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

    /// Fin d'appel : nouveau pseudonyme (M2-03), que la rotation ait été reportée ou non.
    func hangUp() {
        activeCall = nil
        if discovering { rotatePseudonym() }
    }
}
