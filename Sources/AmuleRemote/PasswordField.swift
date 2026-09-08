import SwiftUI

/// Campo password con "occhiolino" per mostrare/nascondere il testo,
/// uguale su tutte le piattaforme. Su macOS il titolo fa da etichetta del
/// Form ("Password:"), su iOS/visionOS è il placeholder del campo.
struct PasswordField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    @State private var revealed = false

    init(_ title: LocalizedStringKey, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        #if os(macOS)
        LabeledContent(title) { fieldRow.labelsHidden() }
        #else
        fieldRow
        #endif
    }

    private var fieldRow: some View {
        HStack(spacing: 8) {
            Group {
                if revealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textContentType(.password)
            .autocorrectionDisabled()
            #if !os(macOS)
            .textInputAutocapitalization(.never)
            #endif
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(revealed ? Text("Nascondi password") : Text("Mostra password"))
            .accessibilityLabel(revealed ? Text("Nascondi password") : Text("Mostra password"))
        }
    }
}
