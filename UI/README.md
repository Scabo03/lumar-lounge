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

## Cosa contiene oggi (M1.7 — tavolo giocabile dal giocatore umano)

`PokerTableView` è ora un **tavolo stratificato e giocabile**: il giocatore umano
è protagonista in basso, i tre bot (personalità di M1.3) sono astratti in alto.

```
 opponents (badge: nome, stack, stato, "di turno")     ← fascia alta
 tavolo: carte comuni · pot · button                   ← centro
 Check/Call    Fold    Raise                            ← barra azioni
 🂡 🂮   le tue carte + stack                            ← fascia bassa (hero)
```

Quando tocca all'umano i tasti si accendono; la sua azione passa alla UI e poi
all'`HumanActionProvider` di M1.4 (`submit`). Il **layout stratificato** (D-022),
la **sincronizzazione del turno umano** (D-021) e il **box Raise a curva
progressiva** (D-020) sono le novità di M1.7.

| Tipo | Ruolo |
|---|---|
| `PokerTableView` / `TableScreen` / `TableCenterView` | La schermata stratificata; il centro mostra solo carte comuni, pot e button. `.id()` per il restart a fine partita. |
| `OpponentBadgesView` | I tre bot in alto: badge con nome, stack, stato (di turno/folded/all-in/bustato). Nessuna carta coperta sul tavolo. |
| `HeroZoneView` | La fascia bassa: le due carte del giocatore, grandi e scoperte, + il suo stack. Nessun bollino ridondante. |
| `ActionBarView` | I tasti Check/Call (testo dinamico), Fold, Raise — attivi solo al turno dell'umano; il box Raise; l'overlay di fine partita. |
| `RaiseCurve` / `RaiseBoxState` | La **curva progressiva** del rilancio (pura, testabile): fine vicino al minimo, accelerazione verso l'all-in. |
| `TableViewModel` | `@MainActor ObservableObject`: possiede la sessione (umano + 3 bot), consuma il flusso a ritmo umano, gestisce il turno umano e il box Raise, e l'esito (`won`/`lost`). |
| `TableState` / `TableReducer` | Stato di presentazione (valore) + riduzione **pura** `evento → stato` (ora anche le carte private dell'umano). Testabile. |
| `TableAnnouncer`, `Announcer`, `HandGate`, `SeatView`, `CardView`, `TablePalette`, `Localization` | Narrazione fonetica, annunci (interrompenti via `NSAttributedString`, D-027), gate produttore/consumatore, sottoviste e helper. |

Punti fermi: **ritmo umano nella UI**; **Dynamic Type** e **alto contrasto**
ovunque; annunci VoiceOver affidabili (proprio turno, proprie carte, ogni
`+/−` del box Raise con priorità interrompente); il box Raise è una **vera
modale d'accessibilità** — sfondo intrappolato, focus dentro, +/− pulsanti
navigabili che annunciano l'importo (D-027); accessibilità di prima classe
su **ogni** nuovo controllo (identifier, label fonetica, stato attivo/disattivo
riflesso anche per VoiceOver).

## Cosa NON contiene ancora (per scelta)

- **Nessun audio**: arriverà come consumatore parallelo del flusso, in un mattone
  dedicato.
- **Nessuna navigazione né altre schermate**, nessun menù, pausa, impostazioni,
  casinò o NPC: c'è solo il tavolo.
- **Nessuna statistica/cronologia mani**, nessuna persistenza, nessuna
  progressione o gettoni.
- **Nessuna logica di gioco** e nessuna modifica a `GameEngine`/`SessionDriver`:
  la UI raccoglie l'input e lo inoltra, poi ascolta il flusso come in M1.6.

## Test

- `Tests/UITests/` (`swift test`): riduzione pura dello stato
  (`TableReducerTests`), mappatura evento→speech (`TableAnnouncerTests`), e la
  **curva del rilancio** (`RaiseCurveTests`). Logica pura, niente SwiftUI.
- `LumarLoungeUITests/` (XCUITest sul simulatore): il layout stratificato è
  accessibile (`table.container`, `opponent.N`, `hero.cards`, i tasti azione);
  i tasti sono attivi al turno dell'umano e disabilitati al turno di un bot; il
  box Raise si apre coi quattro controlli (minus, value, plus, all-in) + conferma
  e annulla e si chiude; e una sequenza minima di gioco prosegue end-to-end.
