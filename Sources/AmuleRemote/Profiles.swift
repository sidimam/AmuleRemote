import Foundation

/// Un profilo di connessione: un server amuled salvato con nome.
/// La password NON è qui: vive nel Portachiavi con account "host:port",
/// lo stesso schema usato fin dalla build 1 (nessuna migrazione richiesta).
struct ServerProfile: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int
    /// Ultima modifica (per la fusione dei profili sincronizzati via iCloud:
    /// vince la versione più recente). Assente nei profili delle build < 18.
    var updatedAt: Date? = nil

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
