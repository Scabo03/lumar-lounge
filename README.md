# Lumar Lounge

App iOS / iPadOS di giochi di carte e da casinò, scritta in Swift e SwiftUI.

> Stato attuale: **impalcatura** (scaffolding). Nessuna logica di gioco è
> ancora implementata. Questo documento raccoglie i parametri operativi del
> progetto e va aggiornato man mano che il lavoro procede.

## Parametri operativi

| Parametro | Valore |
|---|---|
| Nome progetto | **Lumar Lounge** |
| Bundle identifier | `com.scabo.lumarlounge` |
| Repo progetto | https://github.com/Scabo03/lumar-lounge.git |
| Repo certificati Match | https://github.com/Scabo03/lumar-lounge-certs.git |
| Scheme Xcode | `LumarLounge` (condiviso) |
| Percorso project | `LumarLounge.xcodeproj` (alla radice del repo) |
| Linguaggi | Swift + SwiftUI |
| Deployment target | iOS 17.0 |
| Device family | iPhone + iPad (`1,2`) |
| Lingue supportate | **Italiano** (principale), **Inglese** (seconda) |

## Lingue e localizzazione

La lingua di sviluppo è l'**italiano** (`CFBundleDevelopmentRegion = it`);
l'inglese è la seconda lingua. Tutte le stringhe visibili all'utente passano
dai file di localizzazione in `Resources/` — **nessuna stringa utente è scritta
inline nel codice**.

- `Resources/it.lproj/Localizable.strings` — testi UI (italiano)
- `Resources/en.lproj/Localizable.strings` — testi UI (inglese)
- `Resources/it.lproj/InfoPlist.strings` / `en.lproj/InfoPlist.strings` — nome
  app e metadati localizzati del bundle

## Struttura delle cartelle

Il codice è organizzato in quattro moduli Swift separati (target del package
locale `LumarKit`, definito in `Package.swift`) più una cartella risorse. La
separazione in moduli rende la **direzione delle dipendenze verificata dal
compilatore**: importare un modulo che non è una dipendenza dichiarata non
compila.

```
lumar-lounge/
├── Package.swift              # definisce i 4 moduli e il grafo delle dipendenze
├── GameEngine/                # regole pure dei giochi (solo Foundation, portabile)
├── GameWorld/                 # giocatore, fiches, NPC, progressione (usa GameEngine)
├── Audio/                     # suono + aptica, generico e trasversale
├── UI/                        # tutte le viste SwiftUI (usa GameWorld, GameEngine, Audio)
├── Resources/                 # file di localizzazione it / en
├── App/                       # shell dell'app: @main, Info.plist, Assets.xcassets
└── LumarLounge.xcodeproj/     # progetto Xcode (target app `LumarLounge`)
```

### Direzione delle dipendenze (regola architetturale rigida)

```
            ┌─────────────┐
            │     UI      │  (SwiftUI)
            └──────┬──────┘
        ┌──────────┼───────────┐
        ▼          ▼           ▼
  ┌──────────┐ ┌───────┐  ┌─────────┐
  │ GameWorld│ │ Audio │  │GameEngine│
  └────┬─────┘ └───────┘  └─────────┘
       │                       ▲
       └───────────────────────┘
```

- **GameEngine** — non importa nessuno degli altri moduli. Solo `Foundation`.
  Niente SwiftUI / UIKit / AVFoundation / CoreHaptics. Autonomo e portabile.
- **GameWorld** — può importare `GameEngine`. Mai UI né Audio.
- **Audio** — trasversale e generico: non conosce poker, blackjack o alcun
  gioco specifico. Espone un'interfaccia (`AudioServicing`) guidata da
  identificatori opachi.
- **UI** — può importare `GameWorld`, `GameEngine`, `Audio`. Contiene tutte le
  viste; ogni vista imposta già accessibility identifier e label.
- **App** — shell minima che presenta `RootView` dal modulo UI.

## Ambiente di sviluppo

Lo sviluppo, la build, il signing e l'upload TestFlight avvengono su un
**MacBook Pro 14" (Apple Silicon M5 Pro, 24 GB RAM)** personale: ambiente
stabile, persistente e con pieni privilegi. `xcode-select` e `DEVELOPER_DIR` si
usano normalmente.

> **Nota storica.** Fino al commit iniziale il progetto è stato sviluppato su
> MacInCloud Pay-as-you-go, dove ogni sessione partiva da una macchina diversa,
> senza `sudo`, senza persistenza affidabile, e con accorgimenti specifici
> (path completo a `xcodebuild`, niente modifica di `xcode-select`, variabili
> d'ambiente da reimpostare ad ogni login, rituale Simulator per il logout
> pulito). **Quei vincoli non si applicano più** e sono stati rimossi da questa
> documentazione: restano qui solo come contesto.

Per fissare la versione di Xcode (una tantum):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# in alternativa, per sessione:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Build

La build di archiviazione resta basata su `xcodebuild` diretto, **senza
`-destination`** e con la piattaforma device forzata (`SUPPORTED_PLATFORMS=iphoneos`,
`SUPPORTS_MACCATALYST=NO`): è la pipeline collaudata, ed è esattamente quella
incapsulata nella lane `testflight_upload` (vedi sotto). Su un Mac proprio
`xcodebuild` si invoca direttamente, senza path assoluto.

Build di verifica (compilazione, slice device):

```bash
xcodebuild \
  -project LumarLounge.xcodeproj \
  -scheme LumarLounge \
  -configuration Debug \
  SUPPORTED_PLATFORMS=iphoneos \
  SUPPORTS_MACCATALYST=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

Build + esecuzione nel simulatore (verifica runtime):

```bash
xcodebuild \
  -project LumarLounge.xcodeproj -scheme LumarLounge -configuration Debug \
  -sdk iphonesimulator26.5 SUPPORTS_MACCATALYST=NO CODE_SIGNING_ALLOWED=NO build

