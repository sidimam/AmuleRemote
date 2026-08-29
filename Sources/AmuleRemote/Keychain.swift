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

    static func savePassword(_ password: String, account: String) {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
