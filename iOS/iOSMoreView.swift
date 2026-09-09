import SwiftUI
import Network

struct iOSMoreView: View {
    @EnvironmentObject var state: AppState

    /// Binding di un sotto-toggle notifiche che appare spento (e non toccabile)
    /// finché l'interruttore principale delle notifiche è disattivato.
    private func gated(_ source: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { state.notificationsEnabled && source.wrappedValue },
                set: { source.wrappedValue = $0 })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        iOSStatsView()
                    } label: {
                        Label("Statistiche", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        iOSLogView()
                    } label: {
                        Label("Log del server", systemImage: "doc.text")
                    }
                    NavigationLink {
                        iOSServerTestView()
                    } label: {
                        Label("Test connessione", systemImage: "stethoscope")
                    }
                }

                if !state.profiles.isEmpty {
                    Section {
                        Picker("Profilo attivo", selection: Binding(
                            get: { state.currentProfile?.id },
                            set: { newID in
                                if let id = newID, let p = state.profiles.first(where: { $0.id == id }) {
                                    Task { await state.switchProfile(to: p) }
                                }
                            }
                        )) {
                            ForEach(state.profiles) { p in
                                if p.id == state.defaultProfileID {
                                    Label(p.name, systemImage: "star.fill").tag(Optional(p.id))
                                } else {
                                    Text(p.name).tag(Optional(p.id))
                                }
                            }
                            if state.currentProfile == nil {
                                Text(state.demoMode ? "Demo" : "—").tag(Optional<UUID>.none)
                            }
                        }
                        NavigationLink {
                            iOSProfilesView()
                        } label: {
                            Label("Gestisci profili", systemImage: "person.2.badge.gearshape")
                        }
                    } header: {
                        Text("Profili server")
                    } footer: {
                        Text("Cambiando profilo l'app si disconnette dal server corrente e si connette a quello scelto.")
                    }
                }

                Section {
                    Picker("Aspetto", selection: $state.themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.icon).tag(mode)
                        }
                    }
                    Picker(selection: $state.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    } label: {
                        Label("Lingua", systemImage: "globe")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Colore icona", systemImage: "paintpalette")
                        IconColorPicker(selection: $state.iconColor)
                    }
                    Picker(selection: $state.idleTimeout) {
                        Text("Mai").tag(0)
                        Text("60 secondi").tag(60)
                        Text("120 secondi").tag(120)
                        Text("5 minuti").tag(300)
                        Text("10 minuti").tag(600)
                        Text("30 minuti").tag(1800)
                    } label: {
                        Label("Vai offline dopo inattività", systemImage: "zzz")
                    }
                    Toggle(isOn: Binding(
                        get: { state.iCloudSyncEnabled },
                        set: { state.setCloudSync($0) }
                    )) {
                        Label("Sincronizza profili con iCloud", systemImage: "icloud")
                    }
                    .disabled(!CloudSync.isAvailable)
                    Toggle(isOn: Binding(
                        get: { state.biometricLockEnabled },
                        set: { newValue in Task { await state.setBiometricLock(newValue) } }
                    )) {
                        Label("Richiedi \(BiometricAuth.biometryLabel)", systemImage: BiometricAuth.biometryIcon)
                    }
                    .disabled(!BiometricAuth.isAvailable)
                } header: {
                    Text("Impostazioni app")
                } footer: {
                    Text("Dopo il periodo di inattività scelto (e quando l'app va in background) la connessione al server si chiude per risparmiare batteria e dati, ma i dati restano visibili in stato Offline: la connessione riparte da sola al primo tocco o al ritorno in primo piano. Con la sincronizzazione iCloud i profili server e le loro password (Portachiavi iCloud) sono condivisi tra i tuoi dispositivi. Con il blocco attivo, all'apertura l'app chiede \(BiometricAuth.biometryLabel) prima di mostrare i contenuti. Il colore dell'icona si applica a iPhone, iPad e Apple Vision Pro; su Apple Watch resta l'icona originale (limite di watchOS).")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { state.notificationsEnabled },
                        set: { v in Task { await state.setNotificationsEnabled(v) } }
                    )) {
                        Label("Notifiche", systemImage: "bell.badge")
                    }
                    Toggle(isOn: gated($state.notifyDownloadsEnabled)) {
                        Label("Download completati", systemImage: "checkmark.circle")
                    }
                    .disabled(!state.notificationsEnabled)
                    Toggle(isOn: gated($state.notifyNetworkEnabled)) {
                        Label("Disconnessioni eD2k / Kad", systemImage: "wifi.slash")
                    }
                    .disabled(!state.notificationsEnabled)
                    Toggle(isOn: gated($state.backgroundChecksEnabled)) {
                        Label("Controlli in background", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(!state.notificationsEnabled)
                    Picker(selection: $state.checkInterval) {
                        Text("1 minuto").tag(60)
                        Text("5 minuti").tag(300)
                        Text("15 minuti").tag(900)
                        Text("30 minuti").tag(1800)
                        Text("1 ora").tag(3600)
                    } label: {
                        Label("Intervallo controlli", systemImage: "timer")
                    }
                    .disabled(!state.notificationsEnabled)
                } header: {
                    Text("Notifiche")
                } footer: {
                    Text("Attiva le notifiche per ricevere gli avvisi: alla prima attivazione l'app chiede il permesso e invia una notifica di prova. Con i controlli in background l'app verifica il server anche da disconnessa (timeout o caduta della connessione) e ti avvisa di download completati e disconnessioni eD2k/Kad (queste ultime non se sul server è attiva la riconnessione automatica). Con l'app aperta i controlli seguono l'intervallo scelto; in background la cadenza la decide iOS usando questo valore come minimo (mai sotto i 15 minuti, a tutela della batteria). Le notifiche arrivano anche su Apple Watch.")
                }

                Section("Connessione") {
                    LabeledContent {
                        Text(state.demoMode ? "DEMO (dati di esempio)" : "\(state.host):\(state.port)")
                    } label: {
                        Label("Server", systemImage: "server.rack")
                    }
                    LabeledContent {
                        Text(state.serverVersion.isEmpty ? "—" : state.serverVersion)
                    } label: {
                        Label("Versione aMule", systemImage: "info.circle")
                    }
                    Button(role: .destructive) {
                        Task { await state.disconnect() }
                    } label: {
                        Label("Disconnetti", systemImage: "xmark.circle")
                    }
                }

                AppInfoSection()
            }
            .navigationTitle("Altro")
        }
    }
}

