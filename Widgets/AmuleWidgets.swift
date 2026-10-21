import WidgetKit
import SwiftUI
import AppIntents

// Widget e controlli di aMule Remote (iOS/iPadOS):
//  - widget «Velocità» (Home, Lock Screen, StandBy): velocità e download attivi,
//    letti con una connessione EC usa-e-getta verso il profilo corrente
//    (gruppo keychain condiviso con l'app);
//  - controlli del Centro di Controllo / tasto Azione (iOS 18+): Pausa tutti,
//    Riprendi tutti, Aggiungi link (apre l'app sul foglio «Aggiungi link»).

@main
struct AmuleWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpeedWidget()
        if #available(iOS 18.0, *) {
            PauseAllControl()
            ResumeAllControl()
            AddLinkControl()
        }
    }
}

// MARK: - Accesso al server (condiviso dai widget e dai controlli)

enum WidgetEC {
    struct Snapshot {
        var profileName: String
        var dlSpeed: Double
        var ulSpeed: Double
        var active: Int
        var queued: Int
        var ed2k: Bool
        var kad: Bool
        var error: String?
    }

    static func withClient<T>(_ body: (ECClient) async throws -> T) async throws -> T {
        guard let p = Keychain.loadSharedProfile() else {
            throw NSError(domain: "aMuleRemote", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Nessun profilo server configurato in aMule Remote.")])
        }
        guard let password = Keychain.loadPassword(account: p.address), !password.isEmpty else {
            throw NSError(domain: "aMuleRemote", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "Password del server non trovata: apri aMule Remote e connettiti una volta.")])
        }
        let client = ECClient()
        do {
            try await client.connect(host: p.host, port: UInt16(clamping: p.port), password: password)
        } catch {
            throw NSError(domain: "aMuleRemote", code: 3, userInfo: [NSLocalizedDescriptionKey: String(localized: "Server aMule non raggiungibile (\(p.host)).")])
        }
        do {
            let r = try await body(client)
            await client.disconnectNow()
            return r
        } catch {
            await client.disconnectNow()
            throw error
        }
    }

    static func snapshot() async -> Snapshot {
        let name = Keychain.loadSharedProfile()?.name ?? "aMule"
        do {
            return try await withClient { client in
                let statsReply = try await client.request(ECPacket(.statReq, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
                let connReply = try await client.request(ECPacket(.getConnState, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
                let queueReply = try await client.request(ECPacket(.getDloadQueue, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
                let stats = StatsSnapshot.parse(statsReply)
                let conn = ConnState.parse(connReply)
                let queue = queueReply.allTags(.partfile).compactMap(DownloadItem.parse)
                return Snapshot(profileName: name, dlSpeed: stats.dlSpeed, ulSpeed: stats.ulSpeed,
                                active: queue.filter { $0.speed > 0 }.count, queued: queue.count,
                                ed2k: conn.ed2kConnected, kad: conn.kadOK, error: nil)
            }
        } catch {
            return Snapshot(profileName: name, dlSpeed: 0, ulSpeed: 0, active: 0, queued: 0, ed2k: false, kad: false,
                            error: error.localizedDescription)
        }
    }
}

// MARK: - Widget Velocità

struct SpeedEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetEC.Snapshot
}

struct SpeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpeedEntry {
        SpeedEntry(date: .now, snapshot: .init(profileName: "aMule", dlSpeed: 1_200_000, ulSpeed: 240_000, active: 3, queued: 7, ed2k: true, kad: true, error: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (SpeedEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(SpeedEntry(date: .now, snapshot: await WidgetEC.snapshot())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpeedEntry>) -> Void) {
        Task {
            let entry = SpeedEntry(date: .now, snapshot: await WidgetEC.snapshot())
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct SpeedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpeedEntry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "arrow.down")
                Text(shortSpeed(s.dlSpeed)).font(.caption2.monospacedDigit())
            }
        case .accessoryInline:
            Text("↓ \(shortSpeed(s.dlSpeed)) ↑ \(shortSpeed(s.ulSpeed)) · \(s.active) attivi")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(s.profileName).font(.headline).lineLimit(1)
                Text("↓ \(shortSpeed(s.dlSpeed))  ↑ \(shortSpeed(s.ulSpeed))").monospacedDigit()
                Text(s.error == nil ? "\(s.active) attivi · \(s.queued) in coda" : "Non raggiungibile").font(.caption2)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                    Text(s.profileName).font(.headline).lineLimit(1)
                    Spacer()
                }
                if let err = s.error {
                    Text(err).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                } else {
                    Label(formatSpeed(s.dlSpeed), systemImage: "arrow.down").foregroundStyle(.green)
                    Label(formatSpeed(s.ulSpeed), systemImage: "arrow.up").foregroundStyle(.blue)
                    Text("\(s.active) attivi · \(s.queued) in coda").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Label("eD2k", systemImage: s.ed2k ? "circle.fill" : "circle").foregroundStyle(s.ed2k ? .green : .red)
                        Label("Kad", systemImage: s.kad ? "circle.fill" : "circle").foregroundStyle(s.kad ? .green : .red)
                    }
                    .font(.caption2)
                }
                Spacer(minLength: 0)
                Text(entry.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
            }
            .font(.subheadline.monospacedDigit())
        }
    }

    private func shortSpeed(_ v: Double) -> String {
        v >= 1_048_576 ? String(format: "%.1fM", v / 1_048_576) : String(format: "%.0fK", v / 1024)
    }
}

struct SpeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.sdimambro.amule-remote.speed", provider: SpeedProvider()) { entry in
            SpeedWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Velocità aMule")
        .description("Velocità di download e upload e download attivi del tuo server aMule.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Controlli (Centro di Controllo, tasto Azione)

struct WidgetPauseAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Metti in pausa tutti i download"
    static let description = IntentDescription("Mette in pausa tutti i download del server aMule.")
    func perform() async throws -> some IntentResult {
        try await WidgetEC.withClient { client in
            let queue = try await client.request(ECPacket(.getDloadQueue, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)])).allTags(.partfile).compactMap(DownloadItem.parse)
            for item in queue where !item.isPaused && !item.isComplete {
                _ = try? await client.request(ECPacket(.partfilePause, tags: [.hash16(.partfile, item.hash)]))
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct WidgetResumeAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Riprendi tutti i download"
    static let description = IntentDescription("Riprende tutti i download in pausa del server aMule.")
    func perform() async throws -> some IntentResult {
        try await WidgetEC.withClient { client in
            let queue = try await client.request(ECPacket(.getDloadQueue, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)])).allTags(.partfile).compactMap(DownloadItem.parse)
            for item in queue where item.isPaused {
                _ = try? await client.request(ECPacket(.partfileResume, tags: [.hash16(.partfile, item.hash)]))
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Apre l'app sul foglio «Aggiungi link eD2k» (schema amuleremote://addlink).
@available(iOS 18.0, *)
struct WidgetAddLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Aggiungi link eD2k"
    static let description = IntentDescription("Apre aMule Remote per incollare uno o più link eD2k.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "amuleremote://addlink")!))
    }
}

@available(iOS 18.0, *)
struct PauseAllControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.sdimambro.amule-remote.control.pause") {
            ControlWidgetButton(action: WidgetPauseAllIntent()) {
                Label("Pausa tutti", systemImage: "pause.circle")
            }
        }
        .displayName("aMule: pausa tutti")
        .description("Mette in pausa tutti i download del server aMule.")
    }
}

@available(iOS 18.0, *)
struct ResumeAllControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.sdimambro.amule-remote.control.resume") {
            ControlWidgetButton(action: WidgetResumeAllIntent()) {
                Label("Riprendi tutti", systemImage: "play.circle")
            }
        }
        .displayName("aMule: riprendi tutti")
        .description("Riprende tutti i download in pausa del server aMule.")
    }
}

@available(iOS 18.0, *)
struct AddLinkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.sdimambro.amule-remote.control.addlink") {
            ControlWidgetButton(action: WidgetAddLinkIntent()) {
                Label("Aggiungi link eD2k", systemImage: "plus.circle")
            }
        }
        .displayName("aMule: aggiungi link")
        .description("Apre aMule Remote per incollare link eD2k.")
    }
}
