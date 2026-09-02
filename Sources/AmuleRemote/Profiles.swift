import Foundation

/// Un profilo di connessione: un server amuled salvato con nome.
/// La password NON è qui: vive nel Portachiavi con account "host:port",
/// lo stesso schema usato fin dalla build 1 (nessuna migrazione richiesta).
struct ServerProfile: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int
    /// URL HTTP(S) che pubblica la cartella Incoming del server, per il
    /// download in locale dei file completati (opzionale). Eventuali header
    /// (es. Cloudflare Access) sono nel Portachiavi, non qui.
    var incomingURL: String? = nil

    var address: String { "\(host):\(port)" }
}

enum ProfileStore {
    private static let profilesKey = "serverProfiles"
    private static let defaultKey = "defaultProfileID"

    static func load() -> [ServerProfile] {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let list = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return [] }
        return list
    }

    static func save(_ profiles: [ServerProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    static var defaultID: UUID? {
        get {
            guard let s = UserDefaults.standard.string(forKey: defaultKey) else { return nil }
            return UUID(uuidString: s)
        }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id.uuidString, forKey: defaultKey)
            } else {
                UserDefaults.standard.removeObject(forKey: defaultKey)
            }
        }
    }
}
