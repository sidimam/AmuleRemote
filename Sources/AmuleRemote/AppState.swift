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

    // Profili server (default = quello proposto all'avvio e usato in background).
    @Published var profiles: [ServerProfile] { didSet { ProfileStore.save(profiles) } }
    @Published var defaultProfileID: UUID? { didSet { ProfileStore.defaultID = defaultProfileID } }

    // Aspetto: chiaro / scuro / sistema.
    @Published var themeMode: ThemeMode { didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "themeMode") } }

    // Lingua: di sistema o forzata (cambio live per la UI, completo al riavvio).
    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appLanguage")
            appLanguage.applySystemOverride()
        }
    }

    // Blocco biometrico (Face ID / Touch ID) opzionale.
    @Published var biometricLockEnabled: Bool { didSet { UserDefaults.standard.set(biometricLockEnabled, forKey: "biometricLock") } }
    @Published var locked = false

    // Notifiche
    @Published var notifyDownloadsEnabled: Bool { didSet { UserDefaults.standard.set(notifyDownloadsEnabled, forKey: "notifyDownloads") } }
    @Published var notifyNetworkEnabled: Bool { didSet { UserDefaults.standard.set(notifyNetworkEnabled, forKey: "notifyNetwork") } }
    @Published var backgroundChecksEnabled: Bool { didSet { UserDefaults.standard.set(backgroundChecksEnabled, forKey: "backgroundChecks") } }

    // Connection state
    @Published var connected = false
    @Published var connecting = false
    // Modalità demo (login DEMO/DEMO): dati di esempio, nessuna rete.
    @Published var demoMode = false
    @Published var serverVersion = ""
    @Published var lastError: String?
    // Shown as a banner on the connection screen when the server drops the
    // connection (e.g. amuled stopped) — instead of a raw network-error alert.
    @Published var connectionLostMessage: String?

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
                    // Il monitoraggio continua anche da disconnessi: controlli
                    // periodici leggeri con notifiche di completamenti e cadute.
                    self.startOfflineMonitor()
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
        themeMode = ThemeMode(rawValue: defaults.string(forKey: "themeMode") ?? "") ?? .system
        appLanguage = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .system
        biometricLockEnabled = defaults.bool(forKey: "biometricLock")
        notifyDownloadsEnabled = defaults.object(forKey: "notifyDownloads") as? Bool ?? true
        notifyNetworkEnabled = defaults.object(forKey: "notifyNetwork") as? Bool ?? true
        backgroundChecksEnabled = defaults.object(forKey: "backgroundChecks") as? Bool ?? true
        profiles = ProfileStore.load()
        defaultProfileID = ProfileStore.defaultID

        // Migrazione: il server già configurato nelle build precedenti diventa
        // il primo profilo (e quello predefinito).
        if profiles.isEmpty && !host.isEmpty && host.uppercased() != "DEMO" {
            let p = ServerProfile(name: host, host: host, port: port)
            profiles = [p]
            defaultProfileID = p.id
        }
        // All'avvio comanda il profilo predefinito, se esiste.
        if let def = profiles.first(where: { $0.id == defaultProfileID }) {
            host = def.host
            port = def.port
        }

        locked = biometricLockEnabled

        if !host.isEmpty {
            password = Keychain.loadPassword(account: "\(host):\(port)") ?? ""
        }
        // Con il blocco attivo la connessione automatica parte dopo lo sblocco.
        if !locked && autoConnect && !host.isEmpty && !password.isEmpty {
            Task { await connect() }
        }
    }

    // MARK: - Profili

    /// Il profilo che corrisponde ai valori di connessione correnti (se esiste).
    var currentProfile: ServerProfile? {
        profiles.first { $0.host == host && $0.port == port }
    }

    /// Carica host/porta/password di un profilo nei campi correnti (senza connettere).
    func applyProfile(_ p: ServerProfile) {
        host = p.host
        port = p.port
        password = Keychain.loadPassword(account: p.address) ?? ""
    }

    /// Cambio rapido: disconnette dal server corrente e connette al profilo scelto.
    func switchProfile(to p: ServerProfile) async {
        if connected || demoMode { await disconnect() }
        applyProfile(p)
        if !password.isEmpty {
            await connect()
        }
    }

    func upsertProfile(_ p: ServerProfile) {
        if let i = profiles.firstIndex(where: { $0.id == p.id }) {
            profiles[i] = p
        } else {
            profiles.append(p)
        }
        if defaultProfileID == nil { defaultProfileID = p.id }
    }

    func deleteProfile(_ p: ServerProfile) {
        profiles.removeAll { $0.id == p.id }
        if defaultProfileID == p.id { defaultProfileID = profiles.first?.id }
    }

    func setDefaultProfile(_ p: ServerProfile) {
        defaultProfileID = p.id
    }

    // MARK: - Link ed2k:// aperti dal sistema

    /// Link ed2k ricevuto da un clic esterno (Safari, Mail…), in attesa di
    /// conferma dall'utente prima di essere accodato.
    @Published var pendingEd2kLink: String?

    func handleIncomingURL(_ url: URL) {
        let s = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        guard s.lowercased().hasPrefix("ed2k://") else { return }
        pendingEd2kLink = s
    }

    /// Nome file leggibile da un link ed2k://|file|nome|size|hash|/
    nonisolated static func ed2kLinkName(_ link: String) -> String {
        let parts = link.split(separator: "|")
        return parts.count > 2 ? String(parts[2]) : link
    }

    /// Conferma del link in attesa: connette se serve, poi accoda.
    func confirmPendingEd2kLink() async {
        guard let link = pendingEd2kLink else { return }
        pendingEd2kLink = nil
        if !connected {
            await connect()
        }
        guard connected else { return }
        await addEd2kLink(link)
    }

    /// Dopo una connessione riuscita, un server nuovo entra da solo nei profili.
    private func autoCreateProfileIfNeeded() {
        guard currentProfile == nil, !host.isEmpty else { return }
        let p = ServerProfile(name: host, host: host, port: port)
        profiles.append(p)
        if defaultProfileID == nil { defaultProfileID = p.id }
    }

    // MARK: - Blocco biometrico

    func unlock() async {
        guard locked else { return }
        guard await BiometricAuth.authenticate(reason: "Sblocca aMule Remote") else { return }
        locked = false
        if autoConnect && !connected && !host.isEmpty && !password.isEmpty {
            await connect()
        }
    }

    func lockNow() {
        if biometricLockEnabled { locked = true }
    }

    /// Attiva/disattiva il blocco: entrambe le direzioni richiedono
    /// un'autenticazione riuscita, così nessuno può spegnerlo al posto tuo.
    func setBiometricLock(_ enabled: Bool) async {
        guard enabled != biometricLockEnabled else { return }
        let reason = enabled
            ? "Attiva il blocco di aMule Remote"
            : "Disattiva il blocco di aMule Remote"
        guard await BiometricAuth.authenticate(reason: reason) else { return }
        biometricLockEnabled = enabled
        if !enabled { locked = false }
    }

    // MARK: - Connection

    func connect() async {
        guard !connecting else { return }
        // Trim stray spaces/newlines from the host (a leading space pasted into
        // the field makes DNS resolution fail with NWError -65554 NoSuchRecord).
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // Credenziali demo per la revisione App Store e per provare l'app
        // senza un server: tutto simulato in locale, nessuna connessione.
        if isDemoLogin {
            enterDemoMode()
            return
        }
        connecting = true
        lastError = nil
        connectionLostMessage = nil
        do {
            try await client.connect(host: host, port: UInt16(clamping: port), password: password)
            serverVersion = await client.serverVersion
            connected = true
            stopOfflineMonitor()
            lastNetState = nil
            Keychain.savePassword(password, account: "\(host):\(port)")
            autoCreateProfileIfNeeded()
            loadCompletedCache()
            loadFirstSeen()
            markActivity()
            startPolling()
            startIdleWatcher()
            await refreshAll()
            await Notifier.requestPermission()
            pushWatchSnapshot()
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
        stopOfflineMonitor()
        if demoMode {
            exitDemoMode()
        } else {
            await client.disconnectNow()
        }
        connected = false
        serverVersion = ""
        lastNetState = nil
        pushWatchSnapshot()
    }

    // MARK: - Monitor offline (iOS)
    // Dopo la disconnessione per inattività l'app continua a controllare il
    // server una volta al minuto (finché resta in foreground) e a notificare
    // download completati e cadute di rete. In background subentra il
    // Background App Refresh (BackgroundRefresh.swift).
    private var offlineMonitorTask: Task<Void, Never>?

    func startOfflineMonitor() {
        #if os(iOS)
        guard backgroundChecksEnabled, !demoMode, !host.isEmpty, !password.isEmpty else { return }
        let h = host, p = port, pw = password
        offlineMonitorTask?.cancel()
        offlineMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, !self.connected else { return }
                await BackgroundMonitor.checkOnce(host: h, port: p, password: pw,
                                                  notifyDownloads: self.notifyDownloadsEnabled,
                                                  notifyNetwork: self.notifyNetworkEnabled)
            }
        }
        #endif
    }

    func stopOfflineMonitor() {
        offlineMonitorTask?.cancel()
        offlineMonitorTask = nil
    }

    // MARK: - Snapshot per Apple Watch

    /// Pubblica lo stato corrente sull'Apple Watch (solo iOS; no-op su macOS).
    func pushWatchSnapshot() {
        #if os(iOS)
        let items: [[String: Any]] = downloads.prefix(20).map {
            ["n": $0.name, "p": $0.progress, "s": $0.speed, "c": $0.isComplete]
        }
        let payload: [String: Any] = [
            "connected": connected,
            "profile": currentProfile?.name ?? (demoMode ? "Demo" : host),
            "dl": stats.dlSpeed,
            "ul": stats.ulSpeed,
            "ed2k": connState.ed2kConnected,
            "kad": connState.kadOK,
            "items": items,
        ]
        WatchBridge.shared.push(payload)
        #endif
    }

    private func handle(_ error: Error) {
        // Already showing the "server stopped" banner: ignore the follow-up
        // errors from other in-flight requests in the same failure cascade.
        if connectionLostMessage != nil { return }

        // Distinguish a real network/socket drop (server stopped) from a
        // one-off protocol/parse error on a single reply. Parse errors keep the
        // stream aligned (we already consumed the framed bytes), so they must
        // NOT tear down an otherwise healthy session.
        let isNetworkDrop: Bool
        if let ec = error as? ECError {
            let m = ec.message
            isNetworkDrop = m.contains("Connessione chiusa")
                || m.contains("Non connesso")
                || m.contains("Timeout")
                || m.contains("non raggiungibile")
        } else {
            let ns = error as NSError
            isNetworkDrop = ns.domain == "NWErrorDomain"
                || ns.domain == NSPOSIXErrorDomain
                || ns.domain == (kCFErrorDomainCFNetwork as String)
        }

        if isNetworkDrop, connected {
            connectionLostMessage = "Server interrotto: la connessione al server aMule è stata chiusa."
            Task { await disconnect() }
        } else if !connected {
            lastError = error.localizedDescription
        }
        // A parse error while still connected is ignored: the next poll retries.
    }

    func startPolling() {
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
        if demoMode { demoTick(); return }
        await refreshStats()
        await refreshDownloads()
        if selectedSection == .downloads { await refreshUploads() }
        if searchSessions.contains(where: { $0.inProgress }) { await refreshSearch() }
        if selectedSection == .log { await refreshLog() }
        pushWatchSnapshot()
    }

    func refreshAll() async {
        await refreshStats()
        await refreshDownloads()
        await refreshServers()
    }

    // MARK: - Stats

    func refreshStats() async {
        if demoMode { return }
        do {
            let statsReply = try await client.request(
                ECPacket(.statReq, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            stats = StatsSnapshot.parse(statsReply)

            let connReply = try await client.request(
                ECPacket(.getConnState, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            connState = ConnState.parse(connReply)
            notifyNetworkTransitions()
        } catch {
            handle(error)
        }
    }

    // Ultimo stato delle reti visto in QUESTA sessione, per rilevare le
    // transizioni connesso → disconnesso (mai notificare lo stato iniziale).
    private var lastNetState: (ed2k: Bool, kad: Bool)?

    private func notifyNetworkTransitions() {
        let current = (ed2k: connState.ed2kConnected, kad: connState.kadOK)
        defer {
            lastNetState = current
            // Persistito anche per i controlli in background.
            Notifier.recordNetState(server: "\(host):\(port)", ed2k: current.ed2k, kad: current.kad)
        }
        guard notifyNetworkEnabled, let prev = lastNetState else { return }
        if prev.ed2k && !current.ed2k {
            Notifier.post(id: "ed2k-drop", title: "eD2k disconnesso",
                          body: "\(host) non è più connesso alla rete eD2k.")
        }
        if prev.kad && !current.kad {
            Notifier.post(id: "kad-drop", title: "Kad disconnesso",
                          body: "\(host) non è più connesso alla rete Kad.")
        }
    }

    // MARK: - Downloads

    // The daemon drops finished files from its queue; like aMuleGUI we keep
    // them visible client-side until the user clicks "Rimuovi completati".
    // Persisted to disk (per server) so they survive app relaunches on iOS.
    private var completedCache: [Data: DownloadItem] = [:]

    /// Whether a search result hash is already downloading or was downloaded.
    /// Used to colour search rows (red = in transfer, green = already done).
    func matchState(for hash: Data) -> SearchMatch {
        if completedCache[hash] != nil { return .completed }
        if let item = downloads.first(where: { $0.hash == hash }) {
            return item.isComplete ? .completed : .downloading
        }
        return .none
    }
    // Last progress seen for every hash, to detect completion even when a fast
    // download vanishes from the queue between two polls without ever being
    // observed at 100%.
    private var lastProgress: [Data: Double] = [:]

    // Prima volta che l'app ha visto ogni file nella coda download (per server),
    // per stimarne l'età. amuled non espone la data di inizio via EC.
    private var firstSeen: [Data: Date] = [:]

    private var completedKey: String { "completed-\(host):\(port)" }
    private var firstSeenKey: String { "firstseen-\(host):\(port)" }

    private func loadFirstSeen() {
        firstSeen.removeAll()
        guard let data = UserDefaults.standard.data(forKey: firstSeenKey),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else { return }
        for (hex, epoch) in dict {
            if let h = dataFromHex(hex) { firstSeen[h] = Date(timeIntervalSince1970: epoch) }
        }
    }

    private func saveFirstSeen() {
        var dict: [String: Double] = [:]
        for (h, d) in firstSeen { dict[hexString(h)] = d.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: firstSeenKey)
        }
    }

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
        if demoMode { return }
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

            // Snapshot persistito per i controlli in background (nome incluso,
            // per il testo delle notifiche di completamento).
            var bgEntries: [String: Notifier.QueueEntry] = [:]
            for f in fresh {
                let hex = hexString(f.hash)
                bgEntries[hex] = .init(p: max(f.progress, lastProgress[f.hash] ?? 0), n: f.name)
            }
            Notifier.recordQueue(server: "\(host):\(port)", entries: bgEntries)

            // Track first-seen date per hash (download age). New files get "now";
            // files that left the queue are forgotten.
            let now = Date()
            for h in freshHashes where firstSeen[h] == nil { firstSeen[h] = now }
            for h in Array(firstSeen.keys) where !freshHashes.contains(h) { firstSeen.removeValue(forKey: h) }
            saveFirstSeen()

            // If the daemon still reports a file, its live row wins.
            for h in freshHashes { completedCache.removeValue(forKey: h) }
            saveCompletedCache()

            let freshWithAge = fresh.map { item -> DownloadItem in
                var i = item; i.firstSeen = firstSeen[item.hash]; return i
            }
            downloads = (freshWithAge + completedCache.values)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            handle(error)
        }
    }

    func refreshUploads() async {
        if demoMode { return }
        do {
            let reply = try await client.request(
                ECPacket(.getUloadQueue, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            uploads = reply.allTags(.client).enumerated().map { UploadItem.parse($0.element, index: $0.offset) }
        } catch {
            handle(error)
        }
    }

    /// Local notification on download completion; iOS mirrors it to Apple Watch.
    /// Il registro per-server evita doppioni tra polling in foreground e
    /// controlli in background sullo stesso completamento.
    private func notifyDownloadCompleted(_ item: DownloadItem) {
        let hex = hexString(item.hash)
        guard Notifier.markCompletedOnce(server: "\(host):\(port)", hashHex: hex) else { return }
        guard notifyDownloadsEnabled else { return }
        Notifier.post(id: "dl-\(hex)", title: "Download completato ✅", body: item.name)
    }

    private func partfileCommand(_ op: ECOp, hash: Data, children: [ECTag] = []) async {
        if demoMode { demoPartfileCommand(op, hash: hash, children: children); return }
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
        if demoMode { return }
        do {
            _ = try await client.request(ECPacket(.clearCompleted))
            await refreshDownloads()
        } catch { handle(error) }
    }

    func addEd2kLink(_ link: String, category: UInt64 = 0) async {
        if demoMode { demoAddEd2kLink(link); return }
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
        if demoMode { demoStartSearch(text: text, type: type); return }
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
        guard let liveID = liveSearchID else { return }
        // Re-resolve the session by ID after every await: the array can change
        // (tab closed, new search started) while a request is in flight, so a
        // cached index would go out of range. Returns nil if it's gone.
        func indexOfLive() -> Int? { searchSessions.firstIndex { $0.id == liveID } }

        guard let start = indexOfLive(), searchSessions[start].inProgress else { return }
        do {
            let prog = try await client.request(ECPacket(.searchProgress))
            if let i = indexOfLive(), let v = prog.tag(.searchStatus)?.numberValue {
                // 0xffff = progress unknown (Kad); 100 = finished
                if v <= 100 { searchSessions[i].progress = Double(v) / 100 }
                if v >= 100 && v != 0xFFFF { searchSessions[i].inProgress = false }
            }
            let res = try await client.request(
                ECPacket(.searchResults, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            let items = res.allTags(.searchFile).compactMap(SearchResultItem.parse)
            if let i = indexOfLive(), !items.isEmpty || !searchSessions[i].inProgress {
                searchSessions[i].results = items.sorted { $0.sources > $1.sources }
            }
        } catch { handle(error) }
    }

    func stopSearch() async {
        if demoMode {
            for i in searchSessions.indices { searchSessions[i].inProgress = false }
            return
        }
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
        if demoMode { demoDownloadResult(item); return }
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
        if demoMode { return }
        do {
            let reply = try await client.request(
                ECPacket(.getServerList, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            servers = reply.allTags(.server).compactMap(ServerItem.parse)
                .sorted { $0.users > $1.users }
        } catch { handle(error) }
    }

    private func serverCommand(_ op: ECOp, _ server: ServerItem?) async {
        if demoMode { demoServerCommand(op, server); return }
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
        if demoMode { demoAddServer(address: address, port: port, name: name); return }
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
        if demoMode { demoAppendLogLine("Lista server aggiornata da \(url) (demo)."); return }
        do {
            _ = try await client.request(ECPacket(.serverUpdateFromURL, tags: [.string(.string, url)]))
            await refreshServers()
        } catch { handle(error) }
    }

    // ed2k / Kad network controls

    func ed2kConnect() async { await serverCommand(.serverConnect, nil) }
    func kadStart() async {
        if demoMode { demoKad(start: true); return }
        do { _ = try await client.request(ECPacket(.kadStart)); await refreshStats() } catch { handle(error) }
    }
    func kadStop() async {
        if demoMode { demoKad(start: false); return }
        do { _ = try await client.request(ECPacket(.kadStop)); await refreshStats() } catch { handle(error) }
    }
    func connectAll() async {
        if demoMode { demoEd2k(connect: true); demoKad(start: true); return }
        do { _ = try await client.request(ECPacket(.connect)); await refreshStats() } catch { handle(error) }
    }
    func disconnectAll() async {
        if demoMode { demoEd2k(connect: false); demoKad(start: false); return }
        do { _ = try await client.request(ECPacket(.disconnect)); await refreshStats() } catch { handle(error) }
    }

    // MARK: - Shared files

    func refreshShared() async {
        if demoMode { return }
        do {
            let reply = try await client.request(
                ECPacket(.getSharedFiles, tags: [.uint8(.detailLevel, ECDetailLevel.web.rawValue)]))
            sharedFiles = reply.allTags(.knownfile).compactMap(SharedFileItem.parse)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch { handle(error) }
    }

    func reloadSharedFiles() async {
        if demoMode { return }
        do {
            _ = try await client.request(ECPacket(.sharedFilesReload))
            await refreshShared()
        } catch { handle(error) }
    }

    func setSharedPriority(_ item: SharedFileItem, _ prio: FilePriority) async {
        if demoMode { demoSetSharedPriority(item, prio); return }
        do {
            var tag = ECTag.hash16(.knownfile, item.hash)
            tag.children = [.uint8(.knownfilePrio, prio.rawValue)]
            _ = try await client.request(ECPacket(.sharedSetPrio, tags: [tag]))
            await refreshShared()
        } catch { handle(error) }
    }

    // MARK: - Log

    func refreshLog() async {
        if demoMode { return }
        do {
            let reply = try await client.request(ECPacket(.getLog))
            let lines = reply.allTags(.string).compactMap(\.stringValue)
            logText = lines.joined()
        } catch { handle(error) }
    }

    func resetLog() async {
        if demoMode {
            logText = ""
            demoAppendLogLine("Log azzerato.")
            return
        }
        do {
            _ = try await client.request(ECPacket(.resetLog))
            await refreshLog()
        } catch { handle(error) }
    }

    // MARK: - Preferences

    func loadPrefs() async {
        if demoMode { prefsLoaded = true; return }
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
        if demoMode { return }   // le modifiche restano visibili in locale
        do {
            let reply = try await client.request(prefs.buildSetPacket())
            if reply.opcode == .failed {
                lastError = reply.tag(.string)?.stringValue ?? "Salvataggio impostazioni fallito"
            }
            await loadPrefs()
        } catch { handle(error) }
    }

    func shutdownDaemon() async {
        if demoMode { await disconnect(); return }
        do {
            _ = try await client.request(ECPacket(.shutdown))
        } catch {
            // The daemon may close the socket without replying.
        }
        await disconnect()
    }
}
