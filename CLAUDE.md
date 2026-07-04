# CLAUDE.md — punto d'ingresso per le sessioni di Claude Code

Questo file è il **primo posto da leggere** all'avvio di ogni sessione dentro il
repo. Claude Code lo carica automaticamente in contesto: serve a orientarsi in
fretta anche a mesi di distanza o dopo un reset. È il **hub**; i dettagli stanno
nei file collegati.

---

## Dove sto? (orientamento rapido)

**Cos'è.** Lumar Lounge — app iOS/iPadOS di giochi di carte e da casinò
(Swift + SwiftUI). Primo gioco target: **Texas Hold'em No Limit contro bot**.

**Cos'è fatto.**
- Scatola architetturale: 4 moduli (`GameEngine`, `GameWorld`, `Audio`, `UI`)
  con dipendenze verificate dal compilatore; shell d'app; localizzazione it/en.
- Infrastruttura di rilascio: Fastlane Match + pipeline TestFlight (collaudata).
- **`GameEngine` M1.1:** carte, mazzo (shuffle seedabile), valutazione mani
  (10 categorie, kicker, split pot).
- **`GameEngine` M1.2:** motore di una mano di Texas Hold'em No Limit
  (`HoldemHand`): button/blind, street, sei azioni con min-raise No Limit, pot e
  side pot esatti, showdown/split, deterministico via seed.
- **`GameEngine` M1.3:** intelligenza dei bot. Interfaccia `PokerBot` +
  `BotContext` (vista redatta, solo info onesta, D-009), baseline matematico
  (`HandStrength`) modulato da `Personality` (D-010) con tre profili di partenza
  (`eagerNovice`/`conservativeRock`/`hotAggressor`).
- **`GameWorld` M1.4:** `SessionDriver` fa girare una sessione multi-mano
  (cliente puro del motore, D-014): tavolo ad anello, dead button (D-012),
  fiches/bust, ingressi tra le mani, azioni da bot o umano via `ActionProvider`
  async uniforme (D-013).
- **`GameWorld` M1.5:** flusso di eventi osservabile. Il driver **narra** ogni
  momento come `SessionEvent` su un `AsyncStream` multicast (`EventHub` actor),
  con distinzione pubblico/privato per audience (D-015). API M1.4 invariate.
- **`UI` M1.6:** prima schermata. `PokerTableView` ascolta il flusso pubblico e
  mostra una sessione tra 3 bot a **ritmo umano** (D-018), narrata a VoiceOver con
  pronuncia fonetica italiana (D-016), logica di presentazione pura e testabile
  (D-017), alto contrasto + Dynamic Type (D-019).
- **`UI` M1.7:** tavolo **giocabile** dal giocatore umano. Layout stratificato
  (D-022), barra azioni attiva al proprio turno, box Raise a curva progressiva
  (D-020); il turno umano usa l'`HumanActionProvider` di M1.4, sincronizzato col
  display via coda MainActor (D-021).
- **`Audio` M1.8:** modulo audio pieno (`AudioEngine`/AVFoundation), **neutro**;
  mappatura evento→suoni (`AudioScore`) + consumatore parallelo (`AudioDirector`)
  in `UI` (D-023); coordinamento VoiceOver (D-024). **47 mp3 integrati** in
  `Resources/Audio/` (6 del catalogo non consegnati → silenziosi, D-025).
  126 unit test verdi + 1 XCUITest.

**🏁 Fase 1 (M1) completa — il gioco base gira end-to-end con audio ed è pronto
per un primo TestFlight** (motore + bot + sessione + flusso + UI accessibile +
audio pieno). L'app bundle contiene i 47 mp3; mancano solo 6 suoni non consegnati
(4 `tbl_chips_*`, `amb_crowd_distant`, `fx_hand_neutral`), da aggiungere in
`Resources/Audio/` quando prodotti.

**Prossimo passo.** **Fase 2 (`GameWorld` — il mondo attorno al tavolo, M2.x)**:
lo specifico sarà definito con l'utente nella prossima conversazione. Vedi
[`ROADMAP.md`](ROADMAP.md).

**Stato completo, sempre aggiornato:** sezione *Stato di sviluppo* in
[`README.md`](README.md).

## Mappa della documentazione

