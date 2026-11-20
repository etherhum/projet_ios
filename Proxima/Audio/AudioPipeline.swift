import AVFoundation
import Combine

/// Compteurs affichables en DEBUG (aucun contenu : uniquement des nombres).
struct AudioStats: Equatable {
    var sent = 0
    var received = 0
    var rejected = 0
}

/// Découpe le PCM capturé en trames exactes de `framesPerPacket` puis les encode. Utilisé sur la file de capture
/// de l'`AudioIO` uniquement (jamais en concurrence). Le PCM en attente est écrasé à zéro par `reset()`.
final class CaptureChain {
    private let encoder: VoiceEncoder
    private var samples: [Float] = []
    private let lock = NSLock()
    private var muted = false

    init(encoder: VoiceEncoder) { self.encoder = encoder }

    var isMuted: Bool {
        get { lock.lock(); defer { lock.unlock() }; return muted }
        set { lock.lock(); muted = newValue; lock.unlock() }
    }

    var pendingSampleCount: Int { samples.count }

    /// Micro coupé : on encode du silence (débit constant M2-09, l'observateur ne voit pas la coupure).
    func process(_ buffer: AVAudioPCMBuffer) -> [Data] {
        guard let data = buffer.floatChannelData?[0] else { return [] }
        let n = Int(buffer.frameLength)
        if isMuted {
            samples.append(contentsOf: repeatElement(0, count: n))
        } else {
            samples.append(contentsOf: UnsafeBufferPointer(start: data, count: n))
        }
        let fpp = Int(encoder.kind.framesPerPacket)
        var frames: [Data] = []
        while samples.count >= fpp {
            guard let pcm = AVAudioPCMBuffer(pcmFormat: VoiceFormat.pcm, frameCapacity: AVAudioFrameCount(fpp)),
                  let dst = pcm.floatChannelData?[0] else { break }
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { dst.update(from: base, count: fpp) }
            }
            pcm.frameLength = AVAudioFrameCount(fpp)
            samples.removeFirst(fpp)
            if let encoded = try? encoder.encode(pcm) { frames.append(encoded) }
            dst.update(repeating: 0, count: fpp)
        }
        return frames
    }

    func reset() {
        samples.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        samples.removeAll()
    }
}

/// Chaîne audio d'un appel (M3-07) :
/// capture → trames 20 ms → encodage → `sendFrame` (CallSession : `seal(AUDIO)` + Multipeer `.unreliable`) ;
/// réception (déjà authentifiée par `CallSession`) → taille vérifiée → tampon de gigue → décodage → lecture.
/// Point d'entrée unique : `update(for:)` démarre en `.active` et arrête dans tout autre état.
@MainActor
final class AudioPipeline: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var stats = AudioStats()
    @Published var isMuted = false { didSet { chain?.isMuted = isMuted } }
    @Published var speakerOn = false { didSet { io.setSpeaker(speakerOn) } }

    /// Chiffre et envoie une trame (fourni par `AppState` → `CallSession.sendAudio`). Retourne `false` si refusé.
    var sendFrame: ((Data) -> Bool)?

    let codec: VoiceCodecKind
    private let io: AudioIO
    private var chain: CaptureChain?
    private var decoder: VoiceDecoder?
    private var jitter = JitterBuffer()
    /// Incrémenté à chaque arrêt : les trames encodées d'un appel précédent ne sont jamais envoyées.
    private var generation = 0

    init(io: AudioIO, codec: VoiceCodecKind = .resolved) {
        self.io = io
        self.codec = codec
    }

    /// Nombre de trames ou d'échantillons PCM encore en mémoire (0 après `stop()`).
    var bufferedItemCount: Int { jitter.count + (chain?.pendingSampleCount ?? 0) }

    func update(for phase: CallPhase) {
        if case .active = phase { start() } else { stop() }
    }

    func start() {
        guard !isRunning else { return }
        guard let encoder = try? VoiceEncoder(kind: codec), let decoder = try? VoiceDecoder(kind: codec) else {
            AppLog.log(.audioCodecUnavailable)
            return
        }
        if codec != .opus { AppLog.log(.audioCodecFallback) }
        let chain = CaptureChain(encoder: encoder)
        chain.isMuted = isMuted
        generation += 1
        let gen = generation
        do {
            try io.start { [weak self] buffer in
                let frames = chain.process(buffer) // file de capture
                guard !frames.isEmpty else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.send(frames, generation: gen) }
                }
            }
        } catch {
            io.stop()
            return
        }
        io.setSpeaker(speakerOn)
        self.chain = chain
        self.decoder = decoder
        stats = AudioStats()
        isRunning = true
        AppLog.log(.audioStarted)
    }

    func stop() {
        guard isRunning || chain != nil else { return }
        generation += 1
        io.stop() // après retour : plus aucun appel de capture
        chain?.reset()
        chain = nil
        decoder = nil
        jitter.reset()
        isRunning = false
        isMuted = false
        speakerOn = false
        AppLog.log(.audioStopped)
    }

    private func send(_ frames: [Data], generation gen: Int) {
        guard isRunning, gen == generation else { return }
        for f in frames where sendFrame?(f) == true { stats.sent += 1 }
    }

    /// Paquet AUDIO authentifié par `CallSession` (jamais appelé sur des données non authentifiées).
    func receive(_ packet: OpenedPacket) {
        guard isRunning, let decoder, packet.header.type == .audio else { return }
        guard !packet.plaintext.isEmpty, packet.plaintext.count <= codec.maxFrameByteCount else {
            stats.rejected += 1 // taille vérifiée AVANT décodage
            return
        }
        stats.received += 1
        for output in jitter.insert(counter: packet.header.counter, payload: packet.plaintext) {
            switch output {
            case .frame(let d):
                if let pcm = try? decoder.decode(d) {
                    io.play(pcm)
                } else {
                    stats.rejected += 1 // erreur de décodage = paquet invalide (M2-09)
                    if let s = decoder.silence() { io.play(s) }
                }
            case .lost:
                if let s = decoder.silence() { io.play(s) }
            }
        }
    }

    /// Paquet rejeté par `CallSession` (tag invalide…) pendant l'appel actif.
    func noteRejected() {
        guard isRunning else { return }
        stats.rejected += 1
    }
}

// MARK: M3-11 — effacement des secrets

extension AudioPipeline: SessionSecretHolder {
    /// Fin d'appel / arrière-plan / terminaison : capture et lecture arrêtées, PCM en attente écrasé, tampon de gigue vidé.
    func wipeSecrets() { stop() }
}
