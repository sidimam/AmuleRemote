import Foundation
import UserNotifications

/// Notifiche locali + stato persistito per i confronti tra un controllo e
/// l'altro (usato sia dal polling in foreground sia dai controlli in
/// background su iOS). Tutte le chiavi sono per-server ("host:port") così i
/// profili non si mescolano tra loro.
/// Delegate che mostra le notifiche anche con l'app in primo piano
/// (senza, iOS le scarta del tutto quando l'app è aperta).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

enum Notifier {
    /// Da chiamare all'avvio dell'app: aggancia il delegate di presentazione.
    static func activate() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Chiede il consenso se non ancora deciso; ritorna true se le notifiche
    /// sono autorizzate. Con consenso già negato ritorna false senza riproporre
    /// il dialogo di sistema (va cambiato dalle Impostazioni del dispositivo).
    static func requestPermissionGranted() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Notifica di conferma inviata quando l'utente attiva le notifiche.
    static func postTest() {
        post(id: "test-\(UUID().uuidString)",
             title: String(localized: "Notifiche attive"),
             body: String(localized: "Riceverai qui gli avvisi di aMule Remote."))
    }

    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Riconnessione automatica lato server
    // Se amuled ha "Riconnetti automaticamente" attivo, un drop eD2k/Kad è
    // transitorio: per scelta dell'utente NON va notificato. Il flag viene
    // letto dalle preferenze remote e cacheato qui per i controlli offline.

    static func recordServerReconnect(server: String, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "bg-reconnect-\(server)")
    }

    static func serverReconnectEnabled(server: String) -> Bool {
        UserDefaults.standard.bool(forKey: "bg-reconnect-\(server)")
    }

    // MARK: - Stato reti (eD2k / Kad)

    static func recordNetState(server: String, ed2k: Bool, kad: Bool) {
        let d = UserDefaults.standard
        d.set(ed2k, forKey: "bg-ed2k-\(server)")
        d.set(kad, forKey: "bg-kad-\(server)")
    }

    static func lastNetState(server: String) -> (ed2k: Bool, kad: Bool)? {
        let d = UserDefaults.standard
        guard d.object(forKey: "bg-ed2k-\(server)") != nil else { return nil }
        return (d.bool(forKey: "bg-ed2k-\(server)"), d.bool(forKey: "bg-kad-\(server)"))
    }

    // MARK: - Snapshot coda download (per rilevare i completamenti)

    struct QueueEntry: Codable {
        var p: Double   // massimo progresso osservato
        var n: String   // nome file (per il testo della notifica)
    }

    static func recordQueue(server: String, entries: [String: QueueEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: "bg-queue-\(server)")
        }
    }

    static func lastQueue(server: String) -> [String: QueueEntry] {
        guard let data = UserDefaults.standard.data(forKey: "bg-queue-\(server)"),
              let dict = try? JSONDecoder().decode([String: QueueEntry].self, from: data) else { return [:] }
        return dict
    }

    // MARK: - Dedupe completamenti

    /// true solo la PRIMA volta per (server, hash): il chiamante notifica solo
    /// in quel caso, così foreground e background non producono doppioni.
    static func markCompletedOnce(server: String, hashHex: String) -> Bool {
        let key = "notified-\(server)"
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        if list.contains(hashHex) { return false }
        list.append(hashHex)
        if list.count > 300 { list.removeFirst(list.count - 300) }
        UserDefaults.standard.set(list, forKey: key)
        return true
    }
}
