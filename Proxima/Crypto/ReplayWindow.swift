import Foundation

/// Rejets anti-rejeu / fraîcheur (M2-07, règles 3 et 5). Volontairement peu détaillés (pas d'oracle).
enum ReplayError: Error, Equatable {
    /// Compteur déjà vu, trop ancien (≤ max_vu − 64) ou saut abusif (> max_vu + 1000).
    case replayedOrOutOfWindow
    /// Horodatage incohérent de plus de 2 000 ms avec la référence δ₀.
    case staleTimestamp
}

/// Fenêtre anti-rejeu d'**une** direction de réception (M2-07, type RFC 6479 / IPsec) :
/// `max_vu` + masque de 64 bits, plus contrôle de fraîcheur de l'horodatage.
/// Usage : `check` avant déchiffrement (sans effet), `accept` après authentification AES-GCM
/// (vérifie à nouveau, contrôle la fraîcheur puis met à jour l'état). Un paquet falsifié
/// n'atteint jamais `accept` : il ne fait donc pas avancer la fenêtre.
final class ReplayWindow {
    static let windowSize: UInt64 = 64
    static let maxForwardJump: UInt64 = 1_000
    static let freshnessToleranceMs: Int64 = 2_000

    /// Horloge monotone injectable, en millisecondes.
    private let nowMs: () -> UInt64
    /// `nil` tant qu'aucun paquet authentifié n'a été accepté (compteur commençant à 0).
    private var maxSeen: UInt64?
    /// Bit i = compteur `maxSeen − i` déjà vu.
    private var bitmap: UInt64 = 0
    /// δ₀ = reçu₀ − horodatage₀ du premier paquet authentifié.
    private var delta0: Int64?

    init(nowMs: @escaping () -> UInt64 = ReplayWindow.monotonicNowMs) {
        self.nowMs = nowMs
    }

    static func monotonicNowMs() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }

    /// Règle 3 : plausibilité du compteur, sans modifier l'état.
    func check(counter: UInt64) throws {
        guard let maxSeen else {
            // Équivalent à max_vu = −1 : saut abusif au-delà de 999.
            guard counter < Self.maxForwardJump else { throw ReplayError.replayedOrOutOfWindow }
            return
        }
        if counter > maxSeen {
            guard counter - maxSeen <= Self.maxForwardJump else { throw ReplayError.replayedOrOutOfWindow }
            return
        }
        let age = maxSeen - counter
        guard age < Self.windowSize, bitmap & (UInt64(1) << age) == 0 else {
            throw ReplayError.replayedOrOutOfWindow
        }
    }

    /// Règles 3, 5 et 6, à n'appeler **qu'après** authentification réussie.
    func accept(counter: UInt64, timestampMs: UInt32) throws {
        try check(counter: counter)
        let delta = Int64(clamping: nowMs()) - Int64(timestampMs)
        if let delta0 {
            let (diff, overflow) = delta.subtractingReportingOverflow(delta0)
            guard !overflow, diff.magnitude <= UInt64(Self.freshnessToleranceMs) else {
                throw ReplayError.staleTimestamp
            }
        } else {
            delta0 = delta
        }
        // Règle 6 : mise à jour de la fenêtre.
        if let maxSeen, counter <= maxSeen {
            bitmap |= UInt64(1) << (maxSeen - counter)
        } else {
            let shift = maxSeen.map { counter - $0 } ?? Self.windowSize
            bitmap = shift >= Self.windowSize ? 1 : (bitmap << shift) | 1
            maxSeen = counter
        }
    }
}
