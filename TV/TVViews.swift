import SwiftUI

// Sezioni dell'app Apple TV. Ogni riga è un pulsante: la selezione col
// telecomando apre un foglio con le azioni; il tasto Play/Pausa del telecomando
// mette in pausa / riprende il download evidenziato.
//
// Leggibilità: quando una riga di List/Form è evidenziata tvOS la disegna su
// un "platter" bianco ma NON scurisce da solo il testo nel tema scuro (bug
// noto di SwiftUI per Toggle/Picker/Button dentro Form). Ogni riga segue
// quindi il proprio stato di focus con @FocusState e colora il testo di nero
// quando è evidenziata: vedi `TVInk`.

/// Colori del testo di una riga tvOS in funzione del focus.
enum TVInk {
    static func primary(_ focused: Bool) -> Color { focused ? .black : .primary }
    static func secondary(_ focused: Bool) -> Color { focused ? Color.black.opacity(0.62) : Color.secondary }
}

/// Riga "interruttore" per Form tvOS: un pulsante con On/Off disegnato da noi,
/// così anche il valore resta leggibile sulla riga evidenziata (il Toggle di
/// sistema lo scrive in bianco su bianco).
struct TVToggleRow: View {
    let title: LocalizedStringKey
    let icon: String
    @Binding var isOn: Bool
    @FocusState private var focused: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(TVInk.primary(focused))
                Spacer()
                Text(isOn ? "On" : "Off").foregroundStyle(TVInk.secondary(focused))
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? .green : TVInk.secondary(focused))
            }
        }
        .focused($focused)
    }
}

/// Riga "selettore" per Form tvOS: apre un elenco di opzioni con spunta.
struct TVPickerRow<T: Hashable>: View {
    let title: LocalizedStringKey
    let icon: String?
    let options: [(value: T, label: String, icon: String?)]
    @Binding var selection: T
    @FocusState private var focused: Bool

    private var currentLabel: String { options.first { $0.value == selection }?.label ?? "" }

    var body: some View {
        NavigationLink {
            TVOptionList(title: title, options: options, selection: $selection)
        } label: {
            HStack {
                if let icon {
                    Label(title, systemImage: icon).foregroundStyle(TVInk.primary(focused))
                } else {
                    Text(title).foregroundStyle(TVInk.primary(focused))
                }
                Spacer()
                // La freccia la disegna già il NavigationLink.
                Text(currentLabel).foregroundStyle(TVInk.secondary(focused))
            }
        }
        .focused($focused)
    }
}

struct TVOptionList<T: Hashable>: View {
    let title: LocalizedStringKey
    let options: [(value: T, label: String, icon: String?)]
    @Binding var selection: T
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedIndex: Int?

    var body: some View {
        List {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                let focused = focusedIndex == i
                Button {
                    selection = opt.value
                    dismiss()
                } label: {
                    HStack {
                        if let icon = opt.icon {
                            Label(opt.label, systemImage: icon).foregroundStyle(TVInk.primary(focused))
                        } else {
                            Text(opt.label).foregroundStyle(TVInk.primary(focused))
                        }
                        Spacer()
                        if opt.value == selection {
                            Image(systemName: "checkmark").foregroundStyle(focused ? .black : .accentColor)
                        }
                    }
                }
                .focused($focusedIndex, equals: i)
            }
        }
        .navigationTitle(title)
    }
}

/// Barra con velocità e stato reti, in testa alle sezioni (non focalizzabile).
struct TVStatusBar: View {
    @EnvironmentObject var state: AppState
    var title: String? = nil

    var body: some View {
        HStack(spacing: 34) {
            if let title {
                Text(title).font(.title3.bold()).foregroundStyle(.primary)
            }
            Label(formatSpeed(state.stats.dlSpeed), systemImage: "arrow.down")
                .foregroundStyle(.green)
            Label(formatSpeed(state.stats.ulSpeed), systemImage: "arrow.up")
                .foregroundStyle(.blue)
            Spacer()
            HStack(spacing: 10) {
                Circle()
                    .fill(state.connState.ed2kConnected ? (state.connState.lowID ? .yellow : .green) : .red)
                    .frame(width: 16, height: 16)
                Text("eD2k: \(state.connState.ed2kLabel)")
                Circle()
                    .fill(state.connState.kadOK ? (state.connState.kadFirewalled ? .yellow : .green)
                          : (state.connState.kadRunning ? .orange : .red))
                    .frame(width: 16, height: 16)
                    .padding(.leading, 14)
                Text("Kad: \(state.connState.kadLabel)")
            }
            .foregroundStyle(.secondary)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 60)
        .padding(.vertical, 12)
    }
}

// MARK: - Trasferimenti

