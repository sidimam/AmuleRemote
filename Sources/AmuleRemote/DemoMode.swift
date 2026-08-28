// Modalità demo per la revisione App Store (Guideline 2.1(a)) e per provare
// l'app senza un server: inserendo DEMO / DEMO nella schermata di connessione
// l'app si popola con dati di esempio (contenuti liberi: open movie, ISO
// Linux, Project Gutenberg…) e ogni azione viene simulata in locale, senza
// alcuna connessione di rete.
import Foundation

extension AppState {

    /// True se host+password correnti sono le credenziali demo (DEMO/DEMO).
    var isDemoLogin: Bool {
        host.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DEMO"
            && password.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DEMO"
    }

    // MARK: - Entrata / uscita

    func enterDemoMode() {
        demoMode = true
        connected = true
        connecting = false
        lastError = nil
        connectionLostMessage = nil
        serverVersion = "2.3.3 (demo)"

        downloads = DemoData.downloads()
        uploads = DemoData.uploads()
        servers = DemoData.servers()
        sharedFiles = DemoData.sharedFiles()
        stats = DemoData.stats()
        connState = DemoData.connState()
        logText = DemoData.log()
        prefs = DemoData.prefs()
        prefsLoaded = true
        searchSessions = []
        activeSearchID = nil

        markActivity()
        startPolling()          // pollTick() devia su demoTick()
    }

    func exitDemoMode() {
        demoMode = false
        downloads = []
        uploads = []
        servers = []
        sharedFiles = []
        searchSessions = []
        activeSearchID = nil
        stats = StatsSnapshot()
        connState = ConnState()
        logText = ""
        prefsLoaded = false
    }

    // MARK: - Animazione (chiamata dal poll ogni 3 s)

    func demoTick() {
        var dlSum: Double = 0
        for i in downloads.indices {
            var d = downloads[i]
            guard !d.isComplete, !d.isPaused, d.speed > 0 else { continue }
            // Piccola variazione di velocità per un aspetto "vivo".
            let jitter = Double.random(in: 0.85...1.15)
            d.speed = max(30_000, d.speed * jitter)
            d.sizeDone = min(d.sizeFull, d.sizeDone + UInt64(d.speed * 3))
            if d.sizeDone >= d.sizeFull {
                d.status = PartFileStatus.complete.rawValue
                d.speed = 0
            }
            dlSum += d.speed
            downloads[i] = d
        }
        stats.dlSpeed = dlSum
        stats.ulSpeed = max(120_000, stats.ulSpeed * Double.random(in: 0.9...1.1))
        for i in uploads.indices {
            uploads[i].upSpeed = max(40_000, uploads[i].upSpeed * Double.random(in: 0.85...1.15))
            uploads[i].uploadedSession += UInt64(uploads[i].upSpeed * 3)
        }
    }

    // MARK: - Azioni simulate

    func demoPartfileCommand(_ op: ECOp, hash: Data, children: [ECTag]) {
        guard let i = downloads.firstIndex(where: { $0.hash == hash }) else { return }
        switch op {
        case .partfilePause:
            downloads[i].status = PartFileStatus.paused.rawValue
            downloads[i].speed = 0
        case .partfileResume:
            downloads[i].status = PartFileStatus.ready.rawValue
            downloads[i].stopped = false
            if downloads[i].speed <= 0 { downloads[i].speed = Double.random(in: 200_000...900_000) }
        case .partfileStop:
            downloads[i].stopped = true
            downloads[i].speed = 0
        case .partfileDelete:
            downloads.remove(at: i)
        case .partfilePrioSet:
            if let p = children.first?.numberValue { downloads[i].priority = p }
        case .partfileSetCat:
            if let c = children.first?.numberValue { downloads[i].category = c }
        default:
            break
        }
    }

    func demoAddEd2kLink(_ link: String) {
        downloads.append(DemoData.download(seed: 90, name: "Contenuto aggiunto via link eD2k",
                                           size: 350_000_000, done: 0,
                                           speed: 250_000, status: .ready, ageDays: 0))
    }

