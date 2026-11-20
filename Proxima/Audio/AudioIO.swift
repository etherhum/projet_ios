import AVFoundation

/// Entrée/sortie audio de l'appel, abstraite pour tester `AudioPipeline` sans micro ni haut-parleur.
protocol AudioIO: AnyObject {
    /// Démarre capture et lecture. `onCapture` reçoit du PCM au format `VoiceFormat.pcm`, sur une file
    /// série interne (jamais le thread temps réel), en morceaux de taille quelconque.
    func start(onCapture: @escaping (AVAudioPCMBuffer) -> Void) throws
    /// Arrête tout ; après le retour, `onCapture` n'est plus jamais appelé et rien n'est en file de lecture.
    func stop()
    /// Planifie une trame décodée (`VoiceFormat.pcm`) en lecture.
    func play(_ buffer: AVAudioPCMBuffer)
    func setSpeaker(_ on: Bool)
    /// Panne après démarrage (reconstruction du moteur impossible…) : signalée sur la file principale (M3-10).
    var onFailure: (() -> Void)? { get set }
}

/// Implémentation `AVAudioEngine` : tap sur `inputNode` (traitement voix : annulation d'écho),
/// conversion au format cible, `AVAudioPlayerNode` pour la lecture.
final class EngineAudioIO: AudioIO {
    enum IOError: Error { case unavailable }

    /// Au-delà, les trames reçues sont abandonnées (latence bornée à ~200 ms côté lecture).
    static let maxQueuedPlayback = 15

    let session = AudioSessionController()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var converter: AVAudioConverter? // utilisé uniquement sur `queue`
    private let queue = DispatchQueue(label: "proxima.audio.capture", qos: .userInteractive)
    private var onCapture: ((AVAudioPCMBuffer) -> Void)?
    private let queuedLock = NSLock()
    private var queued = 0
    private var configObserver: NSObjectProtocol?
    var onFailure: (() -> Void)?

    init() {
        session.onEvent = { [weak self] event in
            switch event {
            case .interruptionBegan: AppLog.log(.audioInterrupted) // le système met le moteur en pause
            case .interruptionEnded(let resume): if resume { self?.restart() }
            case .routeChanged: break // `AVAudioEngineConfigurationChange` gère la reconfiguration
            }
        }
    }

    func start(onCapture: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard engine == nil else { return }
        self.onCapture = onCapture
        try session.activate()
        do { try build() } catch { stop(); throw error }
    }

    private func build() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true) // annulation d'écho (indispensable en haut-parleur)
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let conv = AVAudioConverter(from: inFormat, to: VoiceFormat.pcm) else { throw IOError.unavailable }
        queue.sync { converter = conv }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: VoiceFormat.pcm)
        input.installTap(onBus: 0, bufferSize: 1_024, format: inFormat) { [weak self] buffer, _ in
            self?.queue.async { self?.convertAndDeliver(buffer) }
        }
        engine.prepare()
        try engine.start()
        queuedLock.lock(); queued = 0; prebuffering = true; queuedLock.unlock() // lecture lancée par `play` après la réserve
        self.engine = engine
        self.player = player
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.configurationChanged()
        }
    }

    /// Changement de configuration signalé par le système. L'activation du traitement voix (annulation
    /// d'écho) en émet un juste après le démarrage et **arrête le moteur** (vérifié sur iPhone) : on
    /// relance le même graphe ; reconstruction complète seulement si la relance échoue.
    private func configurationChanged() {
        guard let engine, !engine.isRunning else { return }
        // Les trames planifiées avant l'arrêt ne seront jamais signalées comme jouées : sans remise à
        // zéro, le compteur resterait au plafond et toute la lecture serait ignorée (silence côté appelé).
        player?.stop()
        queuedLock.lock(); queued = 0; prebuffering = true; queuedLock.unlock()
        do {
            engine.prepare()
            try engine.start()
        } catch {
            restart()
        }
    }

    /// Reconstruit le graphe (changement de route, fin d'interruption) sans changer de session audio.
    /// Le matériel peut ne pas être prêt immédiatement après la libération de l'ancien moteur :
    /// quelques tentatives espacées avant de conclure à une panne (M3-10 : alors fermeture de l'appel).
    private func restart(attempt: Int = 0) {
        guard engine != nil || attempt > 0 else { return }
        tearDownEngine()
        do {
            try build()
        } catch {
            tearDownEngine()
            guard attempt < Self.maxRestartAttempts, onCapture != nil else { onFailure?(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.onCapture != nil, self.engine == nil else { return }
                self.restart(attempt: attempt + 1)
            }
        }
    }

    private static let maxRestartAttempts = 3

    private func convertAndDeliver(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let onCapture else { return }
        let ratio = VoiceFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: VoiceFormat.pcm, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed { inputStatus.pointee = .noDataNow; return nil }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else { return }
        onCapture(out)
    }

    func play(_ buffer: AVAudioPCMBuffer) {
        guard let player, engine?.isRunning == true else { return }
        queuedLock.lock()
        guard queued < Self.maxQueuedPlayback else { queuedLock.unlock(); return }
        if queued == 0, player.isPlaying { player.pause(); prebuffering = true } // file vide : on reconstitue une réserve
        queued += 1
        let startNow = prebuffering && queued >= Self.prebufferFrames
        if startNow { prebuffering = false }
        queuedLock.unlock()
        player.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            self.queuedLock.lock(); self.queued = max(0, self.queued - 1); self.queuedLock.unlock()
        }
        if startNow { player.play() }
    }

    /// Réserve avant lecture (3 × 20 ms) : évite qu'un paquet en retard vide la file et coupe le son.
    static let prebufferFrames = 3
    private var prebuffering = true

    func setSpeaker(_ on: Bool) { session.setSpeaker(on) }

    func stop() {
        tearDownEngine()
        queue.sync { onCapture = nil }
        session.deactivate()
    }

    private func tearDownEngine() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        player?.stop() // abandonne les trames planifiées
        engine?.stop()
        engine = nil
        player = nil
        queue.sync { converter = nil } // attend la fin des conversions en cours
        queuedLock.lock(); queued = 0; queuedLock.unlock()
    }
}
