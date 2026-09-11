import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import UserNotifications

/// Apertura delle impostazioni di sistema dell'app (notifiche) e testi dello
/// stato del permesso, condivisi da iOS/iPadOS, visionOS e macOS.
enum SystemSettings {
    /// Apre la pagina Notifiche dell'app nelle impostazioni di sistema.
    /// Su tvOS non esiste (le app non ricevono notifiche).
    static func openNotificationSettings() {
        #if os(iOS) || os(visionOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        let bundle = Bundle.main.bundleIdentifier ?? "com.sdimambro.amule-remote"
        let specific = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundle)")
        let generic = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        if let url = specific ?? generic {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    /// Etichetta breve dello stato del permesso, per la riga «Notifiche».
    static func statusLabel(_ status: UNAuthorizationStatus) -> LocalizedStringKey {
        switch status {
        case .authorized: return "Attive"
        case .provisional: return "Riepilogo"
        case .denied: return "Disattivate"
        case .notDetermined: return "Non richieste"
        @unknown default: return "Attive"
        }
    }
}

/// Riga «Notifiche ›»: se il permesso non è ancora stato chiesto lo chiede,
/// altrimenti apre la pagina dell'app nelle Impostazioni di sistema.
struct NotificationsSettingsRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button {
            Task {
                if state.notificationStatus == .notDetermined {
                    _ = await state.requestNotificationConsent()
                } else {
                    SystemSettings.openNotificationSettings()
                }
            }
        } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(SystemSettings.statusLabel(state.notificationStatus))
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(.secondary)
            } label: {
                Label("Notifiche", systemImage: "bell.badge")
            }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .foregroundStyle(.primary)
        #endif
        .task { await state.refreshNotificationStatus() }
    }
}