    func demoStartSearch(text: String, type: ECSearchType) {
        var session = SearchSession(query: text, type: type)
        session.inProgress = true
        searchSessions.append(session)
        activeSearchID = session.id
        let sid = session.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, let i = self.searchSessions.firstIndex(where: { $0.id == sid }) else { return }
            self.searchSessions[i].results = DemoData.searchResults(query: text)
            self.searchSessions[i].inProgress = false
            self.searchSessions[i].progress = 1
        }
    }

    func demoDownloadResult(_ item: SearchResultItem) {
        guard !downloads.contains(where: { $0.hash == item.hash }) else { return }
        var d = DemoData.download(seed: 91, name: item.name, size: item.size, done: 0,
                                  speed: Double.random(in: 150_000...600_000),
                                  status: .ready, ageDays: 0)
        d.hash = item.hash          // così il risultato diventa rosso (in coda)
        d.sources = item.sources
        downloads.append(d)
    }

    func demoServerCommand(_ op: ECOp, _ server: ServerItem?) {
        switch op {
        case .serverConnect:
            let target = server ?? servers.first
            connState.ed2kConnected = true
            connState.serverName = target?.name ?? "Demo Server Alpha"
            connState.serverAddress = target?.address ?? ""
        case .serverDisconnect:
            connState.ed2kConnected = false
            connState.serverName = ""
            connState.serverAddress = ""
        case .serverRemove:
            if let s = server { servers.removeAll { $0.id == s.id } }
        default:
            break
        }
    }

    func demoAddServer(address: String, port: String, name: String) {
        let p = UInt16(port.trimmingCharacters(in: .whitespaces)) ?? 4661
        servers.append(ServerItem(ip: 0xCB0071F0, port: p,
                                  name: name.isEmpty ? address : name,
                                  description: "Aggiunto manualmente (demo)",
                                  users: 0, maxUsers: 0, files: 0, ping: 0,
                                  priority: 1, isStatic: false, version: "", failed: 0))
    }

    func demoKad(start: Bool) {
        connState.kadRunning = start
        connState.kadOK = start
        connState.kadFirewalled = false
    }

    func demoEd2k(connect: Bool) {
        demoServerCommand(connect ? .serverConnect : .serverDisconnect, nil)
    }

    func demoSetSharedPriority(_ item: SharedFileItem, _ prio: FilePriority) {
        if let i = sharedFiles.firstIndex(where: { $0.hash == item.hash }) {
            sharedFiles[i].priority = UInt64(prio.rawValue)
        }
    }

    func demoAppendLogLine(_ line: String) {
        logText += "\(DemoData.timestamp()) \(line)\n"
    }
}

// MARK: - Dati di esempio (contenuti liberi / pubblico dominio)

enum DemoData {