// MARK: - Test connessione

struct iOSServerTestView: View {
    @EnvironmentObject var state: AppState
    // Il dominio del webserver viene ricordato SOLO dopo un test riuscito
    // dall'utente: di default il campo è vuoto.
    @AppStorage("webTestHost") private var savedWebHost = ""
    @State private var webHost = ""
    @State private var running = false
    @State private var ecDone = false
    @State private var ecOK = false
    @State private var ecDetail = ""
    @State private var webDone = false
    @State private var webOK = false
    @State private var webDetail = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Indirizzo", value: state.demoMode ? "DEMO (dati di esempio)" : "\(state.host):\(state.port)")
                resultRow("Porta EC raggiungibile", done: ecDone, ok: ecOK, detail: ecDetail)
            } header: {
                Text("Server EC (External Connections)")
            } footer: {
                Text("Verifica che l'app possa aprire una connessione TCP alla porta EC del server aMule.")
            }

            Section {
                TextField("Dominio webserver", text: $webHost)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                resultRow("Webserver risponde", done: webDone, ok: webOK, detail: webDetail)
            } header: {
                Text("Webserver aMule (facoltativo)")
            } footer: {
                Text("Verifica se un eventuale webserver aMule (amuleweb) risponde all'indirizzo indicato, via HTTPS o HTTP.")
            }

            Section {
                Button {
                    Task { await runTests() }
                } label: {
                    HStack {
                        Spacer()
                        if running { ProgressView() } else { Text("Esegui test").bold() }
                        Spacer()
                    }
                }
                .disabled(running || state.host.isEmpty)
            }
        }
        .navigationTitle("Test connessione")
        .navigationBarTitleDisplayMode(.inline)
        // Pre-compila solo con un dominio già testato in precedenza.
        .onAppear { if webHost.isEmpty { webHost = savedWebHost } }
    }

    @ViewBuilder
    private func resultRow(_ title: String, done: Bool, ok: Bool, detail: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if done {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? .green : .red)
                Text(detail).foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private func runTests() async {
        running = true
        ecDone = false; webDone = false
        // In modalità demo il test è simulato (nessuna rete coinvolta).
        if state.demoMode {
            try? await Task.sleep(nanoseconds: 700_000_000)
            ecOK = true; ecDetail = "raggiungibile (demo)"; ecDone = true
            let host = webHost.trimmingCharacters(in: .whitespaces)
            webOK = !host.isEmpty
            webDetail = host.isEmpty ? "nessun dominio" : "HTTPS 200 (demo)"
            webDone = true
            if !host.isEmpty { savedWebHost = host }
            running = false
            return
        }
        let ec = await ServerTest.tcpReachable(host: state.host.trimmingCharacters(in: .whitespaces),
                                               port: UInt16(clamping: state.port))
        ecOK = ec; ecDetail = ec ? "raggiungibile" : "non raggiungibile"; ecDone = true
        let host = webHost.trimmingCharacters(in: .whitespaces)
        if host.isEmpty {
            webOK = false; webDetail = "nessun dominio"; webDone = true
        } else {
            let r = await ServerTest.httpResponds(host: host)
            webOK = r.ok; webDetail = r.detail; webDone = true
            savedWebHost = host   // ricordato solo ora, dopo un test reale
        }
        running = false
    }
}

