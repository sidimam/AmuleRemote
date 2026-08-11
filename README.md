# aMule Remote

App native per **macOS, iOS e iPadOS** (SwiftUI) per controllare da remoto un server **amuled** — ad esempio il container aMule sul tuo Unraid, un NAS o un Raspberry Pi — tramite il protocollo **EC (External Connections)**, lo stesso usato da aMuleGUI e amulecmd. Protocollo EC 0x0204, compatibile con aMule 2.3.x.

> 📖 Guide dettagliate nel **[Wiki](https://github.com/sidimam/AmuleRemoteiOS/wiki)** · 🔒 [Privacy policy](https://sidimam.github.io/AmuleRemoteiOS/)

## Download

- **macOS**: scarica `aMuleRemote-macOS.zip` dalla pagina **[Releases](https://github.com/sidimam/AmuleRemoteiOS/releases)**, decomprimi e trascina l'app in `/Applicazioni`. L'app è firmata localmente: al primo avvio fai **clic destro → Apri** (vedi *Firma e distribuzione*).
- **iOS / iPadOS**: si compila con Xcode (vedi *Versione iOS*) oppure via TestFlight.

## Funzionalità

- **Trasferimenti**: coda download con avanzamento, velocità, fonti, tempo stimato e stato; pausa / riprendi / ferma / elimina; priorità (bassa/normale/alta/auto); assegnazione categoria; aggiunta link ed2k://; rimozione completati; selezione multipla; pannello upload attivi.
- **Ricerca**: **locale** e **globale (server)**, a schede (più ricerche contemporanee), con filtri (tipo file, estensione, dimensione min/max, disponibilità) e timeout automatico di 120 s. Doppio clic / tocco su un risultato per scaricarlo.
- **Server**: lista server con utenti/file/ping, connetti (doppio clic), disconnetti, aggiungi, rimuovi, aggiorna lista da URL server.met; controllo reti **eD2k** e **Kad** (avvia/ferma).
- **File condivisi** *(macOS)*: elenco con richieste/upload, priorità di condivisione, ricarica cartelle condivise, copia link ed2k.
- **Statistiche** e **Log** del server in tempo reale.
- **Impostazioni aMule** (remote), lettura e scrittura diretta su amuled:
  - **macOS**: set completo — Generale, Connessione, Server, File, Sicurezza, Filtri messaggi, Avanzate (core tweaks + Kademlia), Controllo remoto (webserver).
  - **iOS / iPadOS**: le voci più utili di `amule.conf` — Generale e cartelle, Connessione, Server, File, Sicurezza, Avanzate.
- **Notifiche** al completamento dei download (su iOS anche su Apple Watch).
- Password conservata nel **Portachiavi**; disconnessione automatica dopo inattività (iOS) e riconnessione automatica opzionale.

## Configurazione lato server (Unraid / Docker)

Nel file `amule.conf` del container (di solito in `/config/amule/` o simile):

```ini
[ExternalConnect]
AcceptExternalConnections=1
ECPort=4712
ECPassword=<MD5 della tua password>
```

L'hash MD5 si genera con: `echo -n "lamiapassword" | md5sum`.
Esponi/inoltra la porta **4712/TCP** del container. Riavvia il container dopo la modifica.
Guida completa: **[Wiki → Configurazione del server](https://github.com/sidimam/AmuleRemoteiOS/wiki/Configurazione-del-server)**.

> ⚠️ Il traffico EC non è cifrato. Per l'accesso da fuori casa usa una VPN (WireGuard/Tailscale) invece di esporre la 4712 su Internet.

## Compilazione

### macOS

Richiede i Command Line Tools di Xcode (Swift 5.9+):

```bash
cd aMuleRemote
swift build -c release
cp .build/release/AmuleRemote "aMule Remote.app/Contents/MacOS/aMule Remote"
codesign --force --deep --sign "aMule Remote Signing" "aMule Remote.app"
```

### iOS / iPadOS

Il progetto Xcode è generato da `project.yml` con [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
```

Vedi la sezione *Versione iOS* e il **[Wiki → Compilazione e firma](https://github.com/sidimam/AmuleRemoteiOS/wiki/Compilazione-e-firma)**.

## Firma e distribuzione

L'app macOS è firmata con un certificato locale **"aMule Remote Signing"** (autofirmato, valido 10 anni), valido solo sul Mac su cui è stato creato. Su altri Mac, al primo avvio, fai **clic destro sull'app → Apri → Apri** per superare Gatekeeper.

Per una distribuzione senza avvisi servono un account Apple Developer e la notarizzazione:

```bash
# con un certificato "Developer ID Application" installato:
codesign --force --deep --options runtime \
  --sign "Developer ID Application: TUO NOME (TEAMID)" "aMule Remote.app"
ditto -c -k --keepParent "aMule Remote.app" "aMuleRemote.zip"
xcrun notarytool submit aMuleRemote.zip --keychain-profile "AC_PROFILE" --wait
xcrun stapler staple "aMule Remote.app"
```

## Versione iOS

L'app iOS/iPadOS (`AmuleRemoteiOS.xcodeproj`) riusa lo stesso motore EC del Mac. Interfaccia a tab: Trasferimenti (swipe per pausa/riprendi/elimina, selezione multipla), Ricerca a schede, Server (tocco per connettere), e **Altro** (Statistiche, Log, Impostazioni aMule).

Per compilarla serve **Xcode completo** (gratuito, App Store):
1. Installa Xcode e aprilo una volta (accetta la licenza, installa la piattaforma iOS)
2. Apri `AmuleRemoteiOS.xcodeproj`
3. In *Signing & Capabilities* seleziona il tuo Apple ID come Team
4. Collega l'iPhone/iPad, selezionalo come destinazione e premi Run

Con un Apple ID gratuito l'app sul dispositivo scade dopo **7 giorni**; con un account Developer a pagamento dura 1 anno (e puoi usare TestFlight). Guida: **[Wiki → Installazione su iPhone/iPad](https://github.com/sidimam/AmuleRemoteiOS/wiki/Installazione-su-iPhone-e-iPad)**.

## Versioning

La *marketing version* resta **1.0**; cambia solo il numero di **build** progressivo (versione corrente: **build 9**), mantenuto allineato tra macOS e iOS.

## Verifica del protocollo

L'implementazione EC (handshake con salt MD5, framing, tag annidati, tutte le operazioni)
è stata testata end-to-end contro un amuled 2.3.x reale: autenticazione, statistiche,
server add/remove, link ed2k, coda download, pausa/priorità/eliminazione, condivisi,
ricerca, preferenze get/set, log, rifiuto password errata. Dettagli nel
**[Wiki → Protocollo EC](https://github.com/sidimam/AmuleRemoteiOS/wiki/Protocollo-EC)**.
