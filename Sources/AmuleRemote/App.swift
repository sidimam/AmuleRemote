import SwiftUI

@main
struct AmuleRemoteApp: App {
    @StateObject private var state = AppState()
    // Menu del Dock con le azioni rapide (MacQuickActions.swift).
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    init() {
        DockIcon.start()
    }

    var body: some Scene {
        // Il tema è applicato via NSApp.appearance (ThemeMode.applyToApplication):
        // .preferredColorScheme su macOS lascia finestre nel tema sbagliato
        // nelle transizioni sistema→scuro→chiaro.
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 980, minHeight: 620)
        }
        // Dimensione del primo avvio (e canvas naturale per gli screenshot
        // dell'App Store: 1280×800 logici = 2560×1600 px su Retina).
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // Menu app → Informazioni su aMule Remote (versione, licenza, link).
            CommandGroup(replacing: .appInfo) {
                Button("Informazioni su aMule Remote") { MacAboutPanel.show() }
            }
            // Menu Aiuto: guida, segnalazioni, privacy.
            CommandGroup(replacing: .help) {
                Button("Guida di aMule Remote (wiki)") { NSWorkspace.shared.open(AppLinks.wiki) }
                Button("Segnala un problema") { NSWorkspace.shared.open(AppLinks.bugReport) }
                Button("Informativa sulla privacy") { NSWorkspace.shared.open(AppLinks.privacy) }
            }
            // Azioni rapide anche dalla barra dei menu, con scorciatoie.
            CommandMenu("Trasferimenti") {
                Button("Aggiungi link eD2k…") { QuickActionRouter.shared.pending = .addLink }
                    .keyboardShortcut("l")
                Divider()
                Button("Metti in pausa tutti i download") { QuickActionRouter.shared.pending = .pauseAll }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Button("Riprendi tutti i download") { QuickActionRouter.shared.pending = .resumeAll }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Divider()
                Button("Rimuovi completati") { Task { await state.clearCompleted() } }
                    .disabled(!state.connected)
            }
        }
        // App menu → Impostazioni… (⌘,): aspetto, blocco Touch ID, profili.
        Settings {
            MacSettingsView()
                .environmentObject(state)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var router = QuickActionRouter.shared

    var body: some View {
        Group {
            if state.locked {
                LockScreenView()
            } else if state.sessionActive {
                MainSplitView()
            } else {
                ConnectionView()
            }
        }
        // Clic e tasti azzerano il timer di inattività (e riconnettono da offline).
        .onAppear {
            MacActivityMonitor.start { state.markActivity() }
            consumeQuickAction()
            // Collaudo/screenshot: `-appSettings` apre subito la finestra Impostazioni.
            if ProcessInfo.processInfo.arguments.contains("-appSettings") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
        // Azioni rapide dal Dock o dal menu Trasferimenti.
        .onChange(of: router.pending) { _, _ in consumeQuickAction() }
        .onChange(of: state.locked) { _, _ in consumeQuickAction() }
        .alert("aMule Remote", isPresented: Binding(
            get: { state.infoMessage != nil },
            set: { if !$0 { state.infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) { state.infoMessage = nil }
        } message: {
            Text(state.infoMessage ?? "")
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
        .alert("Notifiche non consentite", isPresented: $state.notificationsDenied) {
            Button("OK", role: .cancel) { state.notificationsDenied = false }
        } message: {
            Text("Le notifiche di aMule Remote sono disattivate nelle Impostazioni di sistema. Attivale da Impostazioni di Sistema → Notifiche → aMule Remote.")
        }
        .modifier(AppLocaleModifier(language: state.appLanguage))
    }

    private func consumeQuickAction() {
        guard let action = router.pending, !state.locked else { return }
        router.pending = nil
        Task { await state.perform(action) }
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
        // Aspetto EFFETTIVO dell'app (tiene conto del tema forzato via
        // NSApp.appearance, non solo di quello di sistema).
        let dark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = UserDefaults.standard.string(forKey: "iconColor") ?? "default"
        let base = color == "default" ? "dockicon" : "dockicon-\(color)"
        let name = base + (dark ? "-dark" : "-light")
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
            VStack(spacing: 0) {
                OfflineBanner()
                Group {
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
                Button {
                    Task { await state.disconnect() }
                } label: {
                    Label("Disconnetti", systemImage: "xmark.circle")
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

            if state.cloudProfilesAvailable > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "icloud.and.arrow.down")
                        .foregroundStyle(.blue)
                    Text("Trovati \(state.cloudProfilesAvailable) profili server su iCloud.")
                        .font(.callout)
                    Spacer()
                    Button("Ripristina") { state.restoreProfilesFromCloud() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(12)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
                PasswordField("Password:", text: $state.password)
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
