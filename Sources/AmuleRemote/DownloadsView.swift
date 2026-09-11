import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection = Set<Data>()
    @State private var showAddLink = false
    @State private var confirmDelete = false
    @State private var sortOrder = [KeyPathComparator(\DownloadItem.name)]

    private var sortedDownloads: [DownloadItem] {
        state.downloads.sorted(using: sortOrder)
    }

    private var selectedItems: [DownloadItem] {
        state.downloads.filter { selection.contains($0.hash) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(sortedDownloads, selection: $selection, sortOrder: $sortOrder) {
              Group {
                TableColumn("N.", value: \.partmetID) { item in
                    partCell(item)
                }
                .width(45)

                TableColumn("Nome", value: \.name) { item in
                    Text(item.name).help(item.name)
                }
                .width(min: 200, ideal: 320)

                TableColumn("Dimensione", value: \.sizeFull) { item in
                    Text(formatBytes(item.sizeFull))
                }
                .width(90)

                TableColumn("Completati", value: \.sizeDone) { item in
                    Text(formatBytes(item.sizeDone))
                }
                .width(90)

                TableColumn("Trasferiti", value: \.sizeXfer) { item in
                    Text(formatBytes(item.sizeXfer))
                }
                .width(90)

                TableColumn("Avanzamento", value: \.progress) { item in
                    progressCell(item)
                }
                .width(min: 130, ideal: 170)

              }
              Group {
                TableColumn("Velocità", value: \.speed) { item in
                    speedCell(item)
                }
                .width(85)

                TableColumn("Tempo") { item in
                    Text(item.etaLabel)
                        .foregroundStyle(.secondary)
                }
                .width(75)

                TableColumn("Età", value: \.ageDays) { item in
                    Text(item.isComplete ? "—" : item.ageText)
                        .foregroundStyle(.secondary)
                        .help(item.isComplete ? "" : "In download da \(item.ageText)")
                }
                .width(80)

                TableColumn("Stato", value: \.status) { item in
                    statusCell(item)
                }
                .width(110)

                TableColumn("Fonti", value: \.sources) { item in
                    sourcesCell(item)
                }
                .width(80)

                TableColumn("Priorità", value: \.priority) { item in
                    Text(FilePriority.describe(item.priority))
                }
                .width(90)
              }
            }
            .contextMenu(forSelectionType: Data.self) { hashes in
                contextMenu(for: state.downloads.filter { hashes.contains($0.hash) })
            }

            if !selection.isEmpty {
                selectionBar
            }
            Ed2kLinkBar()
            UploadsBar()
        }
        .navigationTitle("Trasferimenti")
        .navigationSubtitle("\(state.downloads.count) file in coda")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showAddLink = true
                } label: {
                    Label("Aggiungi link eD2k", systemImage: "plus.circle")
                }
                .help("Aggiungi un link ed2k:// o magnet")

                // Stesso "visto" di iOS: menu con selezione e pulizia dei completati.
                Menu {
                    Button {
                        selection = Set(state.downloads.map(\.hash))
                    } label: {
                        Label("Seleziona tutto", systemImage: "checkmark.circle")
                    }
                    .disabled(state.downloads.isEmpty)
                    Button {
                        selection = []
                    } label: {
                        Label("Deseleziona", systemImage: "circle")
                    }
                    .disabled(selection.isEmpty)
                    Divider()
                    Button {
                        Task { await state.clearCompleted() }
                    } label: {
                        Label("Rimuovi completati", systemImage: "text.badge.checkmark")
                    }
                    .disabled(!state.downloads.contains { $0.isComplete })
                } label: {
                    Label("Seleziona", systemImage: "checkmark.circle")
                }
                .help("Seleziona i download o rimuovi dalla lista quelli completati")

                Button {
                    Task { await state.refreshDownloads() }
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
            }
        }
        .onChange(of: state.addLinkRequested) { _, requested in
            if requested { showAddLink = true; state.addLinkRequested = false }
        }
        .onAppear {
            if state.addLinkRequested { showAddLink = true; state.addLinkRequested = false }
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkSheet().environmentObject(state)
        }
        .confirmationDialog("Eliminare i download selezionati?", isPresented: $confirmDelete) {
            Button("Elimina \(selectedItems.count) file", role: .destructive) {
                let items = selectedItems
                Task { for i in items { await state.delete(i) } }
            }
        } message: {
            Text("I file parziali verranno rimossi dal server. L'operazione non è reversibile.")
        }
    }

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            // Stesse azioni e stesse icone della barra di selezione di iOS.
            HStack(spacing: 10) {
                Text("\(selectedItems.count) selezionati")
                    .font(.callout.weight(.medium))
                Button {
                    let items = selectedItems
                    Task { for i in items { await state.resume(i) } }
                } label: { Label("Riprendi", systemImage: "play.fill") }
                Button {
                    let items = selectedItems
                    Task { for i in items { await state.pause(i) } }
                } label: { Label("Pausa", systemImage: "pause.fill") }
                Button {
                    let items = selectedItems
                    Task { for i in items { await state.stop(i) } }
                } label: { Label("Ferma", systemImage: "stop.fill") }
                Menu {
                    ForEach([FilePriority.low, .normal, .high, .auto]) { p in
                        Button(p.label) {
                            let items = selectedItems
                            Task { for i in items { await state.setPriority(i, p) } }
                        }
                    }
                } label: { Label("Priorità", systemImage: "slider.horizontal.3") }
                .fixedSize()
                if !state.prefs.categories.isEmpty {
                    Menu {
                        Button("Nessuna") {
                            let items = selectedItems
                            Task { for i in items { await state.setCategory(i, 0) } }
                        }
                        ForEach(state.prefs.categories) { cat in
                            Button(cat.title) {
                                let items = selectedItems
                                Task { for i in items { await state.setCategory(i, cat.index) } }
                            }
                        }
                    } label: { Label("Categoria", systemImage: "folder") }
                    .fixedSize()
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: { Label("Elimina…", systemImage: "trash") }
                .tint(.red)
                Spacer()
                Button {
                    selection = []
                } label: { Label("Deseleziona", systemImage: "circle") }
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    // MARK: - Table cells (kept small so the type-checker stays fast)

    private func partCell(_ item: DownloadItem) -> some View {
        Text(item.partmetID > 0 ? String(format: "%03d", item.partmetID) : "—")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .help("Numero progressivo: ordina discendente per vedere prima i download aggiunti di recente")
    }

    private func progressCell(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: item.progress)
                .progressViewStyle(.linear)
                .tint(progressColor(item))
            Text(String(format: "%.1f%%", item.progress * 100))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func speedCell(_ item: DownloadItem) -> some View {
        Text(item.speed > 0 ? formatSpeed(item.speed) : "—")
            .foregroundStyle(item.speed > 0 ? Color.green : Color.secondary)
    }

    private func statusCell(_ item: DownloadItem) -> some View {
        Text(item.statusLabel)
            .foregroundStyle(item.isPaused ? Color.orange : Color.primary)
    }

    private func sourcesCell(_ item: DownloadItem) -> some View {
        Text("\(item.sourcesXfer)/\(item.sources)" + (item.sourcesA4AF > 0 ? " (+\(item.sourcesA4AF))" : ""))
    }

    /// aMuleGUI-style bar colors: green complete, blue transferring,
    /// orange paused/stopped, red waiting with nothing moving, dark red on error.
    private func progressColor(_ item: DownloadItem) -> Color {
        if item.isComplete { return .green }
        if item.status == PartFileStatus.error.rawValue { return Color(red: 0.6, green: 0, blue: 0) }
        if item.isPaused { return .orange }
        if item.speed > 0 || item.sourcesXfer > 0 { return .blue }
        return .red
    }

    @ViewBuilder
    private func contextMenu(for items: [DownloadItem]) -> some View {
        Button("Riprendi") {
            Task { for i in items { await state.resume(i) } }
        }
        Button("Pausa") {
            Task { for i in items { await state.pause(i) } }
        }
        Button("Ferma") {
            Task { for i in items { await state.stop(i) } }
        }
        Divider()
        Menu("Priorità") {
            ForEach([FilePriority.low, .normal, .high, .auto]) { p in
                Button(p.label) {
                    Task { for i in items { await state.setPriority(i, p) } }
                }
            }
        }
        if !state.prefs.categories.isEmpty {
            Menu("Categoria") {
                Button("Nessuna") {
                    Task { for i in items { await state.setCategory(i, 0) } }
                }
                ForEach(state.prefs.categories) { cat in
                    Button(cat.title) {
                        Task { for i in items { await state.setCategory(i, cat.index) } }
                    }
                }
            }
        }
        Divider()
        if items.count == 1, let item = items.first, !item.ed2kLink.isEmpty {
            Button("Copia link eD2k") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.ed2kLink, forType: .string)
            }
        }
        let links = items.map(\.ed2kLink).filter { !$0.isEmpty }
        if !links.isEmpty {
            ShareLink(item: links.joined(separator: "\n")) {
                Label(links.count > 1 ? "Condividi link eD2k (\(links.count))" : "Condividi link eD2k", systemImage: "square.and.arrow.up")
            }
        }
        Button("Elimina…", role: .destructive) {
            selection = Set(items.map(\.hash))
            confirmDelete = true
        }
    }
}

struct Ed2kLinkBar: View {
    @EnvironmentObject var state: AppState
    @State private var link = ""

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text("Link eD2k:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("ed2k://|file|…", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send() }
                Button("Invia") { send() }
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private func send() {
        let l = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !l.isEmpty else { return }
        link = ""
        Task { await state.addEd2kLink(l) }
    }
}

struct UploadsBar: View {
    @EnvironmentObject var state: AppState
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            DisclosureGroup(isExpanded: $expanded) {
                Table(state.uploads) {
                    TableColumn("Utente") { u in Text(u.userName) }
                    TableColumn("Client") { u in Text(u.software) }.width(120)
                    TableColumn("File") { u in Text(u.fileName) }.width(min: 200)
                    TableColumn("Velocità") { u in Text(formatSpeed(u.upSpeed)) }.width(90)
                    TableColumn("Caricati (sessione)") { u in Text(formatBytes(u.uploadedSession)) }.width(130)
                }
                .frame(height: 160)
            } label: {
                Label("Upload attivi: \(state.uploads.count)", systemImage: "arrow.up.circle")
                    .font(.callout)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}
