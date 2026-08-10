import Foundation

// MARK: - Helpers

func formatBytes(_ v: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .binary)
}

func formatSpeed(_ bytesPerSec: Double) -> String {
    if bytesPerSec <= 0 { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .binary) + "/s"
}

func ipString(_ ip: UInt32) -> String {
    "\((ip >> 24) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)"
}

func hexString(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined()
}

// MARK: - Priorities

enum FilePriority: UInt8, CaseIterable, Identifiable {
    case low = 0
    case normal = 1
    case high = 2
    case veryHigh = 3
    case veryLow = 4
    case auto = 5
    case powershare = 6

    var id: UInt8 { rawValue }

    var label: String {
        switch self {
        case .low: return "Bassa"
        case .normal: return "Normale"
        case .high: return "Alta"
        case .veryHigh: return "Release"
        case .veryLow: return "Molto bassa"
        case .auto: return "Automatica"
        case .powershare: return "PowerShare"
        }
    }

    /// EC reports current priority +10 when auto-priority is active.
    static func describe(_ raw: UInt64) -> String {
        let auto = raw >= 10
        let base = auto ? raw - 10 : raw
        let name = FilePriority(rawValue: UInt8(min(base, 6)))?.label ?? "?"
        return auto ? "Auto (\(name.lowercased()))" : name
    }
}

// MARK: - Downloads

enum PartFileStatus: UInt64 {
    case ready = 0
    case empty = 1
    case waitingForHash = 2
    case hashing = 3
    case error = 4
    case insufficient = 5
    case unknown = 6
    case paused = 7
    case completing = 8
    case complete = 9

    var label: String {
        switch self {
        case .ready: return "In download"
        case .empty: return "Vuoto"
        case .waitingForHash: return "In attesa di hash"
        case .hashing: return "Hashing"
        case .error: return "Errore"
        case .insufficient: return "Spazio insufficiente"
        case .unknown: return "Sconosciuto"
        case .paused: return "In pausa"
        case .completing: return "Completamento…"
        case .complete: return "Completato"
        }
    }
}

struct DownloadItem: Identifiable, Hashable {
    var hash: Data
    var name: String
    var sizeFull: UInt64
    var sizeDone: UInt64
    var sizeXfer: UInt64
    var speed: Double
    var status: UInt64
    /// Progressive NNN.part number: higher = added more recently.
    var partmetID: UInt64
    var stopped: Bool
    var priority: UInt64
    var sources: UInt64
    var sourcesXfer: UInt64
    var sourcesA4AF: UInt64
    var sourcesNotCurrent: UInt64
    var category: UInt64
    var ed2kLink: String
    var lastSeenComplete: UInt64

    var id: Data { hash }

    var progress: Double {
        sizeFull > 0 ? Double(sizeDone) / Double(sizeFull) : 0
    }

    var statusLabel: String {
        if stopped { return "Fermato" }
        let st = PartFileStatus(rawValue: status)?.label ?? "Sconosciuto"
        if status == 0 && speed <= 0 { return "In attesa" }
        return st
    }

    var isPaused: Bool { status == PartFileStatus.paused.rawValue || stopped }
    var isComplete: Bool { status == PartFileStatus.complete.rawValue }

    /// Estimated seconds remaining, or nil when not downloading.
    var etaSeconds: Double? {
        guard speed > 0, sizeFull > sizeDone else { return nil }
        return Double(sizeFull - sizeDone) / speed
    }

    var etaLabel: String {
        guard let eta = etaSeconds else { return isComplete ? "" : "∞" }
        let f = DateComponentsFormatter()
        f.allowedUnits = eta >= 3600 ? [.hour, .minute] : [.minute, .second]
        f.unitsStyle = .abbreviated
        return f.string(from: eta) ?? "—"
    }

    static func parse(_ tag: ECTag) -> DownloadItem? {
        var hash = tag.hashValue16
        if hash == nil { hash = tag.child(.partfileHash)?.hashValue16 }
        guard let hash else { return nil }
        return DownloadItem(
            hash: hash,
            name: tag.childString(.partfileName) ?? "?",
            sizeFull: tag.childNumber(.partfileSizeFull) ?? 0,
            sizeDone: tag.childNumber(.partfileSizeDone) ?? 0,
            sizeXfer: tag.childNumber(.partfileSizeXfer) ?? 0,
            speed: Double(tag.childNumber(.partfileSpeed) ?? 0),
            status: tag.childNumber(.partfileStatus) ?? 6,
            partmetID: tag.childNumber(.partfilePartmetID) ?? 0,
            stopped: (tag.childNumber(.partfileStopped) ?? 0) != 0,
            priority: tag.childNumber(.partfilePrio) ?? 1,
            sources: tag.childNumber(.partfileSourceCount) ?? 0,
            sourcesXfer: tag.childNumber(.partfileSourceCountXfer) ?? 0,
            sourcesA4AF: tag.childNumber(.partfileSourceCountA4AF) ?? 0,
            sourcesNotCurrent: tag.childNumber(.partfileSourceCountNotCurrent) ?? 0,
            category: tag.childNumber(.partfileCat) ?? 0,
            ed2kLink: tag.childString(.partfileED2KLink) ?? "",
            lastSeenComplete: tag.childNumber(.partfileLastSeenComp) ?? 0
        )
    }
}

