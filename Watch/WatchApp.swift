import SwiftUI
import WatchConnectivity

@main
struct AmuleRemoteWatchApp: App {
    @StateObject private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
        }
    }
}

// MARK: - Modello dello snapshot ricevuto dall'iPhone

struct WatchDownload: Identifiable {
    let id = UUID()
    var name: String
    var progress: Double
    var speed: Double
    var complete: Bool
}

struct WatchSnapshot {
    var connected = false
    var profile = ""
    var dlSpeed: Double = 0
    var ulSpeed: Double = 0
    var ed2k = false
    var kad = false
    var items: [WatchDownload] = []
    var timestamp: Date?
}

/// Riceve gli snapshot pubblicati dall'iPhone via application context.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()

    @Published var snapshot = WatchSnapshot()
    @Published var hasData = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        apply(session.receivedApplicationContext)
    }

    private func apply(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        var snap = WatchSnapshot()
        snap.connected = context["connected"] as? Bool ?? false
        snap.profile = context["profile"] as? String ?? ""
        snap.dlSpeed = context["dl"] as? Double ?? 0
        snap.ulSpeed = context["ul"] as? Double ?? 0
        snap.ed2k = context["ed2k"] as? Bool ?? false
        snap.kad = context["kad"] as? Bool ?? false
        if let ts = context["ts"] as? Double {
            snap.timestamp = Date(timeIntervalSince1970: ts)
        }
        if let items = context["items"] as? [[String: Any]] {
            snap.items = items.map {
                WatchDownload(name: $0["n"] as? String ?? "?",
                              progress: $0["p"] as? Double ?? 0,
                              speed: $0["s"] as? Double ?? 0,
                              complete: $0["c"] as? Bool ?? false)
            }
        }
        DispatchQueue.main.async {
            self.snapshot = snap
            self.hasData = true
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}

// MARK: - Viste

struct WatchRootView: View {
    @EnvironmentObject var store: WatchStore

    var body: some View {
        NavigationStack {
            Group {
                if !store.hasData {
                    VStack(spacing: 10) {
                        Image(systemName: "iphone.gen3")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Apri aMule Remote su iPhone per ricevere i dati.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    WatchStatusList()
                }
            }
            .navigationTitle("aMule")
        }
    }
}

struct WatchStatusList: View {
    @EnvironmentObject var store: WatchStore

    private var snap: WatchSnapshot { store.snapshot }

    var body: some View {
        List {
            Section {
                HStack {
                    Label(watchSpeed(snap.dlSpeed), systemImage: "arrow.down")
                        .foregroundStyle(.green)
                    Spacer()
                    Label(watchSpeed(snap.ulSpeed), systemImage: "arrow.up")
                        .foregroundStyle(.blue)
                }
                .font(.footnote.monospacedDigit())
                HStack(spacing: 10) {
                    networkDot("eD2k", ok: snap.ed2k)
                    networkDot("Kad", ok: snap.kad)
                    Spacer()
                    if !snap.connected {
                        Text("App disconnessa")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                if !snap.profile.isEmpty {
                    Text(snap.profile)
                }
            }

            Section("Download") {
                if snap.items.isEmpty {
                    Text("Nessun file in coda.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snap.items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.caption2)
                                .lineLimit(2)
                            if item.complete {
                                Label("Completato", systemImage: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else {
                                ProgressView(value: item.progress)
                                    .tint(item.speed > 0 ? .green : .secondary)
                                HStack {
                                    Text("\(Int(item.progress * 100))%")
                                    Spacer()
                                    if item.speed > 0 {
                                        Text(watchSpeed(item.speed))
                                    }
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }

            if let ts = snap.timestamp {
                Section {
                    Text("Aggiornato \(ts.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
        }
    }

    @ViewBuilder
    private func networkDot(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label).font(.caption2)
        }
    }
}

/// Formattazione compatta della velocità (il Watch non include Models.swift).
func watchSpeed(_ bytesPerSec: Double) -> String {
    guard bytesPerSec > 0 else { return "0 kB/s" }
    let kb = bytesPerSec / 1024
    if kb >= 1024 { return String(format: "%.1f MB/s", kb / 1024) }
    return String(format: "%.0f kB/s", kb)
}
