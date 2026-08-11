import SwiftUI

struct iOSSearchView: View {
    @EnvironmentObject var state: AppState

    @State private var query = ""
    @State private var searchType: ECSearchType = .global
    @State private var fileType = ""
    @State private var ext = ""
    @State private var minSizeMB: Double? = nil
    @State private var maxSizeMB: Double? = nil
    @State private var showFilters = false
    @State private var downloadTarget: SearchResultItem?
    @FocusState private var searchFieldFocused: Bool
    @AppStorage("iosSortSearch") private var sortKey = "fonti"
    @AppStorage("iosSortSearchAsc") private var sortAsc = false

    private static let fileTypes: [(String, String)] = [
        ("", "Qualsiasi"), ("Audio", "Audio"), ("Video", "Video"),
        ("Image", "Immagini"), ("Pro", "Programmi"), ("Doc", "Documenti"),
        ("Arc", "Archivi"), ("Iso", "Immagini CD/DVD"),
    ]

    private var activeSession: SearchSession? { state.activeSearchSession }

    private var sortedResults: [SearchResultItem] {
        let items = activeSession?.results ?? []
        let sorted: [SearchResultItem]
        switch sortKey {
        case "nome": sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "dimensione": sorted = items.sorted { $0.size < $1.size }
        case "complete": sorted = items.sorted { $0.completeSources < $1.completeSources }
        default: sorted = items.sorted { $0.sources < $1.sources }
        }
        return sortAsc ? sorted : sorted.reversed()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                iOSStatusBar()

                // Search controls
                VStack(spacing: 8) {
                    HStack {
                        TextField("Cerca file…", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($searchFieldFocused)
                            .onSubmit { startSearch() }
                        SortMenu(options: [("fonti", "Fonti"), ("nome", "Nome"),
                                           ("dimensione", "Dimensione"), ("complete", "Fonti complete")],
                                 sortKey: $sortKey, ascending: $sortAsc)
                        Button {
                            startSearch()
                        } label: {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.title2)
                        }
                        .disabled(query.isEmpty)
                        Button {
                            showFilters.toggle()
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                    HStack {
                        Picker("Tipo ricerca", selection: $searchType) {
                            ForEach(ECSearchType.allCases) { t in Text(t.label).tag(t) }
                        }
                        .pickerStyle(.segmented)
                        if state.searchSessions.contains(where: { $0.inProgress }) {
                            Button("Ferma") { Task { await state.stopSearch() } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Session tabs
                if !state.searchSessions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(state.searchSessions) { session in
                                HStack(spacing: 5) {
                                    if session.inProgress { ProgressView().controlSize(.mini) }
                                    Text(session.query).lineLimit(1)
                                    Text("(\(session.results.count))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Button {
                                        Task { await state.closeSearchSession(session.id) }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .font(.footnote)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    state.activeSearchID == session.id
                                        ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                                        : AnyShapeStyle(Color.primary.opacity(0.06)),
                                    in: Capsule())
                                .onTapGesture { state.activeSearchID = session.id }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }
                }

                if let active = activeSession, active.inProgress {
                    ProgressView(value: active.progress > 0 ? active.progress : nil)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 12)
                }

                Divider()

                List {
                    ForEach(sortedResults) { r in
                        Button {
                            downloadTarget = r
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                let m = state.matchState(for: r.hash)
                                HStack(spacing: 5) {
                                    if m != .none {
                                        Image(systemName: m == .completed ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                            .foregroundStyle(m.color ?? .primary)
                                            .font(.caption)
                                    }
                                    Text(r.name)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .foregroundStyle(m.color ?? (r.alreadyKnown ? .secondary : .primary))
                                }
                                HStack {
                                    Text(formatBytes(r.size))
                                    Spacer()
                                    Text("\(r.sources) fonti (\(r.completeSources) complete)")
                                        .foregroundStyle(r.sources > 10 ? .green : .secondary)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Ricerca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        searchFieldFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
            }
            .sheet(isPresented: $showFilters) { filtersSheet }
            .confirmationDialog(downloadTarget?.name ?? "",
                                isPresented: Binding(get: { downloadTarget != nil },
                                                     set: { if !$0 { downloadTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Scarica") {
                    if let t = downloadTarget { Task { await state.downloadResult(t) } }
                    downloadTarget = nil
                }
                Button("Annulla", role: .cancel) { downloadTarget = nil }
            }
        }
    }

    private var filtersSheet: some View {
        NavigationStack {
            Form {
                Picker("Tipo di file", selection: $fileType) {
                    ForEach(Self.fileTypes, id: \.0) { v, label in Text(label).tag(v) }
                }
                TextField("Estensione (es. mkv)", text: $ext)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Dimensione minima (MB)", value: $minSizeMB, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Dimensione massima (MB)", value: $maxSizeMB, format: .number)
                    .keyboardType(.decimalPad)
                Button("Azzera filtri") {
                    fileType = ""; ext = ""; minSizeMB = nil; maxSizeMB = nil
                }
            }
            .navigationTitle("Filtri ricerca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { showFilters = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func startSearch() {
        guard !query.isEmpty else { return }
        Task {
            await state.startSearch(text: query, type: searchType, fileType: fileType,
                                    extension: ext,
                                    minSizeBytes: UInt64((minSizeMB ?? 0) * 1024 * 1024),
                                    maxSizeBytes: UInt64((maxSizeMB ?? 0) * 1024 * 1024),
                                    availability: 0)
        }
    }
}
