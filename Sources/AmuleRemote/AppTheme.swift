import SwiftUI

/// Lingua dell'app: di sistema oppure una forzata dall'utente.
/// Il cambio è immediato per l'interfaccia SwiftUI (environment locale);
/// AppleLanguages viene sincronizzato per completare il cambio (notifiche,
/// formattazioni) al riavvio successivo.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case italian = "it"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case chinese = "zh-Hans"
    case arabic = "ar"

    var id: String { rawValue }

    /// Nome della lingua nella lingua stessa (endonimo), come da convenzione.
    var label: String {
        switch self {
        case .system: return String(localized: "Sistema")
        case .italian: return "Italiano"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .chinese: return "中文（简体）"
        case .arabic: return "العربية"
        }
    }

    /// nil = segue la lingua di sistema.
    var locale: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }

    var isRTL: Bool { self == .arabic }

    /// Sincronizza l'override di sistema (vale dal prossimo avvio per ciò che
    /// non passa da SwiftUI: notifiche, String(localized:), formattatori).
    func applySystemOverride() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// Applica la lingua forzata (locale + direzione destra→sinistra per l'arabo)
/// all'albero SwiftUI; con "Sistema" non tocca nulla.
struct AppLocaleModifier: ViewModifier {
    let language: AppLanguage

    @ViewBuilder
    func body(content: Content) -> some View {
        if let locale = language.locale {
            content
                .environment(\.locale, locale)
                .environment(\.layoutDirection, language.isRTL ? .rightToLeft : .leftToRight)
        } else {
            content
        }
    }
}

/// Aspetto dell'app: chiaro, scuro o come il sistema.
enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// nil = segue il sistema (nessuna forzatura).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
