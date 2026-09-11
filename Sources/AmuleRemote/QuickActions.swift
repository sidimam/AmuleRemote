import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Azioni rapide raggiungibili senza aprire prima l'app: menu dell'icona in
/// Home (iPhone/iPad), menu del Dock e barra dei menu (Mac). Su visionOS e
/// tvOS non esiste un menu dell'icona: lì restano Siri e Comandi rapidi.
enum QuickAction: String, CaseIterable {
    case addLink = "com.sdimambro.amule-remote.addlink"
    case pauseAll = "com.sdimambro.amule-remote.pauseall"
    case resumeAll = "com.sdimambro.amule-remote.resumeall"
    case search = "com.sdimambro.amule-remote.search"
    /// Solo Mac (Dock e menu): su iOS la lettura degli Appunti mostrerebbe l'avviso di sistema.
    case addFromClipboard = "com.sdimambro.amule-remote.addclipboard"

    /// Voci del menu dell'icona in Home (iPhone/iPad).
    static var homeScreenCases: [QuickAction] { [.addLink, .pauseAll, .resumeAll, .search] }

    var title: String {
        switch self {
        case .addLink: return String(localized: "Aggiungi link eD2k")
        case .addFromClipboard: return String(localized: "Aggiungi link dagli Appunti")
        case .pauseAll: return String(localized: "Metti in pausa tutti i download")
        case .resumeAll: return String(localized: "Riprendi tutti i download")
        case .search: return String(localized: "Cerca")
        }
    }

    var systemImage: String {
        switch self {
        case .addLink: return "link.badge.plus"
        case .pauseAll: return "pause.circle"
        case .resumeAll: return "play.circle"
        case .search: return "magnifyingglass"
        case .addFromClipboard: return "doc.on.clipboard"
        }
    }
}

/// Ponte tra il sistema (scene delegate, Dock, menu) e la UI SwiftUI: l'azione
/// resta in attesa finché l'app è connessa (o offline con dati in cache).
@MainActor
final class QuickActionRouter: ObservableObject {
    static let shared = QuickActionRouter()
    @Published var pending: QuickAction?
}

extension AppState {
    /// Esegue un'azione rapida. Se l'app non è ancora connessa ma ha le
    /// credenziali, connette prima (o riprende dallo stato offline).
    func perform(_ action: QuickAction) async {
        if !connected {
            if offline {
                await resumeFromOffline()
            } else if !connecting && !host.isEmpty && !password.isEmpty {
                await connect()
            }
        }
        switch action {
        case .addLink:
            selectedSection = .downloads
            addLinkRequested = true
        case .addFromClipboard:
            selectedSection = .downloads
            #if os(macOS)
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            let links = Self.extractEd2kLinks(text)
            if links.isEmpty {
                infoMessage = String(localized: "Nessun link ed2k:// negli Appunti.")
            } else {
                guard connected else { addLinkRequested = true; return }
                let n = await addEd2kLinks(from: text)
                infoMessage = n == 1 ? String(localized: "Aggiunto ai download: \(Self.ed2kLinkName(links[0]))")
                                     : String(localized: "Aggiunti \(n) link ai download.")
            }
            #else
            addLinkRequested = true
            #endif
        case .search:
            selectedSection = .search
        case .pauseAll:
            guard connected else { return }
            let n = await pauseAll()
            infoMessage = String(localized: "Messi in pausa \(n) download.")
        case .resumeAll:
            guard connected else { return }
            let n = await resumeAll()
            infoMessage = String(localized: "Ripresi \(n) download.")
        }
    }
}