| File | A cosa serve |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | **Questo file.** Ingresso, regole per le sessioni, log decisioni. |
| [`ROADMAP.md`](ROADMAP.md) | Sequenza dei mattoni con stato e dipendenze, fino al primo TestFlight. |
| [`CONVENTIONS.md`](CONVENTIONS.md) | Convenzioni del progetto (lingua, dominio, architettura, accessibilità). |
| [`README.md`](README.md) | Stato di sviluppo, parametri operativi, build e pipeline di rilascio. |
| `GameEngine/README.md` | Filosofia, tipi, cosa NON contiene, prossimo pezzo del motore. |
| `GameWorld/README.md`, `UI/README.md`, `Audio/README.md` | Filosofia e compito di ciascun modulo. |

## Convenzioni essenziali (il minimo da avere in testa)

Riassunto operativo; la versione completa e canonica è in
[`CONVENTIONS.md`](CONVENTIONS.md).

- **Dipendenze:** `UI → GameWorld → GameEngine`, `Audio` trasversale. Verificate
  dal compilatore.
- **`GameEngine` importa SOLO Foundation.** Nessun framework di piattaforma.
- **Codice e commenti in inglese.** Dominio misto: **inglese** per azioni/ruoli
  del poker (fold/call/raise/blind/button), **italiano** per le entità comuni
  (carte/mazzo/tavolo/mano).
- **Fiches** al tavolo, **gettoni** nel casinò esterno: concetti distinti.
- **Italiano principale, inglese seconda.** Nessuna stringa utente inline: tutto
  da `Resources/`.
- **Accessibilità come priorità architetturale:** VoiceOver di prima classe,
  pronuncia italiana curata, principio "nessuno perde niente", approccio
  audio-first.

---

## Regole di comportamento per le sessioni future

Valgono per **ogni** sessione di Claude Code su questo repo:

1. **Leggere prima di lavorare.** All'inizio di ogni sessione, leggere questo
   file, [`ROADMAP.md`](ROADMAP.md) e i README dei moduli toccati, prima di
   scrivere qualsiasi codice.
2. **Documentare insieme al codice, non dopo.** L'aggiornamento della
   documentazione è parte del lavoro, non un afterthought. Chiudere un mattone
   significa anche aggiornare README di modulo, `ROADMAP.md` (stato del mattone)
   e, se il mattone è significativo, la sezione *Stato di sviluppo* del README
   principale e l'orientamento qui sopra.
3. **Non chiudere una sessione senza lasciare tracce.** Alla fine deve essere
   chiaro alla sessione successiva cosa è stato fatto e qual è il prossimo passo.
4. **Nessuna decisione architetturale implicita.** Ogni scelta non banale
   (piattaforme, nuovi tipi, deviazioni dalle convenzioni, dipendenze) va
   **esplicitata** nel log decisioni qui sotto, non lasciata solo intuibile dal
   codice — come è stato fatto per la scelta su `Package.swift` (vedi D-001).
5. **Rispettare i vincoli architetturali** dell'elenco convenzioni: non far
   importare a `GameEngine` nulla oltre Foundation, non violare la direzione
   delle dipendenze, non scrivere stringhe utente inline.

---

## Log delle decisioni architetturali

Decisioni non banali, tracciabili per chiunque legga il progetto in futuro.
Aggiungere una voce ogni volta che si prende una scelta di questo tipo.

### D-001 — `.macOS(.v13)` aggiunto a `Package.swift` (sessione M1.1)
Il package dichiarava solo `.iOS(.v17)`, quindi `swift test` dall'host Mac non
compilava il target `UI` (SwiftUI non disponibile sul deployment macOS di
default) e i test non partivano. È stato aggiunto `.macOS(.v13)` alle
`platforms`.
**Natura:** **additiva** rispetto a iOS. Allarga solo il minimo-OS supportato dal
package per consentire `swift test` da riga di comando; **non modifica la build
dell'app**, che resta iOS (confermato: `xcodebuild -scheme LumarLounge` →
BUILD SUCCEEDED). I layer puri sono comunque dichiarati portabili, quindi la
scelta è coerente con l'architettura.

