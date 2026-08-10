import SwiftUI

struct SearchView: View {
    @EnvironmentObject var state: AppState

    @State private var query = ""
    @State private var searchType: ECSearchType = .global
    @State private var fileType = ""
    @State private var ext = ""
    @State private var minSize: Double? = nil
    @State private var maxSize: Double? = nil
    @State private var minUnit: SizeUnit = .mb
    @State private var maxUnit: SizeUnit = .mb
    @State private var availability: Int? = nil
    @State private var selection = Set<Data>()
    @State private var sortOrder = [KeyPathComparator(\SearchResultItem.sources, order: .reverse)]
    @State private var resultFilter = ""
    @State private var invertFilter = false
    @State private var hideKnown = false

    enum SizeUnit: String, CaseIterable, Identifiable {
        case kb = "KB", mb = "MB", gb = "GB"
        var id: String { rawValue }
        var multiplier: Double {
            switch self {
            case .kb: return 1024
            case .mb: return 1024 * 1024
            case .gb: return 1024 * 1024 * 1024
            }
        }
    }

    private static let fileTypes: [(String, String)] = [
        ("", "Qualsiasi"),
        ("Audio", "Audio"),
        ("Video", "Video"),
        ("Image", "Immagini"),
        ("Pro", "Programmi"),
        ("Doc", "Documenti"),
        ("Arc", "Archivi"),
        ("Iso", "Immagini CD/DVD"),
    ]

    private var activeResults: [SearchResultItem] {
        state.activeSearchSession?.results ?? []
    }

    private var searchRunning: Bool {
        state.searchSessions.contains { $0.inProgress }
    }

