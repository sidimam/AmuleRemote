import SwiftUI

struct iOSMoreView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        iOSStatsView()
                    } label: {
                        Label("Statistiche", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        iOSLogView()
                    } label: {
                        Label("Log del server", systemImage: "doc.text")
                    }
                    NavigationLink {
                        iOSPrefsView()
                    } label: {
                        Label("Impostazioni aMule", systemImage: "gearshape")
                    }
                }

                Section {
                    Picker("Disconnetti dopo inattività", selection: $state.idleTimeout) {
                        Text("Mai").tag(0)
                        Text("60 secondi").tag(60)
                        Text("120 secondi").tag(120)
                        Text("5 minuti").tag(300)
                        Text("10 minuti").tag(600)
                        Text("30 minuti").tag(1800)
                    }
                } header: {
                    Text("Impostazioni app")
                } footer: {
                    Text("Per risparmiare batteria e dati, l'app si disconnette dal server dopo il periodo di inattività scelto.")
                }

                Section("Connessione") {
                    LabeledContent("Server", value: "\(state.host):\(state.port)")
                    LabeledContent("Versione aMule", value: state.serverVersion.isEmpty ? "—" : state.serverVersion)
                    Button("Disconnetti", role: .destructive) {
                        Task { await state.disconnect() }
                    }
                }
            }
            .navigationTitle("Altro")
        }
    }
}

struct iOSStatsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        List {
            Section("Velocità") {
                LabeledContent("Download", value: formatSpeed(state.stats.dlSpeed))
                LabeledContent("Upload", value: formatSpeed(state.stats.ulSpeed))
                LabeledContent("Limite download", value: state.stats.dlSpeedLimit > 0 ? "\(state.stats.dlSpeedLimit) kB/s" : "Illimitato")
                LabeledContent("Limite upload", value: state.stats.ulSpeedLimit > 0 ? "\(state.stats.ulSpeedLimit) kB/s" : "Illimitato")
            }
            Section("Reti") {
                LabeledContent("eD2k", value: state.connState.ed2kLabel)
                LabeledContent("Utenti eD2k", value: "\(state.stats.ed2kUsers)")
                LabeledContent("File eD2k", value: "\(state.stats.ed2kFiles)")
                LabeledContent("Kad", value: state.connState.kadLabel)
                LabeledContent("Utenti Kad", value: "\(state.stats.kadUsers)")
                LabeledContent("Nodi Kad", value: "\(state.stats.kadNodes)")
            }
            Section("Trasferimenti") {
                LabeledContent("Fonti totali", value: "\(state.stats.totalSources)")
                LabeledContent("Coda upload", value: "\(state.stats.uploadQueueLength)")
                LabeledContent("File condivisi", value: "\(state.stats.sharedFileCount)")
                LabeledContent("Totale inviato", value: formatBytes(state.stats.totalSent))
                LabeledContent("Totale ricevuto", value: formatBytes(state.stats.totalReceived))
            }
        }
        .navigationTitle("Statistiche")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct iOSLogView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            Text(state.logText.isEmpty ? "Nessuna riga di log." : state.logText)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .textSelection(.enabled)
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .task { await state.refreshLog() }
        .refreshable { await state.refreshLog() }
    }
}

// MARK: - Preferences (full set, like macOS)

/// Right-aligned numeric field for settings rows.
struct PrefNumField: View {
    let label: String
    @Binding var value: UInt64

    var body: some View {
        LabeledContent(label) {
            TextField("", value: $value, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
        }
    }
}

struct iOSPrefsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.prefsLoaded {
                List {
                    Section {
                        NavigationLink("Generale e cartelle") { PrefsGeneraleForm() }
                        NavigationLink("Connessione") { PrefsConnessioneForm() }
                        NavigationLink("Server") { PrefsServerForm() }
                        NavigationLink("File") { PrefsFileForm() }
                        NavigationLink("Sicurezza") { PrefsSicurezzaForm() }
                        NavigationLink("Filtri messaggi e firma") { PrefsFiltriForm() }
                        NavigationLink("Avanzate (core tweaks)") { PrefsAvanzateForm() }
                        NavigationLink("Controllo remoto (web)") { PrefsRemoteForm() }
                    }
                    Section {
                        Button {
                            Task { await state.savePrefs() }
                        } label: {
                            HStack { Spacer(); Text("Applica al server").bold(); Spacer() }
                        }
                    } footer: {
                        Text("Le modifiche fatte nelle sezioni qui sopra vengono inviate ad amuled solo quando premi \"Applica al server\".")
                    }
                }
            } else {
                ProgressView("Caricamento impostazioni…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Impostazioni aMule")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !state.prefsLoaded { await state.loadPrefs() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await state.loadPrefs() }
                } label: { Image(systemName: "arrow.clockwise") }
            }
        }
    }
}

