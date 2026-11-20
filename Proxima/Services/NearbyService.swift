import Foundation
import MultipeerConnectivity

/// Découverte Multipeer (issu du prototype M2-02). Annonce + navigation sous un pseudonyme
/// éphémère ; AUCUNE connexion automatique (demande/acceptation d'appel : M3-05).
/// Aucun log : les pseudonymes ne sont jamais imprimés.
@MainActor
final class NearbyService: NSObject, PeerDiscovering {
    static let serviceType = "proxima" // cf. NSBonjourServices dans Proxima-Info.plist
    static let discoveryInfo = ["v": "1"] // identique pour tous (M2-03)

    private(set) var localPseudonym = Pseudonym.random()
    var onEvent: ((DiscoveryEvent) -> Void)?

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    func start() {
        guard advertiser == nil else { return }
        // Nouveau pseudonyme et nouveau MCPeerID à chaque démarrage (jamais persisté).
        // TODO M3-03 : rotation toutes les 10 min hors appel.
        localPseudonym = .random()
        let peerID = MCPeerID(displayName: localPseudonym.value)
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: Self.discoveryInfo, serviceType: Self.serviceType)
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        advertiser.delegate = self
        browser.delegate = self
        self.advertiser = advertiser
        self.browser = browser
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
    }
}

extension NearbyService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let name = peerID.displayName
        guard info?["v"] == "1", (1...32).contains(name.count) else { return }
        Task { @MainActor in
            guard browser === self.browser else { return }
            self.onEvent?(.found(NearbyPeer(pseudonym: Pseudonym(value: name))))
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