xcrun simctl install <SIMULATOR_UDID> <path-to>/LumarLounge.app
xcrun simctl launch  <SIMULATOR_UDID> com.scabo.lumarlounge
```

## Icona app

Set di icone placeholder (quadrato bordeaux scuro `#5E1020`, tema casinò) in
`App/Assets.xcassets/AppIcon.appiconset/`. Tutti i PNG sono **RGB senza canale
alfa** (requisito TestFlight) nelle dimensioni richieste da Apple: 1024, 180,
167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20. `CFBundleIconName` è impostato a
`AppIcon` nell'`Info.plist`.

## Build & Upload

Il signing è gestito con **Fastlane Match** (storage `git`, repo certificati
privato `lumar-lounge-certs`). Tutta l'infrastruttura vive in `fastlane/` e si
guida con due lane: `setup_signing` e `testflight_upload`.

Setup una tantum della toolchain (installa fastlane dal `Gemfile`):

```bash
bundle install
```

### Credenziali

I segreti **non** stanno nel repo. Su questa macchina vivono già in un file env
condiviso tra i progetti iOS:

```
~/Developer/private_keys/scabo_deploy.env      # MATCH_PASSWORD, key id/issuer, ecc.
~/Developer/private_keys/AuthKey_MGW9GC97HV.p8 # App Store Connect API key (.p8)
```

Il flusso è: **sourcare** quel file e lanciare la lane. L'identità del progetto
(`APP_IDENTIFIER` = `com.scabo.lumarlounge`, repo certificati = `lumar-lounge-certs`)
è **fissata nel codice Fastlane** (`Appfile`/`Matchfile`/`Fastfile`): così, anche
se il file condiviso porta i valori di un altro progetto, Match colpisce sempre
l'app e il repo giusti.

> Il certificato di distribuzione è **condiviso** con l'altro progetto
> (`Apple Distribution: Luca Scabini`, id `JJ47RUK3DJ`): l'account aveva già
> raggiunto il numero massimo di certificati di distribuzione, quindi invece di
> crearne uno nuovo è stato riusato. Lumar Lounge ha comunque il **suo**
> provisioning profile App Store (`match AppStore com.scabo.lumarlounge`).

### Riallineare i certificati su una macchina nuova

Recupera dal repo `lumar-lounge-certs` il certificato di distribuzione e il
provisioning profile App Store, decifrandoli con `MATCH_PASSWORD` e
installandoli nel keychain:

```bash
source ~/Developer/private_keys/scabo_deploy.env
bundle exec fastlane setup_signing
```

Da quel momento qualsiasi macchina con le credenziali corrette ottiene i
certificati con questo solo comando.

### Upload su TestFlight

Build → archive → export → upload, in un colpo solo (la lane usa `xcodebuild`
diretto per archive/export — senza `-destination`, `SUPPORTED_PLATFORMS=iphoneos`,
`SUPPORTS_MACCATALYST=NO` — e `xcrun altool` per l'upload):

```bash
source ~/Developer/private_keys/scabo_deploy.env
bundle exec fastlane testflight_upload
```

### Variabili d'ambiente

Chiavi lette dall'ambiente (i valori segreti restano fuori dal repo). Le prime
sei sono fornite dal file `scabo_deploy.env`; `APP_IDENTIFIER` e `MATCH_GIT_URL`
sono invece **pinnate nel codice** e non vanno passate da env.

| Chiave | A cosa serve | `setup_signing` | `testflight_upload` | Dove si trova |
|---|---|:---:|:---:|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID dell'API App Store Connect | ✓ | ✓ | App Store Connect → Users and Access → Integrations (`MGW9GC97HV`) |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Issuer ID dell'API | ✓ | ✓ | Stessa pagina (`eb059a17-…`) |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Contenuto del `.p8` (PEM o base64) — alternativa al file | ○ | ○ | Il file `AuthKey_MGW9GC97HV.p8` |
| `APPLE_TEAM_ID` | Apple Developer Team ID | ✓ | ✓ | `D2KQYQ8YU8` |
| `APPLE_ID` | Apple ID dell'account | ✓ | ✓ | `scabo@icloud.com` |
| `MATCH_PASSWORD` | Passphrase di cifratura dei certificati Match | ✓ | ✓ | `scabo_deploy.env` (condivisa con gli altri progetti) |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Auth base64 `user:token` per il repo certs in CI | ○ | ○ | PAT GitHub con accesso a `lumar-lounge-certs` |
| `APP_IDENTIFIER` | Bundle id — **pinnato in `Appfile`/`Fastfile`** | — | — | `com.scabo.lumarlounge` |
| `MATCH_GIT_URL` | Repo certificati — **pinnato in `Matchfile`/`Fastfile`** | — | — | `https://github.com/Scabo03/lumar-lounge-certs.git` |

✓ = richiesta · ○ = opzionale · — = non da env (pinnata nel codice)

Note: in alternativa al contenuto, le lane accettano `APP_STORE_CONNECT_API_KEY_PATH`
(path al `.p8`; default `~/AuthKey.p8`, qui sovrascritto da `scabo_deploy.env`).
In locale `MATCH_GIT_BASIC_AUTHORIZATION` non serve: il push verso il repo
certificati passa per il credential helper `osxkeychain`. Per saltare il
`source` ad ogni lancio si può creare un `fastlane/.env` locale (gitignorato);
vedi `fastlane/.env.example`.
