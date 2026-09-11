import SwiftUI

/// Foglio «Aggiungi link eD2k» condiviso da iPhone/iPad, Apple Vision Pro e
/// Mac: più link insieme (uno per riga o incollati alla rinfusa), pulsante
/// Incolla di sistema (nessun avviso «ha incollato da…», nessun permesso) e,
/// sul Mac, precompilazione automatica dagli Appunti se contengono link ed2k.
struct AddLinkSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var editing: Bool

    private var links: [String] { AppState.extractEd2kLinks(text) }

    var body: some View {
        #if os(macOS)
        content
            .padding(24)
            .frame(width: 560)
        #else
        NavigationStack {
            content
                .padding()
                .navigationTitle("Aggiungi link eD2k")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(addTitle) { add() }.disabled(links.isEmpty)
                    }
                }
        }
        #endif
    }

    // Sempre «Aggiungi»: il numero di link riconosciuti è già nel piè di pagina
    // (con il conteggio nel titolo la barra di iPhone troncava il titolo).
    private var addTitle: LocalizedStringKey { "Aggiungi" }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            #if os(macOS)
            Text("Aggiungi link eD2k").font(.headline)
            #endif
            Text("Incolla uno o più link ed2k:// (anche uno per riga, o un testo che li contiene): l'app li riconosce da sola.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.callout.monospaced())
                .frame(minHeight: 120, maxHeight: 220)
                .focused($editing)
                .autocorrectionDisabled()
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                #else
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                #endif
            HStack {
                // Pulsante Incolla di sistema: legge gli Appunti solo al tocco.
                PasteButton(payloadType: String.self) { strings in
                    let pasted = strings.joined(separator: "\n")
                    text = text.isEmpty ? pasted : text + "\n" + pasted
                }
                .labelStyle(.titleAndIcon)
                Spacer()
                if !links.isEmpty {
                    Text("\(links.count) link riconosciuti")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !text.isEmpty {
                    Text("Nessun link ed2k:// nel testo")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            #if os(macOS)
            HStack {
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(addTitle) { add() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(links.isEmpty)
            }
            #endif
        }
        .onAppear {
            #if os(macOS)
            // Sul Mac gli Appunti sono liberi: se contengono link ed2k li proponiamo subito.
            if text.isEmpty, let s = NSPasteboard.general.string(forType: .string),
               !AppState.extractEd2kLinks(s).isEmpty {
                text = s
            }
            #endif
            editing = true
        }
    }

    private func add() {
        let payload = text
        dismiss()
        Task {
            let n = await state.addEd2kLinks(from: payload)
            if n > 1 { state.infoMessage = String(localized: "Aggiunti \(n) link ai download.") }
        }
    }
}
