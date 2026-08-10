import SwiftUI

@main
struct AmuleRemoteiOSApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            iOSRootView()
                .environmentObject(state)
        }
    }
}

struct iOSRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.connected {
                TabView {
                    iOSTransfersView()
                        .tabItem { Label("Trasferimenti", systemImage: "arrow.down.circle") }
                    iOSSearchView()
                        .tabItem { Label("Ricerca", systemImage: "magnifyingglass") }
                    iOSServersView()
                        .tabItem { Label("Server", systemImage: "server.rack") }
                    iOSMoreView()
                        .tabItem { Label("Altro", systemImage: "ellipsis.circle") }
                }
                // Observe touches to reset the inactivity timer WITHOUT
                // intercepting them (a DragGesture here would swallow taps).
                .background(ActivityObserver { state.markActivity() })
            } else {
                iOSConnectionView()
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

struct iOSConnectionView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.system(size: 48))
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

                Section("Server") {
                    TextField("Host o IP (es. unraid.local)", text: $state.host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Porta EC", value: $state.port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    SecureField("Password", text: $state.password)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
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
            }
            .navigationTitle("Connessione")
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
