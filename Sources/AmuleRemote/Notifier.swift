import Foundation
import UserNotifications

/// Notifiche locali + stato persistito per i confronti tra un controllo e
/// l'altro (usato sia dal polling in foreground sia dai controlli in
/// background su iOS). Tutte le chiavi sono per-server ("host:port") così i
/// profili non si mescolano tra loro.
///
/// Dalla 1.4 l'app non ha più interruttori propri: le notifiche si gestiscono
/// nelle Impostazioni di sistema (consenso chiesto dal walkthrough o dalla
/// riga «Notifiche»). L'app manda tutto ciò che serve: problemi di connessione
/// al server aMule, download avviati e completati, cadute e riconnessioni
/// eD2k/Kad. Se il permesso manca, il sistema scarta le richieste in silenzio.
/// Delegate che mostra le notifiche anche con l'app in primo piano
/// (senza, iOS le scarta del tutto quando l'app è aperta).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        #if os(tvOS)
        [.badge]   // tvOS non mostra banner né suoni alle app
        #else
        [.banner, .list, .sound]
        #endif
    }
}

enum Notifier {
    /// Da chiamare all'avvio dell'app: aggancia il delegate di presentazione.
    static func activate() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    /// tvOS ammette solo il badge; le altre piattaforme avvisi, suono e badge.
    static var authOptions: UNAuthorizationOptions {
        #if os(tvOS)
        [.badge]
        #else
        [.alert, .sound, .badge]
        #endif
    }