### D-002 — Nessun tipo `Hand` separato in M1.1 (sessione M1.1)
Non è stato creato un tipo `Hand`: `HandRank` incapsula già categoria,
tie-breaker e le cinque carte, cioè tutto ciò che serve per **valutare e
confrontare** le mani.
**Piano futuro:** quando arriverà il motore della partita (M1.2) si introdurrà un
tipo `Hand` **giocatore-centrico** (le due hole card di un giocatore), distinto
da `HandRank` che è **valutazione-centrico**. I due concetti non vanno fusi.
**Risolto in M1.2:** `Hand` ora esiste (le due hole card di un seat), distinto da
`HandRank`. Vedi `GameEngine/Hand.swift`.

### D-003 — Struttura dei tipi del motore Hold'em (sessione M1.2)
Scelte di forma per M1.2, per renderlo puro e testabile:
- **`HoldemHand` è uno `struct` stateful con `mutating apply(_:)`** (value type,
  non una classe). Motivazione: snapshot a costo zero, nessun aliasing, e
  determinismo per costruzione — cruciale per riprodurre situazioni complesse.
- **`Seat` (config: id + stack) è distinto da `SeatState`** (stato dinamico
  della mano: hole, streetBet, totalBet, folded, all-in). Gli id sono stabili
  tra le mani così `GameWorld` può mappare seat→giocatore.
- **`Action` con sei casi** (`fold/check/call/bet/raise/allIn`) e amount con
  **semantica "to"** (`bet(n)`/`raise(n)` = totale a cui portare la puntata di
  street, non il delta). `apply` valida e lancia `ActionError`; `legalActions()`
  espone le mosse legali per il seat di turno (utile per bot e UI futuri).
- **Aritmetica dei pot in `PotMath` (funzioni statiche pure)**, separata dal
  motore, così side-pot e split (con chip di resto) sono testabili con input
  costruiti a mano — l'engine guidato dall'RNG non produce a comando pareggi o
  side-pot di forma esatta.

### D-004 — Chip di resto nello split pot al seat alla sinistra del button (M1.2)
In un pareggio con divisione non intera, la/e fiche indivisibile/i vanno al
vincitore più vicino alla **sinistra del button in senso orario** (il primo di
posizione, cioè lato small blind), una fiche per volta in ordine di posizione.
È la convenzione standard delle case da gioco. Implementato in
`winnersOrderedFromButton` + `PotMath.distribute`.

### D-005 — Determinismo via seed (sessione M1.2)
L'unica sorgente di casualità è la mescolata seedabile del mazzo. A parità di
`seed` e di sequenza di azioni, `HoldemHand` produce esattamente lo stesso
risultato (board, hole, pot, payout). Nessun uso di `Date`/`Random` non seedato.

### D-006 — Rotazione del button minimale; ingresso/uscita al `GameWorld` (M1.2)
`HoldemHand.nextButtonIndex(after:seatCount:)` avanza semplicemente al seat
successivo. **Saltare i seat bustati (stack 0) e gestire i giocatori che
entrano/escono dal tavolo è responsabilità di `GameWorld`**, non di una singola
mano pura: una mano riceve già l'insieme di seat che partecipano. Annotato come
lavoro futuro di M2.1, non come mattone `GameEngine`.

### D-007 — Niente burn card (sessione M1.2)
Il motore **non** brucia una carta prima di flop/turn/river: è puramente
cosmetico e in un motore a RNG puro non incide su equità o correttezza. Il
determinismo è garantito comunque dal seed. Se in futuro servisse fedeltà visiva
(es. animazione del burn in UI), la si aggiunge senza toccare la logica.

### D-008 — Big blind short: la puntata corrente resta il big blind nominale (M1.2)
Se il big blind non può coprire la posta, la posta all-in per meno, ma la
**puntata da eguagliare (`currentBet`) resta il big blind nominale** e il
min-raise iniziale resta il big blind. La contribuzione ridotta del seat short è
gestita correttamente dai side pot in base al `totalBet` effettivo.

### D-009 — Informazione onesta garantita da una vista redatta (sessione M1.3)
`HoldemHand.seats` espone le hole card di **tutti** i seat: passare il motore
grezzo a un bot gli permetterebbe di barare. Perciò un bot **non** riceve mai
`HoldemHand`, ma un `BotContext`: una vista **seat-relativa e solo-pubblica**
(board, pot, stack, puntate, posizione) più le **sole** due carte del seat di
turno. L'onestà è quindi garantita **per costruzione**, non per disciplina. Il
`BotContext` si costruisce dal motore (`init?(actingIn:)`) redigendo le carte
altrui; `PublicSeat` non ha proprio un campo per le hole card.

