import Foundation

// Controlli "mordi e fuggi" dello stato del server, condivisi da tutte le
// piattaforme: usati dal monitor offline (app aperta ma disconnessa) e, su
// iOS, dal Background App Refresh.

/// Un controllo "mordi e fuggi" dello stato del server: connessione EC
/// dedicata, confronto con l'ultimo stato persistito, notifiche, disconnessione.
/// Usato dal Background App Refresh e dal monitor in foreground dopo la
/// disconnessione per inattività.
enum BackgroundMonitor {
    /// Controlla il profilo predefinito (o l'ultimo server usato).
    static func checkDefaultServer() async {
        let defaults = UserDefaults.standard
        // Interruttore principale delle notifiche: se spento, nessun controllo.
        guard defaults.bool(forKey: "notificationsEnabled") else { return }
        guard defaults.object(forKey: "backgroundChecks") as? Bool ?? true else { return }
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
        await checkOnce(host: host, port: port, password: password,
                        notifyDownloads: defaults.object(forKey: "notifyDownloads") as? Bool ?? true,
                        notifyNetwork: defaults.object(forKey: "notifyNetwork") as? Bool ?? true)
    }

    static func checkOnce(host: String, port: Int, password: String,
                          notifyDownloads: Bool, notifyNetwork: Bool) async {
        guard !host.isEmpty, !password.isEmpty else { return }
        let server = "\(host):\(port)"
        let client = ECClient()
        do {
            try await client.connect(host: host, port: UInt16(clamping: port), password: password)
        } catch {
            return   // server irraggiungibile: nessuna notifica, si riprova al giro dopo
        }

        // Flag "Riconnetti automaticamente" del server: se attivo, i drop
        // eD2k/Kad sono transitori e per scelta dell'utente non si notificano.
        if let reply = try? await client.request(ECPacket(.getPreferences, tags: [
            .uint32(.selectPrefs, ECPrefs.connections),
            .uint8(.detailLevel, ECDetailLevel.full.rawValue),
        ])) {
            Notifier.recordServerReconnect(server: server, enabled: RemotePrefs.parse(reply).reconnect)
        }
        let reconnects = Notifier.serverReconnectEnabled(server: server)

        // Stato reti eD2k / Kad
        if let reply = try? await client.request(
            ECPacket(.getConnState, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)])) {
            let cs = ConnState.parse(reply)
            if notifyNetwork, !reconnects, let prev = Notifier.lastNetState(server: server) {
                if prev.ed2k && !cs.ed2kConnected {
                    Notifier.post(id: "ed2k-drop", title: "eD2k disconnesso",
                                  body: "\(host) non è più connesso alla rete eD2k.")
                }
                if prev.kad && !cs.kadOK {
                    Notifier.post(id: "kad-drop", title: "Kad disconnesso",
                                  body: "\(host) non è più connesso alla rete Kad.")
                }
            }
            Notifier.recordNetState(server: server, ed2k: cs.ed2kConnected, kad: cs.kadOK)
        }

        // Coda download: un file sparito dalla coda con progresso alto = completato.
        if let reply = try? await client.request(
            ECPacket(.getDloadQueue, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)])) {
            let fresh = reply.allTags(.partfile).compactMap(DownloadItem.parse)
            let previous = Notifier.lastQueue(server: server)
            var current: [String: Notifier.QueueEntry] = [:]
            for f in fresh {
                let hex = hexString(f.hash)
                current[hex] = .init(p: max(f.progress, previous[hex]?.p ?? 0), n: f.name)
            }
            for (hex, entry) in previous where current[hex] == nil && entry.p >= 0.90 {
                if Notifier.markCompletedOnce(server: server, hashHex: hex), notifyDownloads {
                    Notifier.post(id: "dl-\(hex)", title: "Download completato ✅", body: entry.n)
                }
            }
            Notifier.recordQueue(server: server, entries: current)
        }

        await client.disconnectNow()
    }
}