struct TVTransfersView: View {
    @EnvironmentObject var state: AppState
    @State private var selected: DownloadItem?
    @State private var showPriority = false
    @State private var showAddLink = false
    @State private var newLink = ""
    @FocusState private var focusedHash: Data?

    private var sorted: [DownloadItem] {
        state.downloads.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var anyActive: Bool { state.downloads.contains { !$0.isPaused && !$0.isComplete } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TVStatusBar(title: String(localized: "Trasferimenti (\(state.downloads.count))"))
                // Poche azioni, grandi: aggiungi link, pausa/riprendi tutto, pulizia.
                HStack(spacing: 20) {
                    Button { showAddLink = true } label: { Label("Aggiungi link eD2k", systemImage: "plus.circle") }
                    if anyActive {
                        Button {
                            Task { let n = await state.pauseAll(); state.infoMessage = String(localized: "Messi in pausa \(n) download.") }
                        } label: { Label("Pausa tutti", systemImage: "pause.circle") }
                    } else {
                        Button {
                            Task { let n = await state.resumeAll(); state.infoMessage = String(localized: "Ripresi \(n) download.") }
                        } label: { Label("Riprendi tutti", systemImage: "play.circle") }
                        .disabled(!state.downloads.contains { $0.isPaused })
                    }
                    Button { Task { await state.clearCompleted() } } label: {
                        Label("Rimuovi completati", systemImage: "text.badge.checkmark")
                    }
                    .disabled(!state.downloads.contains { $0.isComplete })
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 60)
                .padding(.bottom, 10)

                if sorted.isEmpty {
                    ContentUnavailableView("Nessun download", systemImage: "arrow.down.circle",
                                           description: Text("Aggiungi un link eD2k o cerca un file."))
                } else {
                    List(sorted) { item in
                        Button { selected = item } label: {
                            TVDownloadRow(item: item, focused: focusedHash == item.hash)
                        }
                        .focused($focusedHash, equals: item.hash)
                        // Play/Pausa sul telecomando: agisce sulla riga evidenziata.
                        .onPlayPauseCommand {
                            Task { item.isPaused ? await state.resume(item) : await state.pause(item) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .onChange(of: state.addLinkRequested) { _, requested in
                if requested { showAddLink = true; state.addLinkRequested = false }
            }
            .confirmationDialog(selected?.name ?? "", isPresented: Binding(
                get: { selected != nil && !showPriority },
                set: { if !$0 { selected = nil } }
            ), titleVisibility: .visible) {
                if let item = selected {
                    if item.isPaused {
                        Button("Riprendi") { Task { await state.resume(item) } }
                    } else {
                        Button("Pausa") { Task { await state.pause(item) } }
                    }
                    Button("Ferma") { Task { await state.stop(item) } }
                    Button("Priorità…") { showPriority = true }
                    Button("Elimina", role: .destructive) { Task { await state.delete(item) } }
                    Button("Annulla", role: .cancel) { selected = nil }
                }
            }
            .confirmationDialog("Priorità", isPresented: $showPriority, titleVisibility: .visible) {
                ForEach([FilePriority.low, .normal, .high, .auto]) { p in
                    Button(p.label) {
                        if let item = selected { Task { await state.setPriority(item, p) } }
                        selected = nil
                    }
                }
                Button("Annulla", role: .cancel) { selected = nil }
            }
            .sheet(isPresented: $showAddLink) {
                TVAddLinkSheet(link: $newLink) { link in
                    Task { await state.addEd2kLink(link) }
                }
            }
        }
    }
}

struct TVAddLinkSheet: View {
    @Binding var link: String
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Text("Aggiungi link eD2k").font(.title2.bold())
            Text("Incolla o detta il link: con un iPhone vicino puoi usare la notifica «Tastiera Apple TV».")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("ed2k://|file|…", text: $link)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($fieldFocused)
                .onSubmit { add() }
                .frame(maxWidth: 1200)
            HStack(spacing: 24) {
                Button("Annulla", role: .cancel) { link = ""; dismiss() }
                Button { add() } label: { Label("Aggiungi", systemImage: "plus.circle") }
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(60)
        .onAppear { fieldFocused = true }
    }

    private func add() {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !l.isEmpty else { return }
        link = ""
        onAdd(l)
        dismiss()
    }
}

struct TVDownloadRow: View {
    let item: DownloadItem
    var focused = false

    private var barColor: Color {
        if item.isComplete { return .green }
        if item.status == PartFileStatus.error.rawValue { return Color(red: 0.6, green: 0, blue: 0) }
        if item.isPaused { return .orange }
        if item.speed > 0 || item.sourcesXfer > 0 { return .blue }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.name)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(TVInk.primary(focused))
            ProgressView(value: item.progress)
                .tint(barColor)
            HStack(spacing: 18) {
                Text(String(format: "%.1f%% di %@", item.progress * 100, formatBytes(item.sizeFull)))
                Text("Fonti: \(item.sourcesXfer)/\(item.sources)")
                Text(FilePriority.describe(item.priority))
                Spacer()
                if item.speed > 0 {
                    Text(formatSpeed(item.speed)).foregroundStyle(.green)
                } else if item.isPaused {
                    Text(item.statusLabel).foregroundStyle(.orange)
                } else {
                    Text(item.statusLabel)
                }
                if !item.etaLabel.isEmpty { Text(item.etaLabel) }
            }
            .font(.callout)
            .foregroundStyle(TVInk.secondary(focused))
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Ricerca

/// Ricerca con la barra nativa di tvOS (.searchable): tastiera a schermo,
/// dettatura Siri e tastiera dell'iPhone funzionano da sole.
struct TVSearchView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var type: ECSearchType = .global
    @State private var selected: SearchResultItem?
    @FocusState private var focusedHash: Data?

    private var session: SearchSession? { state.activeSearchSession }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Tipo ricerca", selection: $type) {
                        ForEach(ECSearchType.allCases) { t in Text(t.label).tag(t) }
                    }
                    .pickerStyle(.segmented)
                    if let s = session, s.inProgress {
                        HStack {
                            ProgressView(value: s.progress)
                            Button { Task { await state.stopSearch() } } label: { Label("Ferma", systemImage: "stop.fill") }
                        }
                    }
                }
                if let s = session {
                    Section(s.results.isEmpty && !s.inProgress ? "Nessun risultato" : "Risultati (\(s.results.count))") {
                        ForEach(s.results) { r in
                            let focused = focusedHash == r.hash
                            Button { selected = r } label: {
                                HStack(spacing: 20) {
                                    Text(r.name)
                                        .lineLimit(1)
                                        .foregroundStyle(state.matchState(for: r.hash).color ?? TVInk.primary(focused))
                                    Spacer()
                                    Text(formatBytes(r.size))
                                    Text("Fonti: \(r.completeSources)/\(r.sources)")
                                }
                                .foregroundStyle(TVInk.secondary(focused))
                            }
                            .focused($focusedHash, equals: r.hash)
                        }
                    }
                } else {
                    Section {
                        Text("Scrivi il testo nella barra di ricerca e premi Cerca. I risultati già in download sono in rosso, quelli già scaricati in verde.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: Text("Cerca file…"))
            .onSubmit(of: .search) { search() }
            .confirmationDialog(selected?.name ?? "", isPresented: Binding(
                get: { selected != nil }, set: { if !$0 { selected = nil } }
            ), titleVisibility: .visible) {
                if let r = selected {
                    Button { Task { await state.downloadResult(r) } } label: { Label("Scarica", systemImage: "arrow.down.circle") }
                    Button("Annulla", role: .cancel) { selected = nil }
                }
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        Task {
            await state.startSearch(text: q, type: type, fileType: "", extension: "",
                                    minSizeBytes: 0, maxSizeBytes: 0, availability: 0)
        }
    }
}

// MARK: - Server

struct TVServersView: View {
    @EnvironmentObject var state: AppState
    @State private var selected: ServerItem?
    @FocusState private var focusedID: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TVStatusBar(title: String(localized: "Server (\(state.servers.count))"))
                HStack(spacing: 20) {
                    if state.connState.ed2kConnected || state.connState.ed2kConnecting {
                        Button { Task { await state.disconnectFromServer() } } label: { Label("Disconnetti", systemImage: "bolt.slash") }
                    } else {
                        Button { Task { await state.connectToAnyServer() } } label: { Label("Connetti", systemImage: "bolt") }
                    }
                    if state.connState.kadRunning {
                        Button { Task { await state.kadStop() } } label: { Label("Kad: Ferma", systemImage: "stop.circle") }
                    } else {
                        Button { Task { await state.kadStart() } } label: { Label("Kad: Avvia", systemImage: "play.circle") }
                    }
                    Button { Task { await state.refreshServers() } } label: { Label("Ricarica dal server", systemImage: "arrow.clockwise") }
                    Spacer()
                }
                .font(.callout)
                .padding(.horizontal, 60)
                .padding(.bottom, 10)
                List(state.servers) { s in
                    let focused = focusedID == s.id
                    Button { selected = s } label: {
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(s.name).font(.headline).foregroundStyle(TVInk.primary(focused))
                                Text(s.address).font(.callout).foregroundStyle(TVInk.secondary(focused))
                            }
                            Spacer()
                            Group {
                                Text("Utenti: \(s.users)")
                                Text("File: \(s.files)")
                                Text("Ping: \(s.ping)")
                            }
                            .foregroundStyle(TVInk.secondary(focused))
                            if state.connState.serverAddress == s.address {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                        .font(.callout)
                    }
                    .focused($focusedID, equals: s.id)
                }
                .listStyle(.plain)
            }
            .confirmationDialog(selected?.name ?? "", isPresented: Binding(
                get: { selected != nil }, set: { if !$0 { selected = nil } }
            ), titleVisibility: .visible) {
                if let s = selected {
                    Button { Task { await state.connectToServer(s) } } label: { Label("Connetti", systemImage: "bolt") }
                    Button("Rimuovi", role: .destructive) { Task { await state.removeServer(s) } }
                    Button("Annulla", role: .cancel) { selected = nil }
                }
            }
            .task { if state.servers.isEmpty { await state.refreshServers() } }
        }
    }
}

// MARK: - Statistiche

struct TVStatsView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focusedRow: String?

    var body: some View {
        NavigationStack {
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
                Section("Server aMule") {
                    statRow("Server", "server.rack", state.demoMode ? "DEMO (dati di esempio)" : "\(state.host):\(state.port)")
                    statRow("Versione aMule", "info.circle", state.serverVersion.isEmpty ? "—" : state.serverVersion)
                }
            }
        }
    }

