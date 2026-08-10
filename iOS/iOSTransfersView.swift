import SwiftUI

struct iOSTransfersView: View {
    @EnvironmentObject var state: AppState
    @State private var showAddLink = false
    @State private var newLink = ""
    @State private var selection = Set<Data>()
    @State private var editMode: EditMode = .inactive
    @State private var confirmDelete = false
    @AppStorage("iosSortTransfers") private var sortKey = "nome"
    @AppStorage("iosSortTransfersAsc") private var sortAsc = true

    private var selectedItems: [DownloadItem] {
        state.downloads.filter { selection.contains($0.hash) }
    }

    private var sortedDownloads: [DownloadItem] {
        let items = state.downloads
        let sorted: [DownloadItem]
        switch sortKey {
        case "avanzamento": sorted = items.sorted { $0.progress < $1.progress }
        case "dimensione": sorted = items.sorted { $0.sizeFull < $1.sizeFull }
        case "velocita": sorted = items.sorted { $0.speed < $1.speed }
        case "stato": sorted = items.sorted { $0.status < $1.status }
        case "fonti": sorted = items.sorted { $0.sources < $1.sources }
        case "priorita": sorted = items.sorted { $0.priority < $1.priority }
        case "aggiunti": sorted = items.sorted { $0.partmetID > $1.partmetID } // nuovi prima
        default: sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return sortAsc ? sorted : sorted.reversed()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                iOSStatusBar()
                List(sortedDownloads, selection: $selection) { item in
                    DownloadRow(item: item)
                        .swipeActions(edge: .leading) {
                            if item.isPaused {
                                Button {
                                    Task { await state.resume(item) }
                                } label: { Label("Riprendi", systemImage: "play.fill") }
                                .tint(.green)
                            } else {
                                Button {
                                    Task { await state.pause(item) }
                                } label: { Label("Pausa", systemImage: "pause.fill") }
                                .tint(.orange)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await state.delete(item) }
                            } label: { Label("Elimina", systemImage: "trash") }
                        }
                        .contextMenu {
                            Button("Riprendi") { Task { await state.resume(item) } }
                            Button("Pausa") { Task { await state.pause(item) } }
                            Button("Ferma") { Task { await state.stop(item) } }
                            Divider()
                            Menu("Priorità") {
                                ForEach([FilePriority.low, .normal, .high, .auto]) { p in
                                    Button(p.label) { Task { await state.setPriority(item, p) } }
                                }
                            }
                            if !item.ed2kLink.isEmpty {
                                Button("Copia link eD2k") {
                                    UIPasteboard.general.string = item.ed2kLink
                                }
                            }
                            Divider()
                            Button("Elimina", role: .destructive) {
                                Task { await state.delete(item) }
                            }
                        }
                }
                .listStyle(.plain)
                .environment(\.editMode, $editMode)
                .refreshable { await state.refreshDownloads() }

                if editMode == .active && !selection.isEmpty {
                    selectionBar
                }
            }
            .navigationTitle("Trasferimenti (\(state.downloads.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SortMenu(options: [("aggiunti", "Appena aggiunti"), ("nome", "Nome"),
                                       ("avanzamento", "Avanzamento"), ("dimensione", "Dimensione"),
                                       ("velocita", "Velocità"), ("stato", "Stato"),
                                       ("fonti", "Fonti"), ("priorita", "Priorità")],
                             sortKey: $sortKey, ascending: $sortAsc)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(editMode == .active ? "Fine" : "Seleziona") {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                            if editMode == .inactive { selection = [] }
                        }
                    }
                    if editMode == .inactive {
                        Button {
                            showAddLink = true
                        } label: { Image(systemName: "plus.circle") }
                        Button {
                            Task { await state.clearCompleted() }
                        } label: { Image(systemName: "checkmark.circle") }
                    }
                }
            }
            .alert("Aggiungi link eD2k", isPresented: $showAddLink) {
                TextField("ed2k://|file|…", text: $newLink)
                Button("Annulla", role: .cancel) { newLink = "" }
                Button("Aggiungi") {
                    let l = newLink
                    newLink = ""
                    Task { await state.addEd2kLink(l) }
                }
            }
            .confirmationDialog("Eliminare \(selectedItems.count) file dal server?",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina \(selectedItems.count) file", role: .destructive) {
                    let items = selectedItems
                    selection = []
                    Task { for i in items { await state.delete(i) } }
                }
                Button("Annulla", role: .cancel) {}
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 0) {
            bulkButton("Riprendi", "play.fill") { for i in $0 { await state.resume(i) } }
            bulkButton("Pausa", "pause.fill") { for i in $0 { await state.pause(i) } }
            bulkButton("Ferma", "stop.fill") { for i in $0 { await state.stop(i) } }
            Menu {
                ForEach([FilePriority.low, .normal, .high, .auto]) { p in
                    Button(p.label) {
                        let items = selectedItems
                        Task { for i in items { await state.setPriority(i, p) } }
                    }
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Priorità").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "trash")
                    Text("Elimina").font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func bulkButton(_ title: String, _ icon: String,
                            action: @escaping ([DownloadItem]) async -> Void) -> some View {
        Button {
            let items = selectedItems
            Task { await action(items) }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct DownloadRow: View {
    let item: DownloadItem

    private var barColor: Color {
        if item.isComplete { return .green }
        if item.status == PartFileStatus.error.rawValue { return Color(red: 0.6, green: 0, blue: 0) }
        if item.isPaused { return .orange }
        if item.speed > 0 || item.sourcesXfer > 0 { return .blue }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.name)
                .font(.subheadline)
                .lineLimit(2)
            ProgressView(value: item.progress)
                .tint(barColor)
            HStack {
                Text(String(format: "%.1f%% di %@", item.progress * 100, formatBytes(item.sizeFull)))
                Spacer()
                if item.speed > 0 {
                    Text(formatSpeed(item.speed))
                        .foregroundStyle(.green)
                } else {
                    Text(item.statusLabel)
                        .foregroundStyle(item.isPaused ? .orange : .secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Text("Fonti: \(item.sourcesXfer)/\(item.sources)")
                Spacer()
                Text(FilePriority.describe(item.priority))
                if !item.etaLabel.isEmpty {
                    Text("• \(item.etaLabel)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
