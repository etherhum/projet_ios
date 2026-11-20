import Foundation

/// Raison d'un échec (sans détail technique transmis au pair : pas d'oracle, M2-07).
enum CallFailure: Equatable {
    /// Appelant : l'appelé a refusé ou n'a pas répondu (Multipeer ne distingue pas les deux).
    case declinedOrNoAnswer
    /// Délai de poignée de main ou de vérification dépassé (30 s, M2-05 / M2-06).
    case timeout
    /// Message inattendu, mal formé, engagement faux, paquet non authentique.
    case protocolError
    /// Codes déclarés différents (M2-06).
    case codeMismatch
    /// Connexion perdue avant la fin (ou envoi impossible sur le lien).
    case disconnected
    /// Limite de session atteinte : durée maximale (1 h) ou compteur d'émission épuisé (M2-07, M3-10).
    case sessionLimitReached
    /// Audio impossible à démarrer ou perdu (session audio, codec, moteur) : on ne continue pas sans protection (M3-10).
    case audioUnavailable
}

enum CallEnd: Equatable {
    case localHangUp
    case remoteHangUp
    /// Appelé : l'utilisateur a refusé la demande.
    case declined
}

/// États explicites d'une session d'appel (M3-05).
enum CallPhase: Equatable {
    case idle
    /// Appelant : COMMIT envoyé dans l'invitation, en attente de l'acceptation.
    case outgoingRequest
    /// Appelé : demande reçue, en attente de l'action explicite de l'utilisateur. Aucune clé.
    case incomingRequest
    /// Échange HELLO / REVEAL en cours.
    case handshaking
    /// Clés établies, code de vérification affiché (comparaison humaine M2-06 / M3-06).
    case verifying(code: String)
    /// Codes confirmés des deux côtés (SAS_OK local envoyé ET distant reçu). Seul état où l'audio
    /// est autorisé (`CallSession.canExchangeAudio`, M2-06 : rien avant la confirmation des deux côtés).
    case active(code: String)
    case failed(CallFailure)
    case ended(CallEnd)

    var isBusy: Bool {
        switch self {
        case .idle, .failed, .ended: return false
        default: return true
        }
    }
}

/// Machine à états d'une session d'appel, indépendante de Multipeer (testable avec un transport en mémoire).
///
/// Appelant (I) : `call` → paire éphémère + COMMIT (dans l'invitation) → `outgoingRequest`
///   → connexion → `handshaking` → HELLO reçu → REVEAL envoyé, dérivation → `verifying`.
/// Appelé (R) : invitation (COMMIT) → `incomingRequest` (aucune clé) → `accept()` explicite
///   → paire éphémère → connexion → HELLO envoyé → REVEAL reçu, engagement vérifié, dérivation → `verifying`.
/// Refus, délai, message inattendu, déconnexion : `failed`/`ended`, toutes les clés détruites.
/// Aucun log de donnée (ni pseudonyme, ni clé, ni code) : seuls des événements statiques `AppLog`.
@MainActor
final class CallSession {
    /// Délai de chaque étape (demande, poignée de main, vérification) : 30 s (M2-05, M2-06).
    static let stepTimeout: TimeInterval = 30
    static let requestTimeout: TimeInterval = stepTimeout
    /// Durée maximale d'une session à clés établies : 1 h, puis fermeture et effacement (M2-07, M3-10).
    static let maxSessionDuration: TimeInterval = 3_600
    /// Politique de rejets en appel actif (M2-07 § Politique d'erreur) : plus de 20 rejets en 5 s ⇒ fermeture.
    static let rejectionLimit = 20
    static let rejectionWindow: TimeInterval = 5

    private(set) var phase: CallPhase = .idle {
        didSet { if phase != oldValue { onPhaseChange?(phase) } }
    }
    /// Pseudonyme du pair de l'appel en cours (affiché via son alias).
    private(set) var peerID: String?
    var onPhaseChange: ((CallPhase) -> Void)?
    /// Paquet AUDIO authentifié reçu en appel actif (M3-07).
    var onAudioPacket: ((OpenedPacket) -> Void)?
    /// Paquet rejeté (tag invalide, mal formé) en appel actif (M3-07, compteur DEBUG).
    var onPacketRejected: (() -> Void)?

    private let transport: CallTransport
    private let scheduler: DeadlineScheduler
    private let clock: () -> TimeInterval
    /// Limite du compteur d'émission (injectable pour tester l'épuisement ; défaut M2-07 : 2³²).
    private let sendCounterLimit: UInt64