    /// Riga focalizzabile (così la lista scorre col telecomando) e leggibile a fuoco.
    @ViewBuilder
    private func statRow(_ title: LocalizedStringKey, _ icon: String, _ value: String) -> some View {
        let focused = focusedRow == icon + value
        LabeledContent {
            Text(value).foregroundStyle(TVInk.secondary(focused))
        } label: {
            Label(title, systemImage: icon).foregroundStyle(TVInk.primary(focused))
        }
        .focusable()
        .focused($focusedRow, equals: icon + value)
    }
}

// MARK: - Impostazioni

struct TVSettingsView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focus: Row?

    private enum Row: Hashable { case server, disconnect }

    var body: some View {
        NavigationStack {
            Form {
                if !state.profiles.isEmpty {
                    Section("Profili server") {
                        TVPickerRow(title: "Profilo attivo", icon: "server.rack",
                                    options: state.profiles.map { p in
                                        (value: Optional(p.id), label: p.id == state.defaultProfileID ? "\(p.name) ★" : p.name, icon: nil)
                                    } + (state.currentProfile == nil ? [(value: Optional<UUID>.none, label: state.demoMode ? "Demo" : "—", icon: nil)] : []),
                                    selection: Binding(
                                        get: { state.currentProfile?.id },
                                        set: { newID in
                                            if let id = newID, let p = state.profiles.first(where: { $0.id == id }) {
                                                Task { await state.switchProfile(to: p) }
                                            }
                                        }))
                    }
                }
                Section {
                    TVPickerRow(title: "Aspetto", icon: "circle.lefthalf.filled",
                                options: ThemeMode.allCases.map { (value: $0, label: $0.label, icon: $0.icon) },
                                selection: $state.themeMode)
                    TVPickerRow(title: "Lingua", icon: "globe",
                                options: AppLanguage.allCases.map { (value: $0, label: $0.label, icon: nil) },
                                selection: $state.appLanguage)
                    TVToggleRow(title: "Sincronizza profili con iCloud", icon: "icloud", isOn: Binding(
                        get: { state.iCloudSyncEnabled },
                        set: { state.setCloudSync($0) }))
                } header: {
                    Text("Impostazioni app")
                } footer: {
                    Text("Quando l'app lascia lo schermo la connessione al server si chiude, ma i dati restano visibili in stato Offline: riparte da sola alla riapertura. Con la sincronizzazione iCloud i profili server e le loro password (Portachiavi iCloud) sono condivisi tra i tuoi dispositivi.")
                }
                Section("Connessione") {
                    LabeledContent {
                        Text(state.demoMode ? "DEMO (dati di esempio)" : "\(state.host):\(state.port)")
                            .foregroundStyle(TVInk.secondary(focus == .server))
                    } label: {
                        Label("Server", systemImage: "server.rack")
                            .foregroundStyle(TVInk.primary(focus == .server))
                    }
                    .focusable()
                    .focused($focus, equals: .server)
                    Button(role: .destructive) {
                        Task { await state.disconnect() }
                    } label: {
                        Label("Disconnetti", systemImage: "xmark.circle")
                            .foregroundStyle(focus == .disconnect ? Color.red.opacity(0.85) : Color.red)
                    }
                    .focused($focus, equals: .disconnect)
                }
                AppInfoSection()
            }
        }
    }
}
