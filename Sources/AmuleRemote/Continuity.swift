import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Continuity fra i dispositivi dell'utente:
//  - Handoff (NSUserActivity) su iPhone/iPad, Mac e Vision Pro: l'icona
//    dell'app compare nel Dock/App Switcher dell'altro dispositivo e riapre la
//    stessa sezione (e la stessa ricerca) sullo stesso profilo server;
//  - stato condiviso via iCloud KVS (`continuity.v1`): anche l'Apple TV, che
//    non riceve Handoff, può proporre «Continua la ricerca “…” da iPhone».
// Niente passa per server di terzi: solo Handoff di Apple e l'account iCloud.

enum Continuity {
    static let activityType = "com.sdimambro.amule-remote.browse"
    static let kvsKey = "continuity.v1"
    /// Quanto resta valido uno stato pubblicato da un altro dispositivo.
    static let freshness: TimeInterval = 2 * 60 * 60

    struct Snapshot: Codable, Equatable {
        var section: String
        var profileID: UUID?
        var profileName: String?
        var query: String?
        var searchType: String?
        var deviceName: String
        var date: Date
    }

    static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #elseif os(tvOS)
        return "Apple TV"
        #else
        return UIDevice.current.name
        #endif
    }

    static func pushSnapshot(_ snap: Snapshot) {
        guard CloudSync.isEnabled, let data = try? JSONEncoder().encode(snap) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: kvsKey)
    }

    static func pullSnapshot() -> Snapshot? {
        guard CloudSync.isEnabled, let data = NSUbiquitousKeyValueStore.default.data(forKey: kvsKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return snap
    }
}

extension AppState {
    /// Stato corrente da pubblicare (Handoff e KVS).
    var continuitySnapshot: Continuity.Snapshot {
        let session = activeSearchSession
        return Continuity.Snapshot(section: (selectedSection ?? .downloads).rawValue,
                                   profileID: currentProfile?.id,
                                   profileName: currentProfile?.name,
                                   query: session?.query,
                                   searchType: session.map { String($0.type.rawValue) },
                                   deviceName: Continuity.deviceName,
                                   date: .now)
    }

    /// Pubblica lo stato sugli altri dispositivi (solo con una sessione vera).
    func publishContinuity() {
        guard sessionActive, !demoMode else { return }
        Continuity.pushSnapshot(continuitySnapshot)
    }

    /// Stato recente pubblicato da UN ALTRO dispositivo, se c'è una ricerca da riprendere.
    var pendingContinuitySearch: Continuity.Snapshot? {
        guard let snap = Continuity.pullSnapshot(), snap.deviceName != Continuity.deviceName,
              Date.now.timeIntervalSince(snap.date) < Continuity.freshness,
              let q = snap.query, !q.isEmpty,
              !searchSessions.contains(where: { $0.query == q }) else { return nil }
        return snap
    }

    /// Riprende lo stato ricevuto (Handoff o chip «Continua»).
    func continueActivity(_ snap: Continuity.Snapshot) async {
        if let id = snap.profileID, id != currentProfile?.id,
           let p = profiles.first(where: { $0.id == id }) {
            await switchProfile(to: p)
        }
        if let s = AppSection(rawValue: snap.section) { selectedSection = s }
        if let q = snap.query, !q.isEmpty {
            selectedSection = .search
            let type = snap.searchType.flatMap(UInt8.init).flatMap(ECSearchType.init(rawValue:)) ?? .global
            if !searchSessions.contains(where: { $0.query == q }) {
                await startSearch(text: q, type: type, fileType: "", extension: "",
                                  minSizeBytes: 0, maxSizeBytes: 0, availability: 0)
            } else if let existing = searchSessions.first(where: { $0.query == q }) {
                activeSearchID = existing.id
            }
        }
    }

    func continueActivity(userInfo: [AnyHashable: Any]?) async {
        guard let info = userInfo else { return }
        let snap = Continuity.Snapshot(
            section: info["section"] as? String ?? AppSection.downloads.rawValue,
            profileID: (info["profileID"] as? String).flatMap(UUID.init(uuidString:)),
            profileName: info["profileName"] as? String,
            query: info["query"] as? String,
            searchType: info["searchType"] as? String,
            deviceName: info["deviceName"] as? String ?? "",
            date: .now)
        await continueActivity(snap)
    }
}

/// Pubblica l'attività Handoff e riprende quella ricevuta; aggiorna anche il
/// KVS quando cambiano sezione o ricerca. Da applicare alla radice dell'app.
struct ContinuityModifier: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        let snap = state.continuitySnapshot
        content
            .userActivity(Continuity.activityType, isActive: state.sessionActive && !state.demoMode) { activity in
                activity.title = Self.title(for: snap)
                activity.userInfo = [
                    "section": snap.section,
                    "profileID": snap.profileID?.uuidString ?? "",
                    "profileName": snap.profileName ?? "",
                    "query": snap.query ?? "",
                    "searchType": snap.searchType ?? "",
                    "deviceName": snap.deviceName,
                ]
                activity.requiredUserInfoKeys = ["section"]
                activity.isEligibleForHandoff = true
                activity.isEligibleForSearch = true
                activity.targetContentIdentifier = "\(snap.profileID?.uuidString ?? "-")/\(snap.section)/\(snap.query ?? "")"
            }
            .onContinueUserActivity(Continuity.activityType) { activity in
                Task { await state.continueActivity(userInfo: activity.userInfo) }
            }
            .onChange(of: state.selectedSection) { _, _ in state.publishContinuity() }
            .onChange(of: state.activeSearchID) { _, _ in state.publishContinuity() }
            .onChange(of: state.sessionActive) { _, active in if active { state.publishContinuity() } }
        #endif
    }

    static func title(for snap: Continuity.Snapshot) -> String {
        let section = AppSection(rawValue: snap.section) ?? .downloads
        let base: String
        switch section {
        case .search:
            if let q = snap.query, !q.isEmpty { base = String(localized: "Ricerca “\(q)”") } else { base = String(localized: "Ricerca") }
        case .downloads: base = String(localized: "Trasferimenti")
        case .servers: base = String(localized: "Server")
        default: base = String(localized: "aMule Remote")
        }
        if let p = snap.profileName, !p.isEmpty { return "\(base) · \(p)" }
        return base
    }
}

extension View {
    func continuity(_ state: AppState) -> some View { modifier(ContinuityModifier(state: state)) }
}

/// Chip «Continua la ricerca “…” da iPhone», per le viste Ricerca (anche Apple TV).
struct ContinueSearchChip: View {
    @EnvironmentObject var state: AppState
    @State private var snap: Continuity.Snapshot?
    @State private var dismissed = false

    var body: some View {
        Group {
            if let s = snap, !dismissed {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                    Text("Continua la ricerca “\(s.query ?? "")” da \(s.deviceName)")
                        .lineLimit(2)
                    Spacer()
                    Button {
                        Task { await state.continueActivity(s) }
                        dismissed = true
                    } label: {
                        Text("Continua").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    #if !os(tvOS)
                    .controlSize(.small)
                    #endif
                    Button {
                        dismissed = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
            }
        }
        .onAppear { snap = state.pendingContinuitySearch }
        .onReceive(NotificationCenter.default.publisher(for: CloudSync.changeNotification)) { _ in
            snap = state.pendingContinuitySearch
        }
    }
}