struct PrefsGeneraleForm: View {
    @EnvironmentObject var state: AppState
    @State private var newSharedDir = ""

    var body: some View {
        Form {
            Section("Identità") {
                TextField("Nickname", text: $state.prefs.nick)
            }
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download completati (Incoming)").font(.caption).foregroundStyle(.secondary)
                    TextField("/incoming", text: $state.prefs.dirIncoming)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("File temporanei (Temp)").font(.caption).foregroundStyle(.secondary)
                    TextField("/temp", text: $state.prefs.dirTemp)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            } header: {
                Text("Cartelle sul server")
            } footer: {
                Text("⚠️ Se cambi la cartella Temp con download attivi, sposta prima i file .part (a demone fermo).")
            }
            Section("Cartelle condivise aggiuntive") {
                ForEach(state.prefs.sharedDirs, id: \.self) { dir in
                    Text(dir).font(.callout.monospaced())
                }
                .onDelete { idx in
                    state.prefs.sharedDirs.remove(atOffsets: idx)
                }
                HStack {
                    TextField("Aggiungi percorso…", text: $newSharedDir)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        let d = newSharedDir.trimmingCharacters(in: .whitespaces)
                        if !d.isEmpty && !state.prefs.sharedDirs.contains(d) {
                            state.prefs.sharedDirs.append(d)
                        }
                        newSharedDir = ""
                    } label: { Image(systemName: "plus.circle.fill") }
                    .disabled(newSharedDir.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Toggle("Condividi file nascosti", isOn: $state.prefs.shareHidden)
                Toggle("Riscansione automatica", isOn: $state.prefs.autoRescanShared)
            }
        }
        .navigationTitle("Generale")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrefsConnessioneForm: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Limiti di banda (kB/s, 0 = illimitato)") {
                PrefNumField(label: "Limite download", value: $state.prefs.maxDL)
                PrefNumField(label: "Limite upload", value: $state.prefs.maxUL)
                PrefNumField(label: "Capacità linea down", value: $state.prefs.dlCap)
                PrefNumField(label: "Capacità linea up", value: $state.prefs.ulCap)
                PrefNumField(label: "Banda per slot", value: $state.prefs.slotAllocation)
            }
            Section("Porte") {
                PrefNumField(label: "Porta TCP", value: $state.prefs.tcpPort)
                PrefNumField(label: "Porta UDP", value: $state.prefs.udpPort)
                Toggle("Disabilita UDP", isOn: $state.prefs.udpDisabled)
            }
            Section("Limiti connessioni") {
                PrefNumField(label: "Connessioni massime", value: $state.prefs.maxConnections)
                PrefNumField(label: "Fonti max per file", value: $state.prefs.maxFileSources)
            }
            Section("Reti") {
                Toggle("Rete eD2k", isOn: $state.prefs.networkED2K)
                Toggle("Rete Kademlia", isOn: $state.prefs.networkKad)
                Toggle("Riconnetti automaticamente", isOn: $state.prefs.reconnect)
                Toggle("Connetti all'avvio", isOn: $state.prefs.autoconnect)
            }
        }
        .navigationTitle("Connessione")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrefsServerForm: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Gestione lista server") {
                Toggle("Rimuovi server morti", isOn: $state.prefs.removeDeadServers)
                PrefNumField(label: "Tentativi prima di rimuovere", value: $state.prefs.deadServerRetries)
                Toggle("Aggiorna lista all'avvio", isOn: $state.prefs.serversAutoUpdate)
                TextField("URL lista server", text: $state.prefs.serversUpdateURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Toggle("Aggiungi server dai server", isOn: $state.prefs.serversAddFromServer)
                Toggle("Aggiungi server dai client", isOn: $state.prefs.serversAddFromClient)
            }
            Section("Connessione ai server") {
                Toggle("Sistema di punteggio (score)", isOn: $state.prefs.useScoreSystem)
                Toggle("Controllo intelligente LowID", isOn: $state.prefs.smartIDCheck)
                Toggle("Connessione sicura ai server", isOn: $state.prefs.safeServerConnect)
                Toggle("Autoconnetti solo a statici", isOn: $state.prefs.autoconnStaticOnly)
                Toggle("Priorità alta manuali", isOn: $state.prefs.manualHighPrio)
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrefsFileForm: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Nuovi download") {
                Toggle("Metti in pausa i nuovi download", isOn: $state.prefs.newPaused)
                Toggle("Priorità download automatica", isOn: $state.prefs.newAutoDLPrio)
                Toggle("Priorità upload automatica", isOn: $state.prefs.newAutoULPrio)
                Toggle("Avvia il prossimo in pausa", isOn: $state.prefs.startNextPaused)
                Toggle("Riprendi prima stessa categoria", isOn: $state.prefs.resumeSameCat)
            }
            Section("Integrità e recupero") {
                Toggle("ICH (recupero corruzione)", isOn: $state.prefs.ichEnabled)
                Toggle("Fidati degli hash AICH", isOn: $state.prefs.aichTrust)
                Toggle("Salva fonti", isOn: $state.prefs.saveSources)
                Toggle("Estrai metadati", isOn: $state.prefs.extractMetadata)
            }
            Section("Spazio disco") {
                Toggle("Alloca dimensione completa", isOn: $state.prefs.allocFullSize)
                Toggle("Controlla spazio libero", isOn: $state.prefs.checkFreeSpace)
                PrefNumField(label: "Spazio libero min (MB)", value: $state.prefs.minFreeSpace)
            }
            Section("Upload") {
                Toggle("Carica chunk completi", isOn: $state.prefs.ulFullChunks)
                Toggle("Priorità alta anteprime", isOn: $state.prefs.previewPrio)
            }
        }
        .navigationTitle("File")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrefsSicurezzaForm: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Filtro IP") {
                Toggle("Filtra client", isOn: $state.prefs.ipfilterClients)
                Toggle("Filtra server", isOn: $state.prefs.ipfilterServers)
                Toggle("Aggiornamento automatico", isOn: $state.prefs.ipfilterAutoUpdate)
                TextField("URL ipfilter", text: $state.prefs.ipfilterUpdateURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                PrefNumField(label: "Livello filtro (0-255)", value: $state.prefs.ipfilterLevel)
                Toggle("Filtra anche LAN", isOn: $state.prefs.ipfilterFilterLAN)
            }
            Section("Identificazione e offuscamento") {
                Toggle("SecIdent", isOn: $state.prefs.useSecIdent)
                Toggle("Supporta offuscamento", isOn: $state.prefs.obfuscationSupported)
                Toggle("Richiedi offuscamento", isOn: $state.prefs.obfuscationRequested)
                Toggle("Esigi offuscamento", isOn: $state.prefs.obfuscationRequired)
            }
            Section("Condivisione") {
                Picker("Chi vede i file condivisi", selection: $state.prefs.canSeeShares) {
                    Text("Tutti").tag(UInt64(0))
                    Text("Solo amici").tag(UInt64(1))
                    Text("Nessuno").tag(UInt64(2))
                }
            }
        }
        .navigationTitle("Sicurezza")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrefsFiltriForm: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Filtro messaggi") {
                Toggle("Filtra i messaggi", isOn: $state.prefs.msgFilterEnabled)
                Toggle("Blocca tutti", isOn: $state.prefs.msgFilterAll)
                Toggle("Solo dagli amici", isOn: $state.prefs.msgFilterFriends)
                Toggle("Solo da client identificati", isOn: $state.prefs.msgFilterSecure)
                Toggle("Filtra per parole chiave", isOn: $state.prefs.msgFilterByKeyword)
                TextField("Parole chiave (virgola)", text: $state.prefs.msgFilterKeywords)
            }
            Section("Firma in linea") {
                Toggle("Abilita firma in linea", isOn: $state.prefs.onlineSigEnabled)
            }
            Section {
            } footer: {
                Text("Proxy, Interfaccia ed Eventi non sono esposti dal protocollo EC: si impostano solo in amule.conf sul server.")
            }
        }
        .navigationTitle("Filtri e firma")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrefsAvanzateForm: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Core tweaks") {
                PrefNumField(label: "Nuove conn. max / 5 s", value: $state.prefs.maxConnPerFive)
                PrefNumField(label: "Buffer file (byte)", value: $state.prefs.fileBufferSize)
                PrefNumField(label: "Dimensione coda upload", value: $state.prefs.uploadQueueSize)
                PrefNumField(label: "Keepalive server (s)", value: $state.prefs.serverKeepAliveTimeout)
            }
            Section("Kademlia") {
                TextField("URL nodes.dat", text: $state.prefs.kadUpdateURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("Avanzate")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrefsRemoteForm: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Web server (amuleweb)") {
                Toggle("Avvia automaticamente", isOn: $state.prefs.webserverAutorun)
                PrefNumField(label: "Porta web", value: $state.prefs.webserverPort)
                Toggle("Accesso ospite", isOn: $state.prefs.webserverGuest)
                Toggle("Compressione gzip", isOn: $state.prefs.webserverUseGzip)
                PrefNumField(label: "Refresh pagina (s)", value: $state.prefs.webserverRefresh)
            }
        }
        .navigationTitle("Controllo remoto")
        .navigationBarTitleDisplayMode(.inline)
    }
}
