import Foundation
import BackgroundTasks

/// Controlli periodici in background (Background App Refresh): quando l'app è
/// chiusa o disconnessa per timeout, iOS ci concede ogni tanto qualche secondo
/// per connetterci al server, confrontare lo stato con l'ultimo noto e
/// notificare download completati e disconnessioni eD2k/Kad.
/// La cadenza reale la decide iOS (tipicamente 15+ minuti, dipende dall'uso).
enum BackgroundRefresh {
    static let taskID = "com.sdimambro.amule-remote-ios.refresh"

    /// Da chiamare PRIMA che l'app finisca il lancio (App.init).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()   // ogni esecuzione riprenota la successiva
        let work = Task {
            await BackgroundMonitor.checkDefaultServer()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

/// Un controllo "mordi e fuggi" dello stato del server: connessione EC
/// dedicata, confronto con l'ultimo stato persistito, notifiche, disconnessione.
/// Usato dal Background App Refresh e dal monitor in foreground dopo la
/// disconnessione per inattività.
enum BackgroundMonitor {
    /// Controlla il profilo predefinito (o l'ultimo server usato).
    static func checkDefaultServer() async {
        let defaults = UserDefaults.standard
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

        // Stato reti eD2k / Kad
        if let reply = try? await client.request(
            ECPacket(.getConnState, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)])) {
            let cs = ConnState.parse(reply)
            if notifyNetwork, let prev = Notifier.lastNetState(server: server) {
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