    private var sortedResults: [SearchResultItem] {
        var items = activeResults
        if !resultFilter.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(resultFilter) != invertFilter
            }
        }
        if hideKnown {
            items = items.filter { !$0.alreadyKnown }
        }
        return items.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            VStack(spacing: 12) {
                HStack {
                    TextField("Cerca file…", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { startSearch() }

                    Picker("", selection: $searchType) {
                        ForEach(ECSearchType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    .frame(width: 160)

                    Button {
                        startSearch()
                    } label: {
                        Label("Cerca", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.isEmpty)

                    Button {
                        Task { await state.stopSearch() }
                    } label: {
                        Label("Ferma", systemImage: "stop.fill")
                    }
                    .disabled(!searchRunning)
                }

                // Filters, clearly labeled
                HStack(alignment: .bottom, spacing: 14) {
                    filterField("Tipo di file", width: 150) {
                        Picker("", selection: $fileType) {
                            ForEach(Self.fileTypes, id: \.0) { v, label in
                                Text(label).tag(v)
                            }
                        }
                        .labelsHidden()
                    }
                    filterField("Estensione", width: 100) {
                        TextField("", text: $ext, prompt: Text("es. mkv"))
                    }
                    filterField("Dimensione minima", width: 150) {
                        HStack(spacing: 4) {
                            TextField("", value: $minSize, format: .number, prompt: Text("nessuna"))
                            Picker("", selection: $minUnit) {
                                ForEach(SizeUnit.allCases) { u in Text(u.rawValue).tag(u) }
                            }
                            .labelsHidden()
                            .frame(width: 62)
                        }
                    }
                    filterField("Dimensione massima", width: 150) {
                        HStack(spacing: 4) {
                            TextField("", value: $maxSize, format: .number, prompt: Text("nessuna"))
                            Picker("", selection: $maxUnit) {
                                ForEach(SizeUnit.allCases) { u in Text(u.rawValue).tag(u) }
                            }
                            .labelsHidden()
                            .frame(width: 62)
                        }
                    }
                    filterField("Disponibilità min", width: 100) {
                        TextField("", value: $availability, format: .number, prompt: Text("tutte"))
                    }
                    Button("Azzera campi") {
                        fileType = ""; ext = ""; minSize = nil; maxSize = nil; availability = nil
                        resultFilter = ""; invertFilter = false; hideKnown = false
                    }
                    .controlSize(.small)
                    Spacer()
                }
                .textFieldStyle(.roundedBorder)

                // Client-side filtering of results, like aMuleGUI's "Filtra risultati"
                HStack(spacing: 14) {
                    Text("Filtra risultati:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", text: $resultFilter, prompt: Text("testo nel nome"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Toggle("Inverti risultati", isOn: $invertFilter)
                        .disabled(resultFilter.isEmpty)
                    Toggle("Nascondi file già in coda", isOn: $hideKnown)
                    Spacer()
                    Button {
                        let items = sortedResults.filter { selection.contains($0.hash) }
                        Task { for i in items { await state.downloadResult(i) } }
                    } label: {
                        Label("Scarica", systemImage: "arrow.down.circle.fill")
                    }
                    .disabled(selection.isEmpty)
                }
                .toggleStyle(.checkbox)
                .font(.callout)

                if let active = state.activeSearchSession, active.inProgress {
                    ProgressView(value: active.progress > 0 ? active.progress : nil)
                        .progressViewStyle(.linear)
                }
            }
            .padding(12)

            Divider()

            // Search tabs, one per launched search (results cached per tab)
            if !state.searchSessions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(state.searchSessions) { session in
                            SearchTabView(session: session,
                                          isActive: state.activeSearchID == session.id,
                                          select: {
                                              state.activeSearchID = session.id
                                              selection = []
                                          },
                                          close: {
                                              Task { await state.closeSearchSession(session.id) }
                                          })
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(.bar)
                Divider()
            }

            Table(sortedResults, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Nome", value: \.name) { r in
                    Text(r.name)
                        .foregroundStyle(r.alreadyKnown ? .secondary : .primary)
                        .help(r.name)
                }
                .width(min: 260, ideal: 420)

                TableColumn("Dimensione", value: \.size) { r in
                    Text(formatBytes(r.size))
                }
                .width(95)

                TableColumn("Fonti", value: \.sources) { r in
                    Text("\(r.sources)")
                        .foregroundStyle(r.sources > 10 ? .green : .primary)
                }
                .width(60)

                TableColumn("Complete", value: \.completeSources) { r in
                    Text("\(r.completeSources)")
                }
                .width(70)

                TableColumn("Hash") { r in
                    Text(hexString(r.hash))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 240)
            }
            .contextMenu(forSelectionType: Data.self) { hashes in
                let items = activeResults.filter { hashes.contains($0.hash) }
                Button("Scarica") {
                    Task { for i in items { await state.downloadResult(i) } }
                }
                if !state.prefs.categories.isEmpty {
                    Menu("Scarica nella categoria") {
                        ForEach(state.prefs.categories) { cat in
                            Button(cat.title) {
                                Task { for i in items { await state.downloadResult(i, category: cat.index) } }
                            }
                        }
                    }
                }
            } primaryAction: { hashes in
                let items = activeResults.filter { hashes.contains($0.hash) }
                Task { for i in items { await state.downloadResult(i) } }
            }
            .onTableDoubleClick {
                let items = sortedResults.filter { selection.contains($0.hash) }
                guard !items.isEmpty else { return }
                Task { for i in items { await state.downloadResult(i) } }
            }
        }
        .navigationTitle("Ricerca")
        .navigationSubtitle(activeResults.isEmpty ? "" : "\(activeResults.count) risultati — doppio clic per scaricare")
    }

    private struct SearchTabView: View {
        let session: SearchSession
        let isActive: Bool
        let select: () -> Void
        let close: () -> Void

        var body: some View {
            HStack(spacing: 6) {
                if session.inProgress {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(session.query)
                    .lineLimit(1)
                    .frame(maxWidth: 160)
                Text("(\(session.results.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Chiudi questa ricerca")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                isActive ? AnyShapeStyle(Color.accentColor.opacity(0.25))
                         : AnyShapeStyle(Color.primary.opacity(0.06)),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture(perform: select)
        }
    }

    @ViewBuilder
    private func filterField(_ label: String, width: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .frame(width: width)
        }
    }

    private func startSearch() {
        guard !query.isEmpty else { return }
        Task {
            await state.startSearch(text: query, type: searchType, fileType: fileType,
                                    extension: ext,
                                    minSizeBytes: UInt64((minSize ?? 0) * minUnit.multiplier),
                                    maxSizeBytes: UInt64((maxSize ?? 0) * maxUnit.multiplier),
                                    availability: availability ?? 0)
        }
    }
}
