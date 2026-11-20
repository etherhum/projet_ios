import CryptoKit
import Foundation

/// Type de paquet AEAD (M2-07).
enum PacketType: UInt8 {
    case audio = 0x10
    case control = 0x11
}

/// Codes CONTROL (M2-07).
enum ControlCode: UInt8 {
    case sasOK = 0x01
    case hangUp = 0x02
}

/// En-tête de 14 o, authentifié comme AAD (M2-07).
struct PacketHeader: Equatable {
    let type: PacketType
    let counter: UInt64
    let timestampMs: UInt32

    var bytes: Data {
        var d = Data([CryptoConstants.packetVersion, type.rawValue])
        withUnsafeBytes(of: counter.bigEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: timestampMs.bigEndian) { d.append(contentsOf: $0) }
        return d
    }

    /// Nonce GCM 12 o = 00 00 00 00 ‖ compteur (8 o, grand-boutiste).
    static func nonce(counter: UInt64) -> Data {
        var d = Data(count: 4)
        withUnsafeBytes(of: counter.bigEndian) { d.append(contentsOf: $0) }
        return d
    }

    /// Règles de réception 1-2 de M2-07 (taille, version, type), sans calcul crypto.
    static func parse(_ packet: Data) throws -> PacketHeader {
        let p = [UInt8](packet)
        guard p.count >= CryptoConstants.minPacketByteCount,
              p.count <= CryptoConstants.maxPacketByteCount,
              p[0] == CryptoConstants.packetVersion,
              let type = PacketType(rawValue: p[1]) else {
            throw CryptoError.malformedPacket
        }
        let counter = p[2..<10].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let ts = p[10..<14].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return PacketHeader(type: type, counter: counter, timestampMs: ts)
    }
}

/// Paquet déchiffré et authentifié.
struct OpenedPacket: Equatable {
    let header: PacketHeader
    let plaintext: Data
}

/// Chiffre/déchiffre les paquets M2-07 avec AES-256-GCM et les clés de direction de `SessionKeys`.
/// L'émetteur gère un compteur strictement croissant à partir de 0 (nonce jamais réutilisé).
/// La fenêtre anti-rejeu et la fraîcheur (règles 3, 5, 6) relèvent de M3-08 : `open` ne fait
/// que les règles 1, 2 et 4.
final class PacketCrypter {
    private let keys: SessionKeys
    private(set) var nextSendCounter: UInt64 = 0

    init(keys: SessionKeys) { self.keys = keys }

    func destroy() { keys.destroy() }

    func seal(_ plaintext: Data, type: PacketType, timestampMs: UInt32) throws -> Data {
        let key = try keys.currentSendKey()
        guard plaintext.count <= CryptoConstants.maxPlaintextByteCount else { throw CryptoError.plaintextTooLarge }
        if type == .control { try Self.validateControl(plaintext) }
        guard nextSendCounter < CryptoConstants.maxPacketCounter else { throw CryptoError.counterExhausted }
        let header = PacketHeader(type: type, counter: nextSendCounter, timestampMs: timestampMs)
        let aad = header.bytes
        let box: AES.GCM.SealedBox
        do {
            let nonce = try AES.GCM.Nonce(data: PacketHeader.nonce(counter: header.counter))
            box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        } catch {
            throw CryptoError.authenticationFailed
        }
        nextSendCounter += 1 // jamais réutilisé, même si l'envoi échoue ensuite
        return aad + box.ciphertext + box.tag
    }

    func open(_ packet: Data) throws -> OpenedPacket {
        let key = try keys.currentReceiveKey()
        let header = try PacketHeader.parse(packet)
        let p = Data(packet) // indices à 0
        let aad = p.prefix(CryptoConstants.headerByteCount)
        let ciphertext = p.subdata(in: CryptoConstants.headerByteCount..<(p.count - CryptoConstants.tagByteCount))
        let tag = p.suffix(CryptoConstants.tagByteCount)
        let plaintext: Data
        do {
            let nonce = try AES.GCM.Nonce(data: PacketHeader.nonce(counter: header.counter))
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            plaintext = try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw CryptoError.authenticationFailed
        }
        if header.type == .control { try Self.validateControl(plaintext) }
        return OpenedPacket(header: header, plaintext: plaintext)
    }

    private static func validateControl(_ plaintext: Data) throws {
        guard plaintext.count == 1, let b = plaintext.first, ControlCode(rawValue: b) != nil else {
            throw CryptoError.invalidControlCode
        }
    }
}
