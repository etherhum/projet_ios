import Foundation

/// Protection contre le spam de demandes d'appel (M3-09, menace D1 de M1-07).
///
/// Consultée AVANT tout traitement d'une invitation Multipeer. Refus silencieux côté pair (aucune UI) ; seul un événement statique AppLog, sans pseudonyme, est journalisé (M3-12).
/// - Limite par pair : `perPeerLimit` demandes acceptées par fenêtre glissante de `window` secondes.
/// - Limite globale : `globalLimit` demandes acceptées par fenêtre, toutes sources confondues
///   (un attaquant peut inventer autant de pseudonymes qu'il veut, cf. M2-03).
/// - Liste de blocage : en mémoire uniquement, jamais persistée, vidée à la fin du processus.
///   Elle n'est PAS vidée à la rotation de NOTRE pseudonyme (l'attaquant ne change pas pour autant).
///   Limite connue : le blocage vise le pseudonyme du pair ; à SA rotation (≤ 10 min) il revient
///   sous un nouveau pseudonyme. La limite globale reste alors le filet de sécurité.
///
/// Mémoire bornée : seules les demandes ACCEPTÉES sont horodatées, donc au plus `globalLimit`
/// horodatages vivants par fenêtre ; purge à chaque appel ; plafonds durs `maxTrackedPeers` et
/// `maxBlocked` (éviction du plus ancien). Les demandes refusées ne coûtent aucune allocation.
final class CallRequestGate: @unchecked Sendable {
    static let perPeerLimit = 3
    static let globalLimit = 10
    static let window: TimeInterval = 60
    static let maxTrackedPeers = 64
    static let maxBlocked = 128

    private let perPeerLimit: Int
    private let globalLimit: Int
    private let window: TimeInterval
    private let now: () -> TimeInterval
    private let lock = NSLock()

    private var global: [TimeInterval] = []
    private var perPeer: [String: [TimeInterval]] = [:]
    private var blocked: [String] = []          // ordre d'insertion (éviction FIFO)
    private var blockedSet: Set<String> = []

    /// `now` : horloge monotone injectable (par défaut temps depuis le démarrage, insensible au réglage de l'heure).
    init(perPeerLimit: Int = CallRequestGate.perPeerLimit,
         globalLimit: Int = CallRequestGate.globalLimit,
         window: TimeInterval = CallRequestGate.window,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.perPeerLimit = perPeerLimit
        self.globalLimit = globalLimit
        self.window = window
        self.now = now
    }

    /// `true` si la demande de `peer` (pseudonyme annoncé) peut être traitée ; enregistre alors la demande.
    func allow(peer: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if blockedSet.contains(peer) { return false }
        let t = now()
        purge(before: t - window)
        guard global.count < globalLimit else { return false }
        let mine = perPeer[peer] ?? []
        guard mine.count < perPeerLimit else { return false }
        if mine.isEmpty, perPeer.count >= Self.maxTrackedPeers { return false } // plafond dur (fail-closed)
        global.append(t)
        perPeer[peer, default: []].append(t)
        return true
    }

    /// Bloque `peer` pour la session (mémoire uniquement).
    func block(peer: String) {
        lock.lock(); defer { lock.unlock() }
        guard blockedSet.insert(peer).inserted else { return }
        blocked.append(peer)
        if blocked.count > Self.maxBlocked { blockedSet.remove(blocked.removeFirst()) }
        perPeer[peer] = nil
    }

    func isBlocked(peer: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return blockedSet.contains(peer)
    }

    /// Taille de l'état interne (tests de bornage mémoire).
    var footprint: (global: Int, trackedPeers: Int, blocked: Int) {
        lock.lock(); defer { lock.unlock() }
        return (global.count, perPeer.count, blocked.count)
    }

    private func purge(before limit: TimeInterval) {
        global.removeAll { $0 <= limit }
        for (key, stamps) in perPeer {
            let kept = stamps.filter { $0 > limit }
            perPeer[key] = kept.isEmpty ? nil : kept
        }
    }
}
