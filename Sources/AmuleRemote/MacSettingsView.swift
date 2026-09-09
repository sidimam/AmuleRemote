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
        .frame(width: 520, height: 620)
    }
}

struct MacGeneralSettings: View {
    @EnvironmentObject var state: AppState

    /// Sotto-toggle notifiche: appare spento finché il master è disattivato.
    private func gated(_ source: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { state.notificationsEnabled && source.wrappedValue },
                set: { source.wrappedValue = $0 })
    }

    var body: some View {
        // Stesse righe, stesse icone e stesso ordine della sezione
        // "Impostazioni app" / "Notifiche" di iOS e iPadOS.
        Form {
            Section {
                Picker(selection: $state.themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                } label: {
                    Label("Aspetto", systemImage: "circle.lefthalf.filled")
                }
                Picker(selection: $state.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                } label: {
                    Label("Lingua", systemImage: "globe")
                }
                LabeledContent {
                    IconColorPicker(selection: $state.iconColor)
                } label: {
                    Label("Colore icona", systemImage: "paintpalette")
                }
                Picker(selection: $state.idleTimeout) {
                    Text("Mai").tag(0)
                    Text("60 secondi").tag(60)
                    Text("120 secondi").tag(120)
                    Text("5 minuti").tag(300)
                    Text("10 minuti").tag(600)
                    Text("30 minuti").tag(1800)
                } label: {
                    Label("Vai offline dopo inattività", systemImage: "zzz")
                }
                Toggle(isOn: Binding(
                    get: { state.iCloudSyncEnabled },
                    set: { state.setCloudSync($0) }
                )) {
                    Label("Sincronizza profili con iCloud", systemImage: "icloud")
                }
                .disabled(!CloudSync.isAvailable)
                Toggle(isOn: Binding(
                    get: { state.biometricLockEnabled },
                    set: { newValue in Task { await state.setBiometricLock(newValue) } }
                )) {
                    Label("Richiedi \(BiometricAuth.biometryLabel)", systemImage: BiometricAuth.biometryIcon)
                }
                .disabled(!BiometricAuth.isAvailable)
            } header: {
                Text("Impostazioni app")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dopo il periodo di inattività scelto (nessun clic né tasto) la connessione al server si chiude, ma i dati restano visibili in stato Offline: riparte da sola al primo clic o con «Riconnetti». Il cambio lingua è immediato per l'interfaccia; notifiche e formati si adeguano al prossimo avvio. Il colore cambia l'icona nel Dock; quella nel Finder resta l'originale. Con il blocco attivo, all'avvio l'app chiede \(BiometricAuth.biometryLabel) (o la password del Mac) prima di mostrare i contenuti.")
                    if CloudSync.isAvailable {
                        Text("Con la sincronizzazione iCloud i profili server e le loro password (Portachiavi iCloud) sono condivisi tra i tuoi dispositivi.")
                    } else {
                        Text("La sincronizzazione iCloud richiede la build firmata ufficiale (DMG dal sito, Homebrew o Mac App Store): questa copia non ha il profilo iCloud.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { state.notificationsEnabled },
                    set: { v in Task { await state.setNotificationsEnabled(v) } }
                )) {
                    Label("Notifiche", systemImage: "bell.badge")
                }
                Toggle(isOn: gated($state.notifyDownloadsEnabled)) {
                    Label("Download completati", systemImage: "checkmark.circle")
                }
                .disabled(!state.notificationsEnabled)
                Toggle(isOn: gated($state.notifyNetworkEnabled)) {
                    Label("Disconnessioni eD2k / Kad", systemImage: "wifi.slash")
                }
                .disabled(!state.notificationsEnabled)
                Toggle(isOn: gated($state.backgroundChecksEnabled)) {
                    Label("Controlli anche da disconnesso", systemImage: "clock.arrow.circlepath")
                }
                .disabled(!state.notificationsEnabled)
                Picker(selection: $state.checkInterval) {
                    Text("1 minuto").tag(60)
                    Text("5 minuti").tag(300)
                    Text("15 minuti").tag(900)
                    Text("30 minuti").tag(1800)
                    Text("1 ora").tag(3600)
                } label: {
                    Label("Intervallo controlli", systemImage: "timer")
                }
                .disabled(!state.notificationsEnabled)
            } header: {
                Text("Notifiche")
            } footer: {
                Text("Attiva le notifiche per ricevere gli avvisi: alla prima attivazione l'app chiede il permesso e invia una notifica di prova. Dopo una disconnessione (timeout o server caduto) l'app continua a controllare il server all'intervallo scelto finché resta aperta, notificando download completati e cadute eD2k/Kad (queste ultime solo se sul server la riconnessione automatica è spenta).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AppInfoSection()
        }
        .formStyle(.grouped)
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
                PasswordField("Password:", text: $password)
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
