import AVFoundation

/// Format PCM interne de la voix (M2-09) : 16 kHz, mono, Float32 non entrelacé.
enum VoiceFormat {
    static let sampleRate: Double = 16_000
    // swiftlint:disable:next force_unwrapping
    static let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    /// Débit cible constant (M2-09).
    static let bitRate = 20_000
    /// Taille maximale d'une trame compressée acceptée avant décodage (Opus / AAC-ELD à 20 kbit/s ≈ 50 o).
    static let maxCompressedFrameByteCount = 400
}

/// Codec fixé par la version du protocole, sans négociation (M2-09). Opus est préféré ;
/// AAC-ELD puis PCM 16 bits ne servent que si l'appareil ne sait pas encoder/décoder Opus.
enum VoiceCodecKind: String, Equatable {
    case opus, aacELD, pcm16

    /// Échantillons par trame : 20 ms pour Opus et PCM, 30 ms (480) pour AAC-ELD (taille de trame imposée).
    var framesPerPacket: AVAudioFrameCount {
        switch self {
        case .opus, .pcm16: return 320
        case .aacELD: return 480
        }
    }

    var maxFrameByteCount: Int {
        switch self {
        case .opus, .aacELD: return VoiceFormat.maxCompressedFrameByteCount
        case .pcm16: return Int(framesPerPacket) * 2
        }
    }

    var formatID: AudioFormatID? {
        switch self {
        case .opus: return kAudioFormatOpus
        case .aacELD: return kAudioFormatMPEG4AAC_ELD
        case .pcm16: return nil
        }
    }

    /// Premier codec utilisable sur cet appareil (Opus sur iOS 17, vérifié sur nos iPhones).
    static let resolved: VoiceCodecKind = {
        for kind in [VoiceCodecKind.opus, .aacELD] {
            if (try? VoiceEncoder(kind: kind)) != nil, (try? VoiceDecoder(kind: kind)) != nil { return kind }
        }
        return .pcm16
    }()

    /// Format compressé (avec le « magic cookie » pour AAC-ELD, recalculé localement : rien n'est négocié).
    func compressedFormat() throws -> AVAudioFormat {
        guard let id = formatID else { throw VoiceCodecError.unavailable }
        var asbd = AudioStreamBasicDescription(mSampleRate: VoiceFormat.sampleRate, mFormatID: id, mFormatFlags: 0,
                                               mBytesPerPacket: 0, mFramesPerPacket: framesPerPacket, mBytesPerFrame: 0,
                                               mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        guard let format = AVAudioFormat(streamDescription: &asbd) else { throw VoiceCodecError.unavailable }
        return format
    }
}

enum VoiceCodecError: Error, Equatable {
    case unavailable
    case invalidFrameLength
    case frameTooLarge
    case decodingFailed
    case encodingFailed
}

/// PCM 16 kHz mono → trame compressée (un paquet M2-07 par trame, jamais fragmentée).
final class VoiceEncoder {
    let kind: VoiceCodecKind
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat?
    /// Magic cookie produit par l'encodeur (AAC-ELD) : sert au décodeur local.
    var magicCookie: Data? { converter?.magicCookie }

    init(kind: VoiceCodecKind) throws {
        self.kind = kind
        guard kind != .pcm16 else { converter = nil; outputFormat = nil; return }
        let format = try kind.compressedFormat()
        guard let c = AVAudioConverter(from: VoiceFormat.pcm, to: format) else { throw VoiceCodecError.unavailable }
        if let rates = c.applicableEncodeBitRates?.map(\.intValue), !rates.isEmpty {
            c.bitRate = rates.min(by: { abs($0 - VoiceFormat.bitRate) < abs($1 - VoiceFormat.bitRate) }) ?? VoiceFormat.bitRate
        }
        // Essai à vide : certains appareils créent le convertisseur mais échouent au premier encodage.
        converter = c
        outputFormat = format
        let probe = AVAudioPCMBuffer(pcmFormat: VoiceFormat.pcm, frameCapacity: kind.framesPerPacket)
        probe?.frameLength = kind.framesPerPacket
        guard let probe else { throw VoiceCodecError.unavailable }
        _ = try encode(probe)
        c.reset()
    }