### D-010 — Personalità come modulazione, non sostituzione (sessione M1.3)
La forza matematica (equity, pot odds, posizione) è **comune** a tutti i bot; la
`Personality` è uno strato di manopole 0…1 (tightness, aggression,
bluffFrequency, riskTolerance, positionAwareness, rationality, tiltReactivity)
che modula *come* quella forza si esprime. Un solo `HeuristicBot` parametrizzato
copre molti caratteri; aggiungerne è **additivo** (un preset in più), mentre un
bot radicalmente diverso è un nuovo conforme a `PokerBot`. Determinismo: l'unica
casualità è un `SeededGenerator` inizializzato dal `seed` del bot mescolato col
`fingerprint` del contesto — stesso bot + stessa situazione → stessa azione.
Tre profili di partenza scelti agli estremi dell'asse emotivo-strategico:
- **`eagerNovice`** — gioca troppe mani, si spaventa ai bet grossi, bluff
  improvvisati, molto emotivo (tilt alto), letture fallaci.
- **`conservativeRock`** — solo mani forti, poca aggressione, quasi mai bluff,
  disciplinato e imperturbabile, prevedibile.
- **`hotAggressor`** — rilancia e bluffa spesso, ignora la posizione, ama il
  rischio; rumoroso e sfruttabile.

### D-011 — Equity Monte Carlo contro range uniforme (sessione M1.3)
L'equity postflop è stimata con un Monte Carlo seedato (avversari e board
casuali, molti campioni). Gli avversari sono estratti **uniformemente** (range
non ristretto): è la stima onesta più semplice, come consentito dal perimetro.
Restringere il range in base alle azioni degli avversari è un raffinamento
**additivo** futuro, che non cambia l'ossatura. Preflop si usa un'euristica di
Chen normalizzata (veloce, niente rollout).

### D-012 — Dead button via anello fisico mappato sul motore (sessione M1.4)
Il tavolo del `SessionDriver` è un **anello di posizioni fisse**; il button
avanza di **una posizione** ogni mano, anche se cade su un seat vuoto/bustato
(vero *dead button*). Il motore M1.2, però, vuole un button su un partecipante
reale: si mappa il dead button sul **primo giocatore idoneo scandendo
all'indietro (senso antiorario) dalla posizione del button, incluso**. Il suo
successivo in senso orario è esattamente lo small blind reale, quindi l'ordine
d'azione che il motore produce coincide col dead button. **Semplificazione
consapevole:** non si modella il *dead/half small blind* (blind saltato); SB e
BB sono sempre posti dai due giocatori idonei successivi, coerentemente col
modello di blind del motore. Rebuy dopo bust non implementato: il seat resta
`.bustedOut`, pronto ad accoglierlo in futuro.

### D-013 — Interfaccia azione uniforme bot/umano (`ActionProvider`, M1.4)
Il driver chiede l'azione tramite un unico protocollo **async**
`ActionProvider.provideAction(for: BotContext) async -> Action`. Un bot risponde
in modo sincrono dietro la facciata async (`BotActionProvider`); un umano tramite
`HumanActionProvider`, un **actor** che **sospende** con una `CheckedContinuation`
finché la UI non chiama `submit(_:)`. Dal punto di vista del driver i due casi
sono indistinguibili — nessun threading proprio, solo Swift Concurrency. Il
driver **legalizza** difensivamente l'azione ricevuta (fallback a check/fold) per
restare totale e deterministico anche con un provider scorretto.

