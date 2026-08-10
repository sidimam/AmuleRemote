import Foundation
import SwiftUI
import UserNotifications

enum AppSection: String, CaseIterable, Identifiable {
    case downloads = "Trasferimenti"
    case search = "Ricerca"
    case servers = "Server"
    case shared = "Condivisi"
    case stats = "Statistiche"
    case log = "Log"
    case prefs = "Impostazioni aMule"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .search: return "magnifyingglass"
        case .servers: return "server.rack"
        case .shared: return "folder"
        case .stats: return "chart.bar"
        case .log: return "doc.text"
        case .prefs: return "gearshape"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    let client = ECClient()

    // Connection settings. Backed by UserDefaults manually (not @AppStorage):
    // @AppStorage inside an ObservableObject does not fire objectWillChange,
    // which left bound controls like the idle-timeout Picker "stuck".
    @Published var host: String { didSet { UserDefaults.standard.set(host, forKey: "host") } }
    @Published var port: Int { didSet { UserDefaults.standard.set(port, forKey: "port") } }
    @Published var autoConnect: Bool { didSet { UserDefaults.standard.set(autoConnect, forKey: "autoConnect") } }
    // Auto-disconnect after this many seconds of inactivity (0 = disabled).
    @Published var idleTimeout: Int { didSet { UserDefaults.standard.set(idleTimeout, forKey: "idleTimeout") } }
    @Published var password: String = ""

    // Connection state
    @Published var connected = false
    @Published var connecting = false
    @Published var serverVersion = ""
    @Published var lastError: String?

    @Published var selectedSection: AppSection? = .downloads

    // Data
    @Published var stats = StatsSnapshot()
    @Published var connState = ConnState()
    @Published var downloads: [DownloadItem] = []
    @Published var uploads: [UploadItem] = []
    @Published var servers: [ServerItem] = []
    @Published var sharedFiles: [SharedFileItem] = []
    @Published var searchSessions: [SearchSession] = []
    @Published var activeSearchID: UUID?
    // The daemon runs one search at a time: only this session receives updates.
    private var liveSearchID: UUID?

    var activeSearchSession: SearchSession? {
        searchSessions.first { $0.id == activeSearchID }
    }
    @Published var logText = ""
    @Published var prefs = RemotePrefs()
    @Published var prefsLoaded = false

    private var pollTask: Task<Void, Never>?

    // MARK: - Idle auto-disconnect
    private var idleTask: Task<Void, Never>?
    private var lastActivity = ContinuousClock.now

    /// Call on any user interaction to reset the inactivity timer.
    func markActivity() {
        lastActivity = ContinuousClock.now
    }

