import SwiftUI

/// Gestione dei profili server: elenco, aggiunta, modifica, eliminazione e
/// scelta del profilo predefinito (quello proposto all'avvio dell'app).
struct iOSProfilesView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: ServerProfile?
    @State private var showNew = false

    var body: some View {
        List {
            Section {
                ForEach(state.profiles) { profile in
                    Button {
                        editing = profile
                    } label: {
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .foregroundStyle(.primary)
                                Text(profile.address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profile.id == state.defaultProfileID {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                            if state.connected && state.currentProfile?.id == profile.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            state.deleteProfile(profile)
                        } label: { Label("Elimina", systemImage: "trash") }
                        Button {
                            state.setDefaultProfile(profile)
                        } label: { Label("Predefinito", systemImage: "star") }
                            .tint(.yellow)
                    }
                }
            } footer: {
                Text("Il profilo con la stella è quello predefinito, proposto all'avvio. Scorri a sinistra per eliminare un profilo o renderlo predefinito.")
            }
        }
        .navigationTitle("Profili server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { profile in
            ProfileEditorView(profile: profile)
        }
        .sheet(isPresented: $showNew) {
            ProfileEditorView(profile: nil)
        }
    }
}

/// Editor di un profilo (nuovo o esistente). La password è salvata nel
/// Portachiavi con account "host:port".
struct ProfileEditorView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let original: ServerProfile?
    @State private var name: String
    @State private var host: String
    @State private var port: Int
    @State private var password: String
    @State private var isDefault: Bool

    init(profile: ServerProfile?) {
        original = profile
        _name = State(initialValue: profile?.name ?? "")
        _host = State(initialValue: profile?.host ?? "")
        _port = State(initialValue: profile?.port ?? 4712)
        let stored = profile.flatMap { Keychain.loadPassword(account: $0.address) } ?? ""
        _password = State(initialValue: stored)
        _isDefault = State(initialValue: profile != nil && profile?.id == ProfileStore.defaultID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profilo") {
                    TextField("Nome (es. Unraid casa)", text: $name)
                }
                Section("Server") {
                    TextField("Host o IP", text: $host)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Porta EC", value: $port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    PasswordField("Password", text: $password)
                }
                Section {
                    Toggle("Profilo predefinito", isOn: $isDefault)
                } footer: {
                    Text("Il profilo predefinito viene proposto all'avvio dell'app e usato per i controlli in background.")
                }
            }
            .navigationTitle(original == nil ? "Nuovo profilo" : "Modifica profilo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        var profile = original ?? ServerProfile(name: "", host: "", port: 4712)
        profile.name = cleanName.isEmpty ? cleanHost : cleanName
        profile.host = cleanHost
        profile.port = port
        state.upsertProfile(profile)
        if !password.isEmpty {
            Keychain.savePassword(password, account: profile.address)
        }
        if isDefault {
            state.setDefaultProfile(profile)
        } else if state.defaultProfileID == profile.id {
            // Tolta la stella al profilo che era predefinito.
            state.defaultProfileID = state.profiles.first(where: { $0.id != profile.id })?.id
        }
        dismiss()
    }
}