### D-014 — Il driver è cliente puro di GameEngine (sessione M1.4)
`SessionDriver` **non tocca `GameEngine`**: usa solo le API pubbliche
(`HoldemHand`, `legalActions()`/`apply(_:)`, `HandResult`, `BotContext`,
`nextButtonIndex` non necessario grazie alla mappatura dead button). Il motore
non è stato modificato per accogliere i bot o la sessione. Il criterio di **fine
sessione è esterno**: il driver espone `playHand()`/`run(continuing:)` e lo stato
del tavolo, ma la decisione di fermarsi sta nel chiamante. Il driver è un
`final class` (riferimento, muta stato tra un `await` e l'altro); gli ingressi/
uscite sono ammessi **solo tra le mani** (guardia `isHandInProgress`, robusta
anche alla reentrancy).

### D-015 — Flusso di eventi: `AsyncStream` multicast via `EventHub` actor (M1.5)
La "voce" del driver è un canale a cui più consumatori si iscrivono. Scelta:
**`AsyncStream` multicast** vendute da un `actor EventHub`.
- **Perché AsyncStream e non Combine/observer/publisher:** è pura libreria
  standard (nessuna dipendenza esterna, niente Combine/UIKit), si integra con la
  natura async già presente in M1.4, produce **valori** (eventi struct/enum) e
  supporta naturalmente più iscritti. Buffering **unbounded** ⇒ il driver non si
  blocca mai su un consumatore lento (flusso a velocità di codice, nessun timing).
- **Perché un actor per il fan-out (e non un lock):** il driver resta un
  `final class` — così **tutte le API sincrone di M1.4 restano sincrone** e i suoi
  test girano invariati. La parte sensibile alla concorrenza (registro degli
  iscritti) vive nell'actor `EventHub`: subscribe/emit serializzati senza lock né
  thread nostri. `emit` è `await hub.emit(...)`: hop d'attore, nessun ritardo.
- **Pubblico vs privato per costruzione:** ogni evento porta un `EventAudience`
  (`.everyone`/`.player(id)`); l'iscritto dichiara un `EventViewer`
  (`.spectator`/`.player(id)`) e l'hub instrada. Un giocatore riceve pubblico +
  **solo** il proprio privato (le sue hole card), mai l'altrui — stessa filosofia
  di D-009. Gli eventi privati vengono comunque emessi (consumano un numero di
  sequenza) anche senza iscritti: un consumatore filtrato vede una sottosequenza.
- **API sincrone congelate:** `addPlayer`/`removePlayer` (sync in M1.4) non
  possono `await` l'hub, quindi **accodano** l'evento join/leave e lo si **flusha**
  all'inizio della mano successiva (o su `endSession`) — cronologicamente "tra le
  mani", corretto. `sessionBegan` è emesso pigramente alla prima mano;
  `sessionEnded` da `endSession(reason:)`, che **chiude** i flussi così i
  `for await` dei consumatori terminano.
- **Fedeltà senza toccare il motore:** gli eventi si derivano dall'orchestramento
  del driver — importo di un'azione dal delta di stack (robusto anche quando la
  street avanza e azzera `streetBet`), aperture di street dagli indici del board
  (gestisce il runout multi-street di un all-in), vincitori per-pot ricalcolati
  dai `bestHands` pubblici del `HandResult`. Descrittivo, non prescrittivo:
  nessun riferimento a suoni/viste. Determinismo: sequenza e contenuti identici a
  parità di stato/seed/azioni.

### D-016 — VoiceOver: annunci dinamici e pronuncia fonetica italiana (M1.6)
Gli annunci dinamici usano `UIAccessibility.post(.announcement)`, avvolto in
`#if canImport(UIKit)` così il modulo `UI` **compila sul host macOS** (serve a
`swift test`) dove diventa no-op. La **pronuncia italiana** dei termini poker
(inglesi per convenzione) è resa **foneticamente nelle stringhe `it.lproj`**
("reis", "blaind", "bàtton", "ol-in", "cek", "col", "tern"…), non in codice, così
il TTS italiano li dice bene. La mappatura evento→momento parlato è una funzione
**pura** (`TableAnnouncer.spoken(for:)`) testabile senza localizzazione; la resa
in stringa (`text(for:)`) usa il bundle. Parità vedente/non vedente ("nessuno
perde niente"): le carte sono **coperte durante la mano** (privacy, coerente con
D-009 — lo spettatore non riceve nemmeno le hole altrui nel flusso) e **rivelate
allo showdown** sia visivamente sia a voce, come una vera vista da spettatore.

