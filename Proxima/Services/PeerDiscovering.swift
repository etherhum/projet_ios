import Foundation

enum DiscoveryEvent: Equatable {
    case found(NearbyPeer)
    case lost(id: String)
}

/// Service de découverte des pairs proches. Abstrait Multipeer pour les tests et les modules futurs.
@MainActor
protocol PeerDiscovering: AnyObject {
    var localPseudonym: Pseudonym { get }
    var onEvent: ((DiscoveryEvent) -> Void)? { get set }
    /// Démarre (si arrêté) sous un NOUVEAU pseudonyme et un nouveau MCPeerID.
    func start()
    func stop()
    /// Rotation : arrêt, nouveau pseudonyme jamais utilisé, nouveau MCPeerID, redémarrage.
    func rotate()
}
