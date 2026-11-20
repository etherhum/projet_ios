import Foundation

/// Événements du transport d'appel (Multipeer en production, en mémoire dans les tests).
enum CallTransportEvent: Equatable {
    /// Invitation reçue d'un pair (pseudonyme validé) avec son contexte (= COMMIT).
    case invitation(from: String, context: Data)
    /// Connexion établie avec le pair de l'appel.
    case connected
    /// Connexion perdue, invitation refusée ou expirée.
    case disconnected
    /// Données reçues du pair de l'appel (non fiables).
    case received(Data)
}

/// Transport d'un appel à la fois. Aucune connexion n'est acceptée sans `answerInvitation(accept: true)`.
@MainActor
protocol CallTransport: AnyObject {
    var onCallEvent: ((CallTransportEvent) -> Void)? { get set }
    /// Invite le pair (pseudonyme) avec le contexte donné ; délai côté transport : `CallSession.requestTimeout`.
    func invite(peerID: String, context: Data)
    /// Répond à l'invitation en attente (sans effet s'il n'y en a pas).
    func answerInvitation(accept: Bool)
    func send(_ data: Data)
    /// Ferme la connexion d'appel et annule toute invitation en cours.
    func disconnect()
}

/// Délai annulable (injectable : les tests déclenchent les échéances à la main).
@MainActor
protocol DeadlineScheduler: AnyObject {
    func schedule(after seconds: TimeInterval, _ handler: @escaping @MainActor () -> Void) -> DeadlineToken
}

@MainActor
protocol DeadlineToken: AnyObject {
    func cancel()
}

@MainActor
final class SystemDeadlineScheduler: DeadlineScheduler {
    private final class Token: DeadlineToken {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel(); task = nil }
    }

    func schedule(after seconds: TimeInterval, _ handler: @escaping @MainActor () -> Void) -> DeadlineToken {
        let token = Token()
        token.task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            handler()
        }
        return token
    }
}