### D-017 — Logica di presentazione pura, separata da SwiftUI (M1.6)
Lo stato del tavolo è un valore (`TableState`) e l'evoluzione è una riduzione
**pura** `evento → stato` (`TableReducer`), senza SwiftUI né localizzazione né
logica di gioco. Questo tiene la UI "ascolta e mostra, non decide" e rende la
logica del modulo interamente unit-testabile via `swift test`. Se una logica
sembra "di gioco", appartiene a `GameWorld`/`GameEngine`, non a `UI`.

### D-018 — Il ritmo umano vive nella UI (M1.6)
Il flusso di M1.5 è a velocità di codice; il tempo umano è **responsabilità del
consumatore**. Il `TableViewModel` (`@MainActor ObservableObject`) drena il flusso
e mette una pausa fra un evento e il successivo (ritmi diversi per tipo; il flop
esce **una carta alla volta**). Un `HandGate` (actor) tiene il produttore al più
**una mano avanti**, così i bot non calcolano l'intera sessione in anticipo
(niente front-load del Monte Carlo, buffering limitato). È esattamente ciò che il
principio "eventi descrittivi non prescrittivi" di D-015 permette.

### D-019 — Estetica minimalista ad alto contrasto; gotcha albero accessibilità (M1.6)
Palette definita **in codice** (nessun asset catalog), alto contrasto per
ipovedenti, **Dynamic Type** ovunque (font di sistema + `@ScaledMetric`).
L'app presenta `PokerTableView` (non più `RootView`); un argomento di lancio
`-uiTesting` tiene il tavolo statico per l'XCUITest di struttura.
**Gotcha registrato:** mettere `.accessibilityElement(children: .contain)` (o
persino il solo `.accessibilityIdentifier`) sul contenitore esterno
**collassa l'intero sottoalbero in un unico elemento**, nascondendo gli
identifier dei figli (seat/board/pot). Regola: **niente modificatori di
accessibilità sul contenitore grande**; gli identifier vanno sui **leaf** (e
l'elemento "table.container" è il feltro, reso elemento a sé). *Ribadito in M1.7:
vale per OGNI zona-contenitore (opponents/hero/action bar) — l'identifier sta
sui leaf (`opponent.N`, `hero.cards`, `action.*`), mai sul gruppo.*

### D-020 — Box Raise a curva progressiva (sessione M1.7)
Il rilancio si regola con una **curva progressiva** (`RaiseCurve`, pura e
testabile): +10×3, +25×3, +50×2, +100×2, poi +250 a clic, fino allo stack.
Controllo fine vicino al minimo, accelerazione verso l'all-in. Lo stato del box
(`RaiseBoxState`) tiene un **conteggio di clic** come sorgente di verità; il
valore è derivato e clampato a `[minRaiseTo, maxRaiseTo]` (da `legalActions`).
L'all-in salta al conteggio che raggiunge il massimo, così "−" da all-in scende
di uno step. **Accessibilità:** ogni `+/−` e l'all-in postano un annuncio con
**priorità alta interrompente** (`AttributedString.accessibilitySpeechAnnouncementPriority
= .high`), così una raffica di clic annuncia solo l'ultimo valore senza
accodarsi. Pattern candidato a diventare convenzione riusabile (blackjack,
roulette) — vedi `CONVENTIONS.md`.

### D-021 — Sincronizzazione del turno umano col display (sessione M1.7)
Il seat umano usa l'`HumanActionProvider` di M1.4 (suspend/`submit`); nessuna
logica nuova in `GameWorld`. Il problema: il produttore (a velocità di codice) si
sospende sul turno umano *dopo* aver emesso gli eventi pre-turno, mentre il
consumatore li mostra ancora a ritmo umano. Soluzione **tutta in UI**: il flusso
è **rilanciato in una coda su `MainActor`** posseduta dal view model; i pulsanti
appaiono quando la coda è **svuotata** *e* il provider è in attesa
(`pendingContext != nil`) — cioè quando il display ha raggiunto il punto di
decisione. Alla conferma la UI chiama `submit`, il produttore riprende ed emette
l'azione dell'umano nella coda. **Nota:** qui è stato corretto un bug latente di
M1.6 — `HandGate` ora viene **rilasciato su `handEnded`** (prima non lo era mai;
in M1.6 non emergeva perché i test UI non avviavano la sessione).

### D-022 — Layout stratificato del tavolo giocabile (sessione M1.7)
Il tavolo passa dall'ellisse centrata di M1.6 a un **layout a fasce** più fedele
a un'app di poker mobile: **umano protagonista in basso** (due carte grandi
scoperte + stack, nessun bollino ridondante), **barra azioni** sopra, **tavolo**
al centro (solo carte comuni, pot, button — **nessuna carta coperta degli
avversari sul tavolo**, realisticamente le tengono in mano), **avversari come
badge in alto** (nome, stack, stato, evidenza "di turno"). Resta il principio:
la UI **non decide**, raccoglie input e lo inoltra. Fine partita al bust
dell'umano o dei bot, con esito (`won`/`lost`) e restart via `.id()`.

