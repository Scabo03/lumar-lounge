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
| `SpeechMap` / `SpeechConductor` / `AnnouncementQueue` / `BotChatter` | Il **layer parlato** (D-029..D-032): mappa autorevole evento→sorgente, direttore seriale del croupier, **coda annunci VoiceOver** trasversale, voci-colore dei bot. Vedi sotto. |
| `AudioScore` / `AudioDirector` | Layer **non parlato** (D-029): suoni fisici/effetti puri + ambient dinamico e reazioni di fine mano dei bot. |
| `HandGate`, `SeatView`, `CardView`, `TablePalette`, `Localization` | Gate produttore/consumatore, sottoviste e helper (pronuncia fonetica). |

Punti fermi: **ritmo umano nella UI**; **Dynamic Type** e **alto contrasto**
ovunque; annunci VoiceOver affidabili (proprio turno, proprie carte, ogni
`+/−` del box Raise con priorità interrompente); il box Raise è una **vera
modale d'accessibilità** — sfondo intrappolato, focus dentro, +/− pulsanti
navigabili che annunciano l'importo (D-027); accessibilità di prima classe
su **ogni** nuovo controllo (identifier, label fonetica, stato attivo/disattivo
riflesso anche per VoiceOver).

## `AnnouncementQueue` — coda annunci VoiceOver (componente trasversale, D-032)

Il **canale seriale unico** per ogni annuncio VoiceOver del progetto (poker e giochi
futuri). È l'**unico** punto che chiama `UIAccessibility.post` (test statico lo
verifica). API pubblica (`@MainActor`):

- `enqueue(_ text: String, priority: AnnouncementPriority)` — accoda un annuncio.
  `.high` (personale/critico: proprie carte, proprio turno, conclusione pot, fine
  sessione) non viene **mai** droppato ed è **bumpato** in testa; `.medium` (azioni
  avversari) e `.low` (contenuto carte) vengono droppati sotto backlog.
- `announceLiveValue(_ text: String)` — l'**unica** interruzione deliberata, per un
  controllo a valore vivo (box Raise): un nuovo valore sostituisce il precedente.
- `flushPending()` — scarta gli annunci non ancora partiti (cue time-critical: turno).
- `beginExternalSpeech() async` / `endExternalSpeech()` — coordinamento col croupier:
  mentre un mp3 suona la coda **tiene**, e aspetta la fine di un annuncio in corso
  prima che il croupier parta. Croupier + sintesi = **un unico canale parlato**.

Regole: nessun troncamento (un annuncio iniziato finisce); completamento reale via
`announcementDidFinishNotification` con **tetto** stima+1 s di fallback; strategia di
drop scelta dai dati (Strategia C — vedi D-032). Uso tipico: la `SpeechConductor`
gli passa la sintesi *fire-and-forget* con la priorità della `SpeechMap`; il box Raise
usa `announceLiveValue`. Debug: `SpokenLog.enabled = true` (DEBUG).

## `GameChrome` + `SettingsView` + `AppVoiceOverMode` (chrome e impostazioni, D-033/D-034)

**Componenti riusabili per tutto il progetto**, non specifici al tavolo.

- **`GameChrome<Content>`** — la shell persistente: avvolge qualunque schermata
  principale, mostra una **top bar** col pulsante Impostazioni in alto a destra
  (accessibile: label "Impostazioni", hint, identifier `settings.button`, 44×44),
  e presenta la `SettingsView` come `.sheet`. La barra riserva la propria striscia,
  quindi non copre il contenuto. Ogni schermata futura (menu, casinò) lo riusa.
- **`SettingsView`** — la schermata impostazioni, una `List` a sezioni pensata per
  **crescere** con molte opzioni future. Oggi: lo switch "Modalità VoiceOver
  dell'app".
- **`AppVoiceOverMode`** (`ObservableObject`) — lo stato della **modalità VoiceOver
  dell'app**, **indipendente da iOS**, persistito in `UserDefaults` (store iniettabile
  per i test), default OFF. Vive sopra il confine di restart. Quando ON, il
  `TableViewModel` **attende il canale parlato quieto** (`conductor.isIdle &&
  announcements.isQuiet`) prima di mostrare l'evento successivo (occhio+orecchio
  insieme); quando OFF, ritmo umano veloce. Il cambio è a **effetto immediato** (letto
  per-evento, nessuno stato inconsistente). A iOS VoiceOver spento ma app ON, la coda
  **simula** le durate (`pacedWhenSilent`) così il ritmo teorico è rispettato.

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

## M2.1 — Navigazione a tre livelli e mondo (D-035/036/037)

