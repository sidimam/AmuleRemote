import Foundation
import WatchConnectivity

/// Ponte verso l'app Apple Watch: pubblica lo stato corrente (velocità, reti,
/// coda download) come application context. Il Watch mostra sempre l'ultimo
/// snapshot ricevuto; le notifiche locali dell'iPhone arrivano al polso già
/// con il mirroring di sistema.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var lastSent: Data?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Invia lo snapshot al Watch. Deduplica: se nulla è cambiato rispetto
    /// all'ultimo invio, non fa nulla (updateApplicationContext tiene comunque
    /// solo l'ultimo valore).
    func push(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        if let normalized = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
            if normalized == lastSent { return }
            lastSent = normalized
        }
        var stamped = payload
        stamped["ts"] = Date().timeIntervalSince1970
        try? session.updateApplicationContext(stamped)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
