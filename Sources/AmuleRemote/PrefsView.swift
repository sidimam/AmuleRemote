import SwiftUI

struct PrefsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.prefsLoaded {
                TabView {
                    generalTab.tabItem { Label("Generale", systemImage: "person") }
                    connectionTab.tabItem { Label("Connessione", systemImage: "network") }
                    serversTab.tabItem { Label("Server", systemImage: "server.rack") }
                    filesTab.tabItem { Label("File", systemImage: "doc") }
                    securityTab.tabItem { Label("Sicurezza", systemImage: "lock.shield") }
                    filtersTab.tabItem { Label("Filtri", systemImage: "bubble.left.and.exclamationmark.bubble.right") }
                    tweaksTab.tabItem { Label("Avanzate", systemImage: "wrench.and.screwdriver") }
                    remoteTab.tabItem { Label("Controllo remoto", systemImage: "antenna.radiowaves.left.and.right") }
                }
                .padding(12)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Caricamento impostazioni dal server…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Impostazioni aMule (remoto)")
        .task { if !state.prefsLoaded { await state.loadPrefs() } }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await state.loadPrefs() }
                } label: {
                    Label("Ricarica dal server", systemImage: "arrow.clockwise")
                }
                Button {
                    Task { await state.savePrefs() }
                } label: {
                    Label("Applica al server", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.prefsLoaded)
            }
        }
    }

    // MARK: tabs

    @State private var newSharedDir = ""

    private var generalTab: some View {
        Form {
            SwiftUI.Section("Identità") {
                TextField("Nickname:", text: $state.prefs.nick)
            }
            SwiftUI.Section("Cartelle sul server") {
                TextField("Download completati (Incoming):", text: $state.prefs.dirIncoming)
                    .font(.body.monospaced())
                TextField("File temporanei (Temp):", text: $state.prefs.dirTemp)
                    .font(.body.monospaced())
                Text("I percorsi sono quelli visti dal server (nel container Docker). ⚠️ Se cambi la cartella temporanei con download attivi: ferma il container, sposta i file .part nella nuova cartella e poi riavvia, altrimenti i download spariranno dalla coda.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SwiftUI.Section("Cartelle condivise aggiuntive") {
                if state.prefs.sharedDirs.isEmpty {
                    Text("Nessuna cartella condivisa aggiuntiva (la cartella Incoming è sempre condivisa)")
                        .foregroundStyle(.secondary)
                }
                ForEach(state.prefs.sharedDirs, id: \.self) { dir in
                    HStack {
                        Text(dir).font(.body.monospaced())
                        Spacer()
                        Button {
                            state.prefs.sharedDirs.removeAll { $0 == dir }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Aggiungi cartella (percorso nel server):", text: $newSharedDir)
                        .font(.body.monospaced())
                    Button {
                        let d = newSharedDir.trimmingCharacters(in: .whitespaces)
                        if !d.isEmpty && !state.prefs.sharedDirs.contains(d) {
                            state.prefs.sharedDirs.append(d)
                        }
                        newSharedDir = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newSharedDir.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Toggle("Condividi file nascosti", isOn: $state.prefs.shareHidden)
                Toggle("Riscansione automatica delle cartelle condivise", isOn: $state.prefs.autoRescanShared)
                Text("Dopo le modifiche premi \"Applica al server\" nella barra in alto, poi \"Ricarica condivisioni\" nella sezione Condivisi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SwiftUI.Section("Categorie") {
                if state.prefs.categories.isEmpty {
                    Text("Nessuna categoria definita").foregroundStyle(.secondary)
                } else {
                    ForEach(state.prefs.categories) { cat in
                        LabeledContent(cat.title, value: cat.path)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var connectionTab: some View {
        Form {
            SwiftUI.Section("Limiti di banda (kB/s, 0 = illimitato)") {
                TextField("Limite download:", value: $state.prefs.maxDL, format: .number)
                TextField("Limite upload:", value: $state.prefs.maxUL, format: .number)
                TextField("Capacità linea download:", value: $state.prefs.dlCap, format: .number)
                TextField("Capacità linea upload:", value: $state.prefs.ulCap, format: .number)
                TextField("Banda per slot (kB/s):", value: $state.prefs.slotAllocation, format: .number)
            }
            SwiftUI.Section("Porte") {
                TextField("Porta TCP:", value: $state.prefs.tcpPort, format: .number.grouping(.never))
                TextField("Porta UDP:", value: $state.prefs.udpPort, format: .number.grouping(.never))
                Toggle("Disabilita UDP", isOn: $state.prefs.udpDisabled)
            }
            SwiftUI.Section("Limiti connessioni") {
                TextField("Connessioni massime:", value: $state.prefs.maxConnections, format: .number)
                TextField("Fonti massime per file:", value: $state.prefs.maxFileSources, format: .number)
            }
            SwiftUI.Section("Reti") {
                Toggle("Rete eD2k", isOn: $state.prefs.networkED2K)
                Toggle("Rete Kademlia", isOn: $state.prefs.networkKad)
                Toggle("Riconnetti automaticamente", isOn: $state.prefs.reconnect)
                Toggle("Connetti all'avvio", isOn: $state.prefs.autoconnect)
            }
        }
        .formStyle(.grouped)
    }

    private var serversTab: some View {
        Form {
            SwiftUI.Section("Gestione lista server") {
                Toggle("Rimuovi server morti", isOn: $state.prefs.removeDeadServers)
                TextField("Tentativi prima di rimuovere:", value: $state.prefs.deadServerRetries, format: .number)
                Toggle("Aggiorna lista server all'avvio", isOn: $state.prefs.serversAutoUpdate)
                TextField("URL lista server:", text: $state.prefs.serversUpdateURL)
                Toggle("Aggiungi server ricevuti dai server", isOn: $state.prefs.serversAddFromServer)
                Toggle("Aggiungi server ricevuti dai client", isOn: $state.prefs.serversAddFromClient)
            }
            SwiftUI.Section("Connessione ai server") {
                Toggle("Usa sistema di punteggio (score)", isOn: $state.prefs.useScoreSystem)
                Toggle("Controllo intelligente LowID", isOn: $state.prefs.smartIDCheck)
                Toggle("Connessione sicura ai server", isOn: $state.prefs.safeServerConnect)
                Toggle("Autoconnetti solo a server statici", isOn: $state.prefs.autoconnStaticOnly)
                Toggle("Priorità alta per connessioni manuali", isOn: $state.prefs.manualHighPrio)
            }
        }
        .formStyle(.grouped)
    }

    private var filesTab: some View {
        Form {
            SwiftUI.Section("Nuovi download") {
                Toggle("Metti in pausa i nuovi download", isOn: $state.prefs.newPaused)
                Toggle("Priorità download automatica", isOn: $state.prefs.newAutoDLPrio)
                Toggle("Priorità upload automatica", isOn: $state.prefs.newAutoULPrio)
                Toggle("Avvia il prossimo file in pausa al completamento", isOn: $state.prefs.startNextPaused)
                Toggle("Riprendi prima nella stessa categoria", isOn: $state.prefs.resumeSameCat)
            }
            SwiftUI.Section("Integrità e recupero") {
                Toggle("ICH (Intelligent Corruption Handling)", isOn: $state.prefs.ichEnabled)
                Toggle("Fidati degli hash AICH", isOn: $state.prefs.aichTrust)
                Toggle("Salva fonti (sources seeds)", isOn: $state.prefs.saveSources)
                Toggle("Estrai metadati", isOn: $state.prefs.extractMetadata)
            }
            SwiftUI.Section("Spazio disco") {
                Toggle("Alloca subito la dimensione completa", isOn: $state.prefs.allocFullSize)
                Toggle("Controlla spazio libero", isOn: $state.prefs.checkFreeSpace)
                TextField("Spazio libero minimo (MB):", value: $state.prefs.minFreeSpace, format: .number)
            }
            SwiftUI.Section("Upload") {
                Toggle("Carica chunk completi", isOn: $state.prefs.ulFullChunks)
                Toggle("Priorità alta per anteprime", isOn: $state.prefs.previewPrio)
            }
        }
        .formStyle(.grouped)
    }

    private var securityTab: some View {
        Form {
            SwiftUI.Section("Filtro IP") {
                Toggle("Filtra client", isOn: $state.prefs.ipfilterClients)
                Toggle("Filtra server", isOn: $state.prefs.ipfilterServers)
                Toggle("Aggiornamento automatico ipfilter", isOn: $state.prefs.ipfilterAutoUpdate)
                TextField("URL ipfilter:", text: $state.prefs.ipfilterUpdateURL)
                TextField("Livello filtro (0-255):", value: $state.prefs.ipfilterLevel, format: .number)
                Toggle("Filtra anche indirizzi LAN", isOn: $state.prefs.ipfilterFilterLAN)
            }
            SwiftUI.Section("Identificazione e offuscamento") {
                Toggle("Identificazione sicura (SecIdent)", isOn: $state.prefs.useSecIdent)
                Toggle("Supporta offuscamento protocollo", isOn: $state.prefs.obfuscationSupported)
                Toggle("Richiedi offuscamento", isOn: $state.prefs.obfuscationRequested)
                Toggle("Esigi offuscamento (solo connessioni offuscate)", isOn: $state.prefs.obfuscationRequired)
            }
            SwiftUI.Section("Condivisione") {
                Picker("Chi può vedere i file condivisi:", selection: $state.prefs.canSeeShares) {
                    Text("Tutti").tag(UInt64(0))
                    Text("Solo amici").tag(UInt64(1))
                    Text("Nessuno").tag(UInt64(2))
                }
            }
        }
        .formStyle(.grouped)
    }

    private var tweaksTab: some View {
        Form {
            SwiftUI.Section {
                TextField("Nuove connessioni max ogni 5 secondi:", value: $state.prefs.maxConnPerFive, format: .number)
                TextField("Buffer file (KB):", value: $state.prefs.fileBufferSize, format: .number)
                TextField("Dimensione coda upload:", value: $state.prefs.uploadQueueSize, format: .number)
                TextField("Keepalive server (secondi):", value: $state.prefs.serverKeepAliveTimeout, format: .number)
            } header: {
                Text("Parametri avanzati (core)")
            } footer: {
                Text("Corrispondono a MaxConnectionsPerFiveSeconds, FileBufferSizePref, QueueSizePref e ServerKeepAliveTimeout in amule.conf. Modificali solo se sai cosa fai.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SwiftUI.Section("Kademlia") {
                TextField("URL aggiornamento nodes.dat:", text: $state.prefs.kadUpdateURL)
            }
        }
        .formStyle(.grouped)
    }

    private var filtersTab: some View {
        Form {
            SwiftUI.Section("Filtro messaggi") {
                Toggle("Filtra i messaggi in arrivo", isOn: $state.prefs.msgFilterEnabled)
                Toggle("Blocca tutti i messaggi", isOn: $state.prefs.msgFilterAll)
                Toggle("Accetta solo dagli amici", isOn: $state.prefs.msgFilterFriends)
                Toggle("Solo da client identificati (SecIdent)", isOn: $state.prefs.msgFilterSecure)
                Toggle("Filtra per parole chiave", isOn: $state.prefs.msgFilterByKeyword)
                TextField("Parole chiave (separate da virgola):", text: $state.prefs.msgFilterKeywords)
            }
            SwiftUI.Section("Firma in linea") {
                Toggle("Abilita firma in linea (online signature)", isOn: $state.prefs.onlineSigEnabled)
            }
            SwiftUI.Section {
                Text("Proxy, Interfaccia ed Eventi non sono esposti dal protocollo EC di aMule: non sono configurabili da remoto (nemmeno da aMuleGUI) — vanno impostati nel file amule.conf sul server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var remoteTab: some View {
        Form {
            SwiftUI.Section("Web server (amuleweb)") {
                Toggle("Avvia webserver automaticamente", isOn: $state.prefs.webserverAutorun)
                TextField("Porta web:", value: $state.prefs.webserverPort, format: .number.grouping(.never))
                Toggle("Consenti accesso ospite", isOn: $state.prefs.webserverGuest)
                Toggle("Usa compressione gzip", isOn: $state.prefs.webserverUseGzip)
                TextField("Refresh pagina (secondi):", value: $state.prefs.webserverRefresh, format: .number)
            }
        }
        .formStyle(.grouped)
    }
}
