import Foundation
import Security

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
        savePassword(password, account: account, synchronizable: CloudSync.isEnabled)
    }

    /// Ritorna true se la voce è stata scritta nella variante richiesta. Se la
    /// scrittura sincronizzata fallisce (entitlement assente, iCloud non
    /// configurato…) la password viene comunque salvata in locale: non si
    /// perde MAI una password già nota.
    @discardableResult
    static func savePassword(_ password: String, account: String, synchronizable: Bool) -> Bool {
        let data = Data(password.utf8)
        if synchronizable && CloudSync.isAvailable {
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
        if ok && !synchronizable && CloudSync.isAvailable {
            // Passaggio sincronizzata → locale riuscito: via la copia iCloud.
            SecItemDelete(syncQuery(account: account) as CFDictionary)
        }
        return ok && !synchronizable
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
        if CloudSync.isAvailable {
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
