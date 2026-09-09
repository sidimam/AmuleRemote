#if os(iOS)
import UIKit

// Azioni rapide dal menu dell'icona in Home (pressione lunga sull'icona):
// il sistema le consegna allo scene delegate, che le passa alla UI SwiftUI
// tramite QuickActionRouter (Sources/AmuleRemote/QuickActions.swift).

/// App delegate minimale: serve solo a installare il nostro scene delegate.
/// SwiftUI continua a creare e gestire la finestra della WindowGroup.
final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Avvio a freddo da un'azione rapida.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem, let action = QuickAction(rawValue: item.type) {
            Task { @MainActor in QuickActionRouter.shared.pending = action }
        }
    }

    /// App già in memoria.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let action = QuickAction(rawValue: shortcutItem.type)
        Task { @MainActor in QuickActionRouter.shared.pending = action }
        completionHandler(action != nil)
    }
}

enum HomeScreenShortcuts {
    /// Registra le voci del menu dell'icona, localizzate nella lingua corrente
    /// dell'app (rifatto a ogni passaggio in background così segue i cambi lingua).
    @MainActor static func install() {
        UIApplication.shared.shortcutItems = QuickAction.allCases.map { action in
            UIApplicationShortcutItem(type: action.rawValue,
                                      localizedTitle: action.title,
                                      localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(systemImageName: action.systemImage),
                                      userInfo: nil)
        }
    }
}
#endif
