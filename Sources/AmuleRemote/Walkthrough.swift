import SwiftUI
import Combine

/// Presentazione dell'app (walkthrough) mostrata al primo avvio e al primo
/// avvio dopo un aggiornamento che la rinnova, su iPhone/iPad, Mac, Apple
/// Vision Pro e Apple TV: le funzionalità in poche pagine, poi la proposta
/// di attivare/ripristinare la sincronizzazione iCloud e infine il consenso
/// alle notifiche (non su tvOS, che non le ha). «Salta» è sempre visibile;
/// si può rivedere da Informazioni app.
struct WalkthroughView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0
    @State private var backup: (count: Int, latest: Date?)? = nil
    @State private var backupChecked = false
    @State private var cloudDone = false
    @State private var searchRound = 0   // «Cerca di nuovo» riavvia il .task
    @State private var notificationsRequested = false
    #if os(tvOS)
    @FocusState private var focus: String?
    /// tvOS: il pulsante evidenziato ha il platter del colore di tinta → testo bianco.
    private func navInk(_ key: String) -> Color { focus == key ? .white : .primary }
    #endif

    private struct Page: Identifiable {
        let id: String
        let icon: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey
    }

    private var pages: [Page] {
        var p: [Page] = [
            Page(id: "welcome", icon: "network", title: "Benvenuto in aMule Remote",
                 text: "Il telecomando per il tuo server aMule (amuled) su NAS, Unraid, Raspberry Pi o PC di casa: l'app non scarica nulla sul dispositivo, controlla il server che già possiedi tramite il protocollo EC (External Connections)."),
            Page(id: "transfers", icon: "arrow.down.circle", title: "Trasferimenti e ricerca",
                 text: "Coda dei download con avanzamento, velocità, fonti e tempo stimato; pausa, riprendi, ferma, priorità, categorie ed eliminazione anche in selezione multipla. Ricerca locale e globale a schede, con i risultati già in coda in rosso e quelli già scaricati in verde."),
            Page(id: "profiles", icon: "server.rack", title: "Profili server e stato Offline",
                 text: "Salva più server con un nome e passa dall'uno all'altro in un tocco. Dopo un po' di inattività, o quando l'app va in background, la connessione si chiude per risparmiare batteria e dati: gli ultimi dati restano visibili e la connessione riparte da sola quando torni."),
            Page(id: "quick", icon: "bolt", title: quickTitle, text: quickText),
            Page(id: "demo", icon: "play.circle", title: "Provala senza server",
                 text: "Sulla schermata di connessione trovi «Prova la modalità demo»: l'app si riempie di dati di esempio (contenuti liberi) e ogni funzione è simulata in locale. Utile per esplorarla prima di configurare amuled."),
        ]
        if CloudSync.isAvailable {
            p.append(Page(id: "icloud", icon: "icloud", title: "Sincronizzazione iCloud", text: ""))
        }
        #if !os(tvOS)
        p.append(Page(id: "notifications", icon: "bell.badge", title: "Notifiche", text: ""))
        #endif
        return p
    }

    private var quickTitle: LocalizedStringKey {
        #if os(macOS)
        return "Menu, Dock e scorciatoie"
        #elseif os(tvOS)
        return "Telecomando Siri Remote"
        #else
        return "Azioni rapide e Siri"
        #endif
    }

    private var quickText: LocalizedStringKey {
        #if os(macOS)
        return "Nel menu Trasferimenti e nel menu del Dock trovi Aggiungi link (anche dagli Appunti), Metti in pausa tutti e Riprendi tutti, con le scorciatoie ⌘L, ⌥⌘P e ⌥⌘R. Le Impostazioni (⌘,) raccolgono aspetto, lingua, profili e sincronizzazione iCloud."
        #elseif os(tvOS)
        return "Ogni riga è un pulsante: selezionala per le azioni. Play/Pausa sul telecomando mette in pausa o riprende il download evidenziato. Con un iPhone vicino puoi digitare dalla notifica «Tastiera Apple TV» o dettare con Siri."
        #else
        return "Tieni premuta l'icona dell'app per aggiungere un link, mettere in pausa o riprendere tutti i download e cercare. Con Siri e Comandi rapidi controlli aMule anche ad app chiusa. I link ed2k:// toccati in Safari o Mail si aprono direttamente nell'app."
        #endif
    }

    private var isLast: Bool { page >= pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { state.finishWalkthrough() } label: {
                    #if os(tvOS)
                    Text("Salta").foregroundStyle(navInk("skip"))
                    #else
                    Text("Salta")
                    #endif
                }
                    #if os(tvOS)
                    .focused($focus, equals: "skip")
                    #else
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    #endif
                    .accessibilityLabel(Text("Salta la presentazione"))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer(minLength: 0)

            if pages.indices.contains(page) {
                pageView(pages[page])
                    .id(pages[page].id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }

            Spacer(minLength: 0)

            // Indicatore pagine
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { i in
                    Circle()
                        .fill(i == page ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.35)))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 16)

            HStack {
                if page > 0 {
                    Button {
                        withAnimation { page -= 1 }
                    } label: {
                        #if os(tvOS)
                        Label("Indietro", systemImage: "chevron.left").foregroundStyle(navInk("back"))
                        #else
                        Label("Indietro", systemImage: "chevron.left")
                        #endif
                    }
                    #if os(tvOS)
                    .focused($focus, equals: "back")
                    #else
                    .buttonStyle(.bordered)
                    #endif
                }
                Spacer()
                Button {
                    if isLast { state.finishWalkthrough() } else { withAnimation { page += 1 } }
                } label: {
                    #if os(tvOS)
                    Label(isLast ? "Inizia" : "Avanti", systemImage: isLast ? "checkmark" : "chevron.right")
                        .foregroundStyle(navInk("next"))
                    #else
                    if isLast {
                        Label("Inizia", systemImage: "checkmark")
                    } else {
                        Label("Avanti", systemImage: "chevron.right")
                    }
                    #endif
                }
                #if os(tvOS)
                .focused($focus, equals: "next")
                #else
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        #if os(macOS)
        .frame(width: 720, height: 560)
        #endif
        #if os(tvOS)
        // Su tvOS il fullScreenCover non ha uno sfondo opaco: senza questo la
        // presentazione si sovrappone alla schermata sottostante.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background((colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea())
        #endif
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 22) {
            Image(systemName: p.icon)
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text(p.title)
                .font(titleFont)
                .multilineTextAlignment(.center)
            switch p.id {
            case "icloud": cloudBody
            case "notifications": notificationsBody
            default:
                Text(p.text)
                    .font(bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: maxTextWidth)
    }

    // MARK: - iCloud: cerca il backup e propone ripristino o attivazione

    private var cloudBody: some View {
        VStack(spacing: 16) {
            if state.iCloudSyncEnabled || cloudDone {
                Label("Sincronizzazione attiva: i profili server e le password ti seguono su iPhone, iPad, Mac, Apple Vision Pro e Apple TV.", systemImage: "checkmark.circle.fill")
                    .font(bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if !backupChecked {
                ProgressView("Cerco un backup su iCloud…")
                    .font(bodyFont)
                Text("Al primo avvio iCloud può impiegare qualche secondo a consegnare i dati.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let b = backup {
                Text(b.latest != nil
                     ? "Trovato un backup con \(b.count) profili server (ultimo aggiornamento \(b.latest!.formatted(date: .abbreviated, time: .shortened))). Vuoi ripristinarlo su questo dispositivo?"
                     : "Trovato un backup con \(b.count) profili server. Vuoi ripristinarlo su questo dispositivo?")
                    .font(bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    state.restoreProfilesFromCloud()
                    cloudDone = true
                } label: {
                    #if os(tvOS)
                    Label("Ripristina da iCloud", systemImage: "icloud.and.arrow.down").foregroundStyle(navInk("restore"))
                    #else
                    Label("Ripristina da iCloud", systemImage: "icloud.and.arrow.down")
                    #endif
                }
                #if os(tvOS)
                .focused($focus, equals: "restore")
                #else
                .buttonStyle(.borderedProminent)
                #endif
                Text("Il backup è unico per tutti i tuoi dispositivi. Puoi comunque attivare la sincronizzazione più tardi dalle impostazioni dell'app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Nessun backup su iCloud. Attivando la sincronizzazione, i profili server e le loro password (Portachiavi iCloud) saranno condivisi tra tutti i tuoi dispositivi tramite il tuo account iCloud: nessun dato passa da terzi.")
                    .font(bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    state.setCloudSync(true)
                    cloudDone = true
                } label: {
                    #if os(tvOS)
                    Label("Attiva la sincronizzazione iCloud", systemImage: "icloud").foregroundStyle(navInk("enable"))
                    #else
                    Label("Attiva la sincronizzazione iCloud", systemImage: "icloud")
                    #endif
                }
                #if os(tvOS)
                .focused($focus, equals: "enable")
                #else
                .buttonStyle(.borderedProminent)
                #endif
                Button {
                    backupChecked = false
                    searchRound += 1
                } label: {
                    #if os(tvOS)
                    Label("Cerca di nuovo", systemImage: "arrow.clockwise").foregroundStyle(navInk("retry"))
                    #else
                    Label("Cerca di nuovo", systemImage: "arrow.clockwise")
                    #endif
                }
                #if os(tvOS)
                .focused($focus, equals: "retry")
                #else
                .buttonStyle(.bordered)
                #endif
                Text("Se su un altro dispositivo la sincronizzazione è già attiva, controlla che questo usi lo stesso account iCloud e cerca di nuovo. Puoi attivarla anche più tardi dalle impostazioni dell'app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        // Il KVS al primo avvio (o dopo una reinstallazione) arriva in modo
        // asincrono: si riprova per circa 30 s e la notifica di cambiamento
        // accorcia l'attesa. «Cerca di nuovo» riavvia la ricerca.
        .task(id: searchRound) {
            guard !backupChecked else { return }
            for attempt in 0..<15 {
                if let b = state.cloudBackupSummary() { backup = b; break }
                if attempt < 14 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            }
            backupChecked = true
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudSync.changeNotification)) { _ in
            if backup == nil, let b = state.cloudBackupSummary() { backup = b; backupChecked = true }
        }
        .onChange(of: state.cloudProfilesAvailable) { _, n in
            if n > 0, backup == nil, let b = state.cloudBackupSummary() { backup = b; backupChecked = true }
        }
    }

    // MARK: - Notifiche: consenso di sistema

    private var notificationsBody: some View {
        VStack(spacing: 16) {
            Text("aMule Remote ti avvisa quando un download parte o finisce, quando il server aMule non risponde e quando le reti eD2k e Kad cadono o si riconnettono. Nessun filtro da configurare nell'app: quanto e come riceverle lo decidi nelle Impostazioni di sistema.")
                .font(bodyFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            #if os(macOS)
            Text("Sul Mac le trovi in Impostazioni di Sistema → Notifiche → aMule Remote.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            #else
            Text("Su iPhone e iPad puoi sceglierle subito o nel Riepilogo programmato: lo decidi nella finestra di iOS e, in ogni momento, in Impostazioni → aMule Remote → Notifiche.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            #endif
            switch state.notificationStatus {
            case .authorized, .provisional:
                Label("Notifiche attive", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Text("Le notifiche sono disattivate nelle Impostazioni di sistema.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button {
                    SystemSettings.openNotificationSettings()
                } label: {
                    Label("Apri le Impostazioni", systemImage: "gear")
                }
                #if !os(tvOS)
                .buttonStyle(.bordered)
                #endif
            default:
                Button {
                    notificationsRequested = true
                    Task { _ = await state.requestNotificationConsent() }
                } label: {
                    Label("Consenti le notifiche", systemImage: "bell.badge")
                }
                #if !os(tvOS)
                .buttonStyle(.borderedProminent)
                #endif
                .disabled(notificationsRequested)
                Text("Puoi decidere anche più tardi dalla riga «Notifiche» nelle impostazioni dell'app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await state.refreshNotificationStatus() }
    }

    // MARK: - Metriche per piattaforma

    private var iconSize: CGFloat {
        #if os(tvOS)
        return 120
        #else
        return 64
        #endif
    }
    private var titleFont: Font {
        #if os(tvOS)
        return .largeTitle.bold()
        #else
        return .title.bold()
        #endif
    }
    private var bodyFont: Font {
        #if os(tvOS)
        return .title3
        #else
        return .body
        #endif
    }
    private var maxTextWidth: CGFloat {
        #if os(tvOS)
        return 1300
        #else
        return 560
        #endif
    }
}
