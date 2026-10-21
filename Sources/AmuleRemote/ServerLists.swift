import Foundation
import Combine

// Elenchi server (server.met): fonti affidabili curate + URL personalizzati,
// scaricati e letti DALL'APP (così funziona anche se amuled non ha accesso al
// web e si vede l'anteprima prima di importare), poi aggiunti ad amuled con
// EC_OP_SERVER_ADD uno per uno. In alternativa «Fai scaricare al server»
// passa l'URL ad amuled (EC_OP_SERVER_UPDATE_FROM_URL).

/// Una fonte di server.met (curata o aggiunta dall'utente).
struct ServerListSource: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    var note: String?
    /// Vero per gli URL inseriti dall'utente («Le mie fonti»).
    var custom: Bool = false

    var urlValue: URL? { URL(string: url) }
}

/// Catalogo pubblicato su GitHub Pages: si aggiorna senza una nuova release.
struct ServerListCatalog: Codable {
    var updated: String
    var sources: [ServerListSource]
}

/// Un server letto da un file server.met.
struct ParsedServer: Identifiable, Hashable {
    var ip: String
    var port: UInt16
    var name: String
    var description: String
    var users: UInt64
    var maxUsers: UInt64
    var files: UInt64
    var ping: UInt64
    var version: String
    var id: String { "\(ip):\(port)" }
    var address: String { "\(ip):\(port)" }
}

enum ServerMetError: LocalizedError {
    case notServerMet
    case truncated
    case unknownTag(UInt8)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .notServerMet: return String(localized: "Il file scaricato non è un server.met.")
        case .truncated: return String(localized: "Il file server.met è incompleto o danneggiato.")
        case .unknownTag(let t): return String(localized: "Formato server.met non riconosciuto (tag \(t)).")
        case .http(let code): return String(localized: "Il sito ha risposto con l'errore HTTP \(code).")
        }
    }
}

/// Lettore del formato server.met di eDonkey/eMule/aMule (anche compresso gzip).
enum ServerMetParser {
    static func parse(_ raw: Data) throws -> [ParsedServer] {
        let data = try gunzipIfNeeded(raw)
        guard data.count >= 5, data[data.startIndex] == 0x0E || data[data.startIndex] == 0xE0 else {
            throw ServerMetError.notServerMet
        }
        var r = Reader(data: data, offset: data.startIndex + 1)
        let count = try r.u32()
        var out: [ParsedServer] = []
        out.reserveCapacity(Int(min(count, 10_000)))
        for _ in 0..<count {
            let ip = try r.u32()
            let port = try r.u16()
            let tagCount = try r.u32()
            var s = ParsedServer(ip: Self.dotted(ip), port: port, name: "", description: "",
                                 users: 0, maxUsers: 0, files: 0, ping: 0, version: "")
            for _ in 0..<tagCount {
                var type = try r.u8()
                let special: UInt8?
                var nameBytes = Data()
                if type & 0x80 != 0 {
                    type &= 0x7F
                    special = try r.u8()
                } else {
                    let len = try r.u16()
                    nameBytes = try r.bytes(Int(len))
                    special = len == 1 ? nameBytes.first : nil
                }
                let value: TagValue
                switch type {
                case 0x01: value = .data(try r.bytes(16))
                case 0x02: let len = try r.u16(); value = .string(String(decoding: try r.bytes(Int(len)), as: UTF8.self))
                case 0x03: value = .number(UInt64(try r.u32()))
                case 0x04: _ = try r.u32(); value = .number(0)
                case 0x05: value = .number(UInt64(try r.u8()))
                case 0x06: let n = try r.u16(); _ = try r.bytes(Int((n + 7) / 8)); value = .number(0)
                case 0x07: let len = try r.u32(); value = .data(try r.bytes(Int(len)))
                case 0x08: value = .number(UInt64(try r.u16()))
                case 0x09: value = .number(UInt64(try r.u8()))
                case 0x0A: let len = try r.u8(); value = .data(try r.bytes(Int(len)))
                case 0x0B: value = .number(try r.u64())
                case 0x11...0x20: value = .string(String(decoding: try r.bytes(Int(type) - 0x10), as: UTF8.self))
                default: throw ServerMetError.unknownTag(type)
                }
                let key = special.map { String($0) } ?? String(decoding: nameBytes, as: UTF8.self)
                switch key {
                case "1", "name": if case .string(let v) = value { s.name = v }
                case "11", "description": if case .string(let v) = value { s.description = v }
                case "12", "ping": if case .number(let v) = value { s.ping = v }
                case "135", "maxusers": if case .number(let v) = value { s.maxUsers = v }
                case "136", "users": if case .number(let v) = value { s.users = v }
                case "137", "files": if case .number(let v) = value { s.files = v }
                case "145", "version": if case .string(let v) = value { s.version = v }
                default: break
                }
            }
            if s.name.isEmpty { s.name = s.address }
            out.append(s)
        }
        return out
    }

