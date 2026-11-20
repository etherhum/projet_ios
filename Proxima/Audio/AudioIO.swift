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
}

/// Implémentation `AVAudioEngine` : tap sur `inputNode` (traitement voix : annulation d'écho),
/// conversion au format cible, `AVAudioPlayerNode` pour la lecture.
final class EngineAudioIO: AudioIO {
    enum IOError: Error { case unavailable }

    /// Au-delà, les trames reçues sont abandonnées (latence bornée à ~200 ms côté lecture).
    static let maxQueuedPlayback = 10

    let session = AudioSessionController()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var converter: AVAudioConverter? // utilisé uniquement sur `queue`
    private let queue = DispatchQueue(label: "proxima.audio.capture", qos: .userInteractive)
    private var onCapture: ((AVAudioPCMBuffer) -> Void)?
    private let queuedLock = NSLock()
    private var queued = 0
    private var configObserver: NSObjectProtocol?

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
        player.play()
        self.engine = engine
        self.player = player
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    /// Reconstruit le graphe (changement de route, fin d'interruption) sans changer de session audio.
    private func restart() {
        guard engine != nil else { return }
        tearDownEngine()
        do { try build() } catch { tearDownEngine() }
    }

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
        queued += 1
        queuedLock.unlock()
        player.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            self.queuedLock.lock(); self.queued = max(0, self.queued - 1); self.queuedLock.unlock()
        }
    }

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
