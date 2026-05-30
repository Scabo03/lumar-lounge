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

## Build (ambiente MacInCloud, senza sudo)

L'ambiente di build è MacInCloud Pay-as-you-go senza accesso `sudo`: non si
modifica `xcode-select`, si invoca `xcodebuild` col path completo della versione
di Xcode disponibile, senza `-destination`, forzando la piattaforma device.

Build di verifica (compilazione, slice device):

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
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
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
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

> Da compilare più avanti con i comandi specifici per l'archiviazione e
> l'upload su TestFlight (fastlane / Match, `xcodebuild archive`,
> `xcodebuild -exportArchive`, ecc.).

_(sezione vuota — da riempire quando arriveremo all'upload su TestFlight)_
