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
            // Intestazione reti, stessa disposizione della sezione Server di iOS:
            // stato a sinistra, pulsanti a destra.
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("eD2k: \(state.connState.ed2kLabel)")
                    Text("Kad: \(state.connState.kadLabel)")
                }
                .font(.caption)
                Spacer()
                if state.connState.ed2kConnected || state.connState.ed2kConnecting {
                    Button {
                        Task { await state.disconnectFromServer() }
                    } label: { Label("Disconnetti", systemImage: "bolt.slash") }
                } else {
                    Button {
                        Task { await state.connectToAnyServer() }
                    } label: { Label("Connetti", systemImage: "bolt") }
                    .help("Connette a un server qualsiasi scelto da aMule. Per un server preciso, fai doppio clic sul server nella lista.")
                }
                if state.connState.kadRunning {
                    Button {
                        Task { await state.kadStop() }
                    } label: { Label("Kad: Ferma", systemImage: "stop.fill") }
                } else {
                    Button {
                        Task { await state.kadStart() }
                    } label: { Label("Kad: Avvia", systemImage: "play.fill") }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

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
                // Come su iOS: le azioni secondarie stanno nel menu "…".
                Menu {
                    Button {
                        showUpdateFromURL = true
                    } label: {
                        Label("Aggiorna lista server (server.met)", systemImage: "arrow.down.circle")
                    }
                    Button {
                        Task { await state.refreshServers() }
                    } label: {
                        Label("Ricarica dal server", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Label("Altro", systemImage: "ellipsis.circle")
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
                Text("Aggiorna lista server (server.met)").font(.headline)
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
