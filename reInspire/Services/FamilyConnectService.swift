import Foundation
import MultipeerConnectivity
import Observation
import UIKit
import os.log

private let mcLogger = Logger(subsystem: "com.reinspire", category: "FamilyConnect")

/// Shake-to-connect family pairing over MultipeerConnectivity.
///
/// Both phones shake and start advertising + browsing on the same service type.
/// When they find each other, the device that owns a family code (the parent)
/// sends it; the other device exposes it via `receivedCode` so the UI can join.
/// Local only -- no server, works offline, requires two real devices nearby.
@Observable
final class FamilyConnectService: NSObject {
    enum Phase: Equatable { case idle, searching, connecting, success, failed }

    private(set) var phase: Phase = .idle
    private(set) var peerName: String?
    /// Family code received from a nearby parent -- the View joins with it.
    var receivedCode: String?
    /// True once our own code was delivered to a peer (parent side).
    private(set) var didShareCode = false

    // serviceType: 1-15 chars, lowercase ASCII letters / digits / hyphens.
    private let serviceType = "chlg-fam"
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// nil for a child/individual (they receive a code); set for a parent.
    private var myCode: String?
    private var timeoutWork: DispatchWorkItem?

    /// Begin pairing. `code` = the caller's family invite code if they have one.
    func start(sharingCode code: String?) {
        stop()
        myCode = code
        setOnMain { s in
            s.receivedCode = nil
            s.didShareCode = false
            s.peerName = nil
            s.phase = .searching
        }

        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let info = ["has": code == nil ? "0" : "1"]
        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.phase == .searching || self.phase == .connecting {
                self.setOnMain { $0.phase = .failed }
                self.stop()
            }
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    func stop() {
        timeoutWork?.cancel(); timeoutWork = nil
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session?.disconnect(); session = nil
    }

    func reset() {
        stop()
        setOnMain { s in
            s.phase = .idle
            s.receivedCode = nil
            s.peerName = nil
            s.didShareCode = false
        }
    }

    /// Mutate observable state on the main thread.
    private func setOnMain(_ apply: @escaping (FamilyConnectService) -> Void) {
        if Thread.isMainThread { apply(self) }
        else { DispatchQueue.main.async { [weak self] in if let self { apply(self) } } }
    }

    private func deliverMyCode() {
        guard let session, let myCode, let peer = session.connectedPeers.first,
              let payload = try? JSONSerialization.data(withJSONObject: ["code": myCode]) else { return }
        do {
            try session.send(payload, toPeers: [peer], with: .reliable)
            setOnMain { s in s.didShareCode = true; s.phase = .success }
        } catch {
            mcLogger.error("send code failed: \(error)")
            setOnMain { $0.phase = .failed }
        }
    }
}

// MARK: - Browser

extension FamilyConnectService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        guard let session else { return }
        let name = peerID.displayName
        setOnMain { s in s.phase = .connecting; s.peerName = name }
        // Deterministic tiebreak so only one side sends the invite.
        if myPeerID.displayName <= peerID.displayName {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        mcLogger.error("browse failed: \(error)")
        setOnMain { $0.phase = .failed }
    }
}

// MARK: - Advertiser

extension FamilyConnectService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let name = peerID.displayName
        setOnMain { $0.peerName = name }
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        mcLogger.error("advertise failed: \(error)")
        setOnMain { $0.phase = .failed }
    }
}

// MARK: - Session

extension FamilyConnectService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = peerID.displayName
        switch state {
        case .connected:
            setOnMain { $0.peerName = name }
            // The peer with a code (parent) sends it; the other waits.
            if myCode != nil { deliverMyCode() }
        case .notConnected:
            setOnMain { s in
                if !s.didShareCode && s.receivedCode == nil && s.phase == .connecting {
                    s.phase = .failed
                }
            }
        default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Only a code-less device (child/individual) acts on a received code.
        guard myCode == nil,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = obj["code"] as? String, !code.isEmpty else { return }
        setOnMain { s in s.receivedCode = code.uppercased(); s.phase = .success }
        stop()
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
