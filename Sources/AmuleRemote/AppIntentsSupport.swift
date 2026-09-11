import Foundation
import AppIntents

// Integrazione Siri / Comandi rapidi / Spotlight (App Intents), condivisa da
// iPhone/iPad, Apple Vision Pro, Apple TV e Mac App Store. Gli intent usano una
// connessione EC usa-e-getta verso il profilo predefinito, quindi funzionano
// anche con l'app chiusa. (La build macOS a pacchetto Swift compila questo
// file ma non estrae i metadati: lì gli intent non compaiono in Comandi rapidi.)

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
            throw IntentError(message: String(localized: "Nessun profilo server configurato in aMule Remote."))
        }
        let client = ECClient()
        do {
            try await client.connect(host: host, port: UInt16(clamping: port), password: password)
        } catch {
            throw IntentError(message: String(localized: "Server aMule non raggiungibile (\(host))."))
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

    static func stats(_ client: ECClient) async throws -> (StatsSnapshot, ConnState) {
        let statsReply = try await client.request(
            ECPacket(.statReq, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
        let connReply = try await client.request(
            ECPacket(.getConnState, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
        return (StatsSnapshot.parse(statsReply), ConnState.parse(connReply))
    }

    /// Il download il cui nome contiene il testo (ignorando maiuscole/accenti).
    static func find(_ name: String, in items: [DownloadItem]) throws -> DownloadItem {
        let needle = name.trimmingCharacters(in: .whitespaces)
        guard let item = items.first(where: { $0.name.localizedCaseInsensitiveContains(needle) }) else {
            throw IntentError(message: String(localized: "Nessun download contiene «\(needle)»."))
        }
        return item
    }

    static func partfile(_ client: ECClient, _ op: ECOp, _ item: DownloadItem, children: [ECTag] = []) async throws {
        var tag = ECTag.hash16(.partfile, item.hash)
        tag.children = children
        let reply = try await client.request(ECPacket(op, tags: [tag]))
        if reply.opcode == .failed {
            throw IntentError(message: reply.tag(.string)?.stringValue ?? String(localized: "Operazione fallita"))
        }
    }
}

// MARK: - Stato e statistiche

struct AmuleStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stato di aMule"
    static let description = IntentDescription("Velocità, reti eD2k/Kad e download attivi del server aMule.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = try await IntentEC.withClient { client in
            let (stats, cs) = try await IntentEC.stats(client)
            let items = try await IntentEC.downloadQueue(client)
            let active = items.filter { $0.speed > 0 }.count
            let ed2k = cs.ed2kConnected ? String(localized: "connesso") : String(localized: "disconnesso")
            let kad = cs.kadOK ? String(localized: "connesso") : String(localized: "disconnesso")
            return String(localized: "Download \(formatSpeed(stats.dlSpeed)), upload \(formatSpeed(stats.ulSpeed)). eD2k \(ed2k), Kad \(kad). \(items.count) file in coda, \(active) in scaricamento.")
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct AmuleDownloadSpeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Velocità di download"
    static let description = IntentDescription("Velocità di download attuale del server aMule, in kB/s (numero utilizzabile nelle automazioni).")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let kbps = try await IntentEC.withClient { client in
            try await IntentEC.stats(client).0.dlSpeed / 1024
        }
        let rounded = (kbps * 10).rounded() / 10
        return .result(value: rounded, dialog: IntentDialog(stringLiteral:
            String(localized: "Download a \(formatSpeed(kbps * 1024)).")))
    }
}

struct AmuleUploadSpeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Velocità di upload"
    static let description = IntentDescription("Velocità di upload attuale del server aMule, in kB/s.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let kbps = try await IntentEC.withClient { client in
            try await IntentEC.stats(client).0.ulSpeed / 1024
        }
        let rounded = (kbps * 10).rounded() / 10
        return .result(value: rounded, dialog: IntentDialog(stringLiteral:
            String(localized: "Upload a \(formatSpeed(kbps * 1024)).")))
    }
}

struct AmuleQueueCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Numero di download in coda"
    static let description = IntentDescription("Quanti file sono nella coda download del server aMule.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let n = try await IntentEC.withClient { client in try await IntentEC.downloadQueue(client).count }
        return .result(value: n, dialog: IntentDialog(stringLiteral: String(localized: "\(n) file in coda.")))
    }
}

