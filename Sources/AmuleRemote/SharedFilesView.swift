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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Velocità") {
                    statsGrid([
                        ("Download", formatSpeed(state.stats.dlSpeed)),
                        ("Upload", formatSpeed(state.stats.ulSpeed)),
                        ("Limite download", state.stats.dlSpeedLimit > 0 ? "\(state.stats.dlSpeedLimit) kB/s" : "Illimitato"),
                        ("Limite upload", state.stats.ulSpeedLimit > 0 ? "\(state.stats.ulSpeedLimit) kB/s" : "Illimitato"),
                        ("Overhead up", formatSpeed(Double(state.stats.upOverhead))),
                        ("Overhead down", formatSpeed(Double(state.stats.downOverhead))),
                    ])
                }
                GroupBox("Reti") {
                    statsGrid([
                        ("Utenti eD2k", "\(state.stats.ed2kUsers)"),
                        ("File eD2k", "\(state.stats.ed2kFiles)"),
                        ("Utenti Kad", "\(state.stats.kadUsers)"),
                        ("File Kad", "\(state.stats.kadFiles)"),
                        ("Nodi Kad", "\(state.stats.kadNodes)"),
                        ("Server eD2k", state.connState.ed2kLabel),
                        ("ID client", state.connState.ed2kID > 0 ? "\(state.connState.ed2kID)" : "—"),
                    ])
                }
                GroupBox("Trasferimenti") {
                    statsGrid([
                        ("Fonti totali", "\(state.stats.totalSources)"),
                        ("Coda upload", "\(state.stats.uploadQueueLength)"),
                        ("Client bannati", "\(state.stats.bannedCount)"),
                        ("File condivisi", "\(state.stats.sharedFileCount)"),
                        ("Totale inviato", formatBytes(state.stats.totalSent)),
                        ("Totale ricevuto", formatBytes(state.stats.totalReceived)),
                    ])
                }
                GroupBox("Server aMule") {
                    statsGrid([
                        ("Versione", state.serverVersion.isEmpty ? "—" : state.serverVersion),
                        ("Host", "\(state.host):\(state.port)"),
                    ])
                    HStack {
                        Spacer()
                        Button("Spegni amuled…", role: .destructive) {
                            confirmShutdown = true
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: 700, alignment: .leading)
        }
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

    private func statsGrid(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0).foregroundStyle(.secondary)
                    Text(row.1).font(.body.monospacedDigit())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
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
