import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// Share Extension «Aggiungi ad aMule Remote»: riceve testo, URL o pagine web
// da Note, Safari, Messaggi, Mail…, estrae tutti i link ed2k:// e li accoda
// sul profilo corrente dell'app (letto dal gruppo keychain condiviso) con una
// connessione EC usa-e-getta. Funziona anche con l'app chiusa.

#if canImport(UIKit)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareLinksView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}
#else
final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = NSHostingController(rootView: ShareLinksView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.width, .height]
        view.addSubview(host.view)
        Task { await model.load() }
    }
}
#endif

/// Stato della condivisione: link trovati, profilo, esito.
@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, sending, done(Int), failed(String) }

    @Published var links: [String] = []
    @Published var phase: Phase = .loading
    @Published var profile: SharedProfile? = Keychain.loadSharedProfile()

    private weak var context: NSExtensionContext?

    init(context: NSExtensionContext?) { self.context = context }

    /// Legge testo e URL da tutti gli allegati condivisi.
    func load() async {
        var texts: [String] = []
        let items = context?.inputItems as? [NSExtensionItem] ?? []
        for item in items {
            if let s = item.attributedContentText?.string { texts.append(s) }
            for provider in item.attachments ?? [] {
                for type in [UTType.url, UTType.plainText, UTType.text, UTType.propertyList] {
                    guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }
                    if let value = try? await provider.loadItem(forTypeIdentifier: type.identifier) {
                        switch value {
                        case let url as URL: texts.append(url.absoluteString)
                        case let str as String: texts.append(str)
                        case let data as Data: texts.append(String(decoding: data, as: UTF8.self))
                        case let dict as NSDictionary:
                            // Pagina web (JavaScript preprocessing): testo della pagina.
                            if let results = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                                texts.append(contentsOf: results.values.compactMap { $0 as? String })
                            }
                        default: break
                        }
                    }
                }
            }
        }
        links = Ed2kLink.extract(texts.joined(separator: "\n"))
        phase = .ready
    }

    /// Accoda i link con una connessione EC verso il profilo condiviso.
    func send() async {
        guard let p = profile else { phase = .failed(String(localized: "Nessun profilo server configurato in aMule Remote.")); return }
        guard let password = Keychain.loadPassword(account: p.address), !password.isEmpty else {
            phase = .failed(String(localized: "Password del server non trovata: apri aMule Remote e connettiti una volta."))
            return
        }
        phase = .sending
        let client = ECClient()
        do {
            try await client.connect(host: p.host, port: UInt16(clamping: p.port), password: password)
        } catch {
            phase = .failed(String(localized: "Server aMule non raggiungibile (\(p.host))."))
            return
        }
        var added = 0
        for link in links {
            var tag = ECTag.string(.string, link)
            tag.children = [.number(.partfileCat, 0)]
            let reply = try? await client.request(ECPacket(.addLink, tags: [tag]))
            if let r = reply, r.opcode != .failed { added += 1 }
        }
        await client.disconnectNow()
        phase = .done(added)
    }

    func finish() {
        context?.completeRequest(returningItems: nil)
    }

    func cancel() {
        context?.cancelRequest(withError: NSError(domain: "com.sdimambro.amule-remote.share", code: 0))
    }
}

struct ShareLinksView: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let p = model.profile {
                        LabeledContent("Server") { Text(p.name).foregroundStyle(.secondary) }
                    } else {
                        Label("Nessun profilo server configurato in aMule Remote.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    switch model.phase {
                    case .loading:
                        ProgressView("Lettura del contenuto…")
                    case .ready, .sending, .done, .failed:
                        if model.links.isEmpty {
                            Text("Nessun link ed2k:// nel contenuto condiviso.").foregroundStyle(.secondary)
                        } else {
                            ForEach(model.links, id: \.self) { l in
                                Label(Ed2kLink.name(l), systemImage: "link").lineLimit(2)
                            }
                        }
                    }
                } header: {
                    Text(model.links.isEmpty ? "Link" : "\(model.links.count) link trovati")
                }
                if case .done(let n) = model.phase {
                    Section { Label("Aggiunti \(n) download ad aMule.", systemImage: "checkmark.circle").foregroundStyle(.green) }
                }
                if case .failed(let msg) = model.phase {
                    Section { Label(msg, systemImage: "xmark.octagon").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Aggiungi ad aMule Remote")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch model.phase {
                    case .done:
                        Button("Fine") { model.finish() }
                    case .sending:
                        ProgressView()
                    default:
                        Button("Aggiungi") { Task { await model.send() } }
                            .disabled(model.links.isEmpty || model.profile == nil || model.phase == .loading)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        .padding(.bottom, 8)
        #endif
    }
}
