import Foundation
import Security

/// Sincronizzazione dei profili server tra i dispositivi dell'utente tramite
/// iCloud (opzionale, spenta di default):
///  - l'elenco dei profili, il profilo predefinito e le cancellazioni viaggiano
///    nell'iCloud Key-Value Storage (NSUbiquitousKeyValueStore);
///  - le password restano nel Portachiavi, marcate `kSecAttrSynchronizable`
///    così viaggiano nel Portachiavi iCloud (vedi Keychain.swift).
/// Nessun dato passa per server di terzi: solo l'account iCloud dell'utente.
enum CloudSync {
    static let enabledKey = "iCloudSyncEnabled"
    private static let profilesKey = "profiles.v1"
    private static let defaultKey = "defaultProfile.v1"
    private static let deletedKey = "deletedProfiles.v1"

    /// Interruttore dell'utente (UserDefaults, per dispositivo).
    static var isEnabled: Bool {
        isAvailable && UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// True se il binario ha l'entitlement iCloud KVS: le build App Store
    /// (iOS, iPadOS, visionOS, tvOS, Mac App Store) e il DMG ufficiale (firmato
    /// Developer ID con profilo iCloud + SupportFiles/MacDirect.entitlements).
    /// Una build locale `swift build` senza firma/entitlements non lo ha: lì la
    /// funzione resta disattivata con una nota nelle impostazioni.
    static var isAvailable: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.ubiquity-kvstore-identifier" as CFString, nil) != nil
        #else
        return true
        #endif
    }

    struct Payload: Equatable {
        var profiles: [ServerProfile]
        var defaultID: UUID?
        var deleted: Set<UUID>
    }

    private static var store: NSUbiquitousKeyValueStore { .default }

    /// Scrive lo stato locale su iCloud.
    static func push(_ payload: Payload) {
        guard isAvailable else { return }
        if let data = try? JSONEncoder().encode(payload.profiles) {
            store.set(data, forKey: profilesKey)
        }
        if let id = payload.defaultID {
            store.set(id.uuidString, forKey: defaultKey)
        } else {
            store.removeObject(forKey: defaultKey)
        }
        store.set(payload.deleted.map(\.uuidString), forKey: deletedKey)
        store.synchronize()
    }

    /// Legge lo stato presente su iCloud (nil se non c'è nulla).
    static func pull() -> Payload? {
        guard isAvailable else { return nil }
        store.synchronize()
        guard let data = store.data(forKey: profilesKey),
              let profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return nil }
        let defaultID = store.string(forKey: defaultKey).flatMap(UUID.init(uuidString:))
        let deleted = Set((store.array(forKey: deletedKey) as? [String] ?? []).compactMap(UUID.init(uuidString:)))
        return Payload(profiles: profiles, defaultID: defaultID, deleted: deleted)
    }

    /// Notifica di cambiamento arrivato da un altro dispositivo.
    static var changeNotification: Notification.Name {
        NSUbiquitousKeyValueStore.didChangeExternallyNotification
    }
}

// MARK: - Logica di fusione (AppState)

extension AppState {
    /// ID dei profili cancellati localmente (tombstone), così una cancellazione
    /// si propaga agli altri dispositivi invece di essere "risuscitata".
    var deletedProfileIDs: Set<UUID> {
        get {
            Set((UserDefaults.standard.stringArray(forKey: "deletedProfileIDs") ?? []).compactMap(UUID.init(uuidString:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: "deletedProfileIDs")
        }
    }

    /// Da chiamare all'avvio: osserva iCloud (anche con la sincronizzazione
    /// spenta, per proporre il ripristino) e, se attiva, fonde subito.
    func startCloudSync() {
        guard CloudSync.isAvailable else { return }
        NotificationCenter.default.addObserver(forName: CloudSync.changeNotification,
                                               object: NSUbiquitousKeyValueStore.default,
                                               queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cloudStoreChanged() }
        }
        cloudStoreChanged()
    }

    /// Reagisce a un cambiamento del KVS (o all'avvio).
    func cloudStoreChanged() {
        guard let remote = CloudSync.pull() else { return }
        if iCloudSyncEnabled {
            mergeFromCloud(remote)
        } else if profiles.isEmpty {
            // Dispositivo nuovo: proponi il ripristino dei profili trovati su iCloud.
            let usable = remote.profiles.filter { !remote.deleted.contains($0.id) }
            cloudProfilesAvailable = usable.count
        }
    }

    /// Fusione: vince il profilo modificato più di recente; le cancellazioni
    /// (di qualunque dispositivo) prevalgono; server uguali (host:porta)
    /// creati separatamente sui due lati non vengono duplicati.
    func mergeFromCloud(_ remote: CloudSync.Payload) {
        var deleted = deletedProfileIDs.union(remote.deleted)
        var merged = profiles.filter { !deleted.contains($0.id) }
        for r in remote.profiles where !deleted.contains(r.id) {
            if let i = merged.firstIndex(where: { $0.id == r.id }) {
                if (r.updatedAt ?? .distantPast) > (merged[i].updatedAt ?? .distantPast) {
                    merged[i] = r
                }
            } else if merged.contains(where: { $0.host == r.host && $0.port == r.port }) {
                deleted.insert(r.id)   // stesso server, id diverso: resta la copia locale
            } else {
                merged.append(r)
            }
        }
        deletedProfileIDs = deleted
        if merged != profiles { profiles = merged }
        if defaultProfileID == nil || !merged.contains(where: { $0.id == defaultProfileID }) {
            if let rid = remote.defaultID, merged.contains(where: { $0.id == rid }) {
                defaultProfileID = rid
            } else {
                defaultProfileID = merged.first?.id
            }
        }
        // Riallinea anche il lato remoto (tombstone e profili fusi).
        pushProfilesToCloud()
        // Campi di connessione vuoti (primo avvio): proponi il predefinito.
        if host.isEmpty, let def = merged.first(where: { $0.id == defaultProfileID }) {
            applyProfile(def)
        }
    }

    func pushProfilesToCloud() {
        guard iCloudSyncEnabled else { return }
        CloudSync.push(.init(profiles: profiles, defaultID: defaultProfileID, deleted: deletedProfileIDs))
    }

    /// Attiva/disattiva la sincronizzazione: le password dei profili vengono
    /// riscritte come sincronizzate (Portachiavi iCloud) o solo locali.
    func setCloudSync(_ enabled: Bool) {
        guard CloudSync.isAvailable, enabled != iCloudSyncEnabled else { return }
        iCloudSyncEnabled = enabled
        Keychain.setSynchronizable(enabled, accounts: profiles.map(\.address))
        if enabled {
            cloudProfilesAvailable = 0
            if let remote = CloudSync.pull() {
                mergeFromCloud(remote)
            } else {
                pushProfilesToCloud()
            }
        }
    }

    /// Pulsante "Ripristina da iCloud" del banner sulla schermata di connessione.
    func restoreProfilesFromCloud() {
        setCloudSync(true)
        if let def = profiles.first(where: { $0.id == defaultProfileID }) ?? profiles.first {
            applyProfile(def)
        }
    }
}
