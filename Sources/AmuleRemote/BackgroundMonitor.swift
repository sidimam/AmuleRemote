import Foundation

// Controlli "mordi e fuggi" dello stato del server, condivisi da tutte le
// piattaforme: usati dal monitor offline (app aperta ma disconnessa) e, su
// iOS, dal Background App Refresh.

/// Un controllo "mordi e fuggi" dello stato del server: connessione EC
/// dedicata, confronto con l'ultimo stato persistito, notifiche, disconnessione.
/// Notifica: server non raggiungibile / di nuovo raggiungibile, download
/// avviati e completati, cadute e riconnessioni eD2k/Kad.
enum BackgroundMonitor {
    /// Intervallo dei controlli con l'app aperta ma offline (5 minuti) e minimo
    /// per il Background App Refresh su iOS (15 minuti, deciso dal sistema).
    static let foregroundInterval: UInt64 = 300
    static let backgroundInterval: TimeInterval = 900

    /// Controlla il profilo predefinito (o l'ultimo server usato).
    static func checkDefaultServer() async {
        // Senza il permesso di sistema le notifiche non arrivano: il controllo
        // sarebbe solo consumo di batteria.
        guard await Notifier.isAuthorized() else { return }
        let defaults = UserDefaults.standard
        var host = defaults.string(forKey: "host") ?? ""
        var port = defaults.object(forKey: "port") as? Int ?? 4712
        // Se esiste un profilo predefinito, comanda lui.
        if let def = ProfileStore.defaultID,
           let p = ProfileStore.load().first(where: { $0.id == def }) {
            host = p.host
            port = p.port
        }
        guard !host.isEmpty, host.uppercased() != "DEMO" else { return }
        let password = Keychain.loadPassword(account: "\(host):\(port)") ?? ""
        await checkOnce(host: host, port: port, password: password)
    }

    static func checkOnce(host: String, port: Int, password: String) async {
        guard !host.isEmpty, !password.isEmpty else { return }
        let server = "\(host):\(port)"
        let client = ECClient()
        do {
            try await client.connect(host: host, port: UInt16(clamping: port), password: password)
        } catch {
            // Server irraggiungibile: una notifica sola finché non torna.
            Notifier.serverUnreachable(server: server, host: host)
            return
        }
        Notifier.serverReachableAgain(server: server, host: host)

        // Flag "Riconnetti automaticamente" del server: se attivo, i drop
        // eD2k/Kad sono transitori e per scelta dell'utente non si notificano.
        if let reply = try? await client.request(ECPacket(.getPreferences, tags: [
            .uint32(.selectPrefs, ECPrefs.connections),
            .uint8(.detailLevel, ECDetailLevel.full.rawValue),
        ])) {
            Notifier.recordServerReconnect(server: server, enabled: RemotePrefs.parse(reply).reconnect)
        }

        // Stato reti eD2k / Kad
        if let reply = try? await client.request(
            ECPacket(.getConnState, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)])) {
            let cs = ConnState.parse(reply)
            if let prev = Notifier.lastNetState(server: server) {
                Notifier.notifyNetworkTransition(server: server, host: host, serverName: cs.serverName,
                                                 previous: prev, current: (cs.ed2kConnected, cs.kadOK))
            }
            Notifier.recordNetState(server: server, ed2k: cs.ed2kConnected, kad: cs.kadOK)
        }

        // Coda download: un file nuovo = avviato; un file sparito dalla coda
        // con progresso alto = completato.
        if let reply = try? await client.request(
            ECPacket(.getDloadQueue, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)])) {
            let fresh = reply.allTags(.partfile).compactMap(DownloadItem.parse)
            let hadSnapshot = Notifier.hasQueueSnapshot(server: server)
            let previous = Notifier.lastQueue(server: server)
            var current: [String: Notifier.QueueEntry] = [:]
            for f in fresh {
                let hex = hexString(f.hash)
                current[hex] = .init(p: max(f.progress, previous[hex]?.p ?? 0), n: f.name)
                if hadSnapshot && previous[hex] == nil && !f.isComplete {
                    Notifier.postDownloadStarted(server: server, name: f.name, hashHex: hex)
                }
            }
            for (hex, entry) in previous where current[hex] == nil && entry.p >= 0.90 {
                Notifier.postDownloadCompleted(server: server, name: entry.n, hashHex: hex)
            }
            Notifier.recordQueue(server: server, entries: current)
        }

        await client.disconnectNow()
    }
}