struct AmuleDownloadStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stato di un download"
    static let description = IntentDescription("Avanzamento, velocità e stato del download il cui nome contiene il testo indicato.")

    @Parameter(title: "Nome (o parte)")
    var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = try await IntentEC.withClient { client in
            let item = try IntentEC.find(name, in: try await IntentEC.downloadQueue(client))
            let pctText = "\(Int((item.progress * 100).rounded()))%"
            let speed = item.speed > 0 ? formatSpeed(item.speed) : item.statusLabel
            return String(localized: "\(item.name): \(pctText) di \(formatBytes(item.sizeFull)), \(speed), fonti \(item.sourcesXfer)/\(item.sources).")
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - Download

struct AmulePauseAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Metti in pausa i download"
    static let description = IntentDescription("Mette in pausa tutti i download attivi sul server aMule.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = try await IntentEC.withClient { client in
            let items = try await IntentEC.downloadQueue(client)
            var n = 0
            for item in items where !item.isPaused && !item.isComplete {
                try? await IntentEC.partfile(client, .partfilePause, item)
                n += 1
            }
            return n
        }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Messi in pausa \(count) download.")))
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
                try? await IntentEC.partfile(client, .partfileResume, item)
                n += 1
            }
            return n
        }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Ripresi \(count) download.")))
    }
}

struct AmulePauseDownloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Metti in pausa un download"
    static let description = IntentDescription("Mette in pausa il download il cui nome contiene il testo indicato.")

    @Parameter(title: "Nome (o parte)")
    var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let found = try await IntentEC.withClient { client in
            let item = try IntentEC.find(name, in: try await IntentEC.downloadQueue(client))
            try await IntentEC.partfile(client, .partfilePause, item)
            return item.name
        }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "In pausa: \(found)")))
    }
}

struct AmuleResumeDownloadIntent: AppIntent {
    static let title: LocalizedStringResource = "Riprendi un download"
    static let description = IntentDescription("Riprende il download il cui nome contiene il testo indicato.")

    @Parameter(title: "Nome (o parte)")
    var name: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let found = try await IntentEC.withClient { client in
            let item = try IntentEC.find(name, in: try await IntentEC.downloadQueue(client))
            try await IntentEC.partfile(client, .partfileResume, item)
            return item.name
        }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Ripreso: \(found)")))
    }
}

struct AmuleSetPriorityIntent: AppIntent {
    static let title: LocalizedStringResource = "Imposta la priorità di un download"
    static let description = IntentDescription("Cambia la priorità (bassa, normale, alta, automatica) del download il cui nome contiene il testo indicato.")

    @Parameter(title: "Nome (o parte)")
    var name: String
    @Parameter(title: "Priorità")
    var priority: DownloadPriorityChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let found = try await IntentEC.withClient { client in
            let item = try IntentEC.find(name, in: try await IntentEC.downloadQueue(client))
            try await IntentEC.partfile(client, .partfilePrioSet, item,
                                        children: [.uint8(.partfilePrio, priority.filePriority.rawValue)])
            return item.name
        }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Priorità aggiornata: \(found)")))
    }
}

enum DownloadPriorityChoice: String, AppEnum {
    case low, normal, high, auto
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Priorità")
    static let caseDisplayRepresentations: [DownloadPriorityChoice: DisplayRepresentation] = [
        .low: "Bassa", .normal: "Normale", .high: "Alta", .auto: "Automatica",
    ]
    var filePriority: FilePriority {
        switch self {
        case .low: return .low
        case .normal: return .normal
        case .high: return .high
        case .auto: return .auto
        }
    }
}

struct AmuleClearCompletedIntent: AppIntent {
    static let title: LocalizedStringResource = "Rimuovi i download completati"
    static let description = IntentDescription("Toglie dalla coda del server aMule i file già completati.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentEC.withClient { client in
            _ = try await client.request(ECPacket(.clearCompleted))
        }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Download completati rimossi.")))
    }
}

