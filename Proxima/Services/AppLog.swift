import Foundation
import os

// MARK: - Règles de journalisation (M3-12) — voir docs/M3-12-logs.md
//
// 1. AppLog est la SEULE porte d'entrée vers les logs. Les impressions console, les API de log Foundation/C
//    et toute autre construction de Logger sont interdites ailleurs : scripts/check-forbidden-apis.sh
//    n'autorise la construction de Logger que dans ce fichier (liste blanche explicite).
// 2. On ne journalise que des ÉVÉNEMENTS TYPÉS (`AppLog.Event`) : un cas d'enum sans valeur associée,
//    dont le message est un `StaticString` écrit dans le code. Aucune API n'accepte de `String`,
//    de `Data`, de clé, de pseudonyme, d'alias, de code SAS, de compteur ou d'horodatage lié à un pair.
// 3. Le seul paramètre dynamique possible est `correlation:` ; il est TOUJOURS émis en
//    `.private(mask: .hash)` : illisible dans la console, seulement comparable entre deux lignes.
//    Ne jamais y passer une clé ou un secret (même haché, un hash stable est une empreinte).
// 4. Les événements de niveau `.debug` ne sont émis qu'en build DEBUG (rien en Release).
// 5. Ajouter un événement = ajouter un cas ici, avec un message statique relu en revue de code.

enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "fr.epita.projetios.proxima"

    enum Category: String, CaseIterable {
        case discovery, session, crypto, audio, ui
    }

    enum Level: CaseIterable {
        case debug, info, notice, error
    }

    /// Événements autorisés. Volontairement SANS valeur associée : impossible d'y glisser une donnée.
    enum Event: CaseIterable {
        // Découverte
        case discoveryStarted
        case discoveryStopped
        case pseudonymRotated
        case rotationDeferredDuringCall
        // Session (M3-05) : aucune donnée du pair, seulement la catégorie d'événement
        case invitationDeclined
        case callOutgoing
        case callIncoming
        case callAccepted
        case callDeclined
        case callKeysEstablished
        case callActive
        case callEndedLocally
        case callEndedRemotely
        case callFailedDeclinedOrNoAnswer
        case callFailedTimeout
        case callFailedProtocol
        case callFailedCodeMismatch
        case callFailedDisconnected
        // Anti-spam (M3-09)
        case invitationRateLimited
        case invitationBlocked
        case peerBlocked
        // Anti-rejeu / validation (M3-08)
        case packetReplayRejected
        case packetRejected
        // Arrière-plan (M3-11)
        case secretsWiped
        // Audio
        case microphoneDenied

        var category: Category {
            switch self {
            case .discoveryStarted, .discoveryStopped, .pseudonymRotated, .rotationDeferredDuringCall: return .discovery
            case .invitationDeclined, .callOutgoing, .callIncoming, .callAccepted, .callDeclined, .callActive,
                 .callEndedLocally, .callEndedRemotely, .callFailedDeclinedOrNoAnswer, .callFailedTimeout,
                 .callFailedProtocol, .callFailedCodeMismatch, .callFailedDisconnected,
                 .invitationRateLimited, .invitationBlocked, .peerBlocked: return .session
            case .callKeysEstablished, .packetReplayRejected, .packetRejected, .secretsWiped: return .crypto
            case .microphoneDenied: return .audio
            }
        }

        var level: Level {
            switch self {
            case .rotationDeferredDuringCall, .packetReplayRejected, .packetRejected: return .debug
            case .discoveryStarted, .discoveryStopped, .pseudonymRotated, .invitationDeclined,
                 .callOutgoing, .callIncoming, .callAccepted, .callDeclined, .callKeysEstablished, .callActive,
                 .callEndedLocally, .callEndedRemotely, .callFailedDeclinedOrNoAnswer, .callFailedTimeout,
                 .callFailedDisconnected, .invitationRateLimited, .invitationBlocked, .peerBlocked,
                 .secretsWiped: return .info
            case .microphoneDenied: return .notice
            case .callFailedProtocol, .callFailedCodeMismatch: return .error
            }
        }

        var message: StaticString {
            switch self {
            case .discoveryStarted: return "Découverte démarrée"
            case .discoveryStopped: return "Découverte arrêtée"
            case .pseudonymRotated: return "Rotation du pseudonyme effectuée"
            case .rotationDeferredDuringCall: return "Rotation reportée (appel en cours)"
            case .invitationDeclined: return "Invitation entrante refusée automatiquement"
            case .callOutgoing: return "Appel sortant : demande envoyée"
            case .callIncoming: return "Appel entrant : demande reçue"
            case .callAccepted: return "Appel entrant accepté"
            case .callDeclined: return "Appel entrant refusé par l'utilisateur"
            case .callKeysEstablished: return "Clés de session établies, vérification du code"
            case .callActive: return "Codes confirmés des deux côtés, appel actif"
            case .callEndedLocally: return "Appel terminé localement"
            case .callEndedRemotely: return "Appel terminé par le correspondant"
            case .callFailedDeclinedOrNoAnswer: return "Échec : demande refusée ou sans réponse"
            case .callFailedTimeout: return "Échec : délai dépassé"
            case .callFailedProtocol: return "Échec : erreur de protocole"
            case .callFailedCodeMismatch: return "Échec : codes de vérification différents"
            case .callFailedDisconnected: return "Échec : connexion perdue"
            case .invitationRateLimited: return "Demande d'appel limitée (anti-spam)"
            case .invitationBlocked: return "Demande d'appel d'un pair bloqué ignorée"
            case .peerBlocked: return "Pair bloqué pour la session"
            case .packetReplayRejected: return "Paquet rejeté (rejeu ou hors fenêtre)"
            case .packetRejected: return "Paquet rejeté (format, fraîcheur ou authentification)"
            case .secretsWiped: return "Secrets de session effacés"
            case .microphoneDenied: return "Permission micro refusée"
            }
        }

        /// Événement correspondant à une phase de session (aucune donnée de la phase n'est journalisée).
        static func forCallPhase(_ phase: CallPhase) -> Event? {
            switch phase {
            case .idle, .handshaking: return nil
            case .outgoingRequest: return .callOutgoing
            case .incomingRequest: return .callIncoming
            case .verifying: return .callKeysEstablished
            case .active: return .callActive
            case .ended(.localHangUp): return .callEndedLocally
            case .ended(.remoteHangUp): return .callEndedRemotely
            case .ended(.declined): return .callDeclined
            case .failed(.declinedOrNoAnswer): return .callFailedDeclinedOrNoAnswer
            case .failed(.timeout): return .callFailedTimeout
            case .failed(.protocolError): return .callFailedProtocol
            case .failed(.codeMismatch): return .callFailedCodeMismatch
            case .failed(.disconnected): return .callFailedDisconnected
            }
        }
    }

    /// Les .debug ne sortent qu'en build DEBUG.
    static var isDebugEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func shouldEmit(_ level: Level) -> Bool { level != .debug || isDebugEnabled }

    private static let loggers: [Category: Logger] = Dictionary(uniqueKeysWithValues:
        Category.allCases.map { ($0, Logger(subsystem: subsystem, category: $0.rawValue)) })

    /// Journalise un événement. `correlation` (facultatif) est toujours masqué (`.private(mask: .hash)`).
    static func log(_ event: Event, correlation: String? = nil) {
        guard shouldEmit(event.level), let logger = loggers[event.category] else { return }
        let text = event.message.description // StaticString : contenu figé à la compilation
        let type: OSLogType
        switch event.level {
        case .debug: type = .debug
        case .info: type = .info
        case .notice: type = .default
        case .error: type = .error
        }
        if let correlation {
            logger.log(level: type, "\(text, privacy: .public) [\(correlation, privacy: .private(mask: .hash))]")
        } else {
            logger.log(level: type, "\(text, privacy: .public)")
        }
    }
}