    // Matériel de session : tout est remis à nil par `teardown()`.
    private var role: HandshakeRole?
    private(set) var keyPair: EphemeralKeyPair?
    private var ownNonce: Data?
    private var commitment: Data?
    private(set) var crypter: PacketCrypter?
    private var helloSent = false
    /// L'utilisateur local a confirmé le code (SAS_OK envoyé) ; on attend celui du pair.
    private(set) var localCodeConfirmed = false {
        didSet { if localCodeConfirmed != oldValue { onConfirmationChange?(localCodeConfirmed) } }
    }
    var onConfirmationChange: ((Bool) -> Void)?
    /// Le pair a confirmé le code (SAS_OK authentifié reçu) ; exposé pour guider l'utilisateur (M3-06, QR).
    private(set) var remoteCodeConfirmed = false {
        didSet { if remoteCodeConfirmed != oldValue { onRemoteConfirmationChange?(remoteCodeConfirmed) } }
    }
    var onRemoteConfirmationChange: ((Bool) -> Void)?
    /// DEBUG uniquement (`-ProximaFakeFingerprint`) : empreinte affichée volontairement fausse (M3-06).
    private let fakeFingerprint: Bool
    private var deadline: DeadlineToken?
    /// Échéance de durée maximale de session (armée à l'établissement des clés).
    private var sessionDeadline: DeadlineToken?
    private var sessionStart: TimeInterval = 0
    /// Instants des rejets récents en appel actif (fenêtre glissante de `rejectionWindow`).
    private var rejectionTimes: [TimeInterval] = []

    /// Indique si un matériel de clé (paire éphémère ou clés de session) est encore détenu.
    var holdsKeyMaterial: Bool { keyPair != nil || crypter != nil }

    /// Garde explicite pour l'audio (M3-07) : vrai seulement en `active`, c'est-à-dire après
    /// SAS_OK local envoyé ET SAS_OK distant reçu. Micro et lecture interdits sinon (M2-06).
    var canExchangeAudio: Bool {
        if case .active = phase, crypter != nil { return true }
        return false
    }

    /// Variante QR (M2-06), côté appelant pendant la vérification : `v ‖ C` en hexadécimal.
    var verificationQRPayload: String? {
        guard case .verifying = phase, role == .initiator, let c = displayedCommitment else { return nil }
        return VerificationQR.payload(commitment: c)
    }