struct AmuleAddLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Aggiungi link eD2k"
    static let description = IntentDescription("Accoda uno o più link ed2k:// sul server aMule (anche un testo che li contiene).")

    @Parameter(title: "Link eD2k")
    var link: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let links = AppState.extractEd2kLinks(link)
        guard !links.isEmpty else {
            throw IntentEC.IntentError(message: String(localized: "Nessun link ed2k:// nel testo."))
        }
        let names = try await IntentEC.withClient { client in
            var added: [String] = []
            for l in links {
                var tag = ECTag.string(.string, l)
                tag.children = [.number(.partfileCat, 0)]
                let reply = try await client.request(ECPacket(.addLink, tags: [tag]))
                if reply.opcode == .failed {
                    throw IntentEC.IntentError(message: reply.tag(.string)?.stringValue ?? String(localized: "Link non valido"))
                }
                added.append(AppState.ed2kLinkName(l))
            }
            return added
        }
        let dialog = names.count == 1
            ? String(localized: "Aggiunto ai download: \(names[0])")
            : String(localized: "Aggiunti \(names.count) link ai download.")
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - Ricerca

struct AmuleSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "Cerca file su aMule"
    static let description = IntentDescription("Avvia una ricerca sul server aMule e restituisce i nomi dei primi risultati (attende fino a 15 secondi).")

    @Parameter(title: "Testo da cercare")
    var query: String
    @Parameter(title: "Ricerca globale (server)", default: true)
    var global: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[String]> {
        let names = try await IntentEC.withClient { client in
            _ = try? await client.request(ECPacket(.searchStop))
            let type: ECSearchType = global ? .global : .local
            var tag = ECTag(.searchType, type: .uint32, value: {
                var be = UInt32(type.rawValue).bigEndian
                return Data(bytes: &be, count: 4)
            }())
            tag.children = [.string(.searchName, query), .string(.searchFileType, "")]
            let start = try await client.request(ECPacket(.searchStart, tags: [tag]))
            if start.opcode == .failed {
                throw IntentEC.IntentError(message: start.tag(.string)?.stringValue ?? String(localized: "Ricerca fallita"))
            }
            var results: [SearchResultItem] = []
            for _ in 0..<5 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let res = try await client.request(
                    ECPacket(.searchResults, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
                results = res.allTags(.searchFile).compactMap(SearchResultItem.parse)
                let prog = try await client.request(ECPacket(.searchProgress))
                if let v = prog.tag(.searchStatus)?.numberValue, v >= 100, v != 0xFFFF { break }
            }
            _ = try? await client.request(ECPacket(.searchStop))
            return results.sorted { $0.sources > $1.sources }.prefix(25).map {
                "\($0.name) — \(formatBytes($0.size)), \(String(localized: "fonti")) \($0.sources)"
            }
        }
        let dialog = names.isEmpty
            ? String(localized: "Nessun risultato per «\(query)».")
            : String(localized: "\(names.count) risultati per «\(query)».")
        return .result(value: Array(names), dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - Reti

struct AmuleServerConnectIntent: AppIntent {
    static let title: LocalizedStringResource = "Connetti aMule alla rete eD2k"
    static let description = IntentDescription("Chiede al server aMule di connettersi a un server eD2k (connessione automatica).")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentEC.withClient { client in _ = try await client.request(ECPacket(.serverConnect)) }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Connessione eD2k richiesta.")))
    }
}

struct AmuleServerDisconnectIntent: AppIntent {
    static let title: LocalizedStringResource = "Disconnetti aMule dalla rete eD2k"
    static let description = IntentDescription("Disconnette il server aMule dal server eD2k corrente.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentEC.withClient { client in _ = try await client.request(ECPacket(.serverDisconnect)) }
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Disconnesso dalla rete eD2k.")))
    }
}

struct AmuleKadIntent: AppIntent {
    static let title: LocalizedStringResource = "Avvia o ferma la rete Kad"
    static let description = IntentDescription("Avvia o ferma la rete Kademlia sul server aMule.")

    @Parameter(title: "Avvia", default: true)
    var start: Bool

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentEC.withClient { client in
            _ = try await client.request(ECPacket(start ? .kadStart : .kadStop))
        }
        return .result(dialog: IntentDialog(stringLiteral:
            start ? String(localized: "Rete Kad avviata.") : String(localized: "Rete Kad fermata.")))
    }
}

// MARK: - Comandi rapidi suggeriti (Siri)

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
        AppShortcut(
            intent: AmuleSearchIntent(),
            phrases: [
                "Cerca con \(.applicationName)",
                "Cerca un file su \(.applicationName)",
            ],
            shortTitle: "Cerca",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: AmuleClearCompletedIntent(),
            phrases: [
                "Rimuovi i completati da \(.applicationName)",
            ],
            shortTitle: "Rimuovi completati",
            systemImageName: "text.badge.checkmark"
        )
    }
}