// MARK: - Uploads

struct UploadItem: Identifiable, Hashable {
    var id: String
    var userName: String
    var software: String
    var fileName: String
    var upSpeed: Double
    var uploadedSession: UInt64

    static func parse(_ tag: ECTag, index: Int) -> UploadItem {
        let name = tag.childString(.clientName) ?? "?"
        let hashPart = tag.child(.clientHash)?.hashValue16.map(hexString) ?? "\(index)"
        return UploadItem(
            id: hashPart + name,
            userName: name,
            software: tag.childString(.clientSoftVerStr) ?? "",
            fileName: tag.childString(.clientUploadFile) ?? tag.child(.clientUploadFile)?.hashValue16.map(hexString) ?? "",
            upSpeed: Double(tag.childNumber(.clientUpSpeed) ?? 0),
            uploadedSession: tag.childNumber(.clientUploadSession) ?? 0
        )
    }
}

// MARK: - Search

struct SearchResultItem: Identifiable, Hashable {
    var hash: Data
    var name: String
    var size: UInt64
    var sources: UInt64
    var completeSources: UInt64
    var alreadyKnown: Bool

    var id: Data { hash }

    static func parse(_ tag: ECTag) -> SearchResultItem? {
        var hash = tag.child(.partfileHash)?.hashValue16
        if hash == nil { hash = tag.hashValue16 }
        guard let hash else { return nil }
        return SearchResultItem(
            hash: hash,
            name: tag.childString(.partfileName) ?? "?",
            size: tag.childNumber(.partfileSizeFull) ?? 0,
            sources: tag.childNumber(.partfileSourceCount) ?? 0,
            completeSources: tag.childNumber(.partfileSourceCountXfer) ?? 0,
            alreadyKnown: (tag.childNumber(.knownfileOnQueue) ?? 0) != 0
        )
    }
}

/// One search "tab": results are cached client-side, so old tabs survive
/// even though the daemon only runs the most recent search.
struct SearchSession: Identifiable, Equatable {
    let id = UUID()
    var query: String
    var type: ECSearchType
    var results: [SearchResultItem] = []
    var inProgress = false
    var progress: Double = 0
}

// MARK: - Servers

struct ServerItem: Identifiable, Hashable {
    var ip: UInt32
    var port: UInt16
    var name: String
    var description: String
    var users: UInt64
    var maxUsers: UInt64
    var files: UInt64
    var ping: UInt64
    var priority: UInt64
    var isStatic: Bool
    var version: String
    var failed: UInt64

    var id: String { "\(ip):\(port)" }
    var address: String { "\(ipString(ip)):\(port)" }

    static func parse(_ tag: ECTag) -> ServerItem? {
        guard let addr = tag.ipv4Value else { return nil }
        return ServerItem(
            ip: addr.ip,
            port: addr.port,
            name: tag.childString(.serverName) ?? ipString(addr.ip),
            description: tag.childString(.serverDesc) ?? "",
            users: tag.childNumber(.serverUsers) ?? 0,
            maxUsers: tag.childNumber(.serverUsersMax) ?? 0,
            files: tag.childNumber(.serverFiles) ?? 0,
            ping: tag.childNumber(.serverPing) ?? 0,
            priority: tag.childNumber(.serverPrio) ?? 1,
            isStatic: (tag.childNumber(.serverStatic) ?? 0) != 0,
            version: tag.childString(.serverVersion) ?? "",
            failed: tag.childNumber(.serverFailed) ?? 0
        )
    }
}

// MARK: - Shared files

struct SharedFileItem: Identifiable, Hashable {
    var hash: Data
    var name: String
    var size: UInt64
    var priority: UInt64
    var requests: UInt64
    var requestsAll: UInt64
    var accepts: UInt64
    var acceptsAll: UInt64
    var xferred: UInt64
    var xferredAll: UInt64
    var ed2kLink: String

    var id: Data { hash }

    static func parse(_ tag: ECTag) -> SharedFileItem? {
        var hash = tag.hashValue16
        if hash == nil { hash = tag.child(.partfileHash)?.hashValue16 }
        guard let hash else { return nil }
        return SharedFileItem(
            hash: hash,
            // PARTFILE_NAME is the display name; KNOWNFILE_FILENAME is the
            // on-disk path/filename ("/incoming", "002.part") — wrong for UI.
            name: tag.childString(.partfileName) ?? tag.childString(.knownfileFilename) ?? "?",
            size: tag.childNumber(.partfileSizeFull) ?? 0,
            priority: tag.childNumber(.knownfilePrio) ?? 1,
            requests: tag.childNumber(.knownfileReqCount) ?? 0,
            requestsAll: tag.childNumber(.knownfileReqCountAll) ?? 0,
            accepts: tag.childNumber(.knownfileAcceptCount) ?? 0,
            acceptsAll: tag.childNumber(.knownfileAcceptCountAll) ?? 0,
            xferred: tag.childNumber(.knownfileXferred) ?? 0,
            xferredAll: tag.childNumber(.knownfileXferredAll) ?? 0,
            ed2kLink: tag.childString(.partfileED2KLink) ?? ""
        )
    }
}

