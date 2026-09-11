import SwiftUI
import UIKit

/// Campo di testo nativo per tvOS. Il TextField SwiftUI, aggiornando il
/// binding a ogni carattere, azzera il testo «provvisorio» della tastiera
/// remota dell'iPhone (ogni lettera sostituiva la precedente, cursore che
/// oscilla). Qui il testo vive nel UITextField e il binding riceve il valore
/// solo a fine digitazione (Fine/Invio o perdita del focus).
struct TVTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var returnKey: UIReturnKeyType = .done
    var onSubmit: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let f = UITextField(frame: .zero)
        f.placeholder = placeholder
        f.text = text
        f.isSecureTextEntry = isSecure
        f.keyboardType = keyboard
        f.textContentType = contentType
        f.returnKeyType = returnKey
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.delegate = context.coordinator
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return f
    }

    func updateUIView(_ f: UITextField, context: Context) {
        // Mai toccare il testo mentre l'utente sta scrivendo.
        if !f.isEditing && f.text != text { f.text = text }
        f.placeholder = placeholder
        f.isSecureTextEntry = isSecure
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TVTextField
        init(_ parent: TVTextField) { self.parent = parent }

        private func commit(_ f: UITextField) {
            let value = f.text ?? ""
            if parent.text != value { parent.text = value }
        }

        func textFieldDidEndEditing(_ textField: UITextField) { commit(textField) }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            commit(textField)
            textField.resignFirstResponder()
            parent.onSubmit?()
            return true
        }
    }
}
