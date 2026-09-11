#if os(macOS)
import AppKit
import SwiftUI

/// Menu del Dock (clic destro sull'icona mentre l'app è aperta): stesse azioni
/// rapide del menu dell'icona su iPhone/iPad. Le voci arrivano alla UI tramite
/// QuickActionRouter, come su iOS.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for action in [QuickAction.addLink, .addFromClipboard, .pauseAll, .resumeAll] {
            let item = NSMenuItem(title: action.title, action: #selector(run(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: action.systemImage, accessibilityDescription: nil)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = QuickAction(rawValue: raw) else { return }
        Task { @MainActor in QuickActionRouter.shared.pending = action }
    }
}

/// Clic e tasti nella finestra azzerano il timer di inattività (come il tocco
/// su iOS): senza questo il Mac non saprebbe che l'utente è presente.
enum MacActivityMonitor {
    private static var token: Any?

    static func start(_ onActivity: @escaping () -> Void) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { event in
            onActivity()
            return event
        }
    }
}

/// Pannello "Informazioni su aMule Remote" (menu app): versione, autore,
/// licenza MIT e collegamenti a wiki, segnalazioni e privacy.
enum MacAboutPanel {
    static func show() {
        let credits = NSMutableAttributedString()
        func line(_ text: String, url: URL? = nil) {
            let attrs: [NSAttributedString.Key: Any] = url.map { [.link: $0] } ?? [:]
            credits.append(NSAttributedString(string: text, attributes: attrs))
            credits.append(NSAttributedString(string: "\n"))
        }
        line(String(localized: "Telecomando per un server aMule (amuled) tramite il protocollo EC."))
        line("")
        line(String(localized: "Autore") + ": " + AppLinks.author)
        line(String(localized: "Licenza") + ": MIT", url: AppLinks.license)
        line("")
        line(String(localized: "Guida (wiki)"), url: AppLinks.wiki)
        line(String(localized: "Segnala un problema"), url: AppLinks.bugReport)
        line(String(localized: "Informativa sulla privacy"), url: AppLinks.privacy)
        line(String(localized: "Codice sorgente"), url: AppLinks.repository)
        credits.addAttributes([.font: NSFont.systemFont(ofSize: 11),
                               .foregroundColor: NSColor.labelColor],
                              range: NSRange(location: 0, length: credits.length))
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        credits.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: credits.length))

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "aMule Remote",
            .applicationVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "",
            .version: (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "",
        ])
    }
}
#endif