enum ServerTest {
    /// Apre una connessione TCP e riporta se il server accetta entro il timeout.
    static func tcpReachable(host: String, port: UInt16, timeout: Double = 8) async -> Bool {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        return await withCheckedContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            var finished = false
            func finish(_ v: Bool) {
                if finished { return }
                finished = true
                conn.cancel()
                cont.resume(returning: v)
            }
            let deadline = DispatchWorkItem { finish(false) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
            conn.stateUpdateHandler = { st in
                switch st {
                case .ready: deadline.cancel(); finish(true)
                case .failed, .cancelled, .waiting: deadline.cancel(); finish(false)
                default: break
                }
            }
            conn.start(queue: .global())
        }
    }

    /// GET su https:// poi http://; qualsiasi risposta HTTP = "risponde".
    static func httpResponds(host: String) async -> (ok: Bool, detail: String) {
        for scheme in ["https", "http"] {
            guard let url = URL(string: "\(scheme)://\(host)") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 8)
            req.httpMethod = "GET"
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    return (true, "\(scheme.uppercased()) \(http.statusCode)")
                }
                return (true, "\(scheme.uppercased()) risponde")
            } catch {
                continue
            }
        }
        return (false, "nessuna risposta")
    }
}

struct iOSStatsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List {
            Section("Velocità") {
                statRow("Download", "arrow.down", formatSpeed(state.stats.dlSpeed))
                statRow("Upload", "arrow.up", formatSpeed(state.stats.ulSpeed))
                statRow("Limite download", "speedometer", state.stats.dlSpeedLimit > 0 ? "\(state.stats.dlSpeedLimit) kB/s" : String(localized: "Illimitato"))
                statRow("Limite upload", "speedometer", state.stats.ulSpeedLimit > 0 ? "\(state.stats.ulSpeedLimit) kB/s" : String(localized: "Illimitato"))
            }
            Section("Reti") {
                statRow("eD2k", "server.rack", state.connState.ed2kLabel)
                statRow("Utenti eD2k", "person.2", "\(state.stats.ed2kUsers)")
                statRow("File eD2k", "doc.on.doc", "\(state.stats.ed2kFiles)")
                statRow("Kad", "point.3.connected.trianglepath.dotted", state.connState.kadLabel)
                statRow("Utenti Kad", "person.2", "\(state.stats.kadUsers)")
                statRow("Nodi Kad", "circle.hexagongrid", "\(state.stats.kadNodes)")
            }
            Section("Trasferimenti") {
                statRow("Fonti totali", "person.3", "\(state.stats.totalSources)")
                statRow("Coda upload", "list.number", "\(state.stats.uploadQueueLength)")
                statRow("File condivisi", "folder", "\(state.stats.sharedFileCount)")
                statRow("Totale inviato", "tray.and.arrow.up", formatBytes(state.stats.totalSent))
                statRow("Totale ricevuto", "tray.and.arrow.down", formatBytes(state.stats.totalReceived))
            }
        }
        .navigationTitle("Statistiche")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func statRow(_ title: LocalizedStringKey, _ icon: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            Label(title, systemImage: icon)
        }
    }
}

struct iOSLogView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            Text(state.logText.isEmpty ? "Nessuna riga di log." : state.logText)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .textSelection(.enabled)
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .task { await state.refreshLog() }
        .refreshable { await state.refreshLog() }
    }
}