    static func hash(_ seed: UInt8) -> Data {
        Data((0..<16).map { UInt8(truncatingIfNeeded: Int(seed) &* 37 &+ $0 &* 11 &+ 7) })
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    static func download(seed: UInt8, name: String, size: UInt64, done: UInt64,
                         speed: Double, status: PartFileStatus, ageDays: Int,
                         sources: UInt64 = 0) -> DownloadItem {
        DownloadItem(hash: hash(seed), name: name, sizeFull: size, sizeDone: done,
                     sizeXfer: done, speed: speed, status: status.rawValue,
                     partmetID: UInt64(seed), stopped: false,
                     priority: 11, // Auto (normale): EC segnala prio+10 quando è automatica

                     sources: sources, sourcesXfer: min(sources, 3), sourcesA4AF: 0,
                     sourcesNotCurrent: 0, category: 0,
                     ed2kLink: "", lastSeenComplete: 0,
                     firstSeen: Date().addingTimeInterval(-Double(ageDays) * 86_400))
    }

    static func downloads() -> [DownloadItem] {
        [
            download(seed: 1, name: "Big Buck Bunny (2008) open movie 1080p.mkv",
                     size: 725_000_000, done: 304_000_000, speed: 850_000,
                     status: .ready, ageDays: 2, sources: 14),
            download(seed: 2, name: "Sintel (2010) Blender open movie 1080p.mkv",
                     size: 1_180_000_000, done: 920_000_000, speed: 1_250_000,
                     status: .ready, ageDays: 5, sources: 23),
            download(seed: 3, name: "Debian 12.5 netinst amd64.iso",
                     size: 662_000_000, done: 662_000_000, speed: 0,
                     status: .complete, ageDays: 9, sources: 41),
            download(seed: 4, name: "Ubuntu 24.04 LTS desktop amd64.iso",
                     size: 5_800_000_000, done: 700_000_000, speed: 0,
                     status: .paused, ageDays: 1, sources: 35),
            download(seed: 5, name: "LibreOffice 24.2 Guida introduttiva (italiano).pdf",
                     size: 12_400_000, done: 12_400_000, speed: 0,
                     status: .complete, ageDays: 12, sources: 8),
            download(seed: 6, name: "Tears of Steel (2012) open movie 720p.mkv",
                     size: 550_000_000, done: 2_700_000, speed: 0,
                     status: .ready, ageDays: 0, sources: 0),
            download(seed: 7, name: "Wikipedia (it) dump offline 2026-07.zim",
                     size: 3_200_000_000, done: 1_760_000_000, speed: 400_000,
                     status: .ready, ageDays: 4, sources: 11),
        ]
    }

    static func uploads() -> [UploadItem] {
        [
            UploadItem(id: "u1", userName: "LinuxFan88", software: "aMule 2.3.3",
                       fileName: "Debian 12.5 netinst amd64.iso",
                       upSpeed: 210_000, uploadedSession: 48_000_000),
            UploadItem(id: "u2", userName: "openmovie_fan", software: "eMule 0.60d",
                       fileName: "Big Buck Bunny (2008) open movie 1080p.mkv",
                       upSpeed: 145_000, uploadedSession: 112_000_000),
            UploadItem(id: "u3", userName: "BibliotecaDigitale", software: "aMule 2.3.2",
                       fileName: "LibreOffice 24.2 Guida introduttiva (italiano).pdf",
                       upSpeed: 60_000, uploadedSession: 6_500_000),
        ]
    }

    static func servers() -> [ServerItem] {
        [
            // IP riservati alla documentazione (TEST-NET, RFC 5737): mai instradati.
            ServerItem(ip: 0xC6336414, port: 4661, name: "Demo Server Alpha",
                       description: "Server dimostrativo", users: 12_400, maxUsers: 50_000,
                       files: 4_200_000, ping: 35, priority: 1, isStatic: true,
                       version: "17.15", failed: 0),
            ServerItem(ip: 0xC633641E, port: 4661, name: "Demo Server Beta",
                       description: "Server dimostrativo", users: 8_500, maxUsers: 30_000,
                       files: 2_900_000, ping: 48, priority: 1, isStatic: false,
                       version: "17.15", failed: 0),
            ServerItem(ip: 0xCB007105, port: 4661, name: "Demo Server Gamma",
                       description: "Server dimostrativo", users: 3_400, maxUsers: 20_000,
                       files: 1_100_000, ping: 92, priority: 1, isStatic: false,
                       version: "16.57", failed: 1),
            ServerItem(ip: 0xCB00714D, port: 4661, name: "Demo Server Delta",
                       description: "Server dimostrativo", users: 950, maxUsers: 10_000,
                       files: 380_000, ping: 120, priority: 0, isStatic: false,
                       version: "16.57", failed: 3),
        ]
    }

    static func sharedFiles() -> [SharedFileItem] {
        [
            SharedFileItem(hash: hash(20), name: "Debian 12.5 netinst amd64.iso",
                           size: 662_000_000, priority: 5, requests: 12, requestsAll: 340,
                           accepts: 9, acceptsAll: 260, xferred: 48_000_000,
                           xferredAll: 92_000_000_000, ed2kLink: ""),
            SharedFileItem(hash: hash(21), name: "Big Buck Bunny (2008) open movie 1080p.mkv",
                           size: 725_000_000, priority: 5, requests: 6, requestsAll: 150,
                           accepts: 4, acceptsAll: 118, xferred: 112_000_000,
                           xferredAll: 41_000_000_000, ed2kLink: ""),
            SharedFileItem(hash: hash(22), name: "LibreOffice 24.2 Guida introduttiva (italiano).pdf",
                           size: 12_400_000, priority: 1, requests: 2, requestsAll: 75,
                           accepts: 2, acceptsAll: 60, xferred: 6_500_000,
                           xferredAll: 700_000_000, ed2kLink: ""),
        ]
    }

    static func stats() -> StatsSnapshot {
        var s = StatsSnapshot()
        s.dlSpeed = 2_500_000
        s.ulSpeed = 480_000
        s.dlSpeedLimit = 0
        s.ulSpeedLimit = 600
        s.ed2kUsers = 24_500
        s.kadUsers = 3_800_000
        s.ed2kFiles = 4_200_000
        s.kadFiles = 92_000_000
        s.totalSources = 128
        s.uploadQueueLength = 7
        s.totalSent = 152_000_000_000
        s.totalReceived = 890_000_000_000
        s.sharedFileCount = 3
        s.kadNodes = 187
        return s
    }

    static func connState() -> ConnState {
        var c = ConnState()
        c.ed2kConnected = true
        c.ed2kConnecting = false
        c.kadOK = true
        c.kadRunning = true
        c.kadFirewalled = false
        c.ed2kID = 487_512_344          // HighID
        c.serverName = "Demo Server Alpha"
        c.serverAddress = "198.51.100.20:4661"
        return c
    }

    static func log() -> String {
        let t = timestamp()
        return """
        \(t) aMule 2.3.3 (demo) avviato.
        \(t) Caricamento configurazione completato.
        \(t) Connessione a Demo Server Alpha (198.51.100.20:4661)…
        \(t) Connesso a Demo Server Alpha con HighID.
        \(t) Kademlia: avviata, stato OK.
        \(t) Coda download caricata: 7 file.
        \(t) Condivisione: 3 file condivisi.
        """
    }

    static func prefs() -> RemotePrefs {
        var p = RemotePrefs()
        p.nick = "DemoUser"
        p.maxDL = 0
        p.maxUL = 600
        p.tcpPort = 4662
        p.udpPort = 4672
        p.networkED2K = true
        p.networkKad = true
        p.reconnect = true
        p.removeDeadServers = true
        p.deadServerRetries = 3
        p.ichEnabled = true
        p.previewPrio = false
        p.ipfilterLevel = 127
        p.webserverPort = 4711
        p.categories = [
            CategoryItem(index: 0, title: "Tutti", path: "/incoming", comment: "", color: 0, priority: 1),
            CategoryItem(index: 1, title: "Open source", path: "/incoming/oss", comment: "", color: 0x33AA55, priority: 2),
        ]
        return p
    }

    /// Risultati fittizi generati dal testo cercato: tutti riferiti a contenuti
    /// liberi. Il primo coincide con un download completato (verde) e il secondo
    /// con uno in coda (rosso), per mostrare la colorazione dei risultati.
    static func searchResults(query: String) -> [SearchResultItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [SearchResultItem] = [
            // stesso hash del Debian iso completato -> riga VERDE
            SearchResultItem(hash: hash(3), name: "Debian 12.5 netinst amd64.iso",
                             size: 662_000_000, sources: 41, completeSources: 28, alreadyKnown: true),
            // stesso hash di Big Buck Bunny in coda -> riga ROSSA
            SearchResultItem(hash: hash(1), name: "Big Buck Bunny (2008) open movie 1080p.mkv",
                             size: 725_000_000, sources: 14, completeSources: 6, alreadyKnown: true),
            SearchResultItem(hash: hash(40), name: "\(q) — documentario Creative Commons.mp4",
                             size: 890_000_000, sources: 57, completeSources: 21, alreadyKnown: false),
            SearchResultItem(hash: hash(41), name: "\(q) — audiolibro LibriVox (pubblico dominio).mp3",
                             size: 210_000_000, sources: 33, completeSources: 12, alreadyKnown: false),
            SearchResultItem(hash: hash(42), name: "\(q) — ebook Progetto Gutenberg.epub",
                             size: 2_400_000, sources: 25, completeSources: 19, alreadyKnown: false),
            SearchResultItem(hash: hash(43), name: "\(q) — raccolta foto pubblico dominio.zip",
                             size: 145_000_000, sources: 12, completeSources: 4, alreadyKnown: false),
            SearchResultItem(hash: hash(44), name: "\(q) — dataset aperto (CSV).zip",
                             size: 58_000_000, sources: 7, completeSources: 2, alreadyKnown: false),
            SearchResultItem(hash: hash(45), name: "\(q) — manuale utente (italiano).pdf",
                             size: 9_800_000, sources: 4, completeSources: 1, alreadyKnown: false),
        ]
        // Ordina per fonti, come farebbe il server.
        out.sort { $0.sources > $1.sources }
        return out
    }
}
