import SwiftUI

// Layout adattivi per iPad e iPhone Duo.
//
// - Larghezza compatta (iPhone, Duo chiuso): la TabView classica (iOSRootView).
// - Larghezza regolare (iPad, Duo aperto del tutto): `iOSSplitLayout`, due
//   colonne con l'elenco delle sezioni a sinistra e la sezione a destra, come
//   sul Mac.
// - Cerniera parzialmente aperta (Duo appoggiato «a mini computer»):
//   `iOSHingeDeckLayout`, contenuto nella metà alta dello schermo e comandi
//   (sezioni, stato, azioni rapide, ricerca) nella metà bassa, sopra la piega.

/// Le sezioni raggiungibili dall'interfaccia iPhone/iPad (le altre sono nel Mac).
enum iOSSection: String, CaseIterable, Identifiable {
    case downloads, search, servers, more
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .downloads: return "Trasferimenti"
        case .search: return "Ricerca"
        case .servers: return "Server"
        case .more: return "Altro"
        }
    }

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .search: return "magnifyingglass"
        case .servers: return "server.rack"
        case .more: return "ellipsis.circle"
        }
    }

    var appSection: AppSection {
        switch self {
        case .downloads: return .downloads
        case .search: return .search
        case .servers: return .servers
        case .more: return .stats
        }
    }

    init(_ section: AppSection?) {
        switch section ?? .downloads {
        case .search: self = .search
        case .servers: self = .servers
        case .downloads: self = .downloads
        default: self = .more
        }
    }

    @ViewBuilder var content: some View {
        switch self {
        case .downloads: iOSTransfersView()
        case .search: iOSSearchView()
        case .servers: iOSServersView()
        case .more: iOSMoreView()
        }
    }
}

/// Binding fra la sezione dell'interfaccia e `AppState.selectedSection`
/// (così `-section …`, le azioni rapide e Handoff continuano a funzionare).
struct iOSSectionSelection {
    static func binding(_ state: AppState) -> Binding<iOSSection> {
        Binding(get: { iOSSection(state.selectedSection) },
                set: { state.selectedSection = $0.appSection })
    }
}

/// Due colonne: elenco delle sezioni + contenuto. iPad e iPhone Duo aperto.
struct iOSSplitLayout: View {
    @EnvironmentObject var state: AppState
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        let selection = iOSSectionSelection.binding(state)
        NavigationSplitView(columnVisibility: $columns) {
            List(iOSSection.allCases, selection: Binding(
                get: { Optional(selection.wrappedValue) },
                set: { if let s = $0 { selection.wrappedValue = s } }
            )) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationTitle("aMule Remote")
            .safeAreaInset(edge: .bottom) {
                iOSSidebarStatus()
            }
        } detail: {
            selection.wrappedValue.content
                .id(selection.wrappedValue)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// Velocità e stato delle reti in fondo alla barra laterale.
private struct iOSSidebarStatus: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(formatSpeed(state.stats.dlSpeed), systemImage: "arrow.down")
                    .foregroundStyle(.green)
                Label(formatSpeed(state.stats.ulSpeed), systemImage: "arrow.up")
                    .foregroundStyle(.blue)
            }
            HStack(spacing: 10) {
                iOSNetworkDot(ok: state.connState.ed2kConnected, warn: state.connState.lowID,
                              label: "eD2k")
                iOSNetworkDot(ok: state.connState.kadOK, warn: state.connState.kadFirewalled,
                              pending: state.connState.kadRunning, label: "Kad")
            }
            if let p = state.currentProfile {
                Label(p.name, systemImage: "externaldrive.connected.to.line.below")
                    .lineLimit(1)
            } else if state.demoMode {
                Label("Demo", systemImage: "play.circle")
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct iOSNetworkDot: View {
    let ok: Bool
    var warn = false
    var pending = false
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ok ? (warn ? Color.yellow : .green) : (pending ? .orange : .red))
                .frame(width: 7, height: 7)
            Text(label)
        }
    }
}

/// Postura «mini computer» (cerniera a metà): contenuto sopra la piega,
/// comandi sotto. L'altezza della metà bassa segue la piega (metà schermo).
struct iOSHingeDeckLayout: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GeometryReader { geo in
            let top = max(220, geo.size.height / 2)
            VStack(spacing: 0) {
                iOSSection(state.selectedSection).content
                    .id(iOSSection(state.selectedSection))
                    .frame(height: top)
                    .clipped()
                Divider()
                iOSControlDeck()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
        }
    }
}

/// La «tastiera» del mini computer: sezioni, stato, azioni rapide e ricerca.
struct iOSControlDeck: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var searchType: ECSearchType = .global
    @State private var showAddLink = false
    @State private var lastMessage: LocalizedStringKey?
    @FocusState private var searchFocused: Bool

    var body: some View {
        let selection = iOSSectionSelection.binding(state)
        ScrollView {
            VStack(spacing: 14) {
                Picker("Sezione", selection: selection) {
                    ForEach(iOSSection.allCases) { s in
                        Label(s.title, systemImage: s.icon).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                iOSStatusBar()
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                // Ricerca: parte da qui e porta nella sezione Ricerca.
                HStack {
                    TextField("Cerca file…", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($searchFocused)
                        .onSubmit(startSearch)
                    Picker("Tipo ricerca", selection: $searchType) {
                        ForEach(ECSearchType.allCases) { t in Text(t.label).tag(t) }
                    }
                    .pickerStyle(.menu)
                    Button(action: startSearch) {
                        Image(systemName: "magnifyingglass.circle.fill").font(.title2)
                    }
                    .disabled(query.isEmpty)
                }

                // Azioni rapide (le stesse del menu dell'icona e del Dock).
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    deckButton("Aggiungi link eD2k", "plus.circle") { showAddLink = true }
                    deckButton("Pausa tutti", "pause.circle") {
                        Task { let n = await state.pauseAll(); lastMessage = "Messi in pausa: \(n)" }
                    }
                    deckButton("Riprendi tutti", "play.circle") {
                        Task { let n = await state.resumeAll(); lastMessage = "Ripresi: \(n)" }
                    }
                    if state.connState.ed2kConnected || state.connState.ed2kConnecting {
                        deckButton("Disconnetti", "xmark.circle") {
                            Task { await state.disconnectFromServer() }
                        }
                    } else {
                        deckButton("Connetti", "bolt.circle") {
                            Task { await state.connectToAnyServer() }
                        }
                    }
                }

                if let msg = lastMessage {
                    Text(msg).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkSheet().environmentObject(state)
        }
    }

    private func deckButton(_ title: LocalizedStringKey, _ icon: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func startSearch() {
        guard !query.isEmpty else { return }
        state.selectedSection = .search
        let text = query
        let type = searchType
        Task {
            await state.startSearch(text: text, type: type, fileType: "", extension: "",
                                    minSizeBytes: 0, maxSizeBytes: 0, availability: 0)
        }
        query = ""
        searchFocused = false
    }
}
