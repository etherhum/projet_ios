import Foundation
import MultipeerConnectivity

/// M2-02 — Prototype de faisabilité : deux iPhones se découvrent via
/// Multipeer Connectivity (sans Wi-Fi commun) et échangent un message de test.
/// Code jetable : la version finale (pseudonymes, acceptation explicite,
/// chiffrement applicatif) sera écrite en M3.
@MainActor
final class TransportPrototype: NSObject, ObservableObject {
    static let serviceType = "proxima" // 1–15 caractères, cf. NSBonjourServices

    @Published private(set) var connectedPeers: [String] = []
    @Published private(set) var events: [String] = []

    /// Pseudonyme aléatoire, régénéré à chaque lancement : aucun nom d'appareil diffusé.
    let pseudonym = "P-" + String(UUID().uuidString.prefix(6))

    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    override init() {
        peerID = MCPeerID(displayName: pseudonym)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType)
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        log("Recherche démarrée")
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    func sendTestMessage() {
        guard !session.connectedPeers.isEmpty else { return }
        let text = "Bonjour de \(pseudonym) à \(Date().formatted(date: .omitted, time: .standard))"
        do {
            try session.send(Data(text.utf8), toPeers: session.connectedPeers, with: .reliable)
            log("Envoyé : \(text)")
        } catch {
            log("Échec d'envoi")
        }
    }

    private func log(_ s: String) { events.insert(s, at: 0) }
}

extension TransportPrototype: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let names = session.connectedPeers.map(\.displayName)
        let name = peerID.displayName
        Task { @MainActor in
            self.connectedPeers = names
            switch state {
            case .connected: self.log("Connecté à \(name)")
            case .notConnected: self.log("Déconnecté de \(name)")
            case .connecting: break
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Validation minimale : taille bornée et UTF-8 valide.
        guard data.count <= 256, let text = String(data: data, encoding: .utf8) else { return }
        Task { @MainActor in self.log("Reçu : \(text)") }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension TransportPrototype: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Un seul des deux invite (ordre des pseudonymes) pour éviter les sessions croisées.
        Task { @MainActor in
            guard self.pseudonym < peerID.displayName else { return }
            self.log("Trouvé \(peerID.displayName), invitation envoyée")
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

extension TransportPrototype: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Prototype uniquement : acceptation automatique. En M3-05, acceptation explicite par l'utilisateur.
        Task { @MainActor in
            self.log("Invitation de \(peerID.displayName) acceptée")
            invitationHandler(true, self.session)
        }
    }
}
