import SwiftUI
import Network

struct iOSMoreView: View {
    @EnvironmentObject var state: AppState

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

                Section {
                    Picker("Disconnetti dopo inattività", selection: $state.idleTimeout) {
                        Text("Mai").tag(0)
                        Text("60 secondi").tag(60)
                        Text("120 secondi").tag(120)
                        Text("5 minuti").tag(300)
                        Text("10 minuti").tag(600)
                        Text("30 minuti").tag(1800)
                    }
                } header: {
                    Text("Impostazioni app")
                } footer: {
                    Text("Per risparmiare batteria e dati, l'app si disconnette dal server dopo il periodo di inattività scelto.")
                }

                Section("Connessione") {
                    LabeledContent("Server", value: "\(state.host):\(state.port)")
                    LabeledContent("Versione aMule", value: state.serverVersion.isEmpty ? "—" : state.serverVersion)
                    Button("Disconnetti", role: .destructive) {
                        Task { await state.disconnect() }
                    }
                }

                Section("Informazioni app") {
                    LabeledContent("aMule Remote", value: appVersionString())
                }
            }
            .navigationTitle("Altro")
        }
    }
}

/// "1.0 (build 12)" dal bundle.
func appVersionString() -> String {
    let info = Bundle.main.infoDictionary
    let v = info?["CFBundleShortVersionString"] as? String ?? "?"
    let b = info?["CFBundleVersion"] as? String ?? "?"
    return "\(v) (build \(b))"
}

// MARK: - Test connessione

struct iOSServerTestView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("webTestHost") private var webHost = "amule.manieridimambro.it"
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
                LabeledContent("Indirizzo", value: "\(state.host):\(state.port)")
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
        let ec = await ServerTest.tcpReachable(host: state.host.trimmingCharacters(in: .whitespaces),
                                               port: UInt16(clamping: state.port))
        ecOK = ec; ecDetail = ec ? "raggiungibile" : "non raggiungibile"; ecDone = true
        let host = webHost.trimmingCharacters(in: .whitespaces)
        if host.isEmpty {
            webOK = false; webDetail = "nessun dominio"; webDone = true
        } else {
            let r = await ServerTest.httpResponds(host: host)
            webOK = r.ok; webDetail = r.detail; webDone = true
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
                LabeledContent("Download", value: formatSpeed(state.stats.dlSpeed))
                LabeledContent("Upload", value: formatSpeed(state.stats.ulSpeed))
                LabeledContent("Limite download", value: state.stats.dlSpeedLimit > 0 ? "\(state.stats.dlSpeedLimit) kB/s" : "Illimitato")
                LabeledContent("Limite upload", value: state.stats.ulSpeedLimit > 0 ? "\(state.stats.ulSpeedLimit) kB/s" : "Illimitato")
            }
            Section("Reti") {
                LabeledContent("eD2k", value: state.connState.ed2kLabel)
                LabeledContent("Utenti eD2k", value: "\(state.stats.ed2kUsers)")
                LabeledContent("File eD2k", value: "\(state.stats.ed2kFiles)")
                LabeledContent("Kad", value: state.connState.kadLabel)
                LabeledContent("Utenti Kad", value: "\(state.stats.kadUsers)")
                LabeledContent("Nodi Kad", value: "\(state.stats.kadNodes)")
            }
            Section("Trasferimenti") {
                LabeledContent("Fonti totali", value: "\(state.stats.totalSources)")
                LabeledContent("Coda upload", value: "\(state.stats.uploadQueueLength)")
                LabeledContent("File condivisi", value: "\(state.stats.sharedFileCount)")
                LabeledContent("Totale inviato", value: formatBytes(state.stats.totalSent))
                LabeledContent("Totale ricevuto", value: formatBytes(state.stats.totalReceived))
            }
        }
        .navigationTitle("Statistiche")
        .navigationBarTitleDisplayMode(.inline)
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
