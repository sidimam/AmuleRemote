import SwiftUI

@main
struct AmuleRemoteiOSApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    // Azioni rapide dal menu dell'icona in Home (QuickActions.swift).
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) private var appDelegate
    #endif

    init() {
        // La registrazione del BGTask deve avvenire prima della fine del lancio.
        BackgroundRefresh.register()
        #if os(iOS)
        // Il ponte verso Apple Watch esiste solo su iPhone (niente
        // WatchConnectivity su iPadOS "puro" runtime o visionOS).
        WatchBridge.shared.activate()
        #endif
    }

    var body: some Scene {
        #if os(visionOS)
        // Finestra abbastanza alta da mostrare tutta la schermata di
        // connessione (compreso il pulsante della modalità demo) senza scorrere.
        mainScene.defaultSize(width: 1000, height: 900)
        #else
        mainScene
        #endif
    }

    private var mainScene: some Scene {
        WindowGroup {
            iOSRootView()
                .environmentObject(state)
                .preferredColorScheme(state.themeMode.colorScheme)
                .tint(AppIconColor.tint(for: state.iconColor))
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                state.lockNow()
                // In background la connessione EC si chiude ma i dati restano
                // in cache (stato Offline); al ritorno riparte da sola.
                Task { await state.enterOffline() }
                #if os(iOS)
                HomeScreenShortcuts.install()
                #endif
                if !state.demoMode {
                    BackgroundRefresh.schedule()
                }
            case .active:
                Task { await state.refreshNotificationStatus() }
                if state.offline && !state.locked {
                    Task { await state.resumeFromOffline() }
                }
            default:
                break
            }
        }
    }
}

struct iOSRootView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var router = QuickActionRouter.shared

    var body: some View {
        Group {
            if state.locked {
                LockScreenView()
            } else if state.sessionActive {
              VStack(spacing: 0) {
                OfflineBanner()
                // La tab selezionata segue `selectedSection` (stessa proprietà della
                // barra laterale macOS): così `-section search|servers|stats` funziona
                // anche qui, utile per screenshot e collaudo.
                TabView(selection: Binding(
                    get: {
                        switch state.selectedSection ?? .downloads {
                        case .search: return AppSection.search
                        case .servers: return AppSection.servers
                        case .downloads: return AppSection.downloads
                        default: return AppSection.stats
                        }
                    },
                    set: { state.selectedSection = $0 }
                )) {
                    iOSTransfersView()
                        .tabItem { Label("Trasferimenti", systemImage: "arrow.down.circle") }
                        .tag(AppSection.downloads)
                    iOSSearchView()
                        .tabItem { Label("Ricerca", systemImage: "magnifyingglass") }
                        .tag(AppSection.search)
                    iOSServersView()
                        .tabItem { Label("Server", systemImage: "server.rack") }
                        .tag(AppSection.servers)
                    iOSMoreView()
                        .tabItem { Label("Altro", systemImage: "ellipsis.circle") }
                        .tag(AppSection.stats)
                }
                // Observe touches to reset the inactivity timer WITHOUT
                // intercepting them (a DragGesture here would swallow taps).
                .background(ActivityObserver { state.markActivity() })
              }
            } else {
                iOSConnectionView()
            }
        }
        // Azioni rapide (menu dell'icona): eseguite appena l'app è sbloccata.
        .onChange(of: router.pending) { _, _ in consumeQuickAction() }
        .onChange(of: state.locked) { _, _ in consumeQuickAction() }
        .onAppear { consumeQuickAction() }
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
        // Link ed2k:// aperti da altre app (Safari, Mail…): conferma e accoda.
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
        // Presentazione (funzionalità, iCloud, notifiche) al primo avvio.
        .fullScreenCover(isPresented: $state.showWalkthrough) {
            WalkthroughView()
                .environmentObject(state)
                .tint(AppIconColor.tint(for: state.iconColor))
                .modifier(AppLocaleModifier(language: state.appLanguage))
        }
        .modifier(AppLocaleModifier(language: state.appLanguage))
    }

    private func consumeQuickAction() {
        guard let action = router.pending, !state.locked else { return }
        router.pending = nil
        Task { await state.perform(action) }
    }
}

struct iOSConnectionView: View {
    @EnvironmentObject var state: AppState

