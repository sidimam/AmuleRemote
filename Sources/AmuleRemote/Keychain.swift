import Foundation
import Security

/// Politica di sincronizzazione iCloud letta anche dalle estensioni (Share,
/// widget), che non compilano CloudSync/AppState: stessa chiave UserDefaults
/// e stesso controllo dell'entitlement KVS usati da CloudSync.
enum KeychainSyncPolicy {
    static let enabledKey = "iCloudSyncEnabled"
    static var enabled: Bool { available && UserDefaults.standard.bool(forKey: enabledKey) }
    static var available: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-kvstore-identifier" as CFString, nil) != nil
        #else
        return true
        #endif
    }
}

/// Profilo corrente condiviso con le estensioni (Share, widget) tramite il
/// gruppo keychain: le estensioni non leggono gli UserDefaults dell'app.
struct SharedProfile: Codable, Equatable {
    var host: String
    var port: Int
    var name: String
    var address: String { "\(host):\(port)" }
}

enum Keychain {
    // Storia dei service name:
    //  - "aMule Remote": voci create dalle build firmate col certificato
    //    self-signed. Con il passaggio a Developer ID la firma dell'app è
    //    cambiata e macOS chiede la password del portachiavi a ogni lettura
    //    di quelle voci (ACL legata alla vecchia firma).
    //  - "aMule Remote EC": nuovo nome. L'app non legge MAI le voci vecchie
    //    (nessun prompt); ricrea la propria alla prima connessione, che da
    //    quel momento le appartiene e viene letta in silenzio.
    private static let service = "aMule Remote EC"
    /// Gruppo keychain condiviso da tutte le varianti dell'app (App Store e DMG),
    /// dichiarato in keychain-access-groups: le voci sincronizzate via iCloud
    /// stanno qui, così arrivano su ogni dispositivo qualunque sia il bundle id.
    static let sharedAccessGroup = "X5SR67A8AL.com.sdimambro.amule-remote-ios"

    /// Salva la password del server. Con la sincronizzazione iCloud attiva la
    /// voce è marcata `kSecAttrSynchronizable`, così viaggia nel Portachiavi
    /// iCloud insieme ai profili (stesso account "host:port" su ogni dispositivo).
    static func savePassword(_ password: String, account: String) {
        savePassword(password, account: account, synchronizable: KeychainSyncPolicy.enabled)
    }

    /// Ritorna true se la voce è stata scritta nella variante richiesta. Se la
    /// scrittura sincronizzata fallisce (entitlement assente, iCloud non
    /// configurato…) la password viene comunque salvata in locale: non si
    /// perde MAI una password già nota.
    @discardableResult
    static func savePassword(_ password: String, account: String, synchronizable: Bool) -> Bool {
        let data = Data(password.utf8)
        if synchronizable && KeychainSyncPolicy.available {
            var add = syncQuery(account: account)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemDelete(syncQuery(account: account) as CFDictionary)
            if SecItemAdd(add as CFDictionary, nil) == errSecSuccess {
                SecItemDelete(localQuery(account: account) as CFDictionary)
                return true
            }
        }
        var add = localQuery(account: account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemDelete(localQuery(account: account) as CFDictionary)
        let ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        if ok && !synchronizable && KeychainSyncPolicy.available {
            // Passaggio sincronizzata → locale riuscito: via la copia iCloud.
            SecItemDelete(syncQuery(account: account) as CFDictionary)
        }
        return ok && !synchronizable
    }

    // MARK: Profilo corrente per le estensioni

    private static let sharedService = "aMule Remote Shared"
    private static let sharedAccount = "currentProfile"

    private static func sharedQuery() -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: sharedService,
            kSecAttrAccount as String: sharedAccount,
            kSecAttrAccessGroup as String: sharedAccessGroup,
            kSecAttrSynchronizable as String: false,
        ]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    /// Scritto dall'app a ogni cambio di profilo/connessione; letto dalle estensioni.
    static func saveSharedProfile(host: String, port: Int, name: String) {
        guard !host.isEmpty, host.uppercased() != "DEMO" else { return }
        guard let data = try? JSONEncoder().encode(SharedProfile(host: host, port: port, name: name)) else { return }
        var add = sharedQuery()
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemDelete(sharedQuery() as CFDictionary)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadSharedProfile() -> SharedProfile? {
        var q = sharedQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(SharedProfile.self, from: data)
    }

    static func loadPassword(account: String) -> String? {
        // Prima la voce locale (portachiavi classico), poi quella sincronizzata
        // nel gruppo condiviso (arrivata da iCloud o scritta con la sync attiva).
        for query in [localQuery(account: account), syncQuery(account: account)] {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data, let s = String(data: data, encoding: .utf8) {
                return s
            }
        }
        return nil
    }

    static func deletePassword(account: String) {
        SecItemDelete(localQuery(account: account) as CFDictionary)
        if KeychainSyncPolicy.available {
            SecItemDelete(syncQuery(account: account) as CFDictionary)
        }
    }

    private static func localQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
    }

    private static func syncQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessGroup as String: sharedAccessGroup,
        ]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
        #endif
        return q
    }

    /// Riscrive le password dei profili indicati come locali o sincronizzate
    /// (usato quando l'utente attiva/disattiva la sincronizzazione iCloud).
    /// Ritorna false se almeno una voce non è passata alla variante richiesta.
    @discardableResult
    static func setSynchronizable(_ synchronizable: Bool, accounts: [String]) -> Bool {
        var allOK = true
        for account in accounts {
            guard let pw = loadPassword(account: account), !pw.isEmpty else { continue }
            if !savePassword(pw, account: account, synchronizable: synchronizable) { allOK = false }
        }
        return allOK
    }
}
