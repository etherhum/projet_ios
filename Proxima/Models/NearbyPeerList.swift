import Foundation

/// Pair vu à proximité. `id` = pseudonyme annoncé (éphémère).
struct NearbyPeer: Identifiable, Hashable, Sendable {
    let pseudonym: Pseudonym
    var id: String { pseudonym.value }
    var alias: String { pseudonym.alias }
}

/// Liste des pairs vus, sans doublon, triée de façon stable (alias puis pseudonyme, ordre total).
struct NearbyPeerList: Equatable {
    /// Borne défensive contre l'inondation d'annonces (M3-09 traitera la limitation fine).
    static let maxPeers = 64

    private(set) var peers: [NearbyPeer] = []

    mutating func add(_ peer: NearbyPeer) {
        guard !peers.contains(where: { $0.id == peer.id }), peers.count < Self.maxPeers else { return }
        peers.append(peer)
        peers.sort { ($0.alias, $0.id) < ($1.alias, $1.id) }
    }

    mutating func remove(id: String) { peers.removeAll { $0.id == id } }
    mutating func removeAll() { peers.removeAll() }
}
