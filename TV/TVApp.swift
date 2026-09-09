import SwiftUI

// App per Apple TV (tvOS): stesso motore EC e stesso AppState delle altre
// piattaforme, interfaccia pensata per il telecomando e per una TV grande:
// poche voci, testo grande, ogni riga è un pulsante, azioni in un foglio.
// La digitazione usa la tastiera di tvOS: con un iPhone vicino il sistema
// propone da solo la "Tastiera Apple TV" e la dettatura Siri.

@main
struct AmuleRemoteTVApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environmentObject(state)
                .preferredColorScheme(state.themeMode.colorScheme)
                .modifier(AppLocaleModifier(language: state.appLanguage))
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Su tvOS non c'è timer di inattività: si va offline quando
                // l'app lascia lo schermo e si riconnette da sola al ritorno.
                Task { await state.enterOffline() }
            case .active:
                if state.offline { Task { await state.resumeFromOffline() } }
            default:
                break
            }
        }
    }
}

struct TVRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.sessionActive {
                VStack(spacing: 0) {
                    OfflineBanner()
                    TabView(selection: Binding(
                        get: {
                            switch state.selectedSection ?? .downloads {
                            case .search: return AppSection.search
                            case .servers: return AppSection.servers
                            case .stats, .log: return AppSection.stats
                            case .prefs, .shared: return AppSection.prefs
                            case .downloads: return AppSection.downloads
                            }
                        },
                        set: { state.selectedSection = $0 }
                    )) {
                        TVTransfersView()
                            .tabItem { Label("Trasferimenti", systemImage: "arrow.down.circle") }
                            .tag(AppSection.downloads)
                        TVSearchView()
                            .tabItem { Label("Ricerca", systemImage: "magnifyingglass") }
                            .tag(AppSection.search)
                        TVServersView()
                            .tabItem { Label("Server", systemImage: "server.rack") }
                            .tag(AppSection.servers)
                        TVStatsView()
                            .tabItem { Label("Statistiche", systemImage: "chart.bar") }
                            .tag(AppSection.stats)
                        TVSettingsView()
                            .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                            .tag(AppSection.prefs)
                    }
                }
            } else {
                TVConnectionView()
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
        .alert("aMule Remote", isPresented: Binding(
            get: { state.infoMessage != nil },
            set: { if !$0 { state.infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) { state.infoMessage = nil }
        } message: {
            Text(state.infoMessage ?? "")
        }
    }
}

/// Schermata di connessione a colonna singola: profilo → Connetti in un tocco;
/// i campi si compilano una volta sola (o mai, con i profili da iCloud).
struct TVConnectionView: View {
    @EnvironmentObject var state: AppState
    @State private var portText = ""
    @FocusState private var focused: Field?

    private enum Field { case host, port, password, autoConnect, connect, demo, restore }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.system(size: 96))
                            .foregroundStyle(.tint)
                        Text("aMule Remote")
                            .font(.largeTitle.bold())
                        Text("Connessione al server amuled (External Connections)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                }

                if let msg = state.connectionLostMessage {
                    Section {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if state.cloudProfilesAvailable > 0 {
                    Section {
                        Button {
                            state.restoreProfilesFromCloud()
                            portText = String(state.port)
                        } label: {
                            Label("Ripristina \(state.cloudProfilesAvailable) profili server da iCloud", systemImage: "icloud.and.arrow.down")
                                .foregroundStyle(TVInk.primary(focused == .restore))
                        }
                        .focused($focused, equals: .restore)
                    } footer: {
                        Text("Profili trovati sul tuo account iCloud: nessuna digitazione necessaria.")
                    }
                }

                if !state.profiles.isEmpty {
                    Section("Profilo") {
                        TVPickerRow(title: "Profilo", icon: "server.rack",
                                    options: state.profiles.map { p in
                                        (value: Optional(p.id), label: p.id == state.defaultProfileID ? "\(p.name) ★" : p.name, icon: nil)
                                    } + (state.currentProfile == nil ? [(value: Optional<UUID>.none, label: String(localized: "Nuovo server…"), icon: nil)] : []),
                                    selection: Binding(
                                        get: { state.currentProfile?.id },
                                        set: { newID in
                                            if let id = newID, let p = state.profiles.first(where: { $0.id == id }) {
                                                state.applyProfile(p)
                                                portText = String(p.port)
                                                focused = .connect
                                            }
                                        }))
                    }
                }

                Section {
                    TextField("Host o IP (es. unraid.local)", text: $state.host)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.next)
                        .focused($focused, equals: .host)
                        .onSubmit { focused = .port }
                    TextField("Porta EC", text: $portText)
                        .keyboardType(.numberPad)
                        .submitLabel(.next)
                        .focused($focused, equals: .port)
                        .onChange(of: portText) { _, v in
                            if let p = Int(v.filter(\.isNumber)), p > 0 { state.port = p }
                        }
                        .onSubmit { focused = .password }
                    PasswordField("Password", text: $state.password)
                        .submitLabel(.go)
                        .focused($focused, equals: .password)
                        .onSubmit { if !state.host.isEmpty && !state.password.isEmpty { Task { await state.connect() } } }
                    TVToggleRow(title: "Connetti automaticamente all'avvio", icon: "bolt.badge.clock", isOn: $state.autoConnect)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Suggerimento: con un iPhone vicino puoi digitare dalla notifica «Tastiera Apple TV» o dettare con Siri. Server e password vengono salvati nel Portachiavi.")
                }
                .onChange(of: state.host) { _, _ in state.reloadStoredPassword() }
                .onChange(of: state.port) { _, _ in state.reloadStoredPassword() }

                Section {
                    Button {
                        Task { await state.connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if state.connecting {
                                ProgressView()
                            } else {
                                Label("Connetti", systemImage: "bolt.fill").bold()
                                    .foregroundStyle(TVInk.primary(focused == .connect))
                            }
                            Spacer()
                        }
                    }
                    .disabled(state.host.isEmpty || state.password.isEmpty || state.connecting)
                    .focused($focused, equals: .connect)
                    Button {
                        state.enterDemoMode()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Prova la modalità demo", systemImage: "play.circle")
                                .foregroundStyle(TVInk.primary(focused == .demo))
                            Spacer()
                        }
                    }
                    .disabled(state.connecting)
                    .focused($focused, equals: .demo)
                } footer: {
                    Text("Esplora l'app con dati di esempio, senza un server (equivale a inserire DEMO come host e DEMO come password).")
                }
            }
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            portText = String(state.port)
            // Con un profilo già pronto il focus parte su Connetti: un solo clic.
            focused = (!state.host.isEmpty && !state.password.isEmpty) ? .connect : .host
        }
    }
}