    /// `fakeFingerprint` n'a d'effet qu'en DEBUG (démonstration d'une empreinte fausse).
    init(transport: CallTransport,
         scheduler: DeadlineScheduler? = nil,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         fakeFingerprint: Bool = false,
         sendCounterLimit: UInt64 = CryptoConstants.maxPacketCounter) {
        self.fakeFingerprint = fakeFingerprint
        self.sendCounterLimit = sendCounterLimit
        self.transport = transport
        self.scheduler = scheduler ?? SystemDeadlineScheduler()
        self.clock = clock
        transport.onCallEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: Actions de l'utilisateur

    /// Appelant : envoie la demande d'appel (COMMIT dans le contexte de l'invitation).
    func call(peerID: String) {
        guard !phase.isBusy else { return }
        reset()
        let pair = EphemeralKeyPair()
        let nonce = Handshake.randomNonce()
        guard let c = try? Handshake.commitment(publicKeyX963: pair.publicKeyX963, nonce: nonce) else {
            pair.destroy(); phase = .failed(.protocolError); return
        }
        self.peerID = peerID
        role = .initiator
        keyPair = pair
        ownNonce = nonce
        commitment = c
        phase = .outgoingRequest
        armDeadline(failure: .declinedOrNoAnswer)
        transport.invite(peerID: peerID, context: HandshakeMessage.commit(commitment: c).bytes)
    }

    /// Appelé : acceptation explicite. La paire éphémère n'est créée qu'ici.
    func accept() {
        guard phase == .incomingRequest else { return }
        role = .responder
        keyPair = EphemeralKeyPair()
        ownNonce = Handshake.randomNonce()
        phase = .handshaking
        armDeadline(failure: .timeout)
        transport.answerInvitation(accept: true)
    }

    /// Appelé : refus explicite. Aucune clé n'a été générée.
    func decline() {
        guard phase == .incomingRequest else { return }
        transport.answerInvitation(accept: false)
        finish(.ended(.declined))
    }

    /// « Les codes correspondent » : envoie SAS_OK chiffré (M2-06). Actif quand les deux côtés ont confirmé.
    func confirmCode() {
        guard case .verifying = phase, !localCodeConfirmed else { return }
        guard sendControl(.sasOK) else { return fail(.protocolError) }
        localCodeConfirmed = true
        activateIfConfirmed()
    }

    /// Variante QR (M2-06), côté appelé : compare C scanné (hors bande) à C reçu par radio.
    /// Identique → équivaut à « Les codes correspondent » ; différent ou illisible → échec `codeMismatch`.
    func submitScannedQR(_ payload: String) {
        guard case .verifying = phase, role == .responder, let expected = displayedCommitment else { return }
        guard let scanned = VerificationQR.commitment(fromPayload: payload),
              scanned.count == expected.count,
              Handshake.constantTimeEquals(scanned, expected) else {
            return rejectCode()
        }
        confirmCode()
    }

    /// « Les codes ne correspondent pas » : fermeture immédiate, clés effacées (M2-06).
    func rejectCode() {
        guard case .verifying = phase else { return }
        _ = sendControl(.hangUp)
        guard phase.isBusy else { return } // échec d'envoi : déjà fermé en sécurité
        transport.disconnect()
        finish(.failed(.codeMismatch))
    }

    /// Raccrocher / annuler, à toute étape.
    func hangUp() {
        switch phase {
        case .incomingRequest:
            decline()
        case .outgoingRequest, .handshaking, .verifying, .active:
            _ = sendControl(.hangUp)
            guard phase.isBusy else { return } // échec d'envoi : déjà fermé en sécurité
            transport.disconnect()
            finish(.ended(.localHangUp))
        case .idle, .failed, .ended:
            break
        }
    }

    /// Retour à `idle` après affichage du résultat.
    func reset() {
        guard !phase.isBusy else { return }
        teardown()
        peerID = nil
        phase = .idle
    }

    // MARK: Événements du transport (entrée NON fiable)

    private func handle(_ event: CallTransportEvent) {
        switch event {
        case .invitation(let from, let context):
            handleInvitation(from: from, context: context)
        case .connected:
            if phase == .outgoingRequest {
                phase = .handshaking
                armDeadline(failure: .timeout)
            } else if phase == .handshaking, role == .responder, !helloSent {
                sendHello()
            }
        case .disconnected:
            switch phase {
            case .outgoingRequest: finish(.failed(.declinedOrNoAnswer))
            case .incomingRequest: finish(.failed(.disconnected))
            case .handshaking, .verifying, .active: finish(.failed(.disconnected))
            case .idle, .failed, .ended: break
            }
        case .received(let data):
            handleData(data)
        }
    }

    private func handleInvitation(from: String, context: Data) {
        // Une seule session à la fois : toute demande pendant un appel est refusée automatiquement.
        guard !phase.isBusy,
              Pseudonym.isValid(from),
              case .commit(let c)? = HandshakeMessage.decode(context) else {
            transport.answerInvitation(accept: false)
            return
        }
        reset()
        peerID = from
        commitment = c
        phase = .incomingRequest
        armDeadline(failure: nil) // sans réponse en 30 s : refus (défaut de réponse = refus)
    }

    private func handleData(_ data: Data) {
        guard data.count <= CryptoConstants.maxPacketByteCount else { return fail(.protocolError) }
        switch phase {
        case .handshaking:
            guard let message = HandshakeMessage.decode(data) else { return fail(.protocolError) }
            handleHandshake(message)
        case .outgoingRequest:
            // Le HELLO peut précéder la notification de connexion.
            guard let message = HandshakeMessage.decode(data), case .hello = message else { return fail(.protocolError) }
            phase = .handshaking
            handleHandshake(message)
        case .verifying, .active:
            handlePacket(data)
        case .idle, .incomingRequest, .failed, .ended:
            break // rien n'est attendu : ignoré (aucune connexion acceptée avant `accept()`)
        }
    }

    private func handleHandshake(_ message: HandshakeMessage) {
        guard let pair = keyPair, let ownNonce, let commitment, let role else { return fail(.protocolError) }
        do {
            switch (role, message) {
            case (.initiator, .hello(let pkR, let nonceR)):
                let peerKey = try PeerPublicKey(x963Representation: pkR)
                guard nonceR.count == CryptoConstants.handshakeNonceByteCount else { throw CryptoError.invalidHandshakeNonce }
                let t = try Handshake.transcript(commitment: commitment, responderPublicKeyX963: pkR, responderNonce: nonceR,
                                                 initiatorPublicKeyX963: pair.publicKeyX963, initiatorNonce: ownNonce)
                transport.send(HandshakeMessage.reveal(publicKey: pair.publicKeyX963, nonce: ownNonce).bytes)
                try establish(pair.deriveSessionKeys(role: .initiator, peerPublicKey: peerKey, transcript: t))
            case (.responder, .reveal(let pkI, let nonceI)) where helloSent:
                try Handshake.verifyCommitment(commitment, publicKeyX963: pkI, nonce: nonceI)
                let peerKey = try PeerPublicKey(x963Representation: pkI)
                let t = try Handshake.transcript(commitment: commitment, responderPublicKeyX963: pair.publicKeyX963,
                                                 responderNonce: ownNonce, initiatorPublicKeyX963: pkI, initiatorNonce: nonceI)
                try establish(pair.deriveSessionKeys(role: .responder, peerPublicKey: peerKey, transcript: t))
            default:
                fail(.protocolError) // hors séquence (ex. 2ᵉ COMMIT, REVEAL avant HELLO, HELLO reçu par R)
            }
        } catch {
            fail(.protocolError)
        }
    }

    private func sendHello() {
        guard let pair = keyPair, let ownNonce else { return fail(.protocolError) }
        helloSent = true
        transport.send(HandshakeMessage.hello(publicKey: pair.publicKeyX963, nonce: ownNonce).bytes)
    }

    private func establish(_ keys: SessionKeys) throws {
        // La clé privée est consommée par la dérivation ; on lâche aussi l'objet.
        keyPair = nil
        ownNonce = nil
        var code = try keys.verificationCode()
        #if DEBUG
        if fakeFingerprint { code = FingerprintDemo.alter(code: code) }
        #endif
        crypter = PacketCrypter(keys: keys, sendCounterLimit: sendCounterLimit)
        sessionStart = clock()
        sessionDeadline = scheduler.schedule(after: Self.maxSessionDuration) { [weak self] in
            AppLog.log(.sessionMaxDurationReached)
            self?.fail(.sessionLimitReached) // 1 h maximum (M2-07) : fermeture et effacement
        }
        phase = .verifying(code: code)
        armDeadline(failure: .timeout) // comparaison des codes : 30 s (M2-06)
    }

    private func handlePacket(_ data: Data) {
        guard let crypter else { return fail(.protocolError) }
        let opened: OpenedPacket
        do {
            opened = try crypter.open(data)
        } catch {
            AppLog.log(error as? ReplayError == .replayedOrOutOfWindow ? .packetReplayRejected : .packetRejected)
            // Tag invalide ou paquet rejoué (M3-08) pendant la vérification : fermeture (M2-07).
            // En appel actif : compté (politique de rejets M2-07, M3-10).
            registerRejection()
            return
        }
        if opened.header.type == .audio {
            // AUDIO authentifié et hors rejeu (fenêtre M3-08 dans `open`) : transmis seulement en `.active` (M2-06).
            if canExchangeAudio { onAudioPacket?(opened) }
            return
        }
        guard opened.header.type == .control else { return }
        guard let code = opened.plaintext.first.flatMap(ControlCode.init) else { return }
        switch code {
        case .hangUp:
            transport.disconnect()
            finish(.ended(.remoteHangUp))
        case .sasOK:
            // Un seul SAS_OK par session, et seulement pendant la vérification : un doublon (rejeu)
            // ou un SAS_OK en appel actif est une violation du protocole → fermeture (M3-06).
            guard case .verifying = phase, !remoteCodeConfirmed else { return fail(.protocolError) }
            remoteCodeConfirmed = true
            activateIfConfirmed()
        }
    }

    /// Seule transition vers `active` (garde explicite : les deux confirmations sont requises).
    private func activateIfConfirmed() {
        guard case .verifying(let code) = phase, localCodeConfirmed, remoteCodeConfirmed, crypter != nil else { return }
        deadline?.cancel(); deadline = nil
        phase = .active(code: code)
    }

    @discardableResult
    private func sendControl(_ code: ControlCode) -> Bool {
        guard let packet = seal(Data([code.rawValue]), type: .control) else { return false }
        transport.send(packet)
        return true
    }

    /// Engagement C tel qu'affiché / attendu localement (altéré en démonstration DEBUG).
    private var displayedCommitment: Data? {
        guard let commitment else { return nil }
        #if DEBUG
        if fakeFingerprint { return FingerprintDemo.alter(commitment: commitment) }
        #endif
        return commitment
    }

    /// Trame audio compressée → paquet AUDIO chiffré, envoyé en `.unreliable`. Uniquement en appel actif.
    /// Toute erreur de chiffrement (compteur épuisé, clé détruite…) ferme l'appel (M3-10).
    func sendAudio(_ frame: Data) -> Bool {
        guard canExchangeAudio, let packet = seal(frame, type: .audio) else { return false }
        transport.sendUnreliable(packet)
        return true
    }

    /// Trame audio authentifiée mais invalide pour le codec (taille, erreur de décodage) : compte comme
    /// un paquet invalide (M2-09) dans la politique de rejets.
    func noteInvalidAudioFrame() {
        guard canExchangeAudio else { return }
        AppLog.log(.audioFrameRejected)
        registerRejection()
    }

    /// La chaîne audio n'a pas pu démarrer ou s'est arrêtée (session audio, codec, moteur) :
    /// pas d'appel « actif » sans audio protégé, on ferme et on efface (M3-10).
    func audioFailed() {
        guard phase.isBusy else { return }
        AppLog.log(.audioFailureClosedCall)
        fail(.audioUnavailable)
    }

    /// `nil` = échec, la session est déjà fermée (sauf `keyDestroyed` hors appel, sans effet).
    private func seal(_ plaintext: Data, type: PacketType) -> Data? {
        guard let crypter else { return nil }
        let elapsed = max(0, clock() - sessionStart) * 1000
        let ts = UInt32(min(elapsed, Double(UInt32.max)))
        do {
            return try crypter.seal(plaintext, type: type, timestampMs: ts)
        } catch CryptoError.counterExhausted {
            AppLog.log(.sendCounterExhausted)
            fail(.sessionLimitReached)
            return nil
        } catch {
            AppLog.log(.sealFailed)
            fail(.protocolError)
            return nil
        }
    }

    /// Politique de rejets (M2-07) : en vérification, tout rejet ferme ; en appel actif,
    /// plus de `rejectionLimit` rejets en `rejectionWindow` secondes ferment la session.
    private func registerRejection() {
        switch phase {
        case .verifying:
            fail(.protocolError)
        case .active:
            onPacketRejected?()
            let now = clock()
            rejectionTimes.removeAll { now - $0 >= Self.rejectionWindow }
            rejectionTimes.append(now)
            if rejectionTimes.count > Self.rejectionLimit {
                AppLog.log(.rejectionThresholdExceeded)
                fail(.protocolError)
            }
        default:
            break
        }
    }

    // MARK: Délais et fin

    /// `failure == nil` : délai de la demande entrante (refus automatique).
    private func armDeadline(failure: CallFailure?) {
        deadline?.cancel()
        deadline = scheduler.schedule(after: Self.stepTimeout) { [weak self] in
            guard let self else { return }
            if let failure {
                self.transport.disconnect()
                self.finish(.failed(failure))
            } else if self.phase == .incomingRequest {
                self.transport.answerInvitation(accept: false)
                self.finish(.failed(.timeout))
            }
        }
    }

    /// Échec en sécurité (M3-10) : transport fermé, clés détruites, état terminal `failed`.
    /// Le pair ne reçoit aucun détail (pas d'oracle). Toujours sans effet hors appel.
    private func fail(_ failure: CallFailure) {
        guard phase.isBusy else { teardown(); return }
        transport.disconnect()
        finish(.failed(failure))
    }

    private func finish(_ terminal: CallPhase) {
        teardown()
        phase = terminal
    }

    /// Détruit toutes les clés et oublie l'état de poignée de main.
    fileprivate func teardown() {
        deadline?.cancel(); deadline = nil
        sessionDeadline?.cancel(); sessionDeadline = nil
        rejectionTimes.removeAll()
        keyPair?.destroy(); keyPair = nil
        crypter?.destroy(); crypter = nil
        ownNonce = nil
        commitment = nil
        role = nil
        helloSent = false
        localCodeConfirmed = false
        remoteCodeConfirmed = false
    }
}

// MARK: M3-11 — effacement des secrets

extension CallSession: SessionSecretHolder {
    /// Appelé par `SecretsJanitor` (fin d'appel, arrière-plan, terminaison) : un appel en cours est raccroché
    /// (HANGUP envoyé si possible, transport fermé), puis paire éphémère, clés de session et état de poignée de main
    /// sont détruits. Idempotent.
    func wipeSecrets() {
        if phase.isBusy { hangUp() } else { teardown() }
    }
}
