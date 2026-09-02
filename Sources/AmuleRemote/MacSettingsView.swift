#if os(macOS)
import SwiftUI

/// Impostazioni dell'app macOS (App menu → Impostazioni…, ⌘,):
/// aspetto, blocco Touch ID, notifiche e gestione dei profili server.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            MacGeneralSettings()
                .tabItem { Label("Generale", systemImage: "gearshape") }
            MacProfilesSettings()
                .tabItem { Label("Profili", systemImage: "person.2") }
        }
        .frame(width: 480, height: 380)
    }
}

struct MacGeneralSettings: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                Picker("Aspetto:", selection: $state.themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Lingua:", selection: $state.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
            } footer: {
                Text("Il cambio lingua è immediato per l'interfaccia; notifiche e formati si adeguano al prossimo avvio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Richiedi \(BiometricAuth.biometryLabel) all'apertura", isOn: Binding(
                    get: { state.biometricLockEnabled },
                    set: { newValue in Task { await state.setBiometricLock(newValue) } }
                ))
                .disabled(!BiometricAuth.isAvailable)
            } footer: {
                Text("Con il blocco attivo, all'avvio l'app chiede \(BiometricAuth.biometryLabel) (o la password del Mac) prima di mostrare i contenuti.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifiche") {
                Toggle("Download completati", isOn: $state.notifyDownloadsEnabled)
                Toggle("Disconnessioni eD2k / Kad", isOn: $state.notifyNetworkEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct MacProfilesSettings: View {
    @EnvironmentObject var state: AppState
    @State private var editing: ServerProfile?
    @State private var showNew = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(state.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                            Text(profile.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if profile.id == state.defaultProfileID {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                                .help("Profilo predefinito")
                        }
                        if state.connected && state.currentProfile?.id == profile.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                .help("Connesso")
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Connetti") { Task { await state.switchProfile(to: profile) } }
                        Button("Rendi predefinito") { state.setDefaultProfile(profile) }
                        Button("Modifica…") { editing = profile }
                        Divider()
                        Button("Elimina", role: .destructive) { state.deleteProfile(profile) }
                    }
                    .onTapGesture(count: 2) { editing = profile }
                }
            }
            Divider()
            HStack {
                Button {
                    showNew = true
                } label: { Image(systemName: "plus") }
                Spacer()
                Text("Doppio clic per modificare; clic destro per le azioni.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .sheet(item: $editing) { profile in
            MacProfileEditor(profile: profile)
        }
        .sheet(isPresented: $showNew) {
            MacProfileEditor(profile: nil)
        }
    }
}

struct MacProfileEditor: View {
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
        VStack(spacing: 16) {
            Text(original == nil ? "Nuovo profilo" : "Modifica profilo")
                .font(.headline)
            Form {
                TextField("Nome:", text: $name, prompt: Text("es. Unraid casa"))
                TextField("Host / IP:", text: $host)
                TextField("Porta EC:", value: $port, format: .number.grouping(.never))
                SecureField("Password:", text: $password)
                Toggle("Profilo predefinito", isOn: $isDefault)
            }
            HStack {
                Button("Annulla") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Salva") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
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
            state.defaultProfileID = state.profiles.first(where: { $0.id != profile.id })?.id
        }
        dismiss()
    }
}
#endif
