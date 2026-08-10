# aMule Remote

App nativa per macOS (SwiftUI) per controllare da remoto un server **amuled** — ad esempio il container aMule sul tuo Unraid — tramite il protocollo **EC (External Connections)**, lo stesso usato da aMuleGUI e amulecmd. Protocollo EC 0x0204, compatibile con aMule 2.3.x.

## Funzionalità

- **Trasferimenti**: coda download con avanzamento, velocità, fonti, stato; pausa / riprendi / ferma / elimina; priorità (bassa/normale/alta/auto); assegnazione categoria; aggiunta link ed2k://; rimozione completati; pannello upload attivi.
- **Ricerca**: locale / globale (server) / Kademlia, con filtri (tipo file, estensione, dimensione min/max, disponibilità). Doppio clic su un risultato per scaricarlo (anche in una categoria).
- **Server**: lista server con utenti/file/ping, connetti (doppio clic), disconnetti, aggiungi, rimuovi, aggiorna lista da URL server.met; controllo reti eD2k e Kad (avvia/ferma).
- **File condivisi**: elenco con richieste/upload, priorità di condivisione, ricarica cartelle condivise, copia link ed2k.
- **Statistiche**: velocità, limiti, utenti/file per rete, nodi Kad, totali sessione; spegnimento remoto del demone.
- **Log** del server in tempo reale.
- **Impostazioni aMule** (remote): limiti di banda, porte TCP/UDP, limiti connessioni, reti abilitate, gestione lista server, opzioni file (ICH, AICH, allocazione, spazio libero…), sicurezza (ipfilter, offuscamento, SecIdent), core tweaks, webserver. Lettura e scrittura direttamente su amuled.
- Password conservata nel **Portachiavi** macOS; riconnessione automatica opzionale all'avvio.

## Configurazione lato server (Unraid)

Nel file `amule.conf` del container (di solito in `/config/amule/` o simile):

```ini
[ExternalConnect]
AcceptExternalConnections=1
ECPort=4712
ECPassword=<MD5 della tua password>
```

L'hash MD5 si genera con: `echo -n "lamiapassword" | md5sum`.
Esponi/inoltra la porta **4712/TCP** del container. Riavvia il container dopo la modifica.

> Nota: il traffico EC non è cifrato. Per l'accesso da fuori casa usa una VPN (WireGuard/Tailscale) invece di esporre la 4712 su Internet.

## Compilazione

Richiede i Command Line Tools di Xcode (Swift 5.9+):

```bash
cd aMuleRemote
swift build -c release
```

Il bundle `aMule Remote.app` incluso è già pronto: trascinalo in `/Applicazioni` se vuoi.

Per ricostruire il bundle dopo una modifica:

```bash
swift build -c release
cp .build/release/AmuleRemote "aMule Remote.app/Contents/MacOS/aMule Remote"
codesign --force --deep --sign "aMule Remote Signing" "aMule Remote.app"
```

## Firma e distribuzione

L'app è firmata con il certificato locale **"aMule Remote Signing"** (autofirmato, nel
portachiavi login, valido 10 anni). La firma è stabile tra le ricompilazioni, quindi il
Portachiavi chiede l'autorizzazione una sola volta ("Consenti sempre"). Valida solo su
questo Mac.
Per distribuirla su altri Mac senza avvisi di Gatekeeper servono un account Apple Developer e la notarizzazione:

```bash
# con un certificato "Developer ID Application" installato:
codesign --force --deep --options runtime \
  --sign "Developer ID Application: TUO NOME (TEAMID)" "aMule Remote.app"
ditto -c -k --keepParent "aMule Remote.app" "aMuleRemote.zip"
xcrun notarytool submit aMuleRemote.zip --keychain-profile "AC_PROFILE" --wait
xcrun stapler staple "aMule Remote.app"
```

## Versione iOS

Il progetto include un'app iOS/iPadOS (`AmuleRemoteiOS.xcodeproj`, generato da `project.yml`
con XcodeGen) che riusa lo stesso motore EC del Mac. Interfaccia a tab: Trasferimenti
(swipe per pausa/riprendi/elimina), Ricerca a schede, Server (tap per connettere),
Condivisi, Statistiche/Log/Impostazioni.

Per compilarla serve **Xcode completo** (gratuito, App Store):
1. Installa Xcode e aprilo una volta (accetta la licenza, installa la piattaforma iOS)
2. Apri `AmuleRemoteiOS.xcodeproj`
3. In *Signing & Capabilities* seleziona il tuo Apple ID come Team (basta un account gratuito)
4. Collega l'iPhone, selezionalo come destinazione e premi Run

Con un Apple ID gratuito l'app sul telefono scade dopo **7 giorni** (basta rifare Run);
con un account Developer a pagamento dura 1 anno.

Dopo modifiche a `project.yml` rigenera il progetto con `xcodegen generate`.

## Verifica del protocollo

L'implementazione EC (handshake con salt MD5, framing, tag annidati, tutte le operazioni)
è stata testata end-to-end contro un amuled 2.3.3 reale: 17/17 test superati
(autenticazione, statistiche, server add/remove, link ed2k, coda download,
pausa/priorità/eliminazione, condivisi, ricerca, preferenze get/set, log, rifiuto password errata).
