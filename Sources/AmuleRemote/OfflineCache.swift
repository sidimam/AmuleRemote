import Foundation

/// Ultimo stato noto del server, salvato su disco (per server) e mostrato
/// quando l'app è "Offline": dopo il periodo di inattività, quando l'app va
/// in background e alla riapertura, prima che la connessione EC sia di nuovo
/// attiva. I volumi sono piccoli (qualche centinaio di righe): basta un JSON
/// nella cartella Caches, senza bisogno di un database.
struct OfflineSnapshot: Codable {
    var savedAt: Date
    var serverVersion: String
    var stats: StatsSnapshot
    var connState: ConnState
    var downloads: [DownloadItem]
    var uploads: [UploadItem]
    var servers: [ServerItem]
    var sharedFiles: [SharedFileItem]
    var logText: String
}

enum OfflineCache {
    private static var directory: URL? {
        // Caches è l'unica cartella persistente ammessa anche su tvOS.
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("AmuleRemote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(server: String) -> URL? {
        let safe = server.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return directory?.appendingPathComponent("snapshot-\(String(safe)).json")
    }

    static func save(_ snapshot: OfflineSnapshot, server: String) {
        guard let url = fileURL(server: server) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func load(server: String) -> OfflineSnapshot? {
        guard let url = fileURL(server: server), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OfflineSnapshot.self, from: data)
    }

    static func delete(server: String) {
        guard let url = fileURL(server: server) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