    private enum TagValue { case string(String), number(UInt64), data(Data) }

    private struct Reader {
        let data: Data
        var offset: Int
        mutating func bytes(_ n: Int) throws -> Data {
            guard n >= 0, offset + n <= data.endIndex else { throw ServerMetError.truncated }
            defer { offset += n }
            return data.subdata(in: offset..<offset + n)
        }
        mutating func u8() throws -> UInt8 { try bytes(1)[0] }
        mutating func u16() throws -> UInt16 { let b = try bytes(2); return UInt16(b[b.startIndex]) | UInt16(b[b.startIndex + 1]) << 8 }
        mutating func u32() throws -> UInt32 {
            let b = try bytes(4)
            return UInt32(b[b.startIndex]) | UInt32(b[b.startIndex + 1]) << 8 | UInt32(b[b.startIndex + 2]) << 16 | UInt32(b[b.startIndex + 3]) << 24
        }
        mutating func u64() throws -> UInt64 {
            let lo = UInt64(try u32()); let hi = UInt64(try u32()); return lo | hi << 32
        }
    }

    static func dotted(_ ip: UInt32) -> String {
        "\(ip & 0xFF).\((ip >> 8) & 0xFF).\((ip >> 16) & 0xFF).\(ip >> 24)"
    }

    /// Un server.met.gz è un membro gzip: intestazione (10 byte + campi
    /// opzionali) + deflate grezzo + 8 byte di coda. Apple decomprime il
    /// deflate grezzo con l'algoritmo `.zlib`.
    static func gunzipIfNeeded(_ data: Data) throws -> Data {
        guard data.count > 18, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B else { return data }
        let flags = data[data.startIndex + 3]
        var i = data.startIndex + 10
        func need(_ n: Int) throws { if i + n > data.endIndex { throw ServerMetError.truncated } }
        if flags & 0x04 != 0 { try need(2); let xlen = Int(data[i]) | Int(data[i + 1]) << 8; i += 2 + xlen }
        if flags & 0x08 != 0 { while i < data.endIndex, data[i] != 0 { i += 1 }; i += 1 }
        if flags & 0x10 != 0 { while i < data.endIndex, data[i] != 0 { i += 1 }; i += 1 }
        if flags & 0x02 != 0 { i += 2 }
        guard i < data.endIndex - 8 else { throw ServerMetError.truncated }
        let body = data.subdata(in: i..<data.endIndex - 8)
        do {
            return try (body as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw ServerMetError.notServerMet
        }
    }
}

/// Stato di verifica di una fonte.
struct ServerListStatus: Equatable {
    enum Kind: Equatable { case unknown, checking, ok(count: Int, bytes: Int), failed(String) }
    var kind: Kind = .unknown
    var checkedAt: Date?
    var servers: [ParsedServer] = []
}

/// Catalogo delle fonti + verifica + download. Condiviso da tutte le piattaforme.
@MainActor
final class ServerListManager: ObservableObject {
    static let shared = ServerListManager()

    /// Catalogo pubblicato con la pagina privacy (GitHub Pages del repo).
    static let catalogURL = URL(string: "https://sidimam.github.io/AmuleRemote/server-lists.json")!
    private static let customKey = "customServerListSources"
    private static let catalogCacheKey = "serverListCatalogCache"

    /// Copia di riserva del catalogo (stesse fonti di docs/server-lists.json),
    /// verificate il 21 ottobre 2026.
    static let bundledCatalog = ServerListCatalog(updated: "2026-10-21", sources: [
        ServerListSource(id: "peerates", name: "PeeRates (servers.met)",
                         url: "https://www.peerates.net/servers.met",
                         note: "Elenco mantenuto da peerates.net; una ventina di server eD2k attivi."),
        ServerListSource(id: "gruk", name: "Gruk.org (server.met.gz)",
                         url: "http://www.gruk.org/server.met.gz",
                         note: "Elenco storico, compresso gzip; pochi server ma stabili."),
        ServerListSource(id: "server-met-de", name: "server-met.de (server.met.gz)",
                         url: "http://www.server-met.de/dl.php?load=gz",
                         note: "Elenco di server-met.de (reindirizza ad alldivx.de), compresso gzip."),
    ])

    @Published private(set) var catalog: ServerListCatalog
    @Published private(set) var custom: [ServerListSource]
    @Published private(set) var status: [String: ServerListStatus] = [:]
    @Published private(set) var catalogError: String?