    private func startIdleWatcher() {
        idleTask?.cancel()
        // Idle auto-disconnect is an iOS/iPadOS feature; on macOS the window
        // stays connected (we don't track pointer activity there).
        #if !os(iOS)
        return
        #else
        guard idleTimeout > 0 else { return }
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.connected, self.idleTimeout > 0 else { continue }
                let elapsed = ContinuousClock.now - self.lastActivity
                if elapsed > .seconds(self.idleTimeout) {
                    self.lastError = "Disconnesso per inattività (\(self.idleTimeout)s)."
                    await self.disconnect()
                }
            }
        }
        #endif
    }

    // Both the SwiftUI primaryAction and the AppKit double-click monitor can
    // fire for one physical double-click: collapse duplicates within 1 s.
    private var actionStamps: [String: Date] = [:]
    private func firstFire(_ key: String) -> Bool {
        let now = Date()
        if let last = actionStamps[key], now.timeIntervalSince(last) < 1.0 { return false }
        actionStamps[key] = now
        return true
    }

    init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: "host") ?? ""
        port = defaults.object(forKey: "port") as? Int ?? 4712
        autoConnect = defaults.bool(forKey: "autoConnect")
        idleTimeout = defaults.object(forKey: "idleTimeout") as? Int ?? 120

        if !host.isEmpty {
            password = Keychain.loadPassword(account: "\(host):\(port)") ?? ""
        }
        if autoConnect && !host.isEmpty && !password.isEmpty {
            Task { await connect() }
        }
    }

    // MARK: - Connection

    func connect() async {
        guard !connecting else { return }
        connecting = true
        lastError = nil
        do {
            try await client.connect(host: host, port: UInt16(clamping: port), password: password)
            serverVersion = await client.serverVersion
            connected = true
            Keychain.savePassword(password, account: "\(host):\(port)")
            loadCompletedCache()
            markActivity()
            startPolling()
            startIdleWatcher()
            await refreshAll()
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            lastError = error.localizedDescription
            connected = false
        }
        connecting = false
    }

    /// Re-fill the password from the Keychain when host/port change to a known
    /// server — but ONLY if the field is empty, so it never clobbers a value the
    /// user (or iOS AutoFill from the Passwords app) has just entered.
    func reloadStoredPassword() {
        guard password.isEmpty else { return }
        if let p = Keychain.loadPassword(account: "\(host):\(port)"), !p.isEmpty {
            password = p
        }
    }

    func disconnect() async {
        pollTask?.cancel()
        pollTask = nil
        idleTask?.cancel()
        idleTask = nil
        await client.disconnectNow()
        connected = false
        serverVersion = ""
    }

    private func handle(_ error: Error) {
        lastError = error.localizedDescription
        // A dead socket means every subsequent request fails: drop the session.
        if (error as? ECError)?.message.contains("Connessione chiusa") == true
            || (error as NSError).domain == "NWErrorDomain" {
            Task { await disconnect() }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollTick()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func pollTick() async {
        guard connected else { return }
        await refreshStats()
        await refreshDownloads()
        if selectedSection == .downloads { await refreshUploads() }
        if searchSessions.contains(where: { $0.inProgress }) { await refreshSearch() }
        if selectedSection == .log { await refreshLog() }
    }

    func refreshAll() async {
        await refreshStats()
        await refreshDownloads()
        await refreshServers()
    }

    // MARK: - Stats

    func refreshStats() async {
        do {
            let statsReply = try await client.request(
                ECPacket(.statReq, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            stats = StatsSnapshot.parse(statsReply)

            let connReply = try await client.request(
                ECPacket(.getConnState, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            connState = ConnState.parse(connReply)
        } catch {
            handle(error)
        }
    }

    // MARK: - Downloads

    // The daemon drops finished files from its queue; like aMuleGUI we keep
    // them visible client-side until the user clicks "Rimuovi completati".
    // Persisted to disk (per server) so they survive app relaunches on iOS.
    private var completedCache: [Data: DownloadItem] = [:]
    // Last progress seen for every hash, to detect completion even when a fast
    // download vanishes from the queue between two polls without ever being
    // observed at 100%.
    private var lastProgress: [Data: Double] = [:]

    private var completedKey: String { "completed-\(host):\(port)" }

    private func loadCompletedCache() {
        completedCache.removeAll()
        guard let data = UserDefaults.standard.data(forKey: completedKey),
              let items = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        for item in items { completedCache[item.hash] = item }
    }

    private func saveCompletedCache() {
        if let data = try? JSONEncoder().encode(Array(completedCache.values)) {
            UserDefaults.standard.set(data, forKey: completedKey)
        }
    }

    func refreshDownloads() async {
        do {
            let reply = try await client.request(
                ECPacket(.getDloadQueue, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            let fresh = reply.allTags(.partfile).compactMap(DownloadItem.parse)
            let freshHashes = Set(fresh.map(\.hash))

            // A file that vanished from the queue is treated as completed when
            // it was clearly near the end. We use the highest progress ever
            // seen for that hash (not just the last row) to survive fast
            // downloads that jump from ~90% to gone between two polls.
            let previous = downloads.filter { completedCache[$0.hash] == nil }
            for old in previous where !freshHashes.contains(old.hash) {
                let seenProgress = max(old.progress, lastProgress[old.hash] ?? 0)
                let finished = old.isComplete
                    || old.status == PartFileStatus.completing.rawValue
                    || seenProgress >= 0.90
                if finished && completedCache[old.hash] == nil {
                    var done = old
                    done.status = PartFileStatus.complete.rawValue
                    done.sizeDone = done.sizeFull
                    done.speed = 0
                    done.stopped = false
                    completedCache[old.hash] = done
                    notifyDownloadCompleted(done)
                }
            }
            // Remember progress for the files still in the queue.
            for f in fresh { lastProgress[f.hash] = f.progress }
            // If the daemon still reports a file, its live row wins.
            for h in freshHashes { completedCache.removeValue(forKey: h) }
            saveCompletedCache()

            downloads = (fresh + completedCache.values)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            handle(error)
        }
    }

    func refreshUploads() async {
        do {
            let reply = try await client.request(
                ECPacket(.getUloadQueue, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            uploads = reply.allTags(.client).enumerated().map { UploadItem.parse($0.element, index: $0.offset) }
        } catch {
            handle(error)
        }
    }

    /// Local notification on download completion; iOS mirrors it to Apple Watch.
    private func notifyDownloadCompleted(_ item: DownloadItem) {
        let content = UNMutableNotificationContent()
        content.title = "Download completato ✅"
        content.body = item.name
        content.sound = .default
        let request = UNNotificationRequest(identifier: "dl-\(hexString(item.hash))",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func partfileCommand(_ op: ECOp, hash: Data, children: [ECTag] = []) async {
        do {
            var tag = ECTag.hash16(.partfile, hash)
            tag.children = children
            let reply = try await client.request(ECPacket(op, tags: [tag]))
            if reply.opcode == .failed {
                lastError = reply.tag(.string)?.stringValue ?? "Operazione fallita"
            }
            await refreshDownloads()
        } catch {
            handle(error)
        }
    }

    func pause(_ item: DownloadItem) async { await partfileCommand(.partfilePause, hash: item.hash) }
    func resume(_ item: DownloadItem) async { await partfileCommand(.partfileResume, hash: item.hash) }
    func stop(_ item: DownloadItem) async { await partfileCommand(.partfileStop, hash: item.hash) }

    func delete(_ item: DownloadItem) async {
        // A cached completed row no longer exists on the daemon: just drop it.
        if completedCache.removeValue(forKey: item.hash) != nil {
            saveCompletedCache()
            downloads.removeAll { $0.hash == item.hash }
            return
        }
        await partfileCommand(.partfileDelete, hash: item.hash)
    }

    func setPriority(_ item: DownloadItem, _ prio: FilePriority) async {
        await partfileCommand(.partfilePrioSet, hash: item.hash,
                              children: [.uint8(.partfilePrio, prio.rawValue)])
    }

    func setCategory(_ item: DownloadItem, _ cat: UInt64) async {
        await partfileCommand(.partfileSetCat, hash: item.hash,
                              children: [.number(.partfileCat, cat)])
    }

    func clearCompleted() async {
        completedCache.removeAll()
        saveCompletedCache()
        downloads.removeAll { $0.isComplete }
        do {
            _ = try await client.request(ECPacket(.clearCompleted))
            await refreshDownloads()
        } catch { handle(error) }
    }

    func addEd2kLink(_ link: String, category: UInt64 = 0) async {
        do {
            var tag = ECTag.string(.string, link.trimmingCharacters(in: .whitespacesAndNewlines))
            tag.children = [.number(.partfileCat, category)]
            let reply = try await client.request(ECPacket(.addLink, tags: [tag]))
            if reply.opcode == .failed {
                lastError = reply.tag(.string)?.stringValue ?? "Link non valido"
            }
            await refreshDownloads()
        } catch { handle(error) }
    }

    // MARK: - Search

    func startSearch(text: String, type: ECSearchType, fileType: String,
                     extension ext: String, minSizeBytes: UInt64, maxSizeBytes: UInt64, availability: Int) async {
        do {
            var tag = ECTag(.searchType, type: .uint32, value: {
                var be = UInt32(type.rawValue).bigEndian
                return Data(bytes: &be, count: 4)
            }())
            var children: [ECTag] = [
                .string(.searchName, text),
                .string(.searchFileType, fileType),
            ]
            if !ext.isEmpty { children.append(.string(.searchExtension, ext)) }
            if availability > 0 { children.append(.uint32(.searchAvailability, UInt32(availability))) }
            if minSizeBytes > 0 { children.append(.uint64(.searchMinSize, minSizeBytes)) }
            if maxSizeBytes > 0 { children.append(.uint64(.searchMaxSize, maxSizeBytes)) }
            tag.children = children

            let reply = try await client.request(ECPacket(.searchStart, tags: [tag]))
            if reply.opcode == .failed {
                lastError = reply.tag(.string)?.stringValue ?? "Ricerca fallita"
                return
            }
            // The daemon replaced any running search: freeze the old live tab.
            if let liveID = liveSearchID,
               let i = searchSessions.firstIndex(where: { $0.id == liveID }) {
                searchSessions[i].inProgress = false
            }
            var session = SearchSession(query: text, type: type)
            session.inProgress = true
            searchSessions.append(session)
            activeSearchID = session.id
            liveSearchID = session.id

            // Hard timeout: a search never runs longer than 120 s.
            searchTimeoutTask?.cancel()
            let sid = session.id
            searchTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if self.searchSessions.first(where: { $0.id == sid })?.inProgress == true {
                    await self.stopSearch()
                }
            }
        } catch { handle(error) }
    }

    private var searchTimeoutTask: Task<Void, Never>?

    func refreshSearch() async {
        guard let liveID = liveSearchID,
              let i = searchSessions.firstIndex(where: { $0.id == liveID }),
              searchSessions[i].inProgress else { return }
        do {
            let prog = try await client.request(ECPacket(.searchProgress))
            if let v = prog.tag(.searchStatus)?.numberValue {
                // 0xffff = progress unknown (Kad); 100 = finished
                if v <= 100 { searchSessions[i].progress = Double(v) / 100 }
                if v >= 100 && v != 0xFFFF { searchSessions[i].inProgress = false }
            }
            let res = try await client.request(
                ECPacket(.searchResults, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            let items = res.allTags(.searchFile).compactMap(SearchResultItem.parse)
            if !items.isEmpty || !searchSessions[i].inProgress {
                searchSessions[i].results = items.sorted { $0.sources > $1.sources }
            }
        } catch { handle(error) }
    }

    func stopSearch() async {
        do {
            _ = try await client.request(ECPacket(.searchStop))
            if let liveID = liveSearchID,
               let i = searchSessions.firstIndex(where: { $0.id == liveID }) {
                searchSessions[i].inProgress = false
            }
        } catch { handle(error) }
    }

    func closeSearchSession(_ id: UUID) async {
        if id == liveSearchID,
           searchSessions.first(where: { $0.id == id })?.inProgress == true {
            await stopSearch()
        }
        searchSessions.removeAll { $0.id == id }
        if id == liveSearchID { liveSearchID = nil }
        if activeSearchID == id {
            activeSearchID = searchSessions.last?.id
        }
    }

    func downloadResult(_ item: SearchResultItem, category: UInt64 = 0) async {
        guard firstFire("dl-\(hexString(item.hash))") else { return }
        do {
            var tag = ECTag.hash16(.knownfile, item.hash)
            tag.children = [.number(.partfileCat, category)]
            let reply = try await client.request(ECPacket(.downloadSearchResult, tags: [tag]))
            if reply.opcode == .failed {
                lastError = reply.tag(.string)?.stringValue ?? "Download non avviato"
            }
        } catch { handle(error) }
    }

    // MARK: - Servers

    func refreshServers() async {
        do {
            let reply = try await client.request(
                ECPacket(.getServerList, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            servers = reply.allTags(.server).compactMap(ServerItem.parse)
                .sorted { $0.users > $1.users }
        } catch { handle(error) }
    }

    private func serverCommand(_ op: ECOp, _ server: ServerItem?) async {
        do {
            var tags: [ECTag] = []
            if let server {
                tags.append(.ipv4(.server, ip: server.ip, port: server.port))
            }
            let reply = try await client.request(ECPacket(op, tags: tags))
            if reply.opcode == .failed {
                lastError = reply.tag(.string)?.stringValue ?? "Comando server fallito"
            }
            await refreshStats()
            await refreshServers()
        } catch { handle(error) }
    }

    func connectToServer(_ s: ServerItem) async {
        guard firstFire("srv-\(s.id)") else { return }
        await serverCommand(.serverConnect, s)
    }
    func connectToAnyServer() async { await serverCommand(.serverConnect, nil) }
    func disconnectFromServer() async { await serverCommand(.serverDisconnect, nil) }
    func removeServer(_ s: ServerItem) async { await serverCommand(.serverRemove, s) }

    func addServer(address: String, port: String, name: String) async {
        do {
            let reply = try await client.request(ECPacket(.serverAdd, tags: [
                .string(.serverAddress, "\(address.trimmingCharacters(in: .whitespaces)):\(port.trimmingCharacters(in: .whitespaces))"),
                .string(.serverName, name),
            ]))
            if reply.opcode == .failed {
                lastError = reply.tag(.string)?.stringValue ?? "Server non aggiunto"
            }
            await refreshServers()
        } catch { handle(error) }
    }

    func updateServerListFromURL(_ url: String) async {
        do {
            _ = try await client.request(ECPacket(.serverUpdateFromURL, tags: [.string(.string, url)]))
            await refreshServers()
        } catch { handle(error) }
    }

    // ed2k / Kad network controls

    func ed2kConnect() async { await serverCommand(.serverConnect, nil) }
    func kadStart() async {
        do { _ = try await client.request(ECPacket(.kadStart)); await refreshStats() } catch { handle(error) }
    }
    func kadStop() async {
        do { _ = try await client.request(ECPacket(.kadStop)); await refreshStats() } catch { handle(error) }
    }
    func connectAll() async {
        do { _ = try await client.request(ECPacket(.connect)); await refreshStats() } catch { handle(error) }
    }
    func disconnectAll() async {
        do { _ = try await client.request(ECPacket(.disconnect)); await refreshStats() } catch { handle(error) }
    }

    // MARK: - Shared files

    func refreshShared() async {
        do {
            let reply = try await client.request(
                ECPacket(.getSharedFiles, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            sharedFiles = reply.allTags(.knownfile).compactMap(SharedFileItem.parse)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch { handle(error) }
    }

    func reloadSharedFiles() async {
        do {
            _ = try await client.request(ECPacket(.sharedFilesReload))
            await refreshShared()
        } catch { handle(error) }
    }

    func setSharedPriority(_ item: SharedFileItem, _ prio: FilePriority) async {
        do {
            var tag = ECTag.hash16(.knownfile, item.hash)
            tag.children = [.uint8(.knownfilePrio, prio.rawValue)]
            _ = try await client.request(ECPacket(.sharedSetPrio, tags: [tag]))
            await refreshShared()
        } catch { handle(error) }
    }

    // MARK: - Log

    func refreshLog() async {
        do {
            let reply = try await client.request(ECPacket(.getLog))
            let lines = reply.allTags(.string).compactMap(\.stringValue)
            logText = lines.joined()
        } catch { handle(error) }
    }

    func resetLog() async {
        do {
            _ = try await client.request(ECPacket(.resetLog))
            await refreshLog()
        } catch { handle(error) }
    }

    // MARK: - Preferences

    func loadPrefs() async {
        do {
            let reply = try await client.request(ECPacket(.getPreferences, tags: [
                .uint32(.selectPrefs, ECPrefs.all),
                .uint8(.detailLevel, ECDetailLevel.full.rawValue),
            ]))
            prefs = RemotePrefs.parse(reply)
            prefsLoaded = true
        } catch { handle(error) }
    }

    func savePrefs() async {
        do {
            let reply = try await client.request(prefs.buildSetPacket())
            if reply.opcode == .failed {
                lastError = reply.tag(.string)?.stringValue ?? "Salvataggio impostazioni fallito"
            }
            await loadPrefs()
        } catch { handle(error) }
    }

    func shutdownDaemon() async {
        do {
            _ = try await client.request(ECPacket(.shutdown))
        } catch {
            // The daemon may close the socket without replying.
        }
        await disconnect()
    }
}
