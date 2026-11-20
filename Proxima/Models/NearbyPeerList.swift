import Foundation

/// Pair vu à proximité. `id` = pseudonyme annoncé (éphémère).
struct NearbyPeer: Identifiable, Hashable, Sendable {
    let pseudonym: Pseudonym
    var id: String { pseudonym.value }
    var alias: String { pseudonym.alias }
}

/// Liste des pairs vus, sans doublon, triée par alias pour un affichage stable.
struct NearbyPeerList: Equatable {
    private(set) var peers: [NearbyPeer] = []

    mutating func add(_ peer: NearbyPeer) {
        guard !peers.contains(where: { $0.id == peer.id }) else { return }
        peers.append(peer)
        peers.sort { $0.alias < $1.alias }
    }

    mutating func remove(id: String) { peers.removeAll { $0.id == id } }
    mutating func removeAll() { peers.removeAll() }
}
