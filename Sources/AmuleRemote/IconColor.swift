import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Colori disponibili per l'icona dell'app. "default" = il verde originale.
/// Ogni colore ha varianti chiara e scura (generate da icon_colors.swift).
struct AppIconColor: Identifiable, Equatable {
    let key: String       // chiave persistita e suffisso degli asset
    let label: LocalizedStringKey
    let tint: Color       // pallino mostrato nelle impostazioni

    var id: String { key }

    /// Stesso testo di `label`, come risorsa localizzabile (per String(localized:)).
    var labelText: String.LocalizationValue {
        switch key {
        case "blu": return "Blu"
        case "rosso": return "Rosso"
        case "arancione": return "Arancione"
        case "viola": return "Viola"
        case "teal": return "Verde acqua"
        case "grafite": return "Grafite"
        default: return "Verde (originale)"
        }
    }

    static let all: [AppIconColor] = [
        .init(key: "default", label: "Verde (originale)", tint: Color(red: 0.24, green: 0.62, blue: 0.34)),
        .init(key: "blu", label: "Blu", tint: Color(red: 0.18, green: 0.44, blue: 0.89)),
        .init(key: "rosso", label: "Rosso", tint: Color(red: 0.84, green: 0.27, blue: 0.25)),
        .init(key: "arancione", label: "Arancione", tint: Color(red: 0.91, green: 0.35, blue: 0.05)),
        .init(key: "viola", label: "Viola", tint: Color(red: 0.49, green: 0.30, blue: 0.88)),
        .init(key: "teal", label: "Verde acqua", tint: Color(red: 0.05, green: 0.64, blue: 0.65)),
        .init(key: "grafite", label: "Grafite", tint: Color(red: 0.35, green: 0.40, blue: 0.45)),
    ]

    /// Tinta dell'interfaccia (pulsanti, link, evidenziazioni) coerente con il
    /// colore icona scelto: il verde originale per «default».
    static func tint(for key: String) -> Color {
        all.first { $0.key == key }?.tint ?? all[0].tint
    }

    /// Applica il colore scelto: icone alternative su iOS/iPadOS/visionOS,
    /// icona del Dock su macOS. watchOS non offre alcuna API per cambiare
    /// icona: sull'orologio resta quella predefinita.
    static func apply(_ key: String) {
        #if os(iOS) || os(visionOS)
        DispatchQueue.main.async {
            guard UIApplication.shared.supportsAlternateIcons else { return }
            let name = key == "default" ? nil : "AppIcon-\(key)"
            if UIApplication.shared.alternateIconName != name {
                UIApplication.shared.setAlternateIconName(name)
            }
        }
        #elseif os(macOS)
        DockIcon.update()
        #endif
    }
}

/// Selettore a pallini del colore icona, per le Impostazioni avanzate.
struct IconColorPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppIconColor.all) { c in
                Button {
                    selection = c.key
                } label: {
                    ZStack {
                        Circle()
                            .fill(c.tint)
                            .frame(width: 30, height: 30)
                        if selection == c.key {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(c.label))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