    var sources: [ServerListSource] { catalog.sources + custom }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.catalogCacheKey),
           let c = try? JSONDecoder().decode(ServerListCatalog.self, from: data), !c.sources.isEmpty {
            catalog = c
        } else {
            catalog = Self.bundledCatalog
        }
        if let data = UserDefaults.standard.data(forKey: Self.customKey),
           let list = try? JSONDecoder().decode([ServerListSource].self, from: data) {
            custom = list
        } else {
            custom = []
        }
    }

    // MARK: Catalogo

    /// Scarica il catalogo aggiornato; in caso di errore resta quello in uso.
    func refreshCatalog(demo: Bool) async {
        guard !demo else { return }
        do {
            var req = URLRequest(url: Self.catalogURL, timeoutInterval: 15)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) ?? true else { return }
            let c = try JSONDecoder().decode(ServerListCatalog.self, from: data)
            guard !c.sources.isEmpty else { return }
            catalog = c
            UserDefaults.standard.set(data, forKey: Self.catalogCacheKey)
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
    }

    // MARK: Fonti personalizzate

    @discardableResult
    func addCustom(url rawURL: String, name: String) -> ServerListSource? {
        var text = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty else { return nil }
        if let existing = sources.first(where: { $0.url == text }) { return existing }
        let src = ServerListSource(id: "custom-\(UUID().uuidString)",
                                   name: name.isEmpty ? host : name, url: text, note: nil, custom: true)
        custom.append(src)
        persistCustom()
        return src
    }

    func removeCustom(_ src: ServerListSource) {
        custom.removeAll { $0.id == src.id }
        status[src.id] = nil
        persistCustom()
    }

    private func persistCustom() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: Self.customKey)
        }
    }

    // MARK: Download e verifica

    /// Scarica e legge il server.met di una fonte, aggiornando lo stato.
    @discardableResult
    func fetch(_ src: ServerListSource, demo: Bool) async -> [ParsedServer] {
        status[src.id] = ServerListStatus(kind: .checking, checkedAt: nil, servers: [])
        if demo {
            try? await Task.sleep(nanoseconds: 600_000_000)
            let servers = Self.demoServers(for: src)
            status[src.id] = ServerListStatus(kind: .ok(count: servers.count, bytes: 2048), checkedAt: .now, servers: servers)
            return servers
        }
        do {
            guard let url = src.urlValue else { throw ServerMetError.notServerMet }
            var req = URLRequest(url: url, timeoutInterval: 25)
            req.setValue("aMuleRemote/1.5 (+https://github.com/sidimam/AmuleRemote)", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300 ~= http.statusCode) {
                throw ServerMetError.http(http.statusCode)
            }
            let servers = try ServerMetParser.parse(data)
            status[src.id] = ServerListStatus(kind: .ok(count: servers.count, bytes: data.count), checkedAt: .now, servers: servers)
            return servers
        } catch {
            status[src.id] = ServerListStatus(kind: .failed(error.localizedDescription), checkedAt: .now, servers: [])
            return []
        }
    }

    func checkAll(demo: Bool) async {
        for src in sources { await fetch(src, demo: demo) }
    }

    private static func demoServers(for src: ServerListSource) -> [ParsedServer] {
        [
            ParsedServer(ip: "192.0.2.10", port: 4661, name: "Demo Server Alpha", description: "Server di esempio", users: 123_456, maxUsers: 200_000, files: 9_876_543, ping: 42, version: "17.15"),
            ParsedServer(ip: "198.51.100.7", port: 4242, name: "Demo Server Beta", description: "Server di esempio", users: 54_321, maxUsers: 100_000, files: 4_321_098, ping: 77, version: "17.15"),
            ParsedServer(ip: "203.0.113.3", port: 4500, name: "Demo Server Gamma (\(src.name))", description: "Server di esempio", users: 8_765, maxUsers: 50_000, files: 654_321, ping: 120, version: "16.50"),
        ]
    }
}

extension AppState {
    /// Importa i server scelti in amuled (EC_OP_SERVER_ADD). Con `replace`
    /// rimuove prima i server già presenti nell'elenco.
    /// Ritorna quanti ne sono stati aggiunti.
    @discardableResult
    func importServers(_ list: [ParsedServer], replace: Bool) async -> Int {
        if replace {
            for s in servers { await removeServer(s) }
        }
        let existing = Set(servers.map { "\(ServerMetParser.dotted($0.ip)):\($0.port)" })
        var added = 0
        for s in list where replace || !existing.contains(s.address) {
            await addServer(address: s.ip, port: String(s.port), name: s.name)
            added += 1
        }
        await refreshServers()
        return added
    }
}
