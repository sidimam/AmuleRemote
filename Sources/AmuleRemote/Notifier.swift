import Foundation
import UserNotifications

/// Notifiche locali + stato persistito per i confronti tra un controllo e
/// l'altro (usato sia dal polling in foreground sia dai controlli in
/// background su iOS). Tutte le chiavi sono per-server ("host:port") così i
/// profili non si mescolano tra loro.
enum Notifier {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
