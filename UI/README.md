# UI

Tutte le **viste SwiftUI** dell'app: il cerchio più esterno dell'architettura.

## Filosofia

`UI` è l'unico modulo che parla al giocatore. Può importare `GameWorld`,
`GameEngine` e `Audio`; nessuno importa `UI` tranne la thin shell dell'app.

Due principi non negoziabili, presenti fin dalla prima riga:

- **Accessibilità di prima classe.** Ogni vista imposta accessibility identifier
  e label; VoiceOver è una modalità piena, non un ripiego. Vale il principio
  **"nessuno perde niente"** tra vedenti e non vedenti. La **pronuncia italiana**
  dei termini inglesi del poker è curata foneticamente ("reis" per raise,
  "blaind" per blind, "bàtton" per button…) nelle stringhe `it.lproj`.
- **Nessuna stringa inline.** Ogni testo visibile viene dai file di
  localizzazione in `Resources/` (italiano principale, inglese seconda).

La UI **ascolta e mostra, non decide**: non contiene logica di gioco (quella sta
in `GameEngine`/`GameWorld`). Consuma il flusso di eventi del `SessionDriver`
(M1.5) e ne riflette lo stato.

## Cosa contiene oggi (M1.6 — prima schermata: tavolo dimostrativo)

Una schermata `PokerTableView` che si iscrive al **flusso pubblico** del
`SessionDriver` e mostra una sessione di Texas Hold'em tra **tre bot** (le
personalità di M1.3) che si svolge dall'inizio alla fine, a **ritmo umano** e
interamente **narrata a VoiceOver**.

| Tipo | Ruolo |
|---|---|
| `PokerTableView` | La schermata: tavolo ovale ad alto contrasto, seat attorno, board centrale, pot, indicatore di button, banner del vincitore. Pura ascoltatrice. |
| `TableViewModel` | `@MainActor ObservableObject` che possiede la sessione demo, consuma il flusso a ritmo umano (sleep tra eventi; flop una carta alla volta), riduce in `TableState` e posta gli annunci VoiceOver. |
| `TableState` / `TableReducer` | Lo stato di presentazione (valore puro) e la **riduzione pura** `evento → stato`. Niente SwiftUI, niente localizzazione, niente logica di gioco → testabile. |
| `TableAnnouncer` / `SpokenEvent` | Mappa **pura** evento → momento narrabile (`spoken(for:)`, testabile) + resa localizzata fonetica (`text(for:)`). |
| `Announcer` | Posta gli annunci via `UIAccessibility`, protetto da `#if canImport(UIKit)` (no-op su macOS host, così il modulo compila per `swift test`). |
| `HandGate` | Gate async che tiene il produttore (a velocità di codice) al più **una mano avanti** rispetto al consumatore (a ritmo umano). |
| `SeatView`, `CardView`, `TablePalette`, `Localization` | Sottoviste, palette ad alto contrasto in codice, e helper di localizzazione + naming carte. |

Punti fermi: **ritmo umano nella UI** (il driver resta a velocità di codice come
da M1.5), **Dynamic Type** ovunque, **alto contrasto**, **carte coperte** durante
la mano (privacy) e rivelate solo allo showdown (come una vera vista da
spettatore), ogni seat un unico elemento accessibile con riassunto parlato.

## Cosa NON contiene ancora (per scelta)

- **Nessuna interazione umana**: il giocatore che gioca davvero arriva con M1.7
  (l'infrastruttura `HumanActionProvider` esiste già in `GameWorld`).
- **Nessun audio**: arriverà come consumatore parallelo del flusso, in un mattone
  dedicato.
- **Nessuna navigazione né altre schermate**, nessun menù, casinò o NPC: qui c'è
  solo il tavolo dimostrativo.
- **Nessuna persistenza.** Nessuna estetica ricca di casinò: chiarezza prima di
  tutto.
- **Nessuna logica di gioco** e nessuna modifica a `GameEngine`/`SessionDriver`.

## Test

- `Tests/UITests/` (`swift test`, 17 test): riduzione pura dello stato
  (`TableReducerTests`) e mappatura evento→speech (`TableAnnouncerTests` +
  formattazione simboli carta). Niente localizzazione/SwiftUI: logica pura.
- `LumarLoungeUITests/` (XCUITest sul simulatore): verifica che la struttura di
  accessibilità sia in piedi — `table.container`, i tre `seat.N`, `table.board`,
  `table.pot`, `table.button` esistono e sono raggiungibili per identifier. Usa
  l'argomento di lancio `-uiTesting` per tenere il tavolo statico.
