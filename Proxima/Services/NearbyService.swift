import Foundation
import MultipeerConnectivity

/// Découverte Multipeer (M2-03). Annonce + navigation sous un pseudonyme éphémère ;
/// AUCUNE connexion automatique : une invitation n'est acceptée qu'après l'action explicite
/// de l'utilisateur (`answerInvitation(accept: true)`, M3-05). Sert aussi de transport d'appel.
/// Logs via AppLog uniquement (événements statiques) : ni pseudonyme ni donnée de proximité.
@MainActor
final class NearbyService: NSObject, PeerDiscovering, CallTransport {
    static let serviceType = "proxima" // cf. NSBonjourServices dans Proxima-Info.plist
    static let discoveryInfo = ["v": DiscoveryValidator.protocolVersion] // identique pour tous (M2-03)

    private(set) var localPseudonym = Pseudonym.random()
    var onEvent: ((DiscoveryEvent) -> Void)?

    /// Pseudonymes déjà utilisés pendant ce lancement (mémoire uniquement, jamais persistés) :
    /// garantit qu'aucun pseudonyme, donc aucun MCPeerID, n'est réutilisé.
    private var usedPseudonyms: Set<String> = []

    /// Anti-spam (M3-09) : limite de débit + blocage pour la session, conservé entre rotations.
    nonisolated let requestGate = CallRequestGate()

    /// Bloque un pair pour la session : ses invitations sont refusées silencieusement.
    func block(peerID: String) { requestGate.block(peer: peerID) }
    func isBlocked(peerID: String) -> Bool { requestGate.isBlocked(peer: peerID) }

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // Transport d'appel (un seul appel à la fois).
    var onCallEvent: ((CallTransportEvent) -> Void)?
    /// MCPeerID des pairs valides vus par le browser courant (borné comme la liste).
    private var foundPeers: [String: MCPeerID] = [:]
    /// Pair de l'appel en cours (invité ou ayant invité).
    private var callPeer: MCPeerID?
    /// Invitation entrante en attente de la décision de l'utilisateur (une seule).
    private var pendingInvitation: ((Bool, MCSession?) -> Void)?

    func start() {
        guard advertiser == nil else { return }
        localPseudonym = freshPseudonym()
        // Nouveau MCPeerID + nouvelle session/advertiser/browser à chaque pseudonyme (jamais archivé).
        let peerID = MCPeerID(displayName: localPseudonym.value)
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
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
        disconnect()
        foundPeers.removeAll()
        session?.delegate = nil
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

    // MARK: CallTransport

    func invite(peerID: String, context: Data) {
        guard let browser, let session, let peer = foundPeers[peerID], callPeer == nil else {
            onCallEvent?(.disconnected)
            return
        }
        callPeer = peer
        browser.invitePeer(peer, to: session, withContext: context, timeout: CallSession.requestTimeout)
    }

    func answerInvitation(accept: Bool) {
        guard let handler = pendingInvitation else { return }
        pendingInvitation = nil
        if accept, let session {
            handler(true, session)
        } else {
            handler(false, nil)
            callPeer = nil
        }
    }

    func send(_ data: Data) {
        guard let session, let peer = callPeer, session.connectedPeers.contains(peer) else { return }
        transmit(data, mode: .reliable)
    }

    func sendUnreliable(_ data: Data) {
        transmit(data, mode: .unreliable) // audio temps réel (M3-07)
    }

    /// Envoi sur le lien d'appel. Un échec n'est plus ignoré (M3-10) : lien fermé et `.disconnected` signalé
    /// à la session (différé d'un tour de boucle pour ne pas ré-entrer dans la session pendant son envoi).
    private func transmit(_ data: Data, mode: MCSessionSendDataMode) {
        guard let session, let peer = callPeer else { return }
        guard session.connectedPeers.contains(peer) else { return } // connexion en cours / perdue : délégué
        do {
            try session.send(data, toPeers: [peer], with: mode)
        } catch {
            AppLog.log(.transportSendFailed)
            disconnect()
            Task { @MainActor in self.onCallEvent?(.disconnected) }
        }
    }

    func disconnect() {
        if let handler = pendingInvitation { pendingInvitation = nil; handler(false, nil) }
        if let peer = callPeer { session?.cancelConnectPeer(peer) }
        callPeer = nil
        session?.disconnect()
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
            if self.foundPeers.count < NearbyPeerList.maxPeers || self.foundPeers[name] != nil {
                self.foundPeers[name] = peerID
            }
            self.onEvent?(.found(peer))
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let name = peerID.displayName
        Task { @MainActor in
            guard browser === self.browser else { return }
            if self.callPeer != peerID { self.foundPeers[name] = nil }
            self.onEvent?(.lost(id: name))
        }
    }
}

extension NearbyService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // M3-09 : première vérification, avant tout traitement (Task, invitation en attente…) ;
        // refus silencieux si le pair est bloqué ou si la limite de débit est atteinte.
        guard requestGate.allow(peer: peerID.displayName) else {
            invitationHandler(false, nil)
            AppLog.log(requestGate.isBlocked(peer: peerID.displayName) ? .invitationBlocked : .invitationRateLimited)
            return
        }
        let name = peerID.displayName
        let context = context ?? Data()
        Task { @MainActor in
            // Jamais d'acceptation automatique. Refus immédiat si : autre advertiser (rotation),
            // invitation déjà en attente, appel en cours, ou contexte trop grand.
            guard advertiser === self.advertiser, self.pendingInvitation == nil, self.callPeer == nil,
                  context.count <= HandshakeMessage.maxByteCount else {
                invitationHandler(false, nil)
                AppLog.log(.invitationDeclined)
                return
            }
            self.pendingInvitation = invitationHandler
            self.callPeer = peerID
            // La session décide (validation du pseudonyme et du COMMIT, occupation, choix de l'utilisateur).
            self.onCallEvent?(.invitation(from: name, context: context))
        }
    }
}

extension NearbyService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            guard session === self.session, peerID == self.callPeer else { return }
            switch state {
            case .connected: self.onCallEvent?(.connected)
            case .notConnected:
                self.callPeer = nil
                self.onCallEvent?(.disconnected)
            case .connecting: break
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard session === self.session, peerID == self.callPeer else { return }
            self.onCallEvent?(.received(data)) // taille/format validés par CallSession
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        stream.close() // aucun flux attendu
    }

    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        progress.cancel() // aucune ressource attendue
    }

    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
