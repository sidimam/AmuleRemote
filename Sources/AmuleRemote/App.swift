import SwiftUI

@main
struct AmuleRemoteApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.connected {
                MainSplitView()
            } else {
                ConnectionView()
            }
        }
        .alert("Errore", isPresented: Binding(
            get: { state.lastError != nil },
            set: { if !$0 { state.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { state.lastError = nil }
        } message: {
            Text(state.lastError ?? "")
        }
    }
}

struct MainSplitView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $state.selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                ConnectionFooter()
            }
        } detail: {
            switch state.selectedSection ?? .downloads {
            case .downloads: DownloadsView()
            case .search: SearchView()
            case .servers: ServersView()
            case .shared: SharedFilesView()
            case .stats: StatsView()
            case .log: LogView()
            case .prefs: PrefsView()
            }
        }
    }
}

struct ConnectionFooter: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(.green)
                    Text(formatSpeed(state.stats.dlSpeed))
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.blue)
                    Text(formatSpeed(state.stats.ulSpeed))
                }
            }
            .font(.callout.monospacedDigit().weight(.medium))
            HStack(spacing: 6) {
                Circle()
                    .fill(state.connState.ed2kConnected ? (state.connState.lowID ? .yellow : .green) : .red)
                    .frame(width: 8, height: 8)
                Text("eD2k: \(state.connState.ed2kLabel)")
                    .font(.caption)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(state.connState.kadOK ? (state.connState.kadFirewalled ? .yellow : .green)
                          : (state.connState.kadRunning ? .orange : .red))
                    .frame(width: 8, height: 8)
                Text("Kad: \(state.connState.kadLabel)")
                    .font(.caption)
            }
            HStack {
                Text(state.host)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Disconnetti") {
                    Task { await state.disconnect() }
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(.bar)
    }
}

struct ConnectionView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "network")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("aMule Remote")
                .font(.largeTitle.bold())
            Text("Connessione remota a un server amuled (External Connections)")
                .foregroundStyle(.secondary)

            Form {
                TextField("Host / IP del server:", text: $state.host, prompt: Text("es. unraid.local o 192.168.1.10"))
                TextField("Porta EC:", value: $state.port, format: .number.grouping(.never))
                SecureField("Password:", text: $state.password)
                Toggle("Salva la password nel Portachiavi", isOn: $state.savePassword)
                Toggle("Connetti automaticamente all'avvio", isOn: $state.autoConnect)
            }
            .formStyle(.grouped)
            .frame(maxWidth: 460)

            Button {
                Task { await state.connect() }
            } label: {
                if state.connecting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Connetti").frame(minWidth: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(state.host.isEmpty || state.password.isEmpty || state.connecting)
            .keyboardShortcut(.defaultAction)

            Text("Su Unraid: abilita le External Connections in amule.conf (ECPort 4712, AcceptExternalConnections=1) e apri/inoltra la porta.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
