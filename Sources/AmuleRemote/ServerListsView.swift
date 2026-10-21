import SwiftUI

/// Impostazioni → Elenchi server: fonti curate di server.met, URL personalizzati,
/// anteprima e importazione in amuled. Condivisa da iOS/iPadOS, visionOS,
/// macOS (Impostazioni ⌘,) e tvOS (senza campo URL: sulla TV si usano le fonti).
struct ServerListsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var manager = ServerListManager.shared
    @State private var customURL = ""
    @State private var customName = ""
    @State private var preview: ServerListSource?
    @State private var addError = false

    var body: some View {
        Form {
            Section {
                ForEach(manager.catalog.sources) { src in
                    sourceRow(src)
                }
            } header: {
                Text("Fonti affidabili")
            } footer: {
                Text("Elenco mantenuto nel progetto e aggiornato senza nuove versioni dell'app. Ogni fonte viene scaricata e letta dall'app: vedi i server prima di importarli, anche se il tuo aMule non ha accesso al web.")
            }

            Section {
                ForEach(manager.custom) { src in
                    sourceRow(src)
                        #if !os(tvOS)
                        .swipeActions {
                            Button(role: .destructive) { manager.removeCustom(src) } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                        #endif
                        .contextMenu {
                            Button(role: .destructive) { manager.removeCustom(src) } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                }
                #if !os(tvOS)
                TextField("https://esempio.org/server.met", text: $customURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS) || os(visionOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Nome (facoltativo)", text: $customName)
                Button {
                    if let src = manager.addCustom(url: customURL, name: customName) {
                        customURL = ""; customName = ""
                        Task { await manager.fetch(src, demo: state.demoMode) }
                    } else {
                        addError = true
                    }
                } label: {
                    Label("Aggiungi fonte", systemImage: "plus.circle")
                }
                .disabled(customURL.trimmingCharacters(in: .whitespaces).isEmpty)
                #endif
            } header: {
                Text("Le mie fonti")
            } footer: {
                #if os(tvOS)
                Text("Le fonti personalizzate si aggiungono da iPhone, iPad o Mac.")
                #else
                Text("Hai trovato un server.met sul web? Incolla qui l'indirizzo (anche .gz): l'app lo verifica e lo ricorda tra le tue fonti.")
                #endif
            }

            Section {
                Button {
                    Task { await manager.checkAll(demo: state.demoMode) }
                } label: {
                    Label("Verifica tutte le fonti", systemImage: "checkmark.circle")
                }
                if let err = manager.catalogError {
                    Text("Catalogo non aggiornato: \(err)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Elenchi server")
        .task { await manager.refreshCatalog(demo: state.demoMode) }
        .alert("Indirizzo non valido", isPresented: $addError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Inserisci un indirizzo http:// o https:// che punti a un file server.met.")
        }
        .sheet(item: $preview) { src in
            ServerListPreviewView(source: src)
                .environmentObject(state)
        }
    }

    @ViewBuilder
    private func sourceRow(_ src: ServerListSource) -> some View {
        let st = manager.status[src.id]
        Button {
            preview = src
        } label: {
            HStack(spacing: 12) {
                Image(systemName: src.custom ? "link" : "checkmark.seal")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(src.name).foregroundStyle(.primary)
                    Text(src.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    statusText(st).font(.caption)
                }
                Spacer()
                if case .checking = st?.kind { ProgressView().controlSize(.small) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusText(_ st: ServerListStatus?) -> some View {
        switch st?.kind {
        case .none, .unknown: Text("Non ancora verificata").foregroundStyle(.secondary)
        case .checking: Text("Verifica in corso…").foregroundStyle(.secondary)
        case .ok(let count, _):
            Text("Raggiungibile · \(count) server").foregroundStyle(.green)
        case .failed(let msg):
            Text("Non disponibile: \(msg)").foregroundStyle(.red)
        }
    }
}

/// Anteprima dei server di una fonte, con selezione e importazione.
struct ServerListPreviewView: View {
    let source: ServerListSource
    @EnvironmentObject var state: AppState
    @ObservedObject private var manager = ServerListManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    @State private var replace = false
    @State private var importing = false
    @State private var result: Int?

    private var servers: [ParsedServer] { manager.status[source.id]?.servers ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if case .checking = manager.status[source.id]?.kind {
                    ProgressView("Scaricamento in corso…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if case .failed(let msg) = manager.status[source.id]?.kind {
                    ContentUnavailableView("Fonte non disponibile", systemImage: "exclamationmark.triangle", description: Text(msg))
                } else if servers.isEmpty {
                    ContentUnavailableView("Nessun server nel file", systemImage: "server.rack")
                } else {
                    List {
                        Section {
                            ForEach(servers) { s in
                                Button {
                                    if selected.contains(s.id) { selected.remove(s.id) } else { selected.insert(s.id) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selected.contains(s.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(s.id) ? Color.accentColor : .secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.name).foregroundStyle(.primary)
                                            Text(s.address).font(.caption).foregroundStyle(.secondary)
                                            if s.users > 0 || s.files > 0 {
                                                Text("Utenti: \(s.users.formatted()) · File: \(s.files.formatted())")
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("\(servers.count) server · selezionati \(selected.count)")
                        }
                        Section {
                            Toggle("Sostituisci l'elenco attuale", isOn: $replace)
                            Button {
                                Task { await doImport() }
                            } label: {
                                if importing {
                                    ProgressView()
                                } else {
                                    Label("Importa \(selected.count) server in aMule", systemImage: "square.and.arrow.down")
                                }
                            }
                            .disabled(selected.isEmpty || importing)
                            Button {
                                Task {
                                    await state.updateServerListFromURL(source.url)
                                    result = -1
                                }
                            } label: {
                                Label("Fai scaricare l'elenco al server", systemImage: "arrow.down.to.line")
                            }
                        } footer: {
                            Text("«Sostituisci» rimuove prima i server già presenti in aMule. «Fai scaricare» passa l'indirizzo ad aMule, che deve avere accesso al web.")
                        }
                    }
                }
            }
            .navigationTitle(source.name)
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(selected.count == servers.count ? "Nessuno" : "Tutti") {
                        if selected.count == servers.count { selected.removeAll() } else { selected = Set(servers.map(\.id)) }
                    }
                    .disabled(servers.isEmpty)
                }
            }
            .task {
                if manager.status[source.id]?.servers.isEmpty ?? true {
                    await manager.fetch(source, demo: state.demoMode)
                }
                selected = Set(servers.map(\.id))
            }
            .alert("Elenco server", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                Button("OK") { dismiss() }
            } message: {
                if let r = result, r >= 0 {
                    Text("Aggiunti \(r) server ad aMule.")
                } else {
                    Text("Richiesta inviata ad aMule: l'elenco si aggiorna in pochi secondi.")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
    }

    private func doImport() async {
        importing = true
        let chosen = servers.filter { selected.contains($0.id) }
        let n = await state.importServers(chosen, replace: replace)
        importing = false
        result = n
    }
}