// MARK: - Stats / connection state

struct StatsSnapshot {
    var ulSpeed: Double = 0
    var dlSpeed: Double = 0
    var ulSpeedLimit: UInt64 = 0
    var dlSpeedLimit: UInt64 = 0
    var ed2kUsers: UInt64 = 0
    var kadUsers: UInt64 = 0
    var ed2kFiles: UInt64 = 0
    var kadFiles: UInt64 = 0
    var totalSources: UInt64 = 0
    var bannedCount: UInt64 = 0
    var uploadQueueLength: UInt64 = 0
    var totalSent: UInt64 = 0
    var totalReceived: UInt64 = 0
    var sharedFileCount: UInt64 = 0
    var kadNodes: UInt64 = 0
    var upOverhead: UInt64 = 0
    var downOverhead: UInt64 = 0

    static func parse(_ p: ECPacket) -> StatsSnapshot {
        var s = StatsSnapshot()
        s.ulSpeed = Double(p.tag(.statsULSpeed)?.numberValue ?? 0)
        s.dlSpeed = Double(p.tag(.statsDLSpeed)?.numberValue ?? 0)
        s.ulSpeedLimit = p.tag(.statsULSpeedLimit)?.numberValue ?? 0
        s.dlSpeedLimit = p.tag(.statsDLSpeedLimit)?.numberValue ?? 0
        s.ed2kUsers = p.tag(.statsED2KUsers)?.numberValue ?? 0
        s.kadUsers = p.tag(.statsKadUsers)?.numberValue ?? 0
        s.ed2kFiles = p.tag(.statsED2KFiles)?.numberValue ?? 0
        s.kadFiles = p.tag(.statsKadFiles)?.numberValue ?? 0
        s.totalSources = p.tag(.statsTotalSrcCount)?.numberValue ?? 0
        s.bannedCount = p.tag(.statsBannedCount)?.numberValue ?? 0
        s.uploadQueueLength = p.tag(.statsULQueueLen)?.numberValue ?? 0
        s.totalSent = p.tag(.statsTotalSentBytes)?.numberValue ?? 0
        s.totalReceived = p.tag(.statsTotalReceivedBytes)?.numberValue ?? 0
        s.sharedFileCount = p.tag(.statsSharedFileCount)?.numberValue ?? 0
        s.kadNodes = p.tag(.statsKadNodes)?.numberValue ?? 0
        s.upOverhead = p.tag(.statsUpOverhead)?.numberValue ?? 0
        s.downOverhead = p.tag(.statsDownOverhead)?.numberValue ?? 0
        return s
    }
}

struct ConnState {
    var ed2kConnected = false
    var ed2kConnecting = false
    var kadOK = false
    var kadFirewalled = false
    var kadRunning = false
    var ed2kID: UInt64 = 0
    var clientID: UInt64 = 0
    var serverName: String = ""
    var serverAddress: String = ""

    var lowID: Bool { ed2kConnected && ed2kID < 16777216 }

    var ed2kLabel: String {
        if ed2kConnected {
            let idKind = lowID ? "LowID" : "HighID"
            return serverName.isEmpty ? "Connesso (\(idKind))" : "\(serverName) (\(idKind))"
        }
        if ed2kConnecting { return "Connessione…" }
        return "Disconnesso"
    }

    var kadLabel: String {
        if !kadRunning { return "Fermo" }
        if kadOK { return kadFirewalled ? "Connesso (firewalled)" : "Connesso (OK)" }
        return "In connessione…"
    }

    static func parse(_ p: ECPacket) -> ConnState {
        var c = ConnState()
        guard let tag = p.tag(.connState) else { return c }
        let v = tag.numberValue ?? 0
        c.ed2kConnected = v & 0x01 != 0
        c.ed2kConnecting = v & 0x02 != 0
        c.kadOK = v & 0x04 != 0
        c.kadFirewalled = v & 0x08 != 0
        c.kadRunning = v & 0x10 != 0
        c.ed2kID = tag.childNumber(.ed2kID) ?? 0
        c.clientID = tag.childNumber(.clientID) ?? 0
        if let server = tag.child(.server) {
            c.serverName = server.childString(.serverName) ?? ""
            if let addr = server.ipv4Value {
                c.serverAddress = "\(ipString(addr.ip)):\(addr.port)"
            }
        }
        return c
    }
}

// MARK: - Categories

struct CategoryItem: Identifiable, Hashable {
    var index: UInt64
    var title: String
    var path: String
    var comment: String
    var color: UInt64
    var priority: UInt64

    var id: UInt64 { index }
}
