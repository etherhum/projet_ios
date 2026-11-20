import Foundation
import Combine

/// État racine de l'app : liste des proches + session d'appel (M3-05).
/// Aucune permission n'est demandée à l'init : réseau local au tap « Rechercher », micro au premier appel (M3-02).
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var nearby = NearbyPeerList()
    /// État de la session d'appel (miroir de `call.phase` pour SwiftUI).
    @Published private(set) var callPhase: CallPhase = .idle
    /// Pair de l'appel en cours ou du dernier appel affiché.
    @Published private(set) var callPeer: NearbyPeer?
    /// L'utilisateur a demandé la recherche pendant cette session (non persisté, volontairement).
    @Published private(set) var searchRequested = false
    /// L'utilisateur local a confirmé le code ; en attente de la confirmation du pair (M3-06).
    @Published private(set) var codeConfirmedLocally = false
    /// Alerte affichée quand le micro est refusé.
    @Published var showMicrophoneDeniedAlert = false

    /// Alias local affiché (change à chaque rotation).
    @Published private(set) var myAlias: String

    let discovery: PeerDiscovering
    let microphone: MicrophonePermission
    /// Effacement des secrets de session (M3-11) : la session d'appel y est enregistrée dès qu'un appel commence.
    let janitor: SecretsJanitor
    private let rotationTimer: RotationTimer
    private let rotationInterval: TimeInterval
    /// Rotation échue pendant un appel : effectuée à la fin de l'appel (M2-03).
    private(set) var rotationPending = false
    private var discovering = false
    /// Session d'appel unique (une seule à la fois).
    let call: CallSession
    /// Chaîne audio chiffrée (M3-07), démarrée/arrêtée uniquement par les transitions de `callPhase`.
    let audio: AudioPipeline

    init(discovery: PeerDiscovering, microphone: MicrophonePermission,
         rotationTimer: RotationTimer? = nil,
         rotationInterval: TimeInterval = RotationPolicy.interval,
         callTransport: CallTransport? = nil,
         callScheduler: DeadlineScheduler? = nil,
         fakeFingerprint: Bool = AppState.fakeFingerprintRequested,
         janitor: SecretsJanitor? = nil,
         audioIO: AudioIO? = nil) {
        self.discovery = discovery
        self.janitor = janitor ?? SecretsJanitor()
        self.microphone = microphone
        self.rotationTimer = rotationTimer ?? SystemRotationTimer()
        self.rotationInterval = rotationInterval
        self.myAlias = discovery.localPseudonym.alias
        self.call = CallSession(transport: callTransport ?? (discovery as? CallTransport) ?? NoCallTransport(),
                                scheduler: callScheduler, fakeFingerprint: fakeFingerprint)
        audio = AudioPipeline(io: audioIO ?? EngineAudioIO())
        call.onPhaseChange = { [weak self] phase in self?.callPhaseChanged(phase) }
        call.onConfirmationChange = { [weak self] confirmed in self?.codeConfirmedLocally = confirmed }
        audio.sendFrame = { [weak call] frame in call?.sendAudio(frame) ?? false }
        call.onAudioPacket = { [weak audio] packet in audio?.receive(packet) }
        call.onPacketRejected = { [weak audio] in audio?.noteRejected() }
        // M3-10 : trame audio invalide = paquet invalide ; panne audio = fermeture (différée : on peut être
        // dans une notification de changement de phase de la session).
        audio.onInvalidFrame = { [weak call] in call?.noteInvalidAudioFrame() }
        audio.onFailure = { [weak call] in
            DispatchQueue.main.async { MainActor.assumeIsolated { call?.audioFailed() } }
        }
        discovery.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .found(let peer):
                // Défense en profondeur : jamais soi-même dans la liste.
                guard peer.id != self.discovery.localPseudonym.value else { return }
                guard !self.discovery.isBlocked(peerID: peer.id) else { return } // bloqué (M3-09) : masqué
                self.nearby.add(peer)
            case .lost(let id): self.nearby.remove(id: id)
            }
        }
    }

    /// Démonstration M3-06 : `-ProximaFakeFingerprint` en DEBUG seulement ; toujours faux en Release.
    nonisolated static var fakeFingerprintRequested: Bool {
        #if DEBUG
        return FingerprintDemo.isEnabled
        #else
        return false
        #endif
    }

    /// Un appel est en cours (demande, poignée de main, vérification, actif) : aucune rotation.
    var isInCall: Bool { callPhase.isBusy }
    /// Écran d'appel affiché (y compris le résultat « refusé », « terminé »…).
    var showCallScreen: Bool { callPhase != .idle }

    /// Action explicite de l'utilisateur : déclenche la popup iOS « Réseau local » au premier usage.
    func userRequestedSearch() {
        searchRequested = true
        startDiscovery()
    }

    /// Reprise au premier plan : seulement si l'utilisateur avait déjà lancé la recherche.
    func resumeDiscoveryIfRequested() {
        if searchRequested { startDiscovery() }
    }

    /// Passage en arrière-plan (M3-11) : selon `BackgroundCallPolicy` (`.endCall`), le janitor efface les secrets,
    /// ce qui raccroche l'appel en cours (`CallSession.wipeSecrets`, HANGUP envoyé, clés détruites) ;
    /// puis la découverte s'arrête (M2-03). Une seule logique : plus de `hangUp` direct ici.
    func enterBackground() {
        let callEnded = janitor.appDidEnterBackground()
        guard callEnded || !isInCall else { return } // `.keepCall` : le transport de l'appel doit rester ouvert
        stopDiscovery()
    }

    func stopDiscovery() {
        rotationTimer.stop()
        discovering = false
        discovery.stop()
        nearby.removeAll()
        AppLog.log(.discoveryStopped)
    }

    private func startDiscovery() {
        guard !discovering else { return }
        discovering = true
        discovery.start() // nouveau pseudonyme à chaque démarrage (retour au premier plan inclus)
        myAlias = discovery.localPseudonym.alias
        rotationTimer.start(interval: rotationInterval) { [weak self] in self?.rotationTick() }
        AppLog.log(.discoveryStarted)
    }

    /// Échéance de la minuterie : rotation, sauf pendant un appel (reportée à la fin de l'appel).
    func rotationTick() {
        guard discovering else { return }
        if isInCall { rotationPending = true; AppLog.log(.rotationDeferredDuringCall) } else { rotatePseudonym() }
    }

    private func rotatePseudonym() {
        rotationPending = false
        // Les anciens pairs ont été vus par l'ancien browser : la liste repart de zéro (pas d'entrée périmée).
        nearby.removeAll()
        discovery.rotate()
        myAlias = discovery.localPseudonym.alias
        AppLog.log(.pseudonymRotated)
    }

    /// Lancement d'un appel : le micro est demandé ici (premier usage), jamais au lancement.
    /// Envoie ensuite la demande (COMMIT) ; l'appel ne démarre que si l'autre accepte.
    func requestCall(with peer: NearbyPeer) async {
        guard !isInCall else { return } // double tap / appel déjà en cours : un seul appel
        guard await microphoneGranted(), !isInCall else { return }
        callPeer = peer
        call.call(peerID: peer.id)
    }

    /// Appelé : action explicite « Accepter ». Micro vérifié avant d'accepter (aucune clé avant).
    func acceptIncomingCall() async {
        guard callPhase == .incomingRequest else { return }
        guard await microphoneGranted() else { call.decline(); return }
        AppLog.log(.callAccepted)
        call.accept()
    }

    func declineIncomingCall() { call.decline() }

    /// « Bloquer pour la session » (M3-09) : invitations refusées silencieusement, pair retiré et masqué de la liste.
    func blockPeer(_ peer: NearbyPeer) {
        discovery.block(peerID: peer.id)
        AppLog.log(.peerBlocked)
        nearby.remove(id: peer.id)
    }
    func confirmCode() { call.confirmCode() }
    func rejectCode() { call.rejectCode() }
    /// Variante QR (M2-06) : contenu affiché par l'appelant / scanné par l'appelé.
    var verificationQRPayload: String? { call.verificationQRPayload }
    var isCaller: Bool { call.verificationQRPayload != nil }
    func submitScannedQR(_ payload: String) { call.submitScannedQR(payload) }
    func hangUp() { call.hangUp() }

    /// Fermeture de l'écran de résultat (refusé, terminé…).
    func dismissCall() {
        call.hangUp()
        call.reset()
    }

    private func microphoneGranted() async -> Bool {
        switch microphone.status {
        case .granted: return true
        case .denied: showMicrophoneDeniedAlert = true; AppLog.log(.microphoneDenied); return false
        case .undetermined:
            if await microphone.request() { return true }
            showMicrophoneDeniedAlert = true
            AppLog.log(.microphoneDenied)
            return false
        }
    }

    private func callPhaseChanged(_ phase: CallPhase) {
        let wasBusy = callPhase.isBusy
        callPhase = phase
        if let event = AppLog.Event.forCallPhase(phase) { AppLog.log(event) } // catégorie seulement, jamais le code ni le pair
        // M3-11 : la session et la chaîne audio sont enregistrées auprès du janitor dès le début d'un appel ;
        // toute fin d'appel (local, distant, refus, échec, perte du pair) passe ici → `callDidEnd()`
        // (clés détruites, audio arrêté, tampons PCM effacés).
        if !wasBusy, phase.isBusy { janitor.register(call); janitor.register(audio) }
        // M3-07 : seul point d'entrée de l'audio ; démarrage seulement si `canExchangeAudio` (SAS_OK des deux côtés).
        if call.canExchangeAudio { audio.update(for: phase) } else { audio.stop() }
        if wasBusy, !phase.isBusy { janitor.callDidEnd(); AppLog.log(.secretsWiped) }
        if let id = call.peerID { callPeer = NearbyPeer(pseudonym: Pseudonym(value: id)) }
        if phase == .idle { callPeer = nil }
        // Fin d'appel : nouveau pseudonyme (M2-03), que la rotation ait été reportée ou non.
        if wasBusy, !phase.isBusy, discovering { rotatePseudonym() }
    }
}

/// Transport inerte (tests sans appel, découverte sans transport d'appel).
@MainActor
private final class NoCallTransport: CallTransport {
    var onCallEvent: ((CallTransportEvent) -> Void)?
    func invite(peerID: String, context: Data) {}
    func answerInvitation(accept: Bool) {}
    func send(_ data: Data) {}
    func disconnect() {}
}
