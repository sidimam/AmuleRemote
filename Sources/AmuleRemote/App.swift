import SwiftUI

@main
struct AmuleRemoteApp: App {
    @StateObject private var state = AppState()

    init() {
        DockIcon.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 620)
                .preferredColorScheme(state.themeMode.colorScheme)
        }
        // Dimensione del primo avvio (e canvas naturale per gli screenshot
        // dell'App Store: 1280×800 logici = 2560×1600 px su Retina).
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        // App menu → Impostazioni… (⌘,): aspetto, blocco Touch ID, profili.
        Settings {
            MacSettingsView()
                .environmentObject(state)
                .preferredColorScheme(state.themeMode.colorScheme)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.locked {
                LockScreenView()
            } else if state.connected {
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
        // Link ed2k:// aperti dal sistema (browser ecc.): conferma e accoda.
        .alert("Aggiungere ai download?", isPresented: Binding(
            get: { state.pendingEd2kLink != nil },
            set: { if !$0 { state.pendingEd2kLink = nil } }
        )) {
            Button("Annulla", role: .cancel) { state.pendingEd2kLink = nil }
            Button("Aggiungi") { Task { await state.confirmPendingEd2kLink() } }
        } message: {
            Text(AppState.ed2kLinkName(state.pendingEd2kLink ?? ""))
        }
        .onOpenURL { state.handleIncomingURL($0) }
        .modifier(AppLocaleModifier(language: state.appLanguage))
    }
}

/// Icona del Dock adattiva: segue il tema di sistema (chiaro/scuro) usando le
/// due varianti PNG nel bundle. L'icona statica nel Finder resta la .icns.
enum DockIcon {
    static func start() {
        // In App.init() NSApp non esiste ancora: primo aggiornamento al
        // primo giro di run loop, quando l'applicazione è pronta.
        DispatchQueue.main.async { update() }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async { update() }
        }
    }

    static func update() {
        guard let app = NSApp else { return }
        // NSGlobalDomain: presente solo quando il sistema è in tema scuro.
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let name = dark ? "dockicon-dark" : "dockicon-light"
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            app.applicationIconImage = image
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
                if state.profiles.count > 1 {
                    // Cambio profilo al volo: disconnette e riconnette al server scelto.
                    Menu {
                        ForEach(state.profiles) { p in
                            Button(p.id == state.defaultProfileID ? "\(p.name) ★" : p.name) {
                                Task { await state.switchProfile(to: p) }
                            }
                            .disabled(state.currentProfile?.id == p.id)
                        }
                    } label: {
                        Text(state.currentProfile?.name ?? state.host)
                            .font(.caption2)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    Text(state.host)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
            if let msg = state.connectionLostMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.callout)
                    Spacer()
                    Button {
                        state.connectionLostMessage = nil
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 460)
            }

            Image(systemName: "network")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("aMule Remote")
                .font(.largeTitle.bold())
            Text("Connessione remota a un server amuled (External Connections)")
                .foregroundStyle(.secondary)

            Form {
                if !state.profiles.isEmpty {
                    Picker("Profilo:", selection: Binding(
                        get: { state.currentProfile?.id },
                        set: { newID in
                            if let id = newID, let p = state.profiles.first(where: { $0.id == id }) {
                                state.applyProfile(p)
                            }
                        }
                    )) {
                        ForEach(state.profiles) { p in
                            Text(p.id == state.defaultProfileID ? "\(p.name) ★" : p.name)
                                .tag(Optional(p.id))
                        }
                        if state.currentProfile == nil {
                            Text("Nuovo server…").tag(Optional<UUID>.none)
                        }
                    }
                }
                TextField("Host / IP del server:", text: $state.host, prompt: Text("es. unraid.local o 192.168.1.10"))
                TextField("Porta EC:", value: $state.port, format: .number.grouping(.never))
                SecureField("Password:", text: $state.password)
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

            Button {
                state.enterDemoMode()
            } label: {
                Label("Prova la modalità demo", systemImage: "play.circle")
            }
            .buttonStyle(.link)
            .disabled(state.connecting)

            Text("Esplora l'app con dati di esempio, senza un server (equivale a inserire DEMO come host e DEMO come password).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