    /// Stato attuale del permesso di sistema.
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// True se il sistema consegna le nostre notifiche (autorizzate o provvisorie).
    static func isAuthorized() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional: return true
        case .notDetermined, .denied: return false
        @unknown default: return true   // .ephemeral (App Clip) e futuri stati «consentiti»
        }
    }

    /// Chiede il consenso se non ancora deciso; ritorna true se le notifiche
    /// sono autorizzate. Con consenso già negato ritorna false senza riproporre
    /// il dialogo di sistema (va cambiato dalle Impostazioni del dispositivo).
    static func requestPermissionGranted() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: authOptions)) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Notifica di conferma inviata quando l'utente concede il permesso.
    static func postTest() {
        post(id: "test-\(UUID().uuidString)",
             title: String(localized: "Notifiche attive"),
             body: String(localized: "Riceverai qui gli avvisi di aMule Remote."))
    }

    static func post(id: String, title: String, body: String) {
        #if os(tvOS)
        // tvOS non mostra notifiche alle app (solo badge): nessun avviso.
        _ = (id, title, body)
        #else
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        #endif
    }

    // MARK: - Eventi (testi comuni a foreground e background)

    static func postDownloadStarted(server: String, name: String, hashHex: String) {
        guard markStartedOnce(server: server, hashHex: hashHex) else { return }
        post(id: "start-\(hashHex)", title: String(localized: "Download avviato"), body: name)
    }

    static func postDownloadCompleted(server: String, name: String, hashHex: String) {
        guard markCompletedOnce(server: server, hashHex: hashHex) else { return }
        post(id: "dl-\(hashHex)", title: String(localized: "Download completato ✅"), body: name)
    }

    static func postEd2kDropped(host: String) {
        post(id: "ed2k-drop", title: String(localized: "eD2k disconnesso"),
             body: String(localized: "\(host) non è più connesso alla rete eD2k."))
    }

    static func postKadDropped(host: String) {
        post(id: "kad-drop", title: String(localized: "Kad disconnesso"),
             body: String(localized: "\(host) non è più connesso alla rete Kad."))
    }

    static func postEd2kReconnected(host: String, serverName: String) {
        let body = serverName.isEmpty
            ? String(localized: "\(host) è di nuovo connesso alla rete eD2k.")
            : String(localized: "\(host) è di nuovo connesso alla rete eD2k (\(serverName)).")
        post(id: "ed2k-up", title: String(localized: "eD2k riconnesso"), body: body)
    }

    static func postKadReconnected(host: String) {
        post(id: "kad-up", title: String(localized: "Kad riconnesso"),
             body: String(localized: "\(host) è di nuovo connesso alla rete Kad."))
    }

    /// Server aMule (EC) irraggiungibile: una sola notifica per «periodo di
    /// assenza», poi quella di ritorno quando risponde di nuovo.
    static func serverUnreachable(server: String, host: String) {
        let key = "bg-unreachable-\(server)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        post(id: "srv-down", title: String(localized: "Server aMule non raggiungibile"),
             body: String(localized: "Impossibile connettersi a \(host). Controlla che amuled sia acceso e raggiungibile."))
    }

    static func serverReachableAgain(server: String, host: String) {
        let key = "bg-unreachable-\(server)"
        guard UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(false, forKey: key)
        post(id: "srv-up", title: String(localized: "Server aMule di nuovo raggiungibile"),
             body: String(localized: "\(host) risponde di nuovo."))
    }

    static func postServerConnectionLost(host: String) {
        post(id: "srv-lost", title: String(localized: "Connessione al server interrotta"),
             body: String(localized: "La connessione con \(host) si è chiusa. L'app si riconnetterà da sola."))
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

    /// Cadute viste (per notificare la riconnessione solo dopo una caduta).
    static func recordDropSeen(server: String, ed2k: Bool? = nil, kad: Bool? = nil) {
        let d = UserDefaults.standard
        if let ed2k { d.set(ed2k, forKey: "bg-ed2kdrop-\(server)") }
        if let kad { d.set(kad, forKey: "bg-kaddrop-\(server)") }
    }

    static func dropSeen(server: String) -> (ed2k: Bool, kad: Bool) {
        let d = UserDefaults.standard
        return (d.bool(forKey: "bg-ed2kdrop-\(server)"), d.bool(forKey: "bg-kaddrop-\(server)"))
    }

    /// Applica le regole comuni alle transizioni di rete e manda le notifiche.
    /// `host` è il nome del server per i testi; `serverName` quello eD2k.
    static func notifyNetworkTransition(server: String, host: String, serverName: String,
                                        previous prev: (ed2k: Bool, kad: Bool),
                                        current cur: (ed2k: Bool, kad: Bool)) {
        let reconnects = serverReconnectEnabled(server: server)
        var seen = dropSeen(server: server)
        // Cadute: con la riconnessione automatica lato server sono transitorie
        // e per scelta dell'utente non si notificano, ma le ricordiamo per
        // poter annunciare il ritorno.
        if prev.ed2k && !cur.ed2k {
            seen.ed2k = true
            if !reconnects { postEd2kDropped(host: host) }
        }
        if prev.kad && !cur.kad {
            seen.kad = true
            if !reconnects { postKadDropped(host: host) }
        }
        // Riconnessioni: solo dopo una caduta osservata (mai al primo avvio).
        if !prev.ed2k && cur.ed2k && seen.ed2k {
            postEd2kReconnected(host: host, serverName: serverName)
            seen.ed2k = false
        }
        if !prev.kad && cur.kad && seen.kad {
            postKadReconnected(host: host)
            seen.kad = false
        }
        recordDropSeen(server: server, ed2k: seen.ed2k, kad: seen.kad)
    }

    // MARK: - Snapshot coda download (per rilevare avvii e completamenti)

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

    /// True se per questo server esiste già uno snapshot della coda (quindi
    /// i file nuovi sono davvero nuovi e non il primo caricamento).
    static func hasQueueSnapshot(server: String) -> Bool {
        UserDefaults.standard.data(forKey: "bg-queue-\(server)") != nil
    }

    // MARK: - Dedupe avvii e completamenti

    /// true solo la PRIMA volta per (server, hash): il chiamante notifica solo
    /// in quel caso, così foreground e background non producono doppioni.
    static func markCompletedOnce(server: String, hashHex: String) -> Bool {
        markOnce(key: "notified-\(server)", hashHex: hashHex)
    }

    static func markStartedOnce(server: String, hashHex: String) -> Bool {
        markOnce(key: "started-\(server)", hashHex: hashHex)
    }

    private static func markOnce(key: String, hashHex: String) -> Bool {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        if list.contains(hashHex) { return false }
        list.append(hashHex)
        if list.count > 300 { list.removeFirst(list.count - 300) }
        UserDefaults.standard.set(list, forKey: key)
        return true
    }
}