    @ScaledMetric(relativeTo: .largeTitle) private var iconPoints: CGFloat = 48
    var body: some View {
        NavigationStack {
            Form {
                if let msg = state.connectionLostMessage {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(msg).font(.callout)
                            Spacer()
                            Button {
                                state.connectionLostMessage = nil
                            } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.orange.opacity(0.15))
                }

                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.system(size: iconPoints))
                            .foregroundStyle(.tint)
                        Text("aMule Remote")
                            .font(.title2.bold())
                        Text("Connessione al server amuled (External Connections)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                if state.cloudProfilesAvailable > 0 {
                    Section {
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
                    }
                    .listRowBackground(Color.blue.opacity(0.12))
                }

                if !state.profiles.isEmpty {
                    Section("Profilo") {
                        Picker("Profilo", selection: Binding(
                            get: { state.currentProfile?.id },
                            set: { newID in
                                if let id = newID, let p = state.profiles.first(where: { $0.id == id }) {
                                    state.applyProfile(p)
                                }
                            }
                        )) {
                            ForEach(state.profiles) { p in
                                if p.id == state.defaultProfileID {
                                    Label(p.name, systemImage: "star.fill").tag(Optional(p.id))
                                } else {
                                    Text(p.name).tag(Optional(p.id))
                                }
                            }
                            if state.currentProfile == nil {
                                Text("Nuovo server…").tag(Optional<UUID>.none)
                            }
                        }
                        NavigationLink("Gestisci profili") {
                            iOSProfilesView()
                        }
                    }
                }

                Section("Server") {
                    TextField("Host o IP (es. unraid.local)", text: $state.host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Porta EC", value: $state.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    PasswordField("Password", text: $state.password)
                }
                .onChange(of: state.host) { _, _ in state.reloadStoredPassword() }
                .onChange(of: state.port) { _, _ in state.reloadStoredPassword() }

                Section {
                    Toggle("Connetti automaticamente all'avvio", isOn: $state.autoConnect)
                } footer: {
                    Text("Server e password vengono salvati automaticamente nel Portachiavi.")
                }

                Section {
                    Button {
                        Task { await state.connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if state.connecting {
                                ProgressView()
                            } else {
                                Text("Connetti").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(state.host.isEmpty || state.password.isEmpty || state.connecting)
                }

                Section {
                    Button {
                        state.enterDemoMode()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Prova la modalità demo", systemImage: "play.circle")
                            Spacer()
                        }
                    }
                    .disabled(state.connecting)
                } footer: {
                    Text("Esplora l'app con dati di esempio, senza un server (equivale a inserire DEMO come host e DEMO come password).")
                }
            }
            .navigationTitle("Connessione")
            #if os(visionOS)
            // Su visionOS la finestra può essere bassa e il pulsante demo in
            // fondo al Form resterebbe nascosto: lo si raggiunge anche dalla barra.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        state.enterDemoMode()
                    } label: {
                        Label("Demo", systemImage: "play.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .help("Prova la modalità demo")
                    .disabled(state.connecting)
                }
            }
            #endif
        }
    }
}

/// Attaches a gesture recognizer to the window that reports every touch
/// beginning but never recognizes — so it resets the idle timer without
/// interfering with buttons, scrolling, or text fields.
struct ActivityObserver: UIViewRepresentable {
    let onActivity: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onActivity) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            let g = TouchObservingGesture()
            g.onTouch = context.coordinator.onActivity
            g.cancelsTouchesInView = false
            g.delaysTouchesBegan = false
            g.delaysTouchesEnded = false
            g.delegate = context.coordinator
            window.addGestureRecognizer(g)
            context.coordinator.gesture = g
        }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onActivity: () -> Void
        weak var gesture: UIGestureRecognizer?
        init(_ onActivity: @escaping () -> Void) { self.onActivity = onActivity }
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    final class TouchObservingGesture: UIGestureRecognizer {
        var onTouch: () -> Void = {}
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onTouch()
            state = .failed   // never recognize → never block the touch
        }
    }
}

/// Reusable sort menu: tap a field to sort, tap again to invert direction.
struct SortMenu: View {
    let options: [(key: String, label: String)]
    @Binding var sortKey: String
    @Binding var ascending: Bool

    var body: some View {
        Menu {
            ForEach(options, id: \.key) { opt in
                Button {
                    if sortKey == opt.key {
                        ascending.toggle()
                    } else {
                        sortKey = opt.key
                    }
                } label: {
                    if sortKey == opt.key {
                        Label(opt.label, systemImage: ascending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(opt.label)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
}

/// Small connection status header shown at the top of each tab.
struct iOSStatusBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down").foregroundStyle(.green)
                Text(formatSpeed(state.stats.dlSpeed))
            }
            HStack(spacing: 3) {
                Image(systemName: "arrow.up").foregroundStyle(.blue)
                Text(formatSpeed(state.stats.ulSpeed))
            }
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(state.connState.ed2kConnected ? (state.connState.lowID ? .yellow : .green) : .red)
                    .frame(width: 7, height: 7)
                Text("eD2k")
                Circle()
                    .fill(state.connState.kadOK ? (state.connState.kadFirewalled ? .yellow : .green)
                          : (state.connState.kadRunning ? .orange : .red))
                    .frame(width: 7, height: 7)
                Text("Kad")
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