    /// Encode exactement `framesPerPacket` échantillons. `nil` : l'encodeur n'a pas encore produit de paquet (amorçage).
    func encode(_ pcm: AVAudioPCMBuffer) throws -> Data? {
        guard pcm.frameLength == kind.framesPerPacket, let samples = pcm.floatChannelData?[0] else {
            throw VoiceCodecError.invalidFrameLength
        }
        guard let converter, let outputFormat else {
            var data = Data(capacity: Int(pcm.frameLength) * 2)
            for i in 0..<Int(pcm.frameLength) {
                let v = Int16(max(-1, min(1, samples[i])) * Float(Int16.max))
                withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) }
            }
            return data
        }
        let maxSize = max(converter.maximumOutputPacketSize, kind.maxFrameByteCount)
        let out = AVAudioCompressedBuffer(format: outputFormat, packetCapacity: 1, maximumPacketSize: maxSize)
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed { inputStatus.pointee = .noDataNow; return nil }
            fed = true
            inputStatus.pointee = .haveData
            return pcm
        }
        guard status != .error, error == nil else { throw VoiceCodecError.encodingFailed }
        guard out.packetCount > 0, out.byteLength > 0 else { return nil }
        guard Int(out.byteLength) <= kind.maxFrameByteCount else { throw VoiceCodecError.frameTooLarge }
        return Data(bytes: out.data, count: Int(out.byteLength))
    }
}

/// Trame compressée → PCM 16 kHz mono. N'est appelé qu'APRÈS authentification AES-GCM (M2-09) ;
/// la taille est vérifiée avant tout décodage ; une erreur de décodage = paquet invalide.
final class VoiceDecoder {
    let kind: VoiceCodecKind
    private let converter: AVAudioConverter?
    private let inputFormat: AVAudioFormat?

    init(kind: VoiceCodecKind) throws {
        self.kind = kind
        guard kind != .pcm16 else { converter = nil; inputFormat = nil; return }
        let format = try kind.compressedFormat()
        if kind == .aacELD {
            // Le cookie AAC-ELD est déterministe pour nos paramètres fixes : obtenu d'un encodeur local.
            let cookieSource = try VoiceEncoder(kind: kind)
            format.magicCookie = cookieSource.magicCookie
        }
        guard let c = AVAudioConverter(from: format, to: VoiceFormat.pcm) else { throw VoiceCodecError.unavailable }
        converter = c
        inputFormat = format
    }

    func decode(_ frame: Data) throws -> AVAudioPCMBuffer {
        guard !frame.isEmpty, frame.count <= kind.maxFrameByteCount else { throw VoiceCodecError.frameTooLarge }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: VoiceFormat.pcm, frameCapacity: kind.framesPerPacket),
              let samples = pcm.floatChannelData?[0] else { throw VoiceCodecError.decodingFailed }
        guard let converter, let inputFormat else {
            guard frame.count == kind.maxFrameByteCount else { throw VoiceCodecError.decodingFailed }
            let bytes = [UInt8](frame)
            for i in 0..<Int(kind.framesPerPacket) {
                let v = Int16(bitPattern: UInt16(bytes[2 * i]) | UInt16(bytes[2 * i + 1]) << 8)
                samples[i] = Float(v) / Float(Int16.max)
            }
            pcm.frameLength = kind.framesPerPacket
            return pcm
        }
        let input = AVAudioCompressedBuffer(format: inputFormat, packetCapacity: 1, maximumPacketSize: frame.count)
        frame.withUnsafeBytes { raw in
            if let base = raw.baseAddress { input.data.copyMemory(from: base, byteCount: frame.count) }
        }
        input.byteLength = UInt32(frame.count)
        input.packetCount = 1
        input.packetDescriptions?[0] = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                                    mDataByteSize: UInt32(frame.count))
        var fed = false
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, inputStatus in
            if fed { inputStatus.pointee = .noDataNow; return nil }
            fed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, pcm.frameLength <= kind.framesPerPacket else {
            throw VoiceCodecError.decodingFailed
        }
        return pcm
    }

    /// Trame de silence (trame perdue ou rejetée : pas de PLC, silence de même durée).
    func silence() -> AVAudioPCMBuffer? {
        let pcm = AVAudioPCMBuffer(pcmFormat: VoiceFormat.pcm, frameCapacity: kind.framesPerPacket)
        pcm?.frameLength = kind.framesPerPacket // mémoire mise à zéro par AVAudioPCMBuffer
        if let pcm, let s = pcm.floatChannelData?[0] { s.update(repeating: 0, count: Int(kind.framesPerPacket)) }
        return pcm
    }
}
