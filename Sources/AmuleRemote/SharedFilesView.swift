import SwiftUI

struct SharedFilesView: View {
    @EnvironmentObject var state: AppState
    @State private var selection = Set<Data>()
    @State private var filter = ""
    @State private var sortOrder = [KeyPathComparator(\SharedFileItem.name)]

    private var filtered: [SharedFileItem] {
        let base = filter.isEmpty
            ? state.sharedFiles
            : state.sharedFiles.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        return base.sorted(using: sortOrder)
    }

    var body: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Nome", value: \.name) { f in Text(f.name).help(f.name) }
                .width(min: 240, ideal: 380)

            TableColumn("Dimensione", value: \.size) { f in Text(formatBytes(f.size)) }
                .width(95)

            TableColumn("Priorità", value: \.priority) { f in Text(FilePriority.describe(f.priority)) }
                .width(100)

            TableColumn("Richieste", value: \.requestsAll) { f in Text("\(f.requests) (\(f.requestsAll))") }
                .width(100)

            TableColumn("Accettate", value: \.acceptsAll) { f in Text("\(f.accepts) (\(f.acceptsAll))") }
                .width(100)

            TableColumn("Caricati (sessione / totale)", value: \.xferredAll) { f in
                Text(f.xferredAll == 0 && f.xferred == 0
                     ? "—"
                     : "\(f.xferred == 0 ? "—" : formatBytes(f.xferred)) / \(formatBytes(f.xferredAll))")
            }
            .width(160)
        }
        .contextMenu(forSelectionType: Data.self) { hashes in
            let items = filtered.filter { hashes.contains($0.hash) }
            Menu("Priorità upload") {
                ForEach([FilePriority.veryLow, .low, .normal, .high, .veryHigh, .powershare, .auto]) { p in
                    Button(p.label) {
                        Task { for i in items { await state.setSharedPriority(i, p) } }
                    }
                }
            }
            if items.count == 1, let item = items.first, !item.ed2kLink.isEmpty {
                Button("Copia link eD2k") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.ed2kLink, forType: .string)
                }
            }
        }
        .searchable(text: $filter, prompt: "Filtra per nome")
        .navigationTitle("File condivisi")
        .navigationSubtitle("\(state.sharedFiles.count) file condivisi")
        .task { await state.refreshShared() }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await state.reloadSharedFiles() }
                } label: {
                    Label("Ricarica condivisioni", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Fai rileggere al server le cartelle condivise")

                Button {
                    Task { await state.refreshShared() }
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        // Stesse sezioni, righe e icone della vista Statistiche di iOS.
        Form {
            Section("Velocità") {
                statRow("Download", "arrow.down", formatSpeed(state.stats.dlSpeed))
                statRow("Upload", "arrow.up", formatSpeed(state.stats.ulSpeed))
                statRow("Limite download", "speedometer", state.stats.dlSpeedLimit > 0 ? "\(state.stats.dlSpeedLimit) kB/s" : String(localized: "Illimitato"))
                statRow("Limite upload", "speedometer", state.stats.ulSpeedLimit > 0 ? "\(state.stats.ulSpeedLimit) kB/s" : String(localized: "Illimitato"))
                statRow("Overhead up", "arrow.up.to.line", formatSpeed(Double(state.stats.upOverhead)))
                statRow("Overhead down", "arrow.down.to.line", formatSpeed(Double(state.stats.downOverhead)))
            }
            Section("Reti") {
                statRow("eD2k", "server.rack", state.connState.ed2kLabel)
                statRow("ID client", "number", state.connState.ed2kID > 0 ? "\(state.connState.ed2kID)" : "—")
                statRow("Utenti eD2k", "person.2", "\(state.stats.ed2kUsers)")
                statRow("File eD2k", "doc.on.doc", "\(state.stats.ed2kFiles)")
                statRow("Kad", "point.3.connected.trianglepath.dotted", state.connState.kadLabel)
                statRow("Utenti Kad", "person.2", "\(state.stats.kadUsers)")
                statRow("File Kad", "doc.on.doc", "\(state.stats.kadFiles)")
                statRow("Nodi Kad", "circle.hexagongrid", "\(state.stats.kadNodes)")
            }
            Section("Trasferimenti") {
                statRow("Fonti totali", "person.3", "\(state.stats.totalSources)")
                statRow("Coda upload", "list.number", "\(state.stats.uploadQueueLength)")
                statRow("Client bannati", "person.slash", "\(state.stats.bannedCount)")
                statRow("File condivisi", "folder", "\(state.stats.sharedFileCount)")
                statRow("Totale inviato", "tray.and.arrow.up", formatBytes(state.stats.totalSent))
                statRow("Totale ricevuto", "tray.and.arrow.down", formatBytes(state.stats.totalReceived))
            }
            Section("Server aMule") {
                statRow("Versione aMule", "info.circle", state.serverVersion.isEmpty ? "—" : state.serverVersion)
                statRow("Server", "server.rack", state.demoMode ? String(localized: "DEMO (dati di esempio)") : "\(state.host):\(state.port)")
                Button(role: .destructive) {
                    confirmShutdown = true
                } label: {
                    Label("Spegni amuled…", systemImage: "power")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Statistiche")
        .confirmationDialog("Spegnere il demone aMule sul server?", isPresented: $confirmShutdown) {
            Button("Spegni amuled", role: .destructive) {
                Task { await state.shutdownDaemon() }
            }
        } message: {
            Text("Il demone remoto verrà arrestato e la connessione chiusa. Dovrai riavviarlo da Unraid.")
        }
    }

    @State private var confirmShutdown = false

    @ViewBuilder
    private func statRow(_ title: LocalizedStringKey, _ icon: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).font(.body.monospacedDigit())
        } label: {
            Label(title, systemImage: icon)
        }
    }
}

struct LogView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(state.logText.isEmpty ? "Nessuna riga di log." : state.logText)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
                    .id("logEnd")
            }
            .onChange(of: state.logText) {
                proxy.scrollTo("logEnd", anchor: .bottom)
            }
        }
        .navigationTitle("Log del server")
        .task { await state.refreshLog() }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await state.resetLog() }
                } label: {
                    Label("Svuota log", systemImage: "trash")
                }
                Button {
                    Task { await state.refreshLog() }
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}
