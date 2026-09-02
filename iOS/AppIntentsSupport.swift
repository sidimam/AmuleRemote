import Foundation
import AppIntents

// Integrazione Siri / Comandi rapidi / Spotlight (App Intents).
// Gli intent usano una connessione EC usa-e-getta verso il profilo
// predefinito, quindi funzionano anche con l'app chiusa.

enum IntentEC {
    struct IntentError: Error, CustomLocalizedStringResourceConvertible {
        let message: String
        var localizedStringResource: LocalizedStringResource {
            LocalizedStringResource(stringLiteral: message)
        }
    }

    static func withClient<T>(_ body: (ECClient) async throws -> T) async throws -> T {
        let defaults = UserDefaults.standard
        var host = defaults.string(forKey: "host") ?? ""
        var port = defaults.object(forKey: "port") as? Int ?? 4712
        if let def = ProfileStore.defaultID,
           let p = ProfileStore.load().first(where: { $0.id == def }) {
            host = p.host
            port = p.port
        }
        let password = Keychain.loadPassword(account: "\(host):\(port)") ?? ""
        guard !host.isEmpty, !password.isEmpty, host.uppercased() != "DEMO" else {
            throw IntentError(message: "Nessun profilo server configurato in aMule Remote.")
        }
        let client = ECClient()
        do {
            try await client.connect(host: host, port: UInt16(clamping: port), password: password)
        } catch {
            throw IntentError(message: "Server aMule non raggiungibile (\(host)).")
        }
        do {
            let result = try await body(client)
            await client.disconnectNow()
            return result
        } catch {
            await client.disconnectNow()
            throw error
        }
    }

    static func downloadQueue(_ client: ECClient) async throws -> [DownloadItem] {
        let reply = try await client.request(
            ECPacket(.getDloadQueue, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
        return reply.allTags(.partfile).compactMap(DownloadItem.parse)
    }
}

struct AmuleStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stato di aMule"
    static let description = IntentDescription("Velocità, reti eD2k/Kad e download attivi del server aMule.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = try await IntentEC.withClient { client in
            let statsReply = try await client.request(
                ECPacket(.statReq, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            let stats = StatsSnapshot.parse(statsReply)
            let connReply = try await client.request(
                ECPacket(.getConnState, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            let cs = ConnState.parse(connReply)
            let items = try await IntentEC.downloadQueue(client)
            let active = items.filter { $0.speed > 0 }.count
            let ed2k = cs.ed2kConnected ? String(localized: "connesso") : String(localized: "disconnesso")
            let kad = cs.kadOK ? String(localized: "connesso") : String(localized: "disconnesso")
            return String(localized: "Download \(formatSpeed(stats.dlSpeed)), upload \(formatSpeed(stats.ulSpeed)). eD2k \(ed2k), Kad \(kad). \(items.count) file in coda, \(active) in scaricamento.")
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct AmulePauseAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Metti in pausa i download"
    static let description = IntentDescription("Mette in pausa tutti i download attivi sul server aMule.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = try await IntentEC.withClient { client in
            let items = try await IntentEC.downloadQueue(client)
            var n = 0
            for item in items where !item.isPaused && !item.isComplete {
                var tag = ECTag.hash16(.partfile, item.hash)
                tag.children = []
                _ = try? await client.request(ECPacket(.partfilePause, tags: [tag]))
                n += 1
            }
            return n
        }
        return .result(dialog: IntentDialog(stringLiteral:
            String(localized: "Messi in pausa \(count) download.")))
    }
}

struct AmuleResumeAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Riprendi i download"
    static let description = IntentDescription("Riprende tutti i download in pausa sul server aMule.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = try await IntentEC.withClient { client in
            let items = try await IntentEC.downloadQueue(client)
            var n = 0
            for item in items where item.isPaused {
                var tag = ECTag.hash16(.partfile, item.hash)
                tag.children = []
                _ = try? await client.request(ECPacket(.partfileResume, tags: [tag]))
                n += 1
            }
            return n
        }
        return .result(dialog: IntentDialog(stringLiteral:
            String(localized: "Ripresi \(count) download.")))
    }
}

struct AmuleAddLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Aggiungi link eD2k"
    static let description = IntentDescription("Accoda un link ed2k:// sul server aMule.")

    @Parameter(title: "Link eD2k")
    var link: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = try await IntentEC.withClient { client in
            var tag = ECTag.string(.string, link.trimmingCharacters(in: .whitespacesAndNewlines))
            tag.children = [.number(.partfileCat, 0)]
            let reply = try await client.request(ECPacket(.addLink, tags: [tag]))
            if reply.opcode == .failed {
                throw IntentEC.IntentError(message: reply.tag(.string)?.stringValue ?? String(localized: "Link non valido"))
            }
            return AppState.ed2kLinkName(link)
        }
        return .result(dialog: IntentDialog(stringLiteral:
            String(localized: "Aggiunto ai download: \(name)")))
    }
}

struct AmuleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AmuleStatusIntent(),
            phrases: [
                "Stato di \(.applicationName)",
                "Come va \(.applicationName)",
                "Controlla i download su \(.applicationName)",
            ],
            shortTitle: "Stato",
            systemImageName: "gauge.with.needle"
        )
        AppShortcut(
            intent: AmulePauseAllIntent(),
            phrases: [
                "Metti in pausa \(.applicationName)",
                "Pausa ai download di \(.applicationName)",
            ],
            shortTitle: "Pausa download",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: AmuleResumeAllIntent(),
            phrases: [
                "Riprendi \(.applicationName)",
                "Riprendi i download di \(.applicationName)",
            ],
            shortTitle: "Riprendi download",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: AmuleAddLinkIntent(),
            phrases: [
                "Aggiungi un link a \(.applicationName)",
            ],
            shortTitle: "Aggiungi link",
            systemImageName: "link.badge.plus"
        )
    }
}
