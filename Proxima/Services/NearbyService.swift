import Foundation
import MultipeerConnectivity

/// Découverte Multipeer (M2-03). Annonce + navigation sous un pseudonyme éphémère ;
/// AUCUNE connexion automatique (demande/acceptation d'appel : M3-05).
/// Aucun log : ni pseudonyme ni donnée de proximité ne sont imprimés.
@MainActor
final class NearbyService: NSObject, PeerDiscovering {
    static let serviceType = "proxima" // cf. NSBonjourServices dans Proxima-Info.plist
    static let discoveryInfo = ["v": DiscoveryValidator.protocolVersion] // identique pour tous (M2-03)

    private(set) var localPseudonym = Pseudonym.random()
    var onEvent: ((DiscoveryEvent) -> Void)?

    /// Pseudonymes déjà utilisés pendant ce lancement (mémoire uniquement, jamais persistés) :
    /// garantit qu'aucun pseudonyme, donc aucun MCPeerID, n'est réutilisé.
    private var usedPseudonyms: Set<String> = []

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    func start() {
        guard advertiser == nil else { return }
        localPseudonym = freshPseudonym()
        // Nouveau MCPeerID + nouvelle session/advertiser/browser à chaque pseudonyme (jamais archivé).
        let peerID = MCPeerID(displayName: localPseudonym.value)
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: Self.discoveryInfo, serviceType: Self.serviceType)
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        advertiser.delegate = self
        browser.delegate = self
        self.session = session
        self.advertiser = advertiser
        self.browser = browser
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser?.delegate = nil
        browser?.delegate = nil
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
    }

    func rotate() {
        stop()
        start()
    }

    private func freshPseudonym() -> Pseudonym {
        var p = Pseudonym.random()
        while usedPseudonyms.contains(p.value) { p = .random() }
        usedPseudonyms.insert(p.value)
        return p
    }
}

extension NearbyService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let name = peerID.displayName
        Task { @MainActor in
            guard browser === self.browser,
                  let peer = DiscoveryValidator.peer(displayName: name, info: info, local: self.localPseudonym)
            else { return }
            self.onEvent?(.found(peer))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor in
            guard browser === self.browser else { return }
            self.onEvent?(.lost(id: name))
        }
    }
}

extension NearbyService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // TODO M3-05 : présenter la demande d'appel à l'utilisateur. Pour l'instant : refus.
        invitationHandler(false, nil)
    }
}
