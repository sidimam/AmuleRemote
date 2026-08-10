import SwiftUI

struct iOSServersView: View {
    @EnvironmentObject var state: AppState
    @State private var connectTarget: ServerItem?
    @State private var showAddServer = false
    @State private var addAddress = ""
    @State private var addPort = "4661"
    @State private var addName = ""
    @AppStorage("iosSortServers") private var sortKey = "utenti"
    @AppStorage("iosSortServersAsc") private var sortAsc = false

    private var sortedServers: [ServerItem] {
        let items = state.servers
        let sorted: [ServerItem]
        switch sortKey {
        case "nome": sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case "file": sorted = items.sorted { $0.files < $1.files }
        case "ping": sorted = items.sorted { $0.ping < $1.ping }
        case "errori": sorted = items.sorted { $0.failed < $1.failed }
        default: sorted = items.sorted { $0.users < $1.users }
        }
        return sortAsc ? sorted : sorted.reversed()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                iOSStatusBar()

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("eD2k: \(state.connState.ed2kLabel)")
                        Text("Kad: \(state.connState.kadLabel)")
                    }
                    .font(.caption)
                    Spacer()
                    if state.connState.ed2kConnected || state.connState.ed2kConnecting {
                        Button("Disconnetti") { Task { await state.disconnectFromServer() } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else {
                        Button("Auto") { Task { await state.connectToAnyServer() } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    if state.connState.kadRunning {
                        Button("Ferma Kad") { Task { await state.kadStop() } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else {
                        Button("Avvia Kad") { Task { await state.kadStart() } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

                List {
                    ForEach(sortedServers) { s in
                        Button {
                            connectTarget = s
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    if state.connState.serverAddress == s.address {
                                        Image(systemName: "bolt.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                    }
                                    Text(s.name).font(.subheadline)
                                    if s.failed > 2 {
                                        Text("\(s.failed) errori")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                                HStack {
                                    Text(s.address).font(.caption.monospaced())
                                    Spacer()
                                    if s.users > 0 { Text("\(s.users) utenti") }
                                    if s.ping > 0 { Text("\(s.ping) ms") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await state.removeServer(s) }
                            } label: { Label("Rimuovi", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await state.refreshServers() }
            }
            .navigationTitle("Server (\(state.servers.count))")
            .navigationBarTitleDisplayMode(.inline)
            .task { await state.refreshServers() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SortMenu(options: [("utenti", "Utenti"), ("nome", "Nome"), ("file", "File"),
                                       ("ping", "Ping"), ("errori", "Errori")],
                             sortKey: $sortKey, ascending: $sortAsc)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAddServer = true } label: { Image(systemName: "plus") }
                    Button {
                        Task { await state.updateServerListFromURL("http://gruk.org/server.met.gz") }
                    } label: { Image(systemName: "globe") }
                }
            }
            .confirmationDialog("Connettere a \(connectTarget?.name ?? "")?",
                                isPresented: Binding(get: { connectTarget != nil },
                                                     set: { if !$0 { connectTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Connetti") {
                    if let t = connectTarget { Task { await state.connectToServer(t) } }
                    connectTarget = nil
                }
                Button("Annulla", role: .cancel) { connectTarget = nil }
            }
            .sheet(isPresented: $showAddServer) {
                NavigationStack {
                    Form {
                        TextField("Indirizzo (IP o host)", text: $addAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Porta", text: $addPort)
                            .keyboardType(.numberPad)
                        TextField("Nome (opzionale)", text: $addName)
                    }
                    .navigationTitle("Aggiungi server")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla") { showAddServer = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Aggiungi") {
                                let (a, p, n) = (addAddress, addPort, addName)
                                showAddServer = false
                                Task { await state.addServer(address: a, port: p, name: n) }
                            }
                            .disabled(addAddress.isEmpty || addPort.isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}

struct iOSSharedView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("iosSortShared") private var sortKey = "nome"
    @AppStorage("iosSortSharedAsc") private var sortAsc = true

    private var sortedShared: [SharedFileItem] {
        let items = state.sharedFiles
        let sorted: [SharedFileItem]
        switch sortKey {
        case "dimensione": sorted = items.sorted { $0.size < $1.size }
        case "richieste": sorted = items.sorted { $0.requestsAll < $1.requestsAll }
        case "caricati": sorted = items.sorted { $0.xferredAll < $1.xferredAll }
        default: sorted = items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return sortAsc ? sorted : sorted.reversed()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                iOSStatusBar()
                List {
                    ForEach(sortedShared) { f in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.name).font(.subheadline).lineLimit(2)
                            HStack {
                                Text(formatBytes(f.size))
                                Spacer()
                                Text("Richieste: \(f.requestsAll) • Caricati: \(formatBytes(f.xferredAll))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Menu("Priorità upload") {
                                ForEach([FilePriority.veryLow, .low, .normal, .high, .veryHigh, .powershare, .auto]) { p in
                                    Button(p.label) { Task { await state.setSharedPriority(f, p) } }
                                }
                            }
                            if !f.ed2kLink.isEmpty {
                                Button("Copia link eD2k") {
                                    UIPasteboard.general.string = f.ed2kLink
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await state.refreshShared() }
            }
            .navigationTitle("Condivisi (\(state.sharedFiles.count))")
            .navigationBarTitleDisplayMode(.inline)
            .task { await state.refreshShared() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SortMenu(options: [("nome", "Nome"), ("dimensione", "Dimensione"),
                                       ("richieste", "Richieste"), ("caricati", "Caricati")],
                             sortKey: $sortKey, ascending: $sortAsc)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await state.reloadSharedFiles() }
                    } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                }
            }
        }
    }
}
