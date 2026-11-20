import Foundation

/// Petit tampon de gigue (M3-07) : réordonne les trames par compteur M2-07, ignore doublons et retardataires,
/// déclare une trame perdue (→ silence) dès que `depth` trames plus récentes sont arrivées.
/// Latence ajoutée ≈ (depth − 1) × 20 ms ; taille toujours < `capacity`.
struct JitterBuffer {
    enum Output: Equatable {
        case frame(Data)
        case lost
    }

    let depth: Int
    let capacity: Int
    private var pending: [UInt64: Data] = [:]
    /// Prochain compteur à restituer (fixé à la première restitution).
    private var next: UInt64?

    init(depth: Int = 3, capacity: Int = 8) {
        precondition(depth >= 1 && capacity >= depth)
        self.depth = depth
        self.capacity = capacity
    }

    var count: Int { pending.count }

    mutating func insert(counter: UInt64, payload: Data) -> [Output] {
        if let next, counter < next { return [] } // retardataire ou doublon déjà joué
        guard pending[counter] == nil else { return [] } // doublon en attente
        pending[counter] = payload
        var out: [Output] = []
        while pending.count >= depth {
            guard let minKey = pending.keys.min() else { break }
            var n = next ?? minKey
            // Trou plus grand que le tampon (coupure réseau) : on saute sans générer des secondes de silence.
            if minKey > n, minKey - n > UInt64(capacity) { n = minKey }
            if let d = pending.removeValue(forKey: n) { out.append(.frame(d)) } else { out.append(.lost) }
            next = n + 1
        }
        return out
    }

    /// Vide le tampon (fin d'appel : aucune trame en mémoire).
    mutating func reset() {
        for k in Array(pending.keys) {
            if var d = pending[k] { d.resetBytes(in: 0..<d.count); pending[k] = d }
        }
        pending.removeAll()
        next = nil
    }
}
