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
    func start()
    func stop()
}