| Componente | A cosa serve |
|---|---|
| `AppRootView` | Nuovo **entry point** dell'app: possiede `AppState` (navigazione + gettoni) e la modalità VoiceOver, avvolge ogni schermata in `GameChrome`, e guida l'**ambient per schermata** (Home/Riverwood con fallback lounge; il tavolo lo gestisce l'`AudioDirector`). L'app non apre più su `PokerTableView` (rimosso). |
| `AppState` | `ObservableObject` di livello app: `screen` (`.home`/`.riverwood`/`.table(TableFormat)`) e `chips` (specchio del `PlayerAccount`). `sitDown`/`leaveTable`/`canAfford`. Navigazione **guidata da stato** (non `NavigationStack`) per pieno controllo del chrome e testabilità. |
| `HomeView` | Prima schermata: titolo serif, tagline, lista casinò (Riverwood entrabile + placeholder "In arrivo"). |
| `RiverwoodView` | Lista tavoli del Riverwood: Classico, Rapido, e Five-Card Draw **visibile ma non entrabile** ("In arrivo"). Ogni riga è un blocco VoiceOver unico; disabilitata se gettoni insufficienti. |
| `GameChrome` (esteso) | Ora con azione **leading** opzionale (indietro / lascia tavolo) e riga **saldo gettoni**, oltre al pulsante Impostazioni. |

Il `TableViewModel` è **parametrizzato** da `TableRules` (blind/personalità/buy-in) e
riceve un callback `onLeave` per il cash-out; ospita il **boost mano decisiva** (D-037)
e il **lascia tavolo** (D-036). Estetica rustica del Riverwood resa con palette scura +
**serif**, SwiftUI puro (nessuna texture — gli asset arriveranno dopo).

## M2.4 — Tavolo di Five-Card Draw giocabile (D-044)

La UI del secondo gioco: **speculare** al tavolo Texas ma dedicata, con stato e
riduzione puri propri e — la novità — un **box modale per la fase di scambio**.
Riusa **così com'è** tutta l'infrastruttura trasversale (`GameChrome`,
`AnnouncementQueue`, `SpeechConductor`, `AppVoiceOverMode` + ritmo adattivo,
`HandGate`, `EndOverlay`, `GameOutcome`, `CardView`).

| Componente | A cosa serve |
|---|---|
| `DrawTableState` / `DrawTableReducer` | Stato di presentazione **puro** e riduzione evento→stato del tavolo Draw (cinque carte dell'umano, niente board, fasi firstBet→draw→secondBet, pot progressivo, conteggio scarti per posto, squalifica openers). Testabile in isolamento. |
| `DrawTableViewModel` | Possiede la sessione (`DrawSessionDriver` + umano + tre bot), pace umano/adattivo, narrazione, e **due punti di decisione** dell'umano: barra puntate (limit) e **box di scambio**. Sincronizza il turno umano su **due** sospensioni del provider (D-021 esteso). |
| `DrawTableView` | La schermata giocabile: badge avversari in alto, tavolo con pot + **pot progressivo** + button + fase, barra azioni, cinque carte dell'umano in basso; overlay del box di scambio e di fine partita. |
| `DrawActionBarView` | Fold / Check-Call / **Bet** / **Raise** a **importi fissi** nel testo ("Bet 20", "Raise 40") — limit, nessun box progressivo. Bet attivo anche senza openers (apertura sull'onore, D-039); Raise disabilitato al cap. |
| `DrawBoxView` | Il **box modale d'accessibilità** dello scambio: cinque carte selezionabili al tap con **doppio segnale visivo** (bordo ottone + mark scuro con X), ogni carta pulsante VoiceOver con label di stato, contatore, Conferma sempre attivo (0 = "stai pat"), quinto tap rifiutato con annuncio; focus portato dentro all'apertura. |
| `DrawSpeechMap` | Mappatura autorevole evento→parlato del Draw (pura, come `SpeechMap`): croupier riusato + **cinque nuovi slot** con fallback di sintesi (D-030); sintesi per proprie carte, scarti avversari, pot progressivo, squalifica, conclusione. |
| `DrawAudioScore` / `DrawAudioDirector` | Layer **non parlato** dedicato: suoni fisici puri + ambient Riverwood (fallback lounge) che passa a **teso** quando il pot progressivo supera il doppio del base o su un all-in. |

La "Sala Whiskey" del Riverwood è ora **entrabile** (buy-in 2000): `AppState` ha
`screen == .drawTable` e `sitDownDraw`, e `RiverwoodView` mostra la riga come tavolo
attivo (bloccata se gettoni insufficienti). Coperto da un XCUITest dedicato
(`DrawTableUITests`: apertura dal Riverwood, layout accessibile, box che si apre,
seleziona e conferma) più la navigazione aggiornata.
