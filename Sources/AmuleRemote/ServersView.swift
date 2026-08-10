import SwiftUI

struct ServersView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\ServerItem.users, order: .reverse)]
    @State private var showAddServer = false
    @State private var addAddress = ""
    @State private var addPort = "4661"
    @State private var addName = ""
    @State private var updateURL = "http://gruk.org/server.met.gz"
    @State private var showUpdateFromURL = false

    private var selectedServer: ServerItem? {
        state.servers.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Network controls
            HStack(spacing: 12) {
                GroupBox {
                    HStack(spacing: 10) {
                        Text("eD2k: \(state.connState.ed2kLabel)")
                            .font(.callout)
                        if state.connState.ed2kConnected || state.connState.ed2kConnecting {
                            Button("Disconnetti") { Task { await state.disconnectFromServer() } }
                                .controlSize(.small)
                        } else {
                            Button("Connetti automatico") { Task { await state.connectToAnyServer() } }
                                .controlSize(.small)
                                .help("Connette a un server qualsiasi scelto da aMule. Per un server preciso, fai doppio clic sul server nella lista.")
                        }
                    }
                }
                GroupBox {
                    HStack(spacing: 10) {
                        Text("Kad: \(state.connState.kadLabel)")
                            .font(.callout)
                        if state.connState.kadRunning {
                            Button("Ferma") { Task { await state.kadStop() } }
                                .controlSize(.small)
                        } else {
                            Button("Avvia") { Task { await state.kadStart() } }
                                .controlSize(.small)
                        }
                    }
                }
                Spacer()
            }
            .padding(12)

            Divider()

            Table(state.servers.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Nome", value: \.name) { s in
                    HStack(spacing: 6) {
                        if state.connState.serverAddress == s.address {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.green)
                                .help("Server attualmente connesso")
                        }
                        Text(s.name)
                        if s.isStatic {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("Server statico")
                        }
                    }
                }
                .width(min: 160, ideal: 240)

                TableColumn("Indirizzo", value: \.ip) { s in
                    Text(s.address).font(.callout.monospaced())
                }
                .width(150)

                TableColumn("Descrizione", value: \.description) { s in Text(s.description) }
                    .width(min: 100, ideal: 180)

                TableColumn("Utenti", value: \.users) { s in
                    Text(s.users > 0 ? "\(s.users)" : "—")
                }
                .width(80)

                TableColumn("File", value: \.files) { s in
                    Text(s.files > 0 ? "\(s.files)" : "—")
                }
                .width(90)

                TableColumn("Ping", value: \.ping) { s in
                    Text(s.ping > 0 ? "\(s.ping) ms" : "—")
                }
                .width(70)

                TableColumn("Errori", value: \.failed) { s in
                    Text("\(s.failed)")
                        .foregroundStyle(s.failed > 2 ? .red : .secondary)
                        .help(s.failed > 2 ? "Server probabilmente morto: molti tentativi di connessione falliti" : "")
                }
                .width(50)

                TableColumn("Versione", value: \.version) { s in Text(s.version) }
                    .width(80)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let server = state.servers.first(where: { ids.contains($0.id) }) {
                    Button("Connetti a questo server") {
                        Task { await state.connectToServer(server) }
                    }
                    Divider()
                    Button("Rimuovi server", role: .destructive) {
                        Task { await state.removeServer(server) }
                    }
                }
            } primaryAction: { ids in
                if let server = state.servers.first(where: { ids.contains($0.id) }) {
                    Task { await state.connectToServer(server) }
                }
            }
            .onTableDoubleClick {
                if let server = selectedServer {
                    Task { await state.connectToServer(server) }
                }
            }
        }
        .navigationTitle("Server")
        .navigationSubtitle("\(state.servers.count) server — doppio clic per connettere")
        .task { await state.refreshServers() }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showAddServer = true
                } label: {
                    Label("Aggiungi server", systemImage: "plus")
                }
                Button {
                    showUpdateFromURL = true
                } label: {
                    Label("Aggiorna da URL (server.met)", systemImage: "globe")
                }
                Button {
                    Task { await state.refreshServers() }
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
            }
        }
        .sheet(isPresented: $showAddServer) {
            VStack(spacing: 14) {
                Text("Aggiungi server eD2k").font(.headline)
                Form {
                    TextField("Indirizzo (IP o host):", text: $addAddress)
                    TextField("Porta:", text: $addPort)
                    TextField("Nome (opzionale):", text: $addName)
                }
                .frame(width: 360)
                HStack {
                    Button("Annulla") { showAddServer = false }
                    Button("Aggiungi") {
                        let (a, p, n) = (addAddress, addPort, addName)
                        showAddServer = false
                        Task { await state.addServer(address: a, port: p, name: n) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(addAddress.isEmpty || addPort.isEmpty)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showUpdateFromURL) {
            VStack(spacing: 14) {
                Text("Aggiorna lista server da URL").font(.headline)
                TextField("http://…/server.met", text: $updateURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 420)
                HStack {
                    Button("Annulla") { showUpdateFromURL = false }
                    Button("Aggiorna") {
                        let url = updateURL
                        showUpdateFromURL = false
                        Task { await state.updateServerListFromURL(url) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updateURL.isEmpty)
                }
            }
            .padding(24)
        }
    }
}