### D-023 — Separazione mappatura evento→suoni vs riproduzione (sessione M1.8)
`Audio` resta **neutro e agnostico**: riproduce suoni opachi (`SoundID`) per
categoria (`SoundCategory`), senza conoscere `SessionEvent` né il poker. La
**mappatura evento→suoni** (`AudioScore`, funzione **pura**, come `TableAnnouncer`
per il parlato) e il **consumatore** che si iscrive al flusso (`AudioDirector`)
vivono in **`UI`**, e non in `Audio` né in `GameWorld`, perché:
- **non in `Audio`**: dovrebbe importare `SessionEvent` → non sarebbe più neutro;
- **non in `GameWorld`**: la regola di dipendenza vieta a `GameWorld` di importare
  `Audio` (`Audio` è trasversale). Solo `UI` vede sia `SessionEvent` (via
  `GameWorld`) sia `Audio`.
L'`AudioDirector` è un **consumatore parallelo** al consumatore visivo (seconda
iscrizione multicast, come `.spectator` — l'audio non serve le carte private) e
si **auto-ritma** con la stessa cadenza umana del display (`Pacing` condiviso):
il suono resta agganciato all'immagine, con drift che si azzera a ogni fine mano.
Le voci dei bot sono **probabilistiche e deterministiche** (RNG seedato passato
alla funzione pura). I suoni di **input UI** (tap) li riproduce direttamente la
vista, non il flusso.

### D-024 — Coordinamento audio ↔ VoiceOver (sessione M1.8)
Due voci che parlano insieme si annullano. Strategia adottata (la proposta nella
traccia, valutata la migliore): quando **VoiceOver è attivo**
(`UIAccessibility.isVoiceOverRunning`), i suoni **parlati** (`croupier`,
`botVoice`) vengono **silenziati** (`AudioPolicy.shouldPlay`), mentre i
**non parlati** (ambient, effetti del tavolo, feedback UI, jingle di esito)
continuano. VoiceOver resta la **fonte di verità** per l'informazione parlata:
l'accessibilità non è mai ridotta, l'audio arricchisce e basta. La sessione audio
è `.ambient` + `.mixWithOthers` per non "abbassare" VoiceOver. La policy è una
**funzione pura testabile**; il rilevamento VoiceOver è dietro `#if canImport(UIKit)`
(no-op sul host macOS, così il modulo compila per `swift test`).

### D-025 — Integrazione del catalogo audio e degradazione con grazia (M1.8)
Alla prima esecuzione i file **non erano sul Mac** (Downloads vuoto): si è
costruita **tutta l'architettura** con un manifesto provvisorio, degradazione con
grazia (file mancante → silenzio + log `[Audio] N/M missing…`), e auto-bundling da
`Resources/Audio/` (gruppo `Resources` sincronizzato → **verificato**). Poi
l'utente ha depositato i **48 mp3 + il catalogo** in Downloads. Verifica atteso↔
trovato (mostrata all'utente, **niente rinomina automatica**): **33 esatti**, **15
con nome diverso** (2 typo `botton`→`button`; 5 rinominati; 7 `vob_` senza `_01`;
1 extra `tbl_card_distribution`), **6 mancanti** (4 `tbl_chips_*`,
`amb_crowd_distant`, `fx_hand_neutral`). **Scelta dell'utente: "rinomina tutto al
catalogo"** → importati 47 file in `Resources/Audio/` rinominati alla forma del
catalogo, escluso l'extra; `SoundCatalog` riscritto coi nomi reali (53 voci); i 6
non consegnati restano silenziosi. L'app è pienamente giocabile; il bundle
contiene i 47 mp3 (log a runtime: **6/53 mancanti**).
