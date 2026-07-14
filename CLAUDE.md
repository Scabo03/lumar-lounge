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
  in `UI` (D-023); coordinamento audio↔VoiceOver a **domini separati** con mappatura
  autorevole evento→sorgente vocale e `SpeechConductor` seriale (D-028→…→**D-032**, che superano il silenziamento D-024 dopo i test reali). **51 mp3 integrati** in
  `Resources/Audio/` (2 del catalogo non ancora consegnati → silenziosi, D-025).
  157 unit test verdi + 2 XCUITest.

- **`GameWorld`/`UI` M2.1:** il **mondo attorno al tavolo**. Struttura di
  navigazione a **tre livelli** Home → Riverwood Casinò → Tavolo (D-035, `AppState`
  + `AppRootView`, chrome trasversale). **Gettoni persistenti** del giocatore in
  GameWorld (`PlayerAccount`), distinti dalle fiches al tavolo; buy-in/cash-out/bust,
  lascia-tavolo (D-036). Tavolo **Rapido** con bot più aggressivi e **boost mano
  decisiva** (blind raddoppiate + annuncio croupier, D-037). Five-Card Draw visibile
  ma non entrabile. 174 unit test + 3 XCUITest.
- **`GameEngine` M1.9:** **secondo motore di gioco**, il **Five-Card Draw** ("Jacks
  or Better"), in `Draw/`, **indipendente** dal Texas (solo M1.1 + `PotMath`/`Pot`
  condivisi, D-038). `FiveCardDrawHand`: ante, due giri **limit** (small/big bet, cap
  a tre raise), draw 0–4 carte, showdown a 5 carte. Regole marcanti: **jacks-or-better
  sull'onore + openers verificati allo showdown** (bluff-open punito allo showdown ma
  vincente su fold-out, D-039), **pass-and-out con pot progressivo** (D-040). Bot
  dedicati + tre dial di personalità additivi (D-041). Nessun driver/UI ancora. 31
  unit test (205 nel package).
- **`GameWorld`/`UI` M2.4:** il **Five-Card Draw giocabile** end-to-end. Driver di
  sessione dedicato `DrawSessionDriver` (pot progressivo, ante, due sospensioni umane
  puntata/scambio — D-042) con flusso eventi proprio `DrawSessionEvent` sulla stessa
  infrastruttura EventHub (D-043); **tavolo giocabile** `DrawTableView` con barra
  limit (importi fissi) e **box modale di scambio** accessibile (cinque carte
  selezionabili, doppio segnale visivo, annuncio dello stato — D-044). La "Sala
  Whiskey" del Riverwood è **entrabile** (buy-in 2000). Riuso di tutta l'infrastruttura
  trasversale (chrome, coda annunci, conductor, modalità VoiceOver). Motore/Texas non
  toccati. 234 unit test + XCUITest del tavolo Draw.
- **`GameEngine`/`GameWorld` M1.10:** **terzo motore di gioco**, l'**Omaha Pot Limit**,
  in `Omaha/`, **indipendente** da Texas e Draw (D-061→D-064). `OmahaHand`: quattro
  carte private, quattro street comuni, **valutazione vincolata due-più-tre** (esteso
  `HandEvaluator.evaluateOmaha`, D-061), **betting Pot Limit** col tetto calcolato dal
  vivo (`PotMath.potLimitMax…`, D-062), side pot, determinismo. `HeuristicOmahaBot` con
  euristica pre-flop sulle quattro carte + equity Monte Carlo vincolata (costo **misurato**,
  ~3×/campione → ~⅓ dei campioni per la parità col Texas, D-063) e due leve additive di
  `Personality` (`omahaCoordination`/`omahaNuttiness`). `OmahaSessionDriver` in GameWorld
  con **accelerazione riusabile a conteggio-mani** (`StakeEscalation`: blind escalation,
  mai a tempo — D-064). **Solo motore+bot+driver: nessuna UI, nessun audio, nessun casinò
  ospitante.** 311 test verdi; Texas e Draw invariati.

- **`GameWorld`/`UI` M2 Skypool:** **secondo casinò** e **Omaha giocabile** (D-065/D-066). Il
  pattern casinò è **generalizzato** (`Casino`/`CasinoTable`/`CasinoGame` + registry `Casinos`,
  lobby generica `CasinoLobbyView`, temi per casinò), col **Riverwood invariato**. Lo **Skypool**
  (cittadino, marmo/acqua, freddo) ospita Texas Classico/Rapido con **bot urbani** (tre personalità
  come entità proprie) e la sua specialità **Omaha Pot Limit "Marble"** — ora **giocabile**
  (`OmahaTableView`: quattro carte private lette **per seme**, box raise **Pot Limit** senza shove).
  Accesso **solo economico** (buy-in Skypool ~5×, scala Fast 5000 < Classic 6000 < Marble 10000).
  Novità audio: **due categorie di voce** (informativa→sintesi, ambientale→silenzio); slot Skypool
  dichiarati (nessun file), catalogo in `Skypool_audio_catalog.md`.
- **`UI` M2 croupier per-casinò (D-067):** il **croupier (e l'ambient) è un attributo del CASINÒ,
  non del gioco** — una palette (`CasinoAudio`) per casinò, valida per **tutti** i suoi tavoli.
  Chiude il debito D-066: i Texas dello Skypool ora usano il croupier/ambient/colore-bot **dello
  Skypool** (registro cittadino, cinico), non più quelli del Riverwood. Il **Riverwood è la palette
  identità/default** → invariato per costruzione (pin di regressione). Un casinò nuovo eredita il
  croupier **senza toccare il percorso audio**.

**🏢 Fase 1 (M1) completa; Fase 2 (M2) in corso.** Girano end-to-end **tre giochi** in **due
casinò**: al **Riverwood** Texas Hold'em No Limit (Classico/Rapido) e **Five-Card Draw** (Sala
Whiskey); allo **Skypool** Texas (Classico/Rapido) e **Omaha Pot Limit** (Marble). `GameEngine`
contiene **tre motori**, tutti e tre ora con driver, UI e audio (Omaha via lo Skypool). Navigazione
Home → Casinò → Tavolo con gettoni persistenti e barriera economica.

**Slot audio** (stato reale, dettaglio in `Skypool_audio_catalog.md`):
- **Skypool (D-068): file reali PRODOTTI e CABLATI** — croupier 12/14, ambient 4/4, colore-bot
  6/7. Lo Skypool **parla con la sua voce vera** e i bot urbani si sentono. Restano scoperti (col
  fallback): `vo_it_sky_hand_start` (chime→silenzio), `vo_it_sky_pot_limit` (riservato),
  `vob_sky_aggressor_bluff_giveaway_01` (file `aggressor_nervous` ambiguo, non cablato).
- **Storici ancora aperti:** mondo M2 (`amb_home_neutral`, `amb_riverwood_calm_*`,
  `vo_it_high_stakes`, `ui_navigation`), croupier Draw (`vo_it_ante`, `vo_it_draw_phase`,
  `vo_it_pass_and_out`, `vo_it_carried_pot`, `vo_it_openers_disqualified`, `vo_it_high_stakes_draw`),
  e i 2 storici (`amb_crowd_distant`, `fx_hand_neutral`).

**Prossimo passo** (vedi [`ROADMAP.md`](ROADMAP.md)): **calibrazione comparativa** Riverwood↔Skypool
(dopo che l'utente ha giocato entrambi); **produzione dei file audio Skypool** (croupier + ambient +
`vob_sky_*`) e cablaggio delle `vob_sky_*` quando arrivano (oggi silenti); cassa/DLC per ricarica
gettoni; **NPC narrativi**; piscina/discoteca come luoghi. Il **terzo casinò non è anticipato**.
(Il croupier per-casinò — debito D-066 — è **chiuso** in D-067.)

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
catalogo, escluso l'extra; `SoundCatalog` riscritto coi nomi reali (53 voci).
Poi l'utente ha consegnato anche i **4 `tbl_chips_*`** (nomi già corretti),
importati direttamente → **51/53** integrati; restano **2** non consegnati
(`amb_crowd_distant`, `fx_hand_neutral`), silenziosi e loggati (log a runtime:
**2/53 mancanti**).

### D-026 — Primo TestFlight: app record, build number, export compliance (M1.8)
Primo upload TestFlight riuscito (**Lumar Lounge 1.0**). Tre note operative emerse:
- **App record su App Store Connect:** l'upload `altool` fallisce con *"Cannot
  determine the Apple ID from Bundle ID"* finché la app non esiste su App Store
  Connect. `fastlane produce` **non** accetta la API key (vuole Apple ID + 2FA),
  quindi la creazione una-tantum è **manuale** (fatta dall'utente sul sito). Da lì
  in poi la lane `testflight_upload` gira liscia.
- **Build number auto-incrementale:** la lane inietta `CURRENT_PROJECT_VERSION=
  #{Time.now.to_i}` (epoch Unix in secondi) all'archive; nell'`Info.plist`
  `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`. È monotòno crescente, senza stato
  committato, valido come singolo componente fino al 2106. Si **ignora** l'env
  condiviso `SCABO_BUILD_NUMBER` (valore fisso, romperebbe l'auto-incremento).
- **Export compliance:** `ITSAppUsesNonExemptEncryption = false` nell'`Info.plist`
  (l'app non usa crittografia non esente) → niente domanda di conformità a ogni
  build su TestFlight.

### D-027 — Il box Raise è una vera modale d'accessibilità (fix post primo test su device)
Al primo test su iPhone reale è emerso che il box Raise, pur essendo un overlay
visivo, **non isolava VoiceOver**: solo lo sfondo scurito era `accessibilityHidden`,
mentre l'intero tavolo dietro (avversari/board/pot/action bar/hero) restava nell'
albero d'accessibilità. Il lettore poteva quindi navigare fuori dalla finestra e
confondere gli elementi di sfondo con i controlli del box (che ha i suoi
Conferma/Annulla), e gli annunci interrompenti di +/− si perdevano perché il
focus non era mai entrato nella finestra. Correzione, **tutta in `UI`**:
- **Trapping modale** (`PokerTableView`): il contenuto di fondo diventa
  `.accessibilityHidden(true)` quando `raiseBox != nil` **o** `outcome != nil`
  (stesso difetto latente sull'overlay di fine partita, corretto insieme), così i
  soli elementi raggiungibili sono quelli dell'overlay in primo piano.
- **Focus dentro il box** (`RaiseBoxView`): `@AccessibilityFocusState` sul titolo,
  attivato in `onAppear` (deferito un runloop con `DispatchQueue.main.async`
  perché l'elemento esista già nell'albero). All'apertura VoiceOver atterra sul
  titolo, la cui label combina nome della finestra + cifra iniziale ("Rilancio.
  cifra N fiche"), così **la cifra si sente subito senza swipe**. L'annuncio
  separato in `openRaiseBox` è stato rimosso (ridondante). Da lì gli annunci
  interrompenti a priorità alta di +/− (D-020, già presenti) vengono uditi perché
  il focus è ora confinato nel box. Nessuna nuova stringa: `titleA11y` compone le
  chiavi esistenti `raise.title.*` + `raise.value.a11y`.
- **La cifra dei +/− non si sentiva: causa vera = argomento sbagliato**
  (`Announcer`). L'annuncio interrompente costruiva un `AttributedString` **Swift
  grezzo** e lo passava come argomento di `UIAccessibility.post(.announcement)`, che
  invece si aspetta un `NSAttributedString`: iOS non lo riconosceva e lo
  **scartava silenziosamente**, così sull'attivazione del bottone si sentiva solo la
  sua etichetta ("più"/"meno"). Non era timing. Fix: **bridge esplicito**
  `NSAttributedString(attributed)` prima del post; la priorità `.high` sopravvive e
  fa collassare una raffica di tap all'ultimo valore (differimento +0.1s mantenuto
  come rete contro il drop da attivazione).
- **I +/− restano pulsanti VoiceOver "veri"** (`RaiseBoxView`): un tentativo
  intermedio li aveva resi `accessibilityHidden` sostituendoli con un solo elemento
  *adjustable* (swipe su/giù) — **regressione**: VoiceOver non li agganciava più e
  cambiava il gesto. Scartato. Ora −, cifra, +, All-in, Annulla, Conferma sono tutti
  elementi navigabili; **doppio-tap** su +/− cambia il valore e (con il bridging
  sopra) **annuncia il nuovo importo**. La cifra centrale è un `accessibilityElement`
  **leggibile**: label = nome finestra ("Rilancio"/"Punta"), value =
  `announce.raise.value` ("N fiche", **senza** il prefisso "cifra:" che l'utente ha
  chiesto di togliere); il focus all'apertura ci atterra → si sente subito "Rilancio,
  N fiche". Il titolo è `accessibilityHidden` per non ripetere "Rilancio".

### D-028 — Coordinamento audio↔VoiceOver "strategia C": domini separati, mai concorrenti (fix post-M1.8, primo test reale con VoiceOver)
Al primo test su iPhone reale con VoiceOver attivo dall'inizio sono emersi due
sintomi legati: (1) gli annunci VoiceOver si accavallavano in una cascata
incomprensibile; (2) le voci del croupier (`vo_it_`) si sentivano solo sui
primissimi eventi (blind) poi **sparivano** per tutta la sessione, con loro le
voci dei bot.
**Causa reale, verificata nel codice (non solo l'ipotesi):**
- *Croupier che sparisce:* `AudioEngine.play` aveva
  `guard AudioPolicy.shouldPlay(category, voiceOverRunning: isVoiceOverRunning)`
  che, con la strategia **D-024**, **silenziava** croupier e bot ogni volta che
  `UIAccessibility.isVoiceOverRunning` era `true`. I primissimi passavano perché
  quel flag all'avvio ritorna `false` per qualche centinaio di ms (il server
  accessibilità non è ancora agganciato); appena scatta a `true`, tutto il parlato
  taceva **definitivamente**. Non era uno stato inconsistente del player: era la
  policy stessa, per costruzione.
- *Cascata VoiceOver:* `TableViewModel.present()` annunciava **ogni** evento del
  flusso M1.5 (blind, ogni carta del flop una per una, azioni di ogni bot, street,
  showdown, pot…). Senza il metronomo del croupier (silenziato) gli annunci si
  accodavano più in fretta di quanto VoiceOver potesse pronunciarli.
**Perché D-024 era sbagliata:** far *competere* i due sistemi sullo stesso evento
(croupier vs VoiceOver) e risolvere silenziando uno dei due è fragile e, con la
latenza di `isVoiceOverRunning`, incoerente. **Strategia C (scelta dall'utente):**
niente concorrenza, **domini separati**.
- **Il croupier suona SEMPRE** (a prescindere da VoiceOver) per i soli **eventi
  istituzionali**: hand start, blind, flop/turn/river, showdown, assegnazione pot.
  Ben distanziati, non affaticano. Rimosso del tutto `AudioPolicy` e il rilevamento
  VoiceOver da `AudioEngine`.
- **Le voci dei bot** (`vob_`) restano occasionali e probabilistiche, sempre attive.
- **Le azioni** (fold/call/raise/check) **non** sono più annunciate né dal croupier
  (rimosse le `vo_it_action_*` da `AudioScore.actionCues`/`allInCues`) né da
  VoiceOver: bastano il suono fisico (fiche/muck) e l'eventuale `vob_`. Meno rumore
  ripetitivo. L'azione resta comunque visibile a schermo.
- **VoiceOver** si concentra sul **personale**: proprie hole card, proprio turno
  ("è il tuo turno…"), **conferma della propria azione** (nuovo: "fai reis a N"),
  esito dal proprio punto di vista (proprio pot vinto, win/lose finale). Le carte
  comuni non annunciate automaticamente restano leggibili **on-demand** dall'elemento
  `table.board`, quindi "nessuno perde niente".
- **Ripulitura mappatura:** `TableAnnouncer.spoken(for:heroSeatID:)` è ora l'autorità
  pura e testabile: ritorna un `SpokenEvent` **solo** per i tre momenti personali
  dell'umano (hole card, propria azione, proprio pot), `nil` per tutto il resto.
- **Coordinamento temporale (semplice, una direzione):** quando croupier e VoiceOver
  cadono vicini, **VoiceOver aspetta** la fine della voce in corso. `AudioEngine`
  espone `spokenAudioRemaining()` (max tempo residuo dei player parlati, via
  `duration - currentTime`); `SpeechCoordinator.voiceOverDelay(spokenRemaining:)`
  (puro, testabile) aggiunge un piccolo gap; `Announcer.announce(..., after:)`
  ritarda il post di conseguenza. Il croupier è il metronomo, VoiceOver gli cede il
  passo — mai il contrario, per semplicità.
**Vincoli rispettati:** nessuna modifica a `GameEngine`/`SessionDriver`/flusso M1.5;
cambi solo in `UI` (annunci) e `Audio` (riproduzione/coordinamento); nessuna nuova
dipendenza. **D-024 è superata da questa voce.**

### D-029 — Mappatura autorevole evento→sorgente vocale + fix "disco rotto" (secondo test reale, raffina D-028)
Il secondo test su iPhone ha mostrato che D-028, pur giusta nei principi, era ancora
approssimativa: annunci VoiceOver ancora sovrapposti, e soprattutto **voci ripetute
in loop** (in particolare `vo_it_pot_awarded` 3-4 volte back-to-back), e VoiceOver
che sintetizzava cose per cui **esiste già un mp3** (grave: "è il tuo turno" a sintesi
invece di `vo_it_your_turn.mp3`). Radice: la mappatura evento→mp3 e evento→sintesi
erano ancora costruite **separatamente**, senza una fonte di verità unica.
**Nuova architettura — una sola tabella, due layer parlanti disgiunti:**
- **`SpeechMap` (puro, fonte di verità, D-029):** `plan(for:heroSeatID:names:)`
  ritorna per ogni evento un `SpeechPlan` = (croupier `SoundID?`, `SynthLine?`).
  È la tabella autorevole: chi parla ogni momento. Reso in stringa da `text(for:)`
  (testabile senza localizzazione). Ha sostituito `TableAnnouncer`.
- **`SpeechConductor` (MainActor, seriale):** unico proprietario dei DUE sistemi
  parlanti (mp3 croupier + sintesi VoiceOver). Riproduce un item per volta: prima
  l'mp3 croupier (attesa **completion reale** via `AVAudioPlayerDelegate`, non un
  ritardo fisso), poi la sintesi. Così "flop" (mp3) → carte del flop (sintesi) è in
  ordine garantito, e i due non si sovrappongono mai.
- **Fix del disco rotto — causa reale trovata:** `SessionDriver` emette **un
  `potAwarded` per pot** (`result.pots.enumerated()`); una mano con side pot ne
  emette 3-4 (verificato: nel log dei suoni anche una mano semplice ne emette 2).
  Ogni evento mappava `vo_it_pot_awarded` → il croupier lo diceva N volte. Fix
  **alla radice del layer audio**: il conductor **de-duplica once-per-hand** le voci
  {showdown, pot, split} (reset a `handBegan`), così suonano **una sola volta**;
  ogni evento mantiene la sua sintesi specifica. Non si tocca `GameWorld` (il flusso
  è corretto per gli altri consumatori; consolidare i pot è fuori scopo audio).
  Test: `SpeechConductorTests` prova 3 `potAwarded` → 1 sola riproduzione.
- **"È il tuo turno" ora è l'mp3:** il turno umano riproduce `vo_it_your_turn.mp3`;
  la sintesi aggiunge il **solo** contesto "per chiamare X, pot Y" e **solo** se
  `toCall>0` (check libero → solo mp3). Niente più sintesi ridondante.
- **Sintesi = solo ciò che l'mp3 non può pre-registrare:** proprie carte, contenuto
  di flop/turn/river (dopo il croupier), mani allo showdown ("giocatore 2: …"),
  conclusione pot ("hai vinto con doppia coppia" — categoria presa dallo showdown
  tracciato), fine sessione. L'**azione confermata dell'umano non è più annunciata**
  (correzione di D-028): ci sono i suoni fisici.
- **Layer non-parlato separato e potato:** `AudioScore` (puro) ora emette **solo**
  suoni fisici/effetti, **nessun croupier** (spostato nel conductor) e nessuna voce
  bot. `AudioDirector` (spectator) fa: fisici, effetti (win/lose/bust/all-in),
  **ambient dinamico** (crossfade calm↔`tense` su all-in in gioco; duck +
  `amb_silence_tension` allo showdown; ritorno a calm dopo il pot; layer continuo
  `amb_crowd_distant`), e **voci bot** deterministiche per carattere (novice
  eccitato/deluso/nervoso, rock grunt raro ~10%, aggressor confident/taunt ~22%) con
  **anti-ripetizione** (mai due azioni consecutive dello stesso bot) e seed → sequenza
  riproducibile.
- **Audio: completion + ambient dinamico.** `AudioServicing`/`AudioEngine` ora
  espongono `play(_:category:completion:)` (via delegate; completion immediata se
  file mancante/muto, così una sequenza avanza sempre), `crossfadeAmbient`,
  `startAmbientLayer`, `setAmbientScale`. `AudioEngine` è ora `NSObject` +
  `AVAudioPlayerDelegate`.
**Principio permanente (in CONVENTIONS §4):** con più sorgenti vocali definire per
ogni evento **una sola** sorgente responsabile, mai due che dicono la stessa cosa.
**Vincoli:** solo `UI` + `Audio`, nessuna modifica a `GameEngine`/`SessionDriver`/
flusso M1.5, nessuna dipendenza nuova. 132 test verdi. **Raffina/estende D-028.**

### D-030 — Pattern generale: fallback mp3-mancante → sintesi VoiceOver (terzo test reale)
Introdotto col caso del ruolo "button" (mp3 non ancora prodotto) ma pensato come
**capacità riusabile**: il progetto produrrà voci **gradualmente** (croupier dei
casinò più sfarzosi, nuove personalità di bot). Regola: quando la mappatura chiede
di riprodurre un mp3 che **non è nel bundle** (o non caricabile), il sistema **non**
tace silenziosamente ma cade su un **fallback di sintesi VoiceOver dichiarato nella
mappatura stessa**. Quando il file verrà depositato, il sistema lo rileva e usa
l'mp3, silenziando il fallback — **produzione audio incrementale senza rompere
l'esperienza**. Implementazione: `AudioServicing.isAvailable(_:)` (in `AudioEngine`
= presenza nel bundle); `SpeechPlan.croupierFallback: SynthLine?` dichiara il testo;
il `SpeechConductor`, nel processare un lead, se `!isAvailable` e c'è un fallback
**sintetizza il fallback** invece dell'mp3. Catalogo: aggiunto `vo_it_role_button`
(non consegnato → compare nel log dei mancanti; coperto dal fallback "sei sul
bàtton"). Testato in presenza (mp3 suona, fallback tace) e assenza (mp3 tace,
fallback parla). Diagnostica di supporto: `AudioEngine.playbackLogging` (DEBUG) logga
ogni riproduzione reale (file+timestamp) e `SpeechConductor.logging` (DEBUG) logga
enqueue+motivo+verdetto-dedup; un self-check all'avvio verifica che le voci critiche
(`vo_it_your_turn`/`hand_start`/`pot_awarded`) siano presenti **e caricabili**.

### D-031 — Annuncio di ruolo personale + riempimento acustico degli avversari (terzo test reale)
Due cambi di mappatura dopo il test su iPhone, più i due bug residui.
- **Annuncio di ruolo (sostituisce i blind generici):** l'annuncio a inizio mano
  "small blind, big blind" astratto era inutile e disorientante. Ora, a inizio mano,
  il croupier annuncia **solo il ruolo del giocatore umano** se ne ha uno
  (`SpeechMap.roleAnnouncement`): SB→`vo_it_blind_small`, BB→`vo_it_blind_big`,
  button→`vo_it_role_button` (fallback D-030 "sei sul bàtton"); **nessun ruolo →
  silenzio**. Principio: il croupier parla solo se ha qualcosa da dire *a chi
  ascolta*. `plan(.blindPosted)` è ora `.silent`.
- **Vuoto acustico degli avversari riempito:** le azioni dei bot erano mute (solo
  fisici). Ora ogni azione avversaria ha una **sintesi** attribuita col **numero di
  seat visibile** (non il nome caratteriale): "giocatore N foulda/passa/chiama/
  rilancia a X/va ol-in". L'all-in avversario resta croupier `vo_it_action_all_in`
  **poi** la sintesi di attribuzione. Le `vob_` restano rare (probabilità invariata):
  il vuoto si riempie con le sintesi, non con più voci bot. **Ordine vob→sintesi:**
  la decisione della `vob_` per l'azione è passata da `AudioDirector` a `BotChatter`
  (deterministico, anti-ripetizione) così present() la dà al conductor come **lead**
  prima della sintesi → la `vob_` (colore emotivo) suona, poi la sintesi (info
  precisa). Se la probabilità non sceglie la `vob_`, la sintesi parte subito.
- **Bug pot sdoppiato — causa reale:** `PotMath.sidePots` crea un pot **per livello
  di contribuzione**; anche una mano SB/BB non contesa genera **2 pot** (SB 10, BB
  20). L'mp3 `vo_it_pot_awarded` era già deduplicato (1×), ma la **sintesi di
  conclusione** era accodata **per ogni `potAwarded`** → si ripeteva. Non è un bug di
  GameWorld (matematica corretta). Fix: la conclusione del pot è ora **once-per-hand**
  (guardia `potAnnounced` in present, reset a `handBegan`); l'mp3 lo era già. Test di
  regressione: 3 `potAwarded` → mp3 **e** sintesi **una volta**.
- **Bug turno via sintesi — causa reale:** `vo_it_your_turn.mp3` è nel bundle e
  richiesto correttamente; non esiste alcuna sintesi "è il tuo turno" (le vecchie
  chiavi `announce.your.turn.call/check` erano morte). Era **timing**: la coda
  seriale del conductor, occupata dagli mp3 lenti di hand-start + blind generici,
  faceva partire il turno in ritardo (dopo l'azione umana), lasciando udibile solo la
  sintesi di contesto. Fix: rimossi i blind generici (coda più corta) + il cue del
  turno è **time-critical** → `conductor.flushPending()` scarta la narrazione
  stantia prima di dire il turno. Test: il turno richiede l'mp3 e **non** sintetizza
  la frase del turno.
**Vincoli:** solo `UI` + `Audio`, nessuna modifica a `GameEngine`/`SessionDriver`/
flusso. 143 test verdi. **Estende D-029.**

### D-032 — Coda seriale degli annunci VoiceOver, trasversale a tutto il progetto (Strategia C, dai dati)
Al quarto test reale il croupier era ottimo, ma la **sintesi VoiceOver** si
accavallava: `UIAccessibility.post(.announcement)` di default **interrompe** l'annuncio
precedente, quindi in raffica (dopo il flop, o azioni rapide dei bot) i primi venivano
troncati e passava intero solo l'ultimo. Problema **strutturale e generale** (non del
poker): riguarda ogni parte parlata, presente e futura (blackjack, roulette). Serve
**infrastruttura riusabile**, non una pezza locale.
**Decisione A vs C, presa dai numeri.** Prima di implementare ho strumentato una
**simulazione** di 8 mani (`AnnouncementBurstAnalysisTests`), modellando ogni sintesi
col suo tempo di parlato e una tassonomia di priorità. Risultati: **80** annunci, di
cui **high=1, medium=63 (azioni avversari), low=16 (carte)**; **saturazione 147%** —
154 s di parlato in una sessione di 105 s — mentre l'**high da solo è il 2%**. Sotto
FIFO stretta (strada A) l'audio andrebbe **fino a ~50 s in ritardo** (profondità coda
28). → **Scelta: Strategia C.** A è impraticabile (il canale seriale è saturato da
medium/low); C tiene gli annunci **personali (high) sempre puntuali** droppando
low/medium quando la coda si accumula.
**Infrastruttura — `AnnouncementQueue` (UI, `@MainActor`, game-agnostica).** È l'**unico**
punto che chiama `UIAccessibility.post` in tutto il codice applicativo (guard di test
statico che scandisce `UI/*.swift`). API: `enqueue(_ text, priority)` (serial),
`announceLiveValue(_)` (l'unica interruzione deliberata, per il box Raise: i +/-
rapidi collassano all'ultimo valore), `flushPending()` (per il turno). Regole:
- **Niente troncamenti:** un annuncio iniziato finisce sempre; i nuovi vanno in coda.
- **Priorità + drop (C):** high mai droppato e **bumpato** in testa; low poi medium
  droppati quando il backlog dei soli *in attesa* supera ~2 s (la testa non si droppa
  mai, così un annuncio singolo, per quanto lungo, parte sempre — bug scoperto e
  corretto in fase di test).
- **Completamento reale:** si ascolta `announcementDidFinishNotification` per far
  partire il successivo; **tetto** = tempo stimato + 1 s di pausa max come fallback se
  la notifica non arriva (VoiceOver off → avanza subito).
**Coordinamento col croupier (un unico canale parlato).** La `SpeechConductor` non
usa più un `announcer` diretto: la sua **sintesi** va sulla coda; il suo **mp3
croupier** è suonato con `queue.beginExternalSpeech()`/`endExternalSpeech()`, che
**tengono ferma** la coda mentre l'mp3 suona e la fanno **aspettare** la fine di un
annuncio in corso prima di partire. Croupier e sintesi si comportano come **un solo
canale**, mai in parallelo. La sintesi è consegnata alla coda *fire-and-forget*, così
una raffica (azioni avversari) atterra lì e la coda applica priorità+drop senza mai
bloccare il conductor.
**Log:** un unico flag `SpokenLog.enabled` (DEBUG, nel modulo `Audio`) copre engine,
conductor e coda (post, drop, cap-advance); `AudioEngine.playbackLogging` e
`SpeechConductor.logging` sono confluiti lì. `Announcer` è stato **rimosso** (assorbito
dalla coda).
**Vincoli:** solo `UI` + `Audio`, nessuna modifica a `GameEngine`/`SessionDriver`/
flusso; nessuna dipendenza nuova. 146 test verdi (nuovi: ordine senza troncamento,
raffica di 5 con drop di low/medium e high preservati, bump high, tetto 1 s, blocco
reciproco col croupier, guard statico anti-post-diretto). **Estende D-029..D-031.**

### D-033 — Chrome persistente e schermata impostazioni riusabili
Serviva un pulsante di **impostazioni permanente** al tavolo, ma pensato per **tutto
il progetto** (menu, casinò, accesso futuri), non specifico al poker. Introdotto un
**contenitore di chrome condiviso** `GameChrome<Content>` (UI): una shell che avvolge
qualunque schermata principale e ospita una **top bar** con il pulsante Impostazioni
in alto a destra e presenta la schermata impostazioni (`.sheet`). La top bar **riserva
la propria striscia**, così il pulsante non si sovrappone al contenuto (i bollini
avversari sono ora sotto la barra, non coperti). Il pulsante è pienamente accessibile:
label "Impostazioni" (niente fonetica), hint, identifier `settings.button`, tap target
44×44, alto contrasto. `PokerTableView` avvolge `TableScreen` in `GameChrome`; lo sfondo
del tavolo è passato al chrome. La `SettingsView` è una **schermata riusabile** (List a
sezioni con `NavigationStack` + Done) progettata per **crescere**: oggi una sola voce,
domani molte. Navigabile da VoiceOver dall'alto in basso. Per ora contiene lo switch
"Modalità VoiceOver dell'app" (vedi D-034).

### D-034 — Modalità VoiceOver dell'app (indipendente da iOS) e ritmo visivo adattivo
Dopo il fix della coda annunci, l'utente ha notato uno **sfasamento occhio-orecchio**:
a fine mano la sintesi annuncia ancora il vincitore mentre visivamente sono già uscite
le carte della mano dopo. Causa: il produttore `SessionDriver` emette a velocità di
codice, la UI mostra a ritmo umano, ma la sintesi non ha finito di parlare del passato.
**Direzione (invariata la purezza del produttore):** la sincronizzazione è **solo lato
consumatore** in `UI`; `SessionDriver` **non si tocca** (CONVENTIONS).
- **`AppVoiceOverMode`** (UI, `ObservableObject`): lo stato **osservabile** della
  modalità VoiceOver *dell'app*, **indipendente** da iOS. Default **OFF**. Persistito
  in `UserDefaults` (store iniettabile per i test), ripristinato all'avvio. Vive
  **sopra** il confine di restart (`@StateObject` in `PokerTableView`), così sopravvive
  a una nuova partita.
- **Ritmo adattivo (ON):** il `TableViewModel`, dopo aver mostrato un evento e
  consegnato i suoi annunci, **attende che il canale parlato sia quieto**
  (`conductor.isIdle && announcements.isQuiet`) prima del prossimo evento →
  "un evento visualizzato per ogni annuncio completato". Eventi **senza** annuncio
  passano subito (il canale resta quieto). Il canale parlato include **croupier + coda
  sintesi**: la UI aspetta la combinazione dei due (già serializzati in D-032), non solo
  la sintesi. In ON la coda non accumula backlog (la UI aspetta a ogni passo), quindi
  **nessun drop**: tutti gli annunci sono detti, il ritmo è più lento ma sincrono.
- **Ritmo interno (OFF):** invariato, veloce e fluido (pause umane); il croupier suona
  come effetto **non bloccante**, la UI non lo aspetta; la coda droppa sotto backlog
  come da D-032.
- **Doppia indipendenza da iOS VoiceOver (rispettata):** *(a)* iOS ON + app OFF → la UI
  non attende, gli annunci sono postati normalmente (VoiceOver li legge a modo suo).
  *(b)* iOS OFF + app ON → la coda **simula** le durate (`AnnouncementQueue.pacedWhenSilent`,
  = tempo stimato per annuncio anche se nessuno ascolta) e la UI si adegua al ritmo
  teorico. È esplicitamente la libertà che l'utente ha chiesto.
- **Cambio di modalità mid-game: EFFETTO IMMEDIATO.** Motivazione dai fatti del codice:
  il ritmo è letto **per-evento** in `pace()`; il toggle non tocca lo stato di gioco
  (riduzione + annunci invariati), cambia **solo la tempistica** del prossimo evento →
  **nessuno stato inconsistente mid-hand**. Passando a ON mid-mano la UI semplicemente
  **aspetta** che l'audio recuperi il backlog e poi si sincronizza; passando a OFF
  smette di aspettare. Non serve rimandare alla partita successiva.
- **Log:** `SpokenLog` traccia ogni evento visualizzato con timestamp e modalità.
**Vincoli:** solo `UI`, nessuna modifica a `GameEngine`/`SessionDriver`/`Audio`(salvo
`AnnouncementQueue`); nessuna dipendenza nuova. 157 test verdi + 1 XCUITest impostazioni.

### D-035 — Struttura di navigazione a tre livelli: Home → Casinò → Tavolo (M2.1)
L'app non apre più direttamente sul tavolo: entra su **Home**. Tre livelli espliciti,
spina dorsale di tutto il progetto: **Home** (scelta del casinò) → **Casinò**
(Riverwood, scelta del tavolo) → **Tavolo** (il gioco). Stato di navigazione + saldo
in un `AppState` (`ObservableObject`) al livello app; navigazione **guidata da stato**
(`enum Screen`), non `NavigationStack`, per **pieno controllo del chrome** e
testabilità (transizioni animate, focus/ordine VoiceOver prevedibili). Nuovo entry
point `AppRootView` (l'app usa questo, non più `PokerTableView`, rimosso). **`GameChrome`**
(D-033) avvolge **ogni** schermata: top bar con azione leading opzionale (indietro /
lascia tavolo) + pulsante Impostazioni sempre presente, e riga saldo gettoni (Home/
Casinò). **Riverwood Casinò**: primo casinò, estetica rustica di frontiera resa con
palette scura, feltro desaturato, accenti ottone e **tipografia serif** (SwiftUI puro,
nessuna texture — gli asset arriveranno dopo). Lista tavoli: Classico (buy-in 1000),
Rapido (buy-in 1000), Five-Card Draw "Sala Whiskey" **visibile ma non entrabile** ("In
arrivo", letto da VoiceOver come non disponibile). Home elenca Riverwood + placeholder
"In arrivo" (Velvet Palace, Aurea Lounge). Ogni riga tavolo è un blocco VoiceOver unico
("Tavolo … buy-in … posti liberi. Tocca per sederti."). Config tavolo via `TableRules`
(GameWorld); il `TableViewModel` è ora parametrizzato (blind, personalità, buy-in come
stack). `SessionDriver` **non modificato strutturalmente** (usa i suoi entry di config).

### D-036 — Gettoni persistenti in GameWorld, distinti dalle fiches al tavolo (M2.1)
Nuovo tipo `PlayerAccount` (GameWorld): il conto **gettoni** del giocatore, valuta
**esterna** al tavolo, **persistita** (`ChipsStore` protocollo iniettabile →
`UserDefaultsChipsStore`, `InMemoryChipsStore` per test/UI-test). Prima esecuzione: 5000
gettoni, salvati e ripristinati. Le **fiches** restano valuta **effimera** che vive solo
al tavolo. Flusso: **buy-in** sottrae gettoni → diventano fiches iniziali (stack);
**alzarsi** riconverte le fiches rimaste in gettoni; **bust** riconverte 0. Buy-in
possibile solo se coperto, altrimenti la riga è disabilitata e VoiceOver dice "gettoni
insufficienti". Nessuna ricarica in M2.1 (arriverà la cassa/DLC). UI: `AppState` fa da
specchio osservabile del conto; saldo mostrato in Home/Casinò; al tavolo si vede lo
stack di fiches. **Lascia il tavolo**: pulsante nel tavolo; la mano corrente finisce
regolarmente (nessun abbandono mid-hand), poi ritorno al Riverwood con cash-out;
immediato se già bustato. Vittoria/bust di sessione → ritorno al Riverwood col cash-out
(overlay con "Torna al Riverwood"). **Semplificazione documentata:** per il gate
produttore-consumatore, "lascia" può richiedere la fine di **una** mano ancora prodotta
(il produttore è al più una mano avanti).

### D-037 — Boost "mano decisiva" nel tavolo Rapido: meccanica narrativa trasparente (M2.1)
Il tavolo **Rapido** ha bot **più aggressivi** (personalità in `WorldPersonalities.fast`:
aggression/bluff/risk alzate, tightness abbassata, rationality moderata così non sono
stupidi — definite in **GameWorld**, il motore le riceve, non le decide) e il **boost
mano decisiva**: dopo **3 mani consecutive senza fold pre-flop**, la mano successiva è
**decisiva** — il croupier la annuncia (`vo_it_high_stakes`, non ancora consegnato →
**fallback di sintesi** "mano decisiva", D-030), l'ambient passa a `amb_lounge_tense_01`,
e le **blind raddoppiano** per quella singola mano; poi si torna al ritmo normale. È
**trasparente** (il giocatore lo capisce e lo aspetta). Architettura: componente
osservabile/testabile `DecisiveHandBoost` (GameWorld) col contatore; il rilevamento
"fold pre-flop" è tracciato dal consumatore (`present`) e alimenta il boost a fine mano,
**prima** del rilascio del gate, così il produttore vede lo streak aggiornato; la mano
decisiva usa l'**override additivo** `SessionDriver.playHand(overrideSmallBlind:
overrideBigBlind:)` — nessuna modifica strutturale al driver. Il `present` rileva la mano
decisiva dai blind raddoppiati nell'evento `handBegan` (niente flag condiviso), l'
`AudioDirector` idem per l'ambient (riceve il big blind base). 174 test verdi (+ XCUITest
navigazione): gettoni (buy-in/cash-out/bust/insufficiente/persistenza), boost, raddoppio
blind via override, personalità Rapide più aggressive (caratterizzazione). **Chiude
M1, apre M2.**

### D-038 — Secondo motore di gioco (Five-Card Draw) parallelo e indipendente dal Texas (M1.9)
Il Five-Card Draw è il **secondo motore** del progetto e vive **interamente** in
`GameEngine`, in una sottocartella dedicata `Draw/` (i file del Texas restano flat:
scelta **non invasiva**, nessun refactoring dell'esistente). I due motori sono
**paralleli e indipendenti**: nessun `import` incrociato, **nessun tipo di regole
condiviso**. Ciò che condividono è **solo** (a) i tipi fondazionali di M1.1
(`Card`/`Rank`/`Suit`/`Deck`/`HandEvaluator`) e (b) l'**aritmetica dei chip
game-agnostica** `PotMath`/`Pot`, che è matematica pura dei pot (side pot, chip di
resto), **non** regole del Texas — riusarla è esplicitamente ammesso e la tiene DRY.
Perciò il Draw definisce i **propri** tipi speculari (`DrawSeat`/`DrawSeatState`/
`DrawAction`/`DrawResult`/`DrawLegalActions`/`DrawPhase`/`DrawOptions`) e **non** riusa
`Seat`/`Action`/… del Texas (che sono M1.2, non fondazionali). `FiveCardDrawHand` è,
come `HoldemHand`, un value type con transizioni `mutating`, sincrono e deterministico
via seed. **Estensione additiva di `Personality`:** tre nuovi dial specifici del draw
(`drawDiscipline`/`drawBluffiness`/`openingDiscipline`) aggiunti **con valori di
default** nell'initializer, così tutti i call site esistenti (incl. `WorldPersonalities`
in GameWorld) compilano invariati e il Texas — che non li legge — non cambia
comportamento. **Nome scelto:** `FiveCardDrawHand` (esteso, non ambiguo). Solo
`GameEngine`, solo Foundation.

### D-039 — Jacks-or-better sull'onore + openers verificati allo showdown (M1.9)
La regola di apertura è la parte più delicata. Due letture nella traccia
sembravano in tensione ("bet senza openings validi rifiutato" vs "apre bluffando
senza jack, perde d'ufficio"): la seconda è **impossibile** se l'apertura è bloccata
a monte. Scelta, **fedele al jackpot poker tradizionale**: l'apertura è **sull'onore**.
Chiunque può fare fisicamente il primo bet (`legalActions.canBet` non richiede i
jack); `legalActions.hasOpeners` espone se il seat **potrebbe** dimostrarli, come
guida per deciso­ri corretti. Al momento dell'apertura il motore **snapshotta** gli
`openers` (le due carte della coppia jacks-or-better, o l'intera combinazione
superiore) — `nil` se ha aperto **su aria**. Enforcement allo **showdown**: se
l'apritore arriva allo showdown e ha `openers == nil`, è **squalificato** e **perde
d'ufficio** comunque sia la sua mano finale; le sue fiches **restano nel pot** e sono
vinte normalmente dagli altri (fallback: un pot rimasto senza aventi diritto va alla
miglior mano viva non squalificata, così nessuna fiche svanisce). **Ma** se tutti
foldano prima dello showdown (bluff riuscito), **nessuna prova è richiesta e
l'apritore vince**: è ciò che rende sensato il dial `openingDiscipline` — aprire
leggeri è un **rischio**, non un divieto. Gli openers sono conservati **anche se
scartati nel draw**. Questo riconcilia entrambe le richieste della traccia e rende
costruibile il test "openers negativo". Le azioni realmente illegali (check di fronte
a un bet, raise oltre il cap, call/raise senza nulla da chiamare/rilanciare, azione a
mano finita, draw fuori fase, scarto >4 o carta non posseduta) restano rifiutate.

### D-040 — Pass-and-out con pot progressivo (variante B): la mano pura gestisce un solo giro (M1.9)
Il pot progressivo delle mani annullate è un concetto **fra le mani**, non di una
singola mano pura. Perciò `FiveCardDrawHand` gestisce **un solo giro di
distribuzione**: se il primo giro di puntata si chiude **senza apertura**
(`currentBet == 0`), la mano è **nulla** — esito `.passedIn` — ed espone
`carriedPot` = ante di questa mano + eventuale pot già portato. Il pot progressivo
vive **fuori** (nel futuro driver di GameWorld), che riceve `carriedPot`, rimescola
e ridistribuisce passando quel valore come parametro `carryPot: Int` alla mano
successiva. Il `carryPot` è **dead money**: entra nella mano, si fonde nel main pot
al finish, e viene vinto normalmente quando la mano si gioca davvero. Il **button
non ruota** sulle mani annullate (`nextButtonIndex` è per le mani *giocate*; la
rotazione la decide comunque il driver, come per il Texas D-006/D-012). Caso limite
documentato: se tutti sono all-in sull'ante (nessuno **può** aprire) la mano **non**
è passed-in ma va a draw+showdown (nessuna apertura da declinare); la gestione di
seat bustati/assenti resta un compito del driver.

### D-041 — Betting limit a due giri, draw a turni, euristiche di scarto pure (M1.9)
Struttura di puntata **limit** (non No Limit come il Texas), quindi le `DrawAction`
**non portano importo**: `bet`/`raise` valgono un'unità fissa (small bet nel primo
giro, big bet = parametro nel secondo), `call`/`check`/`fold` come di consueto.
**Cap** a quattro escalation per giro (`aggressiveCount < 4`: bet + raise + re-raise
+ cap, poi solo call/fold); un all-in corto sotto una raise piena **non riapre**
l'azione, come nel Texas. Il **draw** è a **turni, un seat alla volta** a sinistra
del button (`drawingSeatID` + `drawOptions()` + `discard(_ cards:)`), scartando
**0–4** carte per valore (validate come sottoinsieme della mano); i rimpiazzi
vengono dalla cima del mazzo (gli scarti non rientrano — con ≤7 seat il mazzo non si
esaurisce mai). Le carte di ogni seat sono tenute **ordinate** (rank desc). I **bot**
del Draw (`HeuristicDrawBot`) decidono **puntata** e **scarto** su informazione onesta
(`DrawBotContext`/`DrawDrawContext`: proprie 5 carte + stato pubblico, incluso il n°
di carte cambiate dagli avversari — pubblico dopo il draw). L'euristica di scarto
"da manuale" è isolata in `DrawStrategy` (**pura e testabile**: stand pat sui punti
fatti, tieni la coppia/il tris, pesca a four-flush/four-straight), poi **modulata**
dai tre dial (D-038): `drawDiscipline` (quanto segue il manuale), `drawBluffiness`
(stand pat / short-draw per fingere forza), `openingDiscipline` (se bluff-apre su
aria). Determinismo via `SeededGenerator` come il bot Hold'em. 31 unit test (99 nel
modulo, 205 nel package), tutti verdi.

### D-042 — `DrawSessionDriver` in GameWorld: driver dedicato, riuso mirato senza astrazioni forzate (M2.4)
Il Five-Card Draw giocabile ha bisogno di un **driver di sessione proprio**,
`DrawSessionDriver`, **speculare** al `SessionDriver` del Texas ma **indipendente**:
il driver Texas **non è toccato**. Dove il Texas ha già risolto un problema
architetturale ne **riuso la forma provata** (anello a capacità fissa, dead button,
fan-out eventi via actor, cambi strutturali solo tra le mani, `HandGate` in UI), ma
**non i tipi**: i tipi del Draw sono dedicati (`DrawSessionPlayer`,
`DrawSeatAssignment`, `DrawHandOutcome`, `DrawSessionError`, `DrawActionProvider`)
perché le regole differiscono abbastanza (ante, due giri limit, draw, pass-and-out)
che condividere un'astrazione aggiungerebbe rigidità, non valore. **La coerenza
esteriore per l'utente conta più della fattorizzazione interna** (principio di
sessione). Novità rispetto al Texas: **due sospensioni** del provider umano
(`HumanDrawActionProvider`: `provideAction` per la puntata e `provideDiscards` per lo
scambio, nettamente separate — solo una pendente per volta); il **pot progressivo**
orchestrato esplicitamente (tra una mano annullata e la successiva il driver conserva
il `carriedPot` esposto dal motore e lo passa come `carryPot`; **il button NON ruota**
e il contatore delle mani giocate non avanza sulle mani annullate, D-040); un seme
per-deal monotòno così anche le ri-distribuzioni delle mani passate rimescolano.
`playHand()` gioca **una sola** distribuzione (che può essere passata: `wasPlayed=false`),
emette i suoi eventi e ritorna; il consumatore la narra (incluso il messaggio di
pass-and-out) e rilascia il gate — stesso ritmo del Texas. Cliente puro del motore,
deterministico, fiches conservate (invariante testato: `Σstack + carriedPot`
costante). 6 unit test.

### D-043 — Flusso eventi del Draw distinto ma sulla stessa infrastruttura EventHub (M2.4)
Il driver del Draw **narra** con una **tassonomia di eventi propria**,
`DrawSessionEvent`/`DrawEventPayload`, **non unificata** con `SessionEvent` del Texas:
sono giochi con vocabolari diversi (ante, apertura, pass-and-out, draw con conteggio
scarti, openers, pot progressivo), e forzare un tipo comune sarebbe fragile. Riusa
**solo** i tipi game-agnostici `EventAudience`/`EventViewer` (instradamento pubblico/
privato, D-015). L'attore di fan-out è un `DrawEventHub` speculare a `EventHub` —
**piccola duplicazione consapevole** invece di un generico forzato sui due tipi
(coerente con D-042), che lascia il Texas intatto. Pubblico/privato come D-015: le
proprie cinque carte iniziali e le carte pescate al draw sono **strettamente private**
(audience `.player(id)`); tutto il resto pubblico (incluso **quante** carte cambia
ogni avversario — informazione pubblica dopo il draw, non **quali**). Copertura:
ordine canonico di una mano giocata, di un pass-and-out, e di una squalifica per
openers; routing pubblico/privato; determinismo. 4 unit test.

### D-044 — UI del tavolo Draw: box modale dedicato per lo scambio, doppio segnale di selezione (M2.4)
La UII del Draw (`DrawTableView` + `DrawTableViewModel` + `DrawTableReducer`/
`DrawTableState`, il tutto avvolto da `GameChrome`) è **speculare** a quella del Texas
ma dedicata, con **stato e riduzione puri** propri (cinque carte dell'umano, niente
board, macchina a fasi firstBet→draw→secondBet, pot progressivo, conteggio scarti per
posto, squalifica openers). **Riusa** l'infrastruttura trasversale **così com'è**:
`GameChrome`, `AnnouncementQueue`, `SpeechConductor`, `AppVoiceOverMode` + ritmo
adattivo (D-034), `CardView` (esteso **additivamente** con misure `medium`/`huge`),
`HandGate`, `EndOverlay`, `GameOutcome`. **Betting limit:** barra Fold/Check-Call/Bet/
Raise con **importi fissi nel testo** ("Bet 20", "Raise 40"), **nessun box di rilancio
progressivo**; il Bet resta attivo anche senza openers (apertura sull'onore, D-039), il
Raise si disabilita al raggiungimento del cap. **Principio nuovo (in CONVENTIONS §4):**
quando un gioco introduce una **fase che il primo gioco non aveva** (qui il draw),
l'interazione dedicata a quella fase vive in un **box modale con la propria trappola di
accessibilità**, non nel layout principale del tavolo. Il `DrawBoxView`: cinque carte
grandi selezionabili al tap, **doppio segnale visivo** per ogni selezione (bordo ottone
brillante **e** mark scuro con X sulla faccia, così chi ha problemi visivi ne coglie
almeno uno); ogni carta è un **pulsante VoiceOver** con label esplicita di rango, seme
e stato ("asso di picche, selezionato per lo scarto"), e il tap **annuncia** il nuovo
stato via `announceLiveValue` (interruzione deliberata, come i +/- del box Raise); un
contatore ("N carte da scartare") e un **Conferma sempre attivo** (0 selezioni = "stai
pat"); **nessun Annulla** (deselezionare tutto equivale). Il quinto tap è rifiutato con
annuncio "non puoi scartare più di quattro carte". È una **vera modale d'accessibilità**
(D-027): sfondo `accessibilityHidden`, focus portato dentro all'apertura, ordine di
lettura carte→contatore→conferma. La **sincronizzazione del turno umano** (D-021) è
estesa alle **due** sospensioni: la barra puntate appare quando il provider attende una
puntata, il box quando attende uno scambio. **Layer parlato** (`DrawSpeechMap`, autorità
pura come D-029) e **non parlato** (`DrawAudioScore`/`DrawAudioDirector`) dedicati:
croupier riusato dove serve (turno, all-in, showdown, pot) + **cinque nuovi slot**
`vo_it_ante`/`vo_it_draw_phase`/`vo_it_pass_and_out`/`vo_it_carried_pot`/
`vo_it_openers_disqualified` **non ancora prodotti → fallback di sintesi** (D-030);
sintesi per proprie carte iniziali/pescate, scarti degli avversari ("giocatore N scarta
X carte"), pot progressivo, squalifica, conclusione. Ambient Riverwood (fallback lounge)
che passa a **teso** quando il pot progressivo supera il doppio del base o su un all-in.
**Cablaggio Riverwood:** la "Sala Whiskey" (buy-in **2000** gettoni) da slot "in arrivo"
diventa **entrabile** (`AppState.Screen.drawTable` + `sitDownDraw`); buy-in/cash-out via
lo stesso `PlayerAccount`. `GameEngine`/motore Texas/driver Texas/UI Texas **non
toccati**. 234 unit test + XCUITest del tavolo Draw (apertura dal Riverwood, layout
accessibile, box che si apre/seleziona/conferma) + navigazione aggiornata, tutti verdi.

### D-045 — Annunci di showdown: combinazione + kicker rilevante, mai carta per carta (fix post-test, trasversale)
Dopo il test reale del Draw è emerso che lo showdown leggeva **tutte le carte** di
ogni giocatore ancora in gioco (Texas: due coperte + cinque comuni; Draw: cinque
proprie): il momento più drammatico della mano diventava una lettura lunga e piatta
di rango e seme. **Motivazione narrativa:** lo showdown è un *momento drammatico*, non
una lezione di poker — si comunica **chi vince e con che mano**, asciutto. Fix **a
livello di mappatura degli annunci** (non del motore né del flusso): una funzione pura
condivisa `SpeechMap.handDescription(category:bestFive:)` rende la mano come
**combinazione + eventuale kicker** solo dove il kicker può decidere (coppia, doppia
coppia, tris); mai le carte singole. Vale per **tutti i giochi** presenti e futuri
(Texas e Draw la usano già; `DrawSpeechMap` la riusa). Esempi: "colore all'asso",
"doppia coppia, assi e dieci, kicker donna", "full di re sui sette", "scala colore al
re", "hai vinto con doppia coppia, kicker donna", e per il pari "pareggio tra giocatore
2 e giocatore 3, entrambi coppia di assi, kicker donna" (nuovo caso `.splitWon`).
Dettagli: `bestFive` (già negli eventi `handShown`) è ordinato combinazione-prima, così
i ranghi si leggono direttamente; la **wheel A-2-3-4-5** è gestita (le carte valutate
mettono l'asso in testa ma la scala è al cinque → "scala al cinque"); l'**elisione
italiana** ("al re" / "all'asso") sceglie la variante `.vowel` in base al **rango**
(asso, otto), non alla stringa localizzata, così è corretta anche senza bundle (test) e
indipendente dalla lingua. I nomi dei ranghi hanno ora una forma **plurale**
(`card.rank.plural.*`) per le combinazioni. Le voci mp3 del croupier (showdown, pot)
**restano**: cambia solo la **sintesi** che le segue. I view model tracciano il
`bestFive` del vincitore (non solo la categoria) per la conclusione del pot. Solo `UI`
(+ stringhe). Test aggiornati/aggiunti (vedi sotto).

### D-046 — Focus VoiceOver nel box di draw: la selezione aggiorna lo stato, non tocca il focus (fix post-test)
Nel box modale di scambio, toccare una carta per selezionarla **inchiodava** il focus
VoiceOver sulla carta invece di lasciare la navigazione a swipe fluida verso la
successiva. **Causa reale:** il sottoalbero d'accessibilità del pulsante-carta
**cambiava struttura** alla selezione — un `if selected { … }` **aggiungeva/rimuoveva**
la patina scura e la X — e c'era un `.accessibilityAddTraits(.isButton)` **ridondante**
sopra un `Button`; ad ogni toggle SwiftUI **ricreava** l'elemento accessibile e VoiceOver
vi **ri-atterrava**, spezzando l'ordine di swipe. **Fix (solo `DrawBoxView`):** i due
segnali visivi di selezione (patina + X) sono ora **sempre presenti**, commutati con
`.opacity`, così il sottoalbero è **strutturalmente stabile**; ogni carta è **un solo
leaf** (`.accessibilityElement(children: .ignore)` sul contenuto del label, che assorbe
l'elemento interno di `CardView`), con la sola **label** che cambia a riflettere lo
stato ("selezionato"/"non selezionato") e l'annuncio del cambio via `announceLiveValue`
(interruzione a bassa priorità già esistente). Rimosso il trait ridondante. Niente
`accessibilityElement` forzato né `children` che collassa la griglia (il container resta
`.contain`). **Pattern generale (in CONVENTIONS §4):** la **selezione di un elemento in
una griglia accessibile aggiorna lo stato ma non sposta né intrappola il focus, e non
ristruttura il sottoalbero** — commuta con opacity, non con inserimento condizionale.
XCUITest aggiunto: dopo ogni selezione/deselezione tutte le cinque carte + contatore +
conferma restano raggiungibili e nell'ordine originale. Solo `UI`.

### D-047 — Seed hardcoded in produzione: ogni partita distribuiva le stesse carte (bug critico, primo test utente su device)
Al primo test utente reale su iPhone **ogni singola partita distribuiva le stesse
identiche carte** (Texas e Draw), con sempre lo stesso bot vincente: gioco di fatto
ingiocabile. **Causa reale, verificata nel codice:** il motore è deterministico dato un
seed fin da M1.1 (giusto), e i driver derivano il seed di ogni mano **deterministicamente**
dal `baseSeed` (`handSeed`/`dealSeed` = SplitMix64(baseSeed + n·C)). Ma il `baseSeed`
arrivava da una **costante cablata** nei view model/schermate della UI
(`TableViewModel(seed: 20_260_704)`, `DrawTableViewModel(seed: 20_260_709)`, ripetuta nei
`TableScreen`/`DrawTableScreen`): ad ogni lancio lo **stesso** baseSeed → gli stessi seed
per-mano → le stesse carte in ogni sessione (le mani **entro** una sessione variavano per
`handNumber`, ma la sessione N era identica alla sessione M). Anche bot e audio erano
seedati dalla stessa costante. **I test verdi lo mascheravano** perché iniettano seed fissi
apposta (determinismo desiderato nei test).
**Fix (semantica: motore invariato, driver casuali in produzione):**
- **`GameEngine` NON toccato:** riceve ancora un seed e resta deterministico rispetto ad
  esso; i test continuano a passare seed fissi.
- **Driver in `GameWorld`:** `SessionDriver`/`DrawSessionDriver` hanno ora `seed: UInt64?
  = nil`. Con seed **impostato** (test) → seed per-mano **deterministico** come prima; con
  seed **nil** (produzione) → `handSeed`/`dealSeed` estraggono un seed **fresco casuale**
  da `SystemRandomNumberGenerator` (`UInt64.random(in: .min ... .max)`) **a ogni mano**:
  carte sempre diverse, ogni mano e ogni sessione.
- **Tocco minimo alla UI (inevitabile: la costante viveva lì):** i view model hanno
  `seed: UInt64? = nil`; passano l'opzionale **direttamente al driver** (nil→casuale in
  produzione) e derivano un `rootSeed = seed ?? UInt64.random(...)` **concreto** per bot e
  audio (casuale per-sessione in produzione, fisso nei test). Le schermate non passano più
  la costante. Nessun'altra logica UI cambiata; motore/flusso eventi intatti.
- **Bot e voci (D-010/D-018):** il bot combina il **proprio** seed statico col
  **fingerprint del contesto** (che include le carte): con carte casuali il fingerprint
  varia → decisioni varie, anche a seed di bot fisso. Le `vob_` dipendono da RNG seedati che
  avanzano su eventi ora variabili → naturalmente varie. Verificato: nessun seed residuo
  cablato le rendeva ripetitive.
**Verifica pratica:** test d'integrazione (`SeedRandomizationTests`) che girano **20 mani
Texas + 20 Draw** in modalità produzione (seed nil): carte private dell'umano diverse quasi
ogni mano, vincitori distribuiti su ≥2 posti; e **10 sessioni successive** producono ≥9
distribuzioni di prime carte diverse (il bug dava 1). Confermato anche che con seed
iniettato tutto resta **identico** (i test restano riproducibili). 247 test verdi.

### ⚠️ Nota di autocritica per sessioni future — determinismo vs casualità in produzione
Quando un motore è **deterministico dato un seed** (scelta corretta per test/replay),
**verifica sempre che in produzione la generazione del seed a livello di driver sia
genuinamente casuale a ogni nuova mano** (fonte di sistema), e che nessun seed non sia una
**costante cablata** propagata da un livello superiore (view model, schermata, config del
tavolo). È un bug **silenzioso**: i test restano verdi — anzi *devono* usare seed fissi —
quindi il difetto sopravvive fino al test su device reale. Regola pratica: cerca ogni
letterale numerico passato come `seed:` fuori dai test e chiediti "questo viene mai
rigenerato a caso in produzione?".

### D-048 — Propensione al fold: `pressureResistance` e `trashFoldTendency`, calibrate per tavolo (test reale)
Al test su iPhone i bot **non foldavano quasi mai**: un bluff pesante post-flop (o
post-draw) veniva chiamato sistematicamente, perché le personalità calibravano sulla
**sola matematica** di equity contro range uniforme (D-011) senza pesare i **segnali di
pressione** dell'avversario. Mancava anche una differenziazione sensibile Classico/Rapido
sulla propensione al fold. **Direzione:** due **nuove dimensioni additive** della
`Personality` (in `GameEngine`, dove vive `Personality`), calibrate diversamente per i due
tavoli (i preset per tavolo vivono in `GameWorld`; il motore resta ignaro dei tavoli).
- **`pressureResistance` (0…1):** quanto resiste al fold di fronte a una **bet grossa**.
  Meccanica (pura e testabile, `Personality.callThresholdMultiplier`): calcolato il
  rapporto **bet/pot prima della bet**; se supera **0.6** (segnale forte di mano fatta),
  la **soglia di equity per chiamare** viene moltiplicata per `1 + min(0.8, betFraction ×
  (1 − pressureResistance) × 0.9)` — cresce molto per un bot pressure-shy, pochissimo per
  uno stubborn. Calibrazione (bet 70% del pot): pR 0.3 → **+44%** equity richiesta; pR 0.9
  → **+6%**. Le mani forti (che superano la `valueBar`) chiamano/rilanciano comunque: la
  pressione morde **solo le mani marginali**.
- **`trashFoldTendency` (0…1):** quanto folda **pre-flop** (Texas) / al **primo giro**
  (Draw) le mani **chiaramente spazzatura**, anche senza pressione. Texas: garbage =
  forza preflop (Chen normalizzato) sotto `0.18` (cattura 7-2o, 8-3o…, non i connettori
  suited). Draw: garbage = `DrawStrategy.isPreDrawGarbage` (nessuna coppia e nessun
  progetto → `optimalDiscards` butta 4 carte). Con probabilità `trashFoldTendency` il bot
  folda la spazzatura invece di proseguire.
- **Stabilità RNG:** entrambe non spostano lo stream per le decisioni non interessate — il
  `trashRoll` è pescato **dopo** il `roll` principale e **solo** nel ramo garbage (guardia
  `trashFoldTendency > 0`); la penalità di pressione è deterministica. I **default
  riproducono il comportamento precedente**: `pressureResistance = 1.0` (nessuna penalità),
  `trashFoldTendency = 0.0` (nessun trash-fold), così una personalità che non li imposta è
  identica a prima (retrocompatibile — vedi il principio additivo in CONVENTIONS §1).
**Valori — Classico (preset in `GameEngine`) / Rapido (in `WorldPersonalities.fast`,
`GameWorld`):**
| Archetipo | Classico pR / tFT | Rapido pR / tFT |
|---|---|---|
| Novice | 0.35 / 0.30 | 0.60 / 0.15 |
| Rock   | 0.50 / 0.90 | 0.70 / 0.75 |
| Aggressor | 0.75 / 0.15 | 0.90 / 0.05 |
Al **Rapido** tutti più stubborn (pR più alta) e più propensi a giocare qualsiasi mano
(tFT più bassa), coerente col carattere di scontro drammatico (D-037). **Motivazione
narrativa:** rendere il **bluff possibile** al Classico (rock/novice folderanno visibilmente
su pressione forte) mantenendo l'**intensità** al Rapido. Applicato a **Texas e Draw**
(nel Draw: pressione al secondo giro, trash-fold al primo); le nuove dimensioni si
integrano con le tre del Draw (D-038) senza sovrapposizioni (quelle: draw/apertura; queste:
fold). Solo `GameEngine` (dimensioni+logica+preset Classico) + `GameWorld` (preset Rapido);
motore/driver/flusso/UI non toccati. **Test:** moltiplicatore puro sui tre scenari;
trash-fold la cui frequenza approssima `trashFoldTendency`; caratterizzazione Classico
(rock/novice foldano più dell'aggressor su pressione) e Classico-vs-Rapido (il Rapido folda
meno); analoghi per il Draw; mani forti mai foldate. 255 test verdi.

### D-049 — Verifica sistematica delle rese fonetiche dei termini poker (fix "Raise"→"Ace")
Al test reale, VoiceOver italiano pronunciava **"Raise" come "Ace"**: la resa fonetica
corretta è **"reis"** (CONVENTIONS §4). **Causa reale:** l'elemento *valore* del box
Raise (su cui atterra il focus all'apertura) aveva come `accessibilityLabel` la stringa
**visibile** `raise.title.raise` = "Raise" (parola inglese grezza), non la resa fonetica
— così il focus leggeva "Ace, N fiche". **Fix (solo localizzazione + UI):** nuove chiavi
`raise.title.raise.a11y` = "reis" / `raise.title.bet.a11y` = "bett", usate come label
dell'elemento valore. **Passata di scansione completa** di tutti i termini canonici su
**ogni stringa parlata** (label `*.a11y` + annunci `announce.*`/`draw.announce.*`), con la
lista di riferimento: fold→"fould", check→"cek", call→"col", raise→"reis", blind→"blaind",
button→"bàtton", flop→"flop", turn→"tern", river→"river", all-in→"ol-in",
showdown→"sciodaun" (solo mp3 croupier, mai sintetizzato), small/big blind. **Buchi trovati
e sistemati: 3 live** — (1) box Raise "Raise"/"Bet"→"reis"/"bett"; (2) `action.fold.a11y`
"fold"→"fould"; (3) `seat.a11y.folded` "fold"→"fould" — più 2 stringhe morte M1.6 allineate
per coerenza. Gli altri termini erano già foneticamente resi (le azioni avversarie usano
verbi italiani "passa/chiama/rilancia", i blind/button/all-in erano già "blaind/bàtton/ol-in").
La **lista canonica sopra resta come reference** per le sessioni future e per i nuovi giochi.
**Test (`PhoneticsTests`):** legge il vero file `it.lproj` da disco (le `.strings` non si
caricano sotto `swift test`) e verifica la tabella fonetica canonica per completezza; un
**guardiano** assicura che **nessuna** stringa parlata contenga la parola grezza "raise" o
un "fold" senza la 'u'. Solo `UI`/localizzazione; motore/driver/logica intatti.

### D-050 — Flag `DebugFlags.freePlay` (gioco libero) temporaneo per la fase di test post-M2.1
L'utente ha **esaurito i gettoni** testando le calibrazioni dei bot (D-048) e non poteva
più sedersi ai tavoli. Introdotto un flag di **modalità gioco libero** — `DebugFlags.freePlay`
in `GameWorld` — **attivo di default in questa build**. Quando attivo: **buy-in ignorato**
(ci si siede a qualsiasi tavolo a prescindere dal saldo), saldo **ripristinato a 5000 a ogni
avvio** e **pinnato** (buy-in/cash-out no-op → ogni test parte fresco), tavoli sempre
entrabili. Implementazione **tutta in `PlayerAccount`** (parametro `freePlay: Bool =
DebugFlags.freePlay` che modula `canAfford`/`buyIn`/`cashOut`/init): `AppState`,
`RiverwoodView` e i driver **non cambiano** (leggono `canAfford`/`buyIn` come sempre; il
motore riceve stack/buy-in come parametri e ignora la restrizione a monte). **Visibilità
del temporaneo:** file `DebugFlags.swift` con intestazione "⚠️ TEMPORANEO — rimuovere prima
del rilascio pubblico", commenti D-050 su ogni ramo in `PlayerAccount`, un **badge arancione
"GIOCO LIBERO"** nel `GameChrome` (ogni schermata, non invasivo, con label VoiceOver
"Modalità test gioco libero attiva"), e una sezione **"Modalità di sviluppo attualmente
attive"** nel README principale. **Rimozione:** in una sessione dedicata al rilascio si
mette `freePlay = false` (o si toglie il flag) — il badge sparisce e l'economia torna reale;
i test dell'economia già passano `freePlay: false` esplicitamente. **Test:** `PlayerAccount`
in free-play (reset a 5000 ignorando il salvato, buy-in ignorato, saldo pinnato); XCUITest
`FreePlayUITests` (badge presente su Home e Riverwood, saldo 5000, tutti i tavoli — incluso
il Draw da 2000 — entrabili). 260 test verdi.

### D-051 — Deduplicazione once-per-hand come regola generale del `SpeechConductor` (fix squalifica ripetuta)
La voce di **squalifica per openers** veniva detta **due volte** di fila. **Causa reale**
(verificata, non due eventi): la `DrawSpeechMap.plan(.openersDisqualified)` dichiarava
**sia** un `synthesis` **sia** un `croupierFallback` con lo **stesso testo** seat-specifico;
col mp3 non ancora prodotto, il `SpeechConductor` diceva il fallback **e poi** la sintesi
identica (stesso anti-pattern del pot in D-045). Stessa cosa scoperta e sistemata anche per
la voce del **pot progressivo** (`carriedPot`), che aveva la stessa doppia dichiarazione.
**Fix locale:** per questi eventi il piano ha **una sola** riga parlata — croupier + il suo
fallback, **niente sintesi separata** che la duplichi. **Consolidamento:** la
deduplicazione è ora una **lista dichiarata unica** `SpeechConductor.oncePerHandVoices`
(showdown, pot, split, **openers disqualified**, **decisive-hand**), consultata
automaticamente dal conductor — per rendere una voce once-per-hand basta **aggiungerla
lì**, senza logica ad hoc per evento. Su una ripetizione il **lead** croupier (mp3 o
fallback) è soppresso; una sintesi che varia legittimamente per chiamata (es. la mano di
ogni giocatore allo showdown) parla comunque. **Principio in CONVENTIONS §4.** Solo `UI`.
Test: due segnali di squalifica per la stessa mano → voce detta **una volta**; dedup della
voce decisiva; la lista è la fonte unica (`admits` la rispetta). Vive nel `SpeechConductor`.

### D-052 — Ante progressivo al tavolo Whiskey del Draw
Il Draw tradizionale (ante fisso, limit, pass-and-out) ha un ritmo lento: mezz'ora senza
bust. **Meccanica (solo Whiskey):** ogni **pass-and-out** fa crescere l'ante della mano
successiva del **20% composto** rispetto all'ante corrente (base 20 → 24 → 29 → 35 → …,
arrotondato); l'incremento continua finché una mano viene **giocata**, poi l'ante **torna
al base** per la mano dopo. La mano giocata **usa** l'ante cresciuto (più drammatica). Il
pot progressivo (D-040) di conseguenza cresce più in fretta. **Vive nel driver**
(`DrawSessionDriver`, flag `progressiveAnte`): `currentAnte` cresce a ogni passed, si
resetta a `ante` (base) dopo una giocata; il valore effettivo è nell'evento `handBegan` e
nell'outcome (`ante`). Il motore riceve l'ante come parametro, non lo decide. La UI mostra
"Ante: N" (cresce a vista). Test: crescita 20% per pass-and-out, ritorno al base dopo una
mano giocata. Vive in `GameWorld`; motore non toccato.

### D-053 — Mani decisive al tavolo Whiskey (innesco casuale + forzato, boost temporaneo)
Per far volare le fiches senza snaturare le regole: ogni **5–8 mani giocate** (soglia
**casuale** per intervallo, deterministica coi test come D-047) una mano è **decisiva**;
inoltre **forzata** dopo **tre pass-and-out consecutivi** (rompe il ciclo). Struttura della
mano decisiva: il croupier la annuncia dopo gli ante e prima delle carte
(`vo_it_high_stakes_draw.mp3`, **non consegnato → fallback sintesi "mano decisiva"**, D-030);
**bet raddoppiate** (small/big ×2), **cap raise da 3 a 5**, e i **bot boostati per quella
sola mano** (aggression +0.15, trashFoldTendency ×0.5). Al termine si torna al normale.
Interazione con l'ante progressivo (D-052): un pass-and-out **non** avanza il contatore
delle mani giocate; una decisiva forzata dopo 3 pass **usa comunque** l'ante progressivo
alto. Ambient teso (`amb_lounge_tense_01`) durante la decisiva, ritorno al calm dopo il pot
(come il Rapido Texas D-037). **Architettura — tutto nel driver come override contestuale:**
il contatore/innesco e i valori boostati vivono in `DrawSessionDriver` (flag
`decisiveHands`); il **cap raise** è ora un **parametro additivo** del motore
(`FiveCardDrawHand.maxRaisesPerRound`, default 3 → comportamento invariato); il **boost dei
bot** è passato **via contesto** (`DrawBotContext.aggressionBonus`/`trashFoldScale`,
additivi, default 0/1 → nessun cambio) e applicato dal `HeuristicDrawBot` alla singola
decisione — la **`Personality` permanente non è mai modificata**. Nuovo evento
`decisiveHandStarted`; UI mostra un banner "MANO DECISIVA". Test: forzatura dopo 3 pass,
bet/cap raddoppiati, intervallo osservato in 5–8 su 20 seed, boost bot (trashFold dimezzato,
raise aumentati), disattivazione. Solo `GameEngine` (parametri additivi) + `GameWorld`
(logica) + `UI`/`Audio` (reazione); flusso eventi esteso di un caso, motore-regole non
ristrutturato. 272 test verdi. **Slot audio nuovo:** `vo_it_high_stakes_draw` (fallback).

### D-054 — La copertura fonetica dei termini poker vale per ogni elemento UI accessibile, non solo per le voci parlate (test reale, estende D-049)
Al test su iPhone col Tavolo Rapido, VoiceOver leggeva ancora "Ace" — questa volta
percepito **prima** di aprire il box Raise. **Verifica nel codice del build reale
(1783771001 = HEAD 8866e2d, che *include* già D-049):** il pulsante Raise della barra
azioni **usa già** `action.raise.a11y` = "reis" (via il parametro `a11yLabel` di
`ActionButton`), così come tutti gli altri pulsanti azione (`action.fold.a11y`=fould,
`action.call.a11y`=col, `draw.action.raise.a11y`, `draw.action.bet.a11y`…). Cioè
**quel** pulsante era già foneticamente corretto nel build testato; la percezione "Ace"
era transitoria o legata a un elemento diverso. **La lezione operativa vera** è che
D-049 aveva controllato le *stringhe* (il valore `.a11y`) ma non aveva un guardiano che
verificasse che il **codice UI usa davvero le chiavi `.a11y`** su ogni elemento letto da
VoiceOver — è la seconda volta che lo stesso termine sfugge in un contesto nuovo.
**Passata sistematica** su ogni `accessibilityLabel`/`a11yLabel:` dei sorgenti UI: tutti
i pulsanti azione erano già a posto, **un buco reale trovato e sistemato** → il pulsante
Check/Call in stato **idle** (non è il tuo turno) leggeva la sua stringa **visibile**
`action.checkcall.idle` = "Check / Call" (inglese grezzo) come label: aggiunta
`action.checkcall.idle.a11y` = "cek, col" e usata nei due action bar (Texas + Draw).
**Guardiano nuovo (PhoneticsTests, D-054):** oltre alla tabella fonetica delle stringhe,
un **test statico che scandisce i sorgenti** `ActionBarView.swift`/`DrawActionBarView.swift`
ed estrae ogni chiave che finisce come **accessibility label** (argomento `a11yLabel:`,
riga `.accessibilityLabel(...)`, e corpo delle funzioni helper `*Label`), verificando che
**termini in `.a11y`** — così una futura regressione in cui una chiave *visibile* viene
cablata come label (esattamente questo bug) fallisce in CI. **Principio permanente
(CONVENTIONS §4):** la pronuncia curata copre **ogni elemento UI accessibile**, non solo
le voci parlate; `PhoneticsTests` scandisce l'intera UI. Solo `UI` + localizzazione.

### D-055 — Niente annuncio contestuale "per chiamare X" al turno umano: il pulsante parla da sé (test reale)
Al turno umano, dopo l'mp3 `vo_it_your_turn`, la sintesi aggiungeva "per chiamare X, pot
Y" (`SynthLine.yourTurnContext`). **Ridondante e dannoso:** il pulsante Call mostra già
"Call X" e lo pronuncia da solo quando VoiceOver ci arriva con lo swipe; peggio, la
sintesi partiva mentre l'utente cercava di agganciare lo slot delle proprie carte e lo
**interrompeva**. **Fix:** il turno umano riproduce **solo** l'mp3 `vo_it_your_turn`,
sintesi `nil` (Texas `TableViewModel.runHumanTurn` **e** Draw
`DrawTableViewModel.runBettingTurn`). Il caso `yourTurnContext` resta **definito** nella
mappa (capacità pura, ancora usato dai test di *rendering* di `text(for:)`), ma non è più
prodotto al turno. **Principio (CONVENTIONS §4):** un annuncio dinamico contestuale
(importi, pot, contatori) **non deve duplicare** un pulsante visibile che già lo comunica
— il pulsante parla da sé. Solo `UI`.

### D-056 — Il ritmo adattivo con VoiceOver ON ha un timeout di salvaguardia; e la completion del croupier è garantita (blocco pre-flop, test reale)
Col Tavolo Rapido e la **modalità VoiceOver dell'app ON**, nel pre-flop capitava che dopo
un'azione (es. Call) la UI si **bloccasse**; a un secondo tocco "di sblocco" collassava in
un colpo conferma-azione + flop + turno post-flop, e il secondo tocco veniva interpretato
come azione post-flop, **scippando** la scelta consapevole.
**Causa reale, individuata nel codice (da confermare sul device col logging aggiunto):**
il ritmo adattivo (D-034) fa attendere la UI finché il **canale parlato** non è quieto
(`awaitSpokenChannelQuiet`: `conductor.isIdle && announcements.isQuiet`). Il
`SpeechConductor`, mentre suona un mp3 croupier, **tiene l'intero canale** e si sospende
su `await withCheckedContinuation { audio.play(lead) { cont.resume() } }`. Se la
**completion dell'`AVAudioPlayer` non arriva mai** — sul device un `play()` fallito o
interrotto **non** chiama `audioPlayerDidFinishPlaying` — la continuation non riprende, il
conductor resta `isBusy` per sempre, e con la modalità ON la UI **si blocca all'infinito**;
un'interazione successiva che innesca un altro `play`/pump del runloop fa poi cascare il
backlog accumulato dal produttore (che gira una mano avanti) sul turno sbagliato. (Gli
annunci *droppati* dalla coda **non** erano la causa: un drop rimuove dalla coda *pending*,
non blocca `isQuiet`.)
**Fix su due livelli:**
- **`AudioEngine` — la completion è garantita (causa reale):** ogni `play(_:completion:)`
  registra la completion e la fa scattare **al più una volta** da chi arriva prima — il
  delegate di fine, il ramo `play()==false` (fire immediato), o un **timeout** = durata del
  clip + margine. Così il conductor non può mai restare appeso su un callback perso.
- **View model — salvaguardia temporale (rete di sicurezza):** `awaitSpokenChannelQuiet`
  ora usa `SpokenChannelPacing.awaitQuiet` (UI, puro, testabile) con un **tetto cumulativo**
  (`maxWait` 3 s): superato il tetto la UI **procede comunque**, loggando la salvaguardia.
  Meglio un breve sovrapporsi di annunci che una UI congelata che ruba una scelta.
  **L'usabilità reale ha precedenza sulla perfezione della sintesi.**
- **Logging (D-056):** `SpokenLog` traccia inizio/fine attesa per evento (`visual WAIT
  begin/end … quiet=…`) e lo scatto della salvaguardia, così il prossimo test sul device
  mostra dove si accumula il ritardo. `AudioEngine` logga la completion di fallback.
**Test:** `SpokenChannelPacing` con canale mai-quieto → procede entro il tetto (no blocco
infinito), ritorna subito se già quieto, si ferma appena diventa quieto, rispetta la
cancellazione. Solo `UI` + `Audio`; API pubbliche invariate; `GameEngine`/`SessionDriver`/
flusso non toccati.

### D-057 — Pattern generale di atterraggio del focus VoiceOver a ogni cambio di visualizzazione
Cambiando schermata (Home→Riverwood, Riverwood→Tavolo, apertura di modali) il focus
VoiceOver restava **agganciato all'elemento della schermata precedente** ormai inesistente:
dopo la transizione l'outline era nel vuoto e uno swipe dava il "tonk" di fine corsa.
**Pattern riusabile (`FocusLanding.swift`, D-057):** un modificatore
`.voiceOverFocusLanding()` che, all'`onAppear` dell'elemento, (a) chiede a VoiceOver di
**ri-scansionare** la schermata (`.screenChanged`) e (b) porta il focus **su quell'elemento**
via `@AccessibilityFocusState` (deferito un runloop, come D-027). Il `.screenChanged` è
**instradato** attraverso `AnnouncementQueue.postScreenChanged()` — la coda resta l'**unico**
punto che posta a VoiceOver (D-032), così il guardiano statico anti-post-diretto non si
rompe. **Applicato a:** Home (titolo), Riverwood (titolo), Tavolo Texas e Draw (lo stack
dell'umano, sempre presente), Impostazioni (primo toggle), overlay di fine partita
(messaggio d'esito); i due box modali (Raise, Draw) **riusano** lo stesso modificatore sul
loro elemento di focus esistente (valore del box Raise per D-027; titolo del box Draw per
D-044/D-046), sostituendo il plumbing manuale. **Coordinamento con la coda:** il
`.screenChanged` (ri-scan + focus) scatta all'apparizione e non trasporta testo, quindi non
compete con gli annunci contestuali della coda (canale separato). **Principio (CONVENTIONS
§4):** ogni schermata principale e ogni modale/overlay dichiara esplicitamente il proprio
primo elemento di focus. *Limite noto:* al **dismiss** di una modale il focus non viene
ancora riportato esplicitamente sul tavolo (le modali gestiscono il focus in apertura); da
affinare se emergerà al test. Test statico: ogni sorgente-schermata applica
`.voiceOverFocusLanding()`. Solo `UI`.

### D-058 — Le voci dei bot bustati sono filtrate dallo stato attuale del tavolo, non da uno snapshot iniziale (test reale)
Un bot eliminato (es. il novice bustato) continuava **occasionalmente** a emettere la sua
voceline (`vob_novice_disappointed`) nelle mani **successive** all'eliminazione. **Causa
reale, verificata:** `AudioDirector.botHandEndVoicelines` reagiva confrontando
`startChips[seat]` (aggiornato solo per i **partecipanti** in `handBegan.seats`) con
`handEnded.chips[seat]`; ma `handEnded.chips` = **tutti** i giocatori, inclusi i bustati a
0, mentre `handBegan.seats` **esclude** i bustati → per il bot bustato `startChips` restava
il valore **stantio** dell'ultima mano giocata (es. 40) e `final=0 < 40` → "disappointed"
di nuovo, ogni mano. **Fix (D-058):** il selezionatore consulta lo **stato attuale** dei
partecipanti, non uno snapshot: `AudioDirector`/`DrawAudioDirector` tengono `activeSeats`
(dai `handBegan.seats` correnti) e `bustedSeats` (dagli eventi `.playerBusted`, già nel
flusso), e `botHandEndVoicelines` reagisce **solo** per un posto `activeSeats.contains(seat)
&& !bustedSeats.contains(seat)`. Analogo guard additivo in `BotChatter`/`DrawBotChatter`
(voce d'azione solo per un posto nel set attivo). La mano in cui il bot **busta** reagisce
ancora una volta (il `.playerBusted` arriva dopo `handEnded`), poi silenzio. **Nessuna
nuova iscrizione**: i director già consumano il flusso, si aggiunge solo la gestione di
`.playerBusted`. **Principio (CONVENTIONS §4):** le voci caratteriali (`vob_`) sono scelte
**a ogni scelta** consultando i partecipanti attuali, mai da snapshot congelati; un bot
bustato non emette più voci. Test: un novice che busta → zero voci nelle mani seguenti
(pur restando in `handEnded.chips` a 0); un novice attivo continua a reagire. Solo `UI`.

**Sessione di rifinitura post-M2 (VoiceOver + audio):** 280 test verdi. Cinque fix da test
reale su iPhone (build 1783771001), tutti in `UI`/`Audio`: copertura fonetica estesa ai
pulsanti (D-054), annuncio turno più asciutto (D-055), salvaguardia anti-blocco del ritmo
adattivo + completion audio garantita (D-056), atterraggio del focus VoiceOver (D-057),
voci dei bot bustati filtrate (D-058).

### D-059 — Pronuncia dei pulsanti Raise via IPA, non via grafema indovinato (terzo intervento sulla stessa parola)
Entrambi i pulsanti Raise (Texas secco che apre il box, Draw con importo fisso) leggevano
ancora "ace" invece di "reis", nonostante D-049/D-054. **Diagnosi al fondo, empirica, non
assunta:** ho letto la **label a runtime** dei due pulsanti con un XCUITest
(`element.label`, cioè ciò che VoiceOver annuncia): Texas = **"reis"**, Draw = **"reis a 0"**.
Quindi:
- *Ipotesi 1 (nessuna chiave localizzata come label → niente da scandire)* → **FALSA**: entrambi
  passano un `a11yLabel: uiLocalized("…​.a11y")` e la label È applicata a runtime.
- *Ipotesi 3 (un solo call-site cablato, l'altro grezzo)* → **FALSA**: entrambi i call-site
  reali (`ActionBarView` e `DrawActionBarView`) sono cablati e leggono "reis".
- *Ipotesi 2 (la grafia "reis" viene comunque letta "ace" dalla voce italiana)* → **VERA**.
  La narrazione parlata funziona perché usa il **verbo italiano** "rilancia" (parola reale); i
  pulsanti tengono il termine inglese e ne spellano la pronuncia con un **grafema inventato**
  ("reis"), e un grafema inventato **non è una specifica affidabile di un suono**: la voce
  italiana lo pronuncia a modo suo ("ace").
**Perché il guardiano statico era passato verde su un buco vivo:** `PhoneticsTests` verificava
che la label usasse **la grafia fonetica dichiarata** ("reis"), non che quella grafia
**suonasse** giusta — e nessun test statico può *sentire* il TTS. Ha quindi validato "reis"
come "fonetico" mentre "reis" era esso stesso una grafia sbagliata.
**Fix — pronuncia deterministica via IPA (`accessibilitySpeechPhoneticNotation`,
`IPANotationAttribute`):** invece di indovinare lettere, si allega la **notazione IPA esatta**
del suono. `PokerSpeech` (nuovo, `UI`) costruisce la label come `AttributedString` con
`raiseIPA = "ˈreɪz"` (il suono di "raise"); VoiceOver pronuncia i fonemi esatti a prescindere
dal grafema. **L'IPA non può essere "indovinato sbagliato" come un grafema** — è la specifica
standardizzata del suono, ed è ciò che rende il fix definitivo dopo due tentativi grafemici
falliti. **Pulsante Draw con importo:** la label è composta in **due run** — la parola con IPA
+ il numero (" a N") come run **normale**, così il numero non corrompe la pronuncia della
parola (D-059). La stringa base resta "reis"/"reis a N" (fallback di spell-mode / se l'IPA non
fosse onorato → **nessuna regressione** rispetto a oggi; su iOS 17+ l'IPA è onorato → corretto).
**Rinforzo del guardiano (perché il buco non ripassi verde):** per il termine che continua a
fallire si pretende ora l'unica cosa che un test *può* verificare senza orecchie — una
**pronuncia IPA esplicita**. `PokerSpeechTests` fissa l'IPA canonico ("ˈreɪz") e verifica che
la label del Raise porti quell'IPA sul run della parola (e **non** sul numero, nel Draw). Un
guardiano sorgente in `PhoneticsTests` pretende che **entrambi** i call-site Raise passino
`a11yAttributed` via `PokerSpeech.raiseLabel` (un ritorno al grafema nudo fallisce). Un
XCUITest (`RaiseButtonLabelUITests`) blocca il cablaggio a runtime (label = "reis"/"reis …"
su entrambi i pulsanti, così le ipotesi 1/3 non possono rigredire). **Catalogo canonico:** la
pronuncia autorevole di "raise" è ora l'**IPA /ˈreɪz/** (in `PokerSpeech.raiseIPA` + nota in
CONVENTIONS §4); "reis" resta solo come grafia di fallback. **Vincoli:** solo `UI` +
localizzazione; nessuna modifica a `GameEngine`/flusso; nessuna chiamata diretta a
`UIAccessibility.post`; narrazione "rilancia" non toccata. Scope limitato ai due pulsanti
Raise (fold/call/check non toccati). **285 test verdi** + XCUITest. **Nota onesta:** l'IPA è
il meccanismo sancito da Apple per la pronuncia e la sua correttezza è verificata
*by construction* (l'IPA È il suono); la conferma *udibile* finale resta il test sul device.

### ⚠️ Nota di autocritica per sessioni future — un guardiano che non può "sentire"
Un test statico/unità **non può verificare che una grafia fonetica suoni giusta**: può solo
verificare che *una* grafia sia presente. Per i termini la cui pronuncia conta (poker inglese
letto da voce italiana), non affidarsi a grafemi inventati "verificati a occhio": specificare
la pronuncia con **IPA** (deterministica) e far verificare al guardiano la *presenza dell'IPA*,
non la plausibilità del grafema. Se un termine legge male sul device nonostante il verde, la
prima mossa è **leggere `element.label` a runtime con un XCUITest** per distinguere "label non
applicata" (ipotesi 1/3) da "grafia mispronunciata" (ipotesi 2) — come fatto qui.

### D-060 — La resa fonetica non si dichiara risolta senza ascoltarla: campioni audio sulla voce reale, poi grafie piane verificate (quarto e definitivo intervento)
Anche dopo D-059 (IPA) i pulsanti Raise leggevano ancora "ace", e Fold suonava "Fohold"
(raddoppio vocalico). **Causa reale, al fondo di TRE fallimenti — nessuno di noi aveva mai
ASCOLTATO.** D-049/D-054/D-059 hanno tutte ragionato a tavolino su grafie/IPA e spedito
senza sentire la voce di destinazione; il guardiano ha codificato assunzioni **mai udite** ed
è passato verde su un bug vivo. Il metodo che ha rotto il ciclo: **generare audio reale** con
la stessa voce di VoiceOver iOS (**Alice it-IT compact**, via `AVSpeechSynthesizer.write` +
`AVSpeechSynthesisIPANotationAttribute`) per ogni candidato, e farli **ascoltare all'utente**.
- **Perché l'IPA di D-059 non ha funzionato:** l'analisi dei byte dei campioni mostra che la
  sintesi **onora** l'IPA (con IPA presente il testo base è ignorato: "reis"+IPA e "Raise"+IPA
  danno file byte-identici). Ma /ˈreɪz/ reso dalla voce **compatta** Alice **non** suona come
  la parola inglese "raise" che l'utente voleva; e resta il dubbio (mai provato) che il percorso
  SwiftUI `.accessibilityLabel(Text(AttributedString))` consegni davvero l'attributo a VoiceOver
  sul device. In breve: l'IPA era la specifica giusta di un suono che l'utente **non** voleva.
- **Cosa ha scelto l'orecchio (sorprendente e semplice):** la **parola inglese piana "Raise"**
  letta da Alice è la resa giusta per Raise (l'invenzione "reis" leggeva "ace"); per Fold la
  grafia piana **"fohld"** è resa /ˈfold/ (l'invenzione "fould" raddoppiava in "Fohold").
- **Fix — grafie PIANE, verificate all'orecchio, niente IPA:** `action.raise.a11y`="Raise",
  `action.fold.a11y`="fohld" (idem box valore/conferma e Draw "Raise a %d"). **Device-safe** per
  costruzione: sono stringhe piane (nessuna dipendenza dal fatto che il device onori l'IPA di
  SwiftUI). Byte-identità verificata: la label **così com'è nel codice** rigenerata in audio è
  **identica** al campione approvato dall'utente ("Raise"==raise_02, "fohld"==fold_03). La
  macchineria IPA di D-059 (`PokerSpeech`) è **rimossa**.
- **Guardiano adeguato, non aggirato (il vero fallimento strutturale):** il guardiano non può
  *sentire*, quindi **non deve più affermare che una grafia inventata è giusta**. Ora (a)
  **àncora alle rese VERIFICATE all'orecchio** (`PhoneticsTests.testEarVerifiedButtonRenderings`
  le asserisce esatte, byte-identiche ai campioni approvati; guardia anti-ritorno di
  "reis"/"fould"); (b) **traccia i termini NON ancora verificati** come semplice rilevatore di
  modifica (`…UnverifiedCatalogTermsUnchanged…`) senza dichiararli corretti — chi ne cambia uno
  è **costretto a ri-verificarlo all'orecchio** e promuoverlo all'àncora; (c) mantiene lo scan
  strutturale (`.a11y`) e (d) l'XCUITest runtime (`RaiseButtonLabelUITests`: label "Raise"/"fohld"
  su Texas **e** Draw). Il perno di D-060: **si asserisce solo ciò che un umano ha udito.**
- **Ambito:** solo i due pulsanti Raise + il pulsante Fold (scelti dall'utente all'ascolto), più
  gli elementi Raise gemelli (box valore/conferma) per coerenza della stessa parola. Gli altri
  termini del catalogo (cek, col, blaind, bàtton, ol-in, tern, sciodaun, e la narrazione "fould"/
  "foulda") sono **campionati** e in attesa dell'ascolto dell'utente in una passata dedicata —
  **non toccati alla cieca**. Narrazione a verbi italiani ("rilancia") non toccata. Nessun
  `UIAccessibility.post` diretto. Label visibili in inglese invariate.
- **Verifica:** 279 test verdi + XCUITest (label runtime, interazione). **TestFlight solo dopo
  la conferma acustica dell'utente sui campioni `FINAL_*` — non prima.** I campioni vivono in
  `~/Desktop/lumar-phonetics/`. **Supera D-059** sull'approccio (IPA → grafia piana verificata).

### D-060 (chiusura) — Resa finale cablata + comportamento REALE dell'IPA, verificato empiricamente
Chiusura formale di D-060. **Resa finale cablata (verificata byte-identica ai campioni approvati
dall'utente):** pulsante **Raise** = parola inglese piana **"Raise"** su **entrambi** i call-site
(Texas `action.raise.a11y`, box valore `raise.title.raise.a11y`, conferma `raise.confirm.a11y`;
Draw `draw.action.raise.a11y` = "Raise a %d") — identica al campione `raise_02`; pulsante **Fold**
= grafia piana ASCII **"fohld"** (Alice la legge /ˈfold/) — identica al campione `fold_03`.
Nessuna discrepanza tra codice e ascolto; nessuna dipendenza da IPA (grafie piane → device-safe).
**Il punto oscuro del riepilogo M1.10 chiarito (misurato, non ipotizzato).** La frase "una grafia
piana risultava byte-identica alla notazione IPA" era **ambigua e NON significa che l'IPA sia
inutile**. Matrice empirica su Alice it-IT (`AVSpeechSynthesisIPANotationAttribute`, lo stesso a
cui mappa `accessibilitySpeechPhoneticNotation`; md5 dell'audio):
- **L'IPA È onorato e CAMBIA la pronuncia:** `"reis"` piano ≠ `"reis"`+IPA/ˈreɪz/ (DIVERSI);
  `"Skypool"` piano ≠ `"Skypool"`+IPA/ˈskaɪpuːl/ (DIVERSI, **su un termine nuovo**);
  `"fold"` piano ≠ `"fold"`+IPA/ˈfold/ (DIVERSI).
- **Il CONTENUTO dell'IPA conta**, non solo la sua presenza: `"fold"`+IPA/ˈfold/ ≠
  `"fold"`+IPA-assurdo/təˈmɑːtoʊ/ (DIVERSI).
- **La "byte-identità" di D-060 era una COINCIDENZA fra due input diversi che danno lo stesso
  output**, non "IPA == testo piano": la grafia piana **"fohld"** (senza attributo) produce audio
  **identico** a `"fold"`+IPA/ˈfold/. Due input diversi → stesso suono. È per questo che abbiamo
  potuto **sostituire** l'IPA con una grafia piana per Fold, non perché l'IPA fallisse.
**Conclusione operativa (informazione permanente, ci servirà per "Skypool" e il nuovo casinò):**
1. **A livello di sintesi, l'IPA è affidabile ed efficace** — dimostrato per reis, Skypool, fold.
2. **Il vero anello NON verificato non è l'IPA ma il percorso app→device:** se iOS VoiceOver
   onori davvero l'attributo IPA quando è su una `.accessibilityLabel(Text(AttributedString))` di
   SwiftUI **sul telefono reale** non è mai stato confermato end-to-end (la sintesi lo onora — via
   `AVSpeechSynthesizer`, lo stesso motore — ma il ponte SwiftUI→VoiceOver no; questa build di
   D-060 spedisce **grafie piane**, quindi non testa nemmeno quel percorso).
3. **Regola per i termini futuri (es. "Skypool"):** provare **prima** una **grafia piana
   verificata all'orecchio** (device-safe, nessuna dipendenza dal percorso IPA di SwiftUI); usare
   l'IPA **solo** se nessuna grafia piana produce il suono voluto, e in quel caso **verificarlo
   sul device reale**. L'IPA è uno strumento affidabile; il dubbio è la **consegna** SwiftUI→
   VoiceOver, non l'IPA in sé.

### ⚠️ Metodo canonico per la fonetica (da D-060) — ASCOLTARE prima di dichiarare
Per qualunque termine la cui pronuncia conta: **(1)** genera un campione audio reale con la
**voce di destinazione** (Alice it-IT) e più candidati (parola inglese piana, grafie, IPA);
**(2)** falli **ascoltare** e fatti dire quale è giusto; **(3)** cabla la resa scelta, **(4)**
rigenera il campione della label *così com'è nel codice* e conferma **byte-identità** al
candidato approvato; **(5)** solo dopo la conferma acustica → commit/TestFlight. Il guardiano
pinna **solo rese udite**. Preferire una **grafia piana verificata** all'IPA quando esiste
(device-safe, nessuna dipendenza dal percorso SwiftUI→VoiceOver). Lo strumento per generare i
campioni è nello scratchpad di sessione (`render1.swift`: un processo per campione — la write
di `AVSpeechSynthesizer` smette di produrre audio dopo ~20 chiamate nello stesso processo).

### D-061 — `HandEvaluator` esteso (non sostituito) per la valutazione vincolata di Omaha (M1.10)
Omaha impone che la mano sia composta da **esattamente due** delle quattro carte private
ed **esattamente tre** delle cinque comuni. Il valutatore attuale
(`HandEvaluator.evaluate`) trova la migliore mano di cinque **senza vincolo di
provenienza** — usa liberamente quattro o cinque carte dal board — quindi non basta.
**Scelta:** estenderlo **additivamente**, non sostituirlo. Aggiunto
`HandEvaluator.evaluateOmaha(hole:board:)` che enumera le combinazioni **2-su-4 di mano
× 3-su-5 di board** (6 × fino a 10 = 60 valutazioni a cinque carte al river) riusando
`evaluateFive`/`combinations` interni, e ne prende la migliore. Texas e Draw continuano a
chiamare `evaluate` **invariato**: nessuno dei due è toccato (verificato dai loro test).
La regola due-più-tre è la fonte di quasi tutti gli errori di Omaha, quindi è coperta ai
casi di frontiera: flush di board inutilizzabile senza due carte del seme in mano, quads di
board che diventano al più un full, "la mano migliore non è quella intuitiva perché il
vincolo la esclude". Solo `GameEngine` (foundational), solo Foundation.

### D-062 — Motore Omaha Pot Limit (`OmahaHand`) + tetto pot-limit in `PotMath`, engine parallelo e separato (M1.10)
Terzo motore del progetto, in `GameEngine/Omaha/`, **parallelo e indipendente** da Texas e
Draw (D-038): nessun import incrociato, **nessun tipo di regole condiviso**. Condivide solo i
fondazionali (`Card`/`Rank`/`Suit`/`Deck`/`HandEvaluator`) e l'aritmetica chip game-agnostica
(`PotMath`/`Pot`). **Resistito alla tentazione** di riusare il motore Texas: la somiglianza
(blind, quattro street comuni, side pot) è superficiale — la regola due-più-tre (D-061) e il
Pot Limit la rompono alla radice — quindi tipi propri (`OmahaSeat`/`OmahaSeatState`/
`OmahaAction`/`OmahaLegalActions`/`OmahaResult`/`OmahaStreet`). `OmahaHand` è, come `HoldemHand`,
un value type con transizioni `mutating`, sincrono e deterministico via seed; distribuisce
**quattro** carte private, gioca le quattro street, e allo showdown valuta con `evaluateOmaha`.
**Pot Limit (non negoziabile):** ogni bet/raise è limitato alla dimensione del piatto. La
matematica canonica del tetto vive in **`PotMath`** (fondazionale, dove sta già l'aritmetica
chip; scelta di riuso, non un file Omaha): `potLimitMaxBetTo(pot:)` = piatto;
`potLimitMaxRaiseTo(pot:currentBet:toCall:)` = `currentBet + (pot + toCall)` — cioè "chiama,
poi rilancia della dimensione del piatto dopo la chiamata". Calcolato **dal vivo** in
`legalActions()`/`apply(_:)` così il tetto traccia correttamente raise multipli nello stesso
giro, all-in corti (che non riaprono l'azione), e i side pot. L'`allIn` in Pot Limit è
**cappato al piatto** (uno stack più grande del piatto non può shovare: diventa un bet/raise
di dimensione-piatto), gestito nel motore. Coperto da test dedicati sul tetto (apertura, dopo
una call, dopo raise multipli, all-in corto + side pot) e determinismo. Solo `GameEngine`,
solo Foundation. Nessun driver/UI ancora in questo file.

### D-063 — Bot di Omaha + dimensioni Personality dedicate; costo equity MISURATO e contenuto (M1.10)
I bot devono giocare Omaha **come Omaha**, non col ragionamento del Texas: con quattro carte
private quasi tutti floppano qualcosa, le mani marginali del Texas sono spazzatura, e il valore
sta nella **connessione tra le quattro carte** e nella **disciplina del nut**. `HeuristicOmahaBot`
(specchio di `HeuristicBot`, sizing Pot Limit) usa una forza pre-flop **euristica sulle quattro
carte** (coordinazione: coppie da set, suited per il nut flush, connessi per i wrap; penalizza
carte morte/tris in mano) e un'equity post-flop **Monte Carlo vincolato** (`evaluateOmaha`,
avversari a quattro carte). **Due nuove dimensioni additive di `Personality`** (default 0.5,
neutro): `omahaCoordination` (quanto pretende che le quattro carte siano coordinate per giocare
pre-flop) e `omahaNuttiness` (disciplina del nut: quanto svaluta una mano "fatta" ma non-nut
sotto pressione Pot Limit). Sono **leve, non valori calibrati** — la calibrazione è un confronto
tra casinò più avanti; i default producono un gioco sensato. **Retrocompatibilità additiva
verificata:** Texas e Draw **non leggono** le nuove dimensioni → comportamento identico (test:
due personalità che differiscono solo nelle leve Omaha danno la stessa decisione Texas e Draw);
i preset esistenti hanno valori Omaha differenziati (rock nut-disciplinato/coordinato, aggressor
loose) **senza toccare** i campi Texas/Draw.
**Costo equity — MISURATO, non stimato (vincolo del task):** la valutazione vincolata costa
~**3× per campione** rispetto al Texas (60 valutazioni a cinque carte vs 21; misurato:
rapporto **≈2.8–3.0×**, build debug). Per tenere i bot **rapidi come il Texas** si esegue
**~⅓ dei campioni** (`defaultEquitySamples = 60` vs ~200 del Texas): misurato in debug, l'equity
Omaha a 60 campioni (~103 ms/call) è **alla pari** col Texas a 200 (~123 ms/call) — in release
è ~15–30× più veloce. "Meglio un bot leggermente meno preciso che risponde subito." I numeri
sono in `OmahaEquityCostTests` (stampa il rapporto e afferma la parità, non un ms assoluto).
Solo `GameEngine`.

### D-064 — Accelerazione di sessione: `StakeEscalation` (blind su CONTEGGIO MANI) in GameWorld; niente mano decisiva No-Limit
Le sessioni di Omaha Pot Limit tendono a essere lunghe. Serve una meccanica che le acceleri,
del genere di quelle esistenti (ante progressivo Whiskey D-052, boost mano decisiva Rapido
D-037). **Scelta e motivazione onesta:** in Pot Limit i piatti crescono **già** per costruzione,
quindi un boost transitorio di un-piatto-più-grande aggiunge poco; una **escalation permanente
delle blind su schedule** (stile livelli di torneo) accorcia la sessione in modo **affidabile**
(stack corti rispetto alle blind → all-in più rapidi) e resta **coerente col Pot Limit** (la
struttura di puntata non cambia, crescono solo le blind). **Rifiutata la mano decisiva in No
Limit dentro una sessione Pot Limit:** sarebbe un **tradimento dell'identità del tavolo** — il
Pot Limit *è* il contratto del tavolo; permettere shove No-Limit per una mano è arbitrario e
spezza la texture strategica. Se un giorno servisse una "mano decisiva" per Omaha, boosti le
**blind** (restando PL), non la struttura.
**Dove vive:** in **GameWorld**, non nel motore — è una meccanica di sessione. Nuovo tipo
riusabile e game-agnostico `StakeEscalation { interval, factor }` che calcola un moltiplicatore
dallo **schedule di mani giocate** (`multiplier(afterPlayedHands:)` = `factor^(playedHands/
interval)`); il driver decide cosa moltiplicare (blind per Omaha/Texas; ante/bet per un gioco
limit). È un **parametro configurabile del tavolo** (`OmahaTableRules.escalation`), applicabile
in futuro a Texas, Draw e ogni gioco successivo. Non ho migrato i meccanismi esistenti di
Rapido/Whiskey (per non rischiarne il comportamento/determinismo): restano com'erano e
potrebbero adottare `StakeEscalation` più avanti. `OmahaSessionDriver` la applica per mano dal
`handNumber` (mani **giocate**), emette `stakesEscalated` sul level-up, e mette le blind
scalate nell'evento `handBegan` e nell'`OmahaHandOutcome`.
**Principio permanente (accessibilità, in CONVENTIONS §4):** ogni meccanica di accelerazione
scatta su un **contatore di mani giocate, MAI su un cronometro**. Un giocatore cieco impiega
più tempo reale per la stessa quantità di gioco: una meccanica a minuti lo punirebbe per la sua
velocità di ascolto invece che per le sue scelte. È "nessuno perde niente" applicato al tempo,
valido per ogni meccanica futura del progetto.
**OmahaSessionDriver:** sorella di `SessionDriver`/`DrawSessionDriver` con flusso eventi proprio
(`OmahaSessionEvent`/`OmahaEventHub`, riusando solo `EventAudience`/`EventViewer`, D-015), dead
button (D-012), eventi descrittivi non prescrittivi, audience privata esplicita (le quattro
carte solo al proprietario), bot via `BotContext` redatto, e **seed casuale per mano in
produzione / iniettabile nei test** (D-047, non riscoperto). Cliente puro del motore.

**🧱 `GameEngine` M1.10 — Omaha Pot Limit: motore + bot + driver di sessione, MA NON GIOCABILE.**
Terzo motore completo (carte/mazzo condivisi, valutazione vincolata due-più-tre, betting Pot
Limit, side pot, determinismo), bot che lo giocano da Omaha con due leve di personalità dedicate,
e `OmahaSessionDriver` in GameWorld con accelerazione a conteggio-mani riusabile. **Residuo
aperto (esplicito):** mancano **UI** (niente `OmahaTableView`/viste/SwiftUI), **audio** (niente
voce croupier, nessun file, nessuna estensione `SpeechMap`), e il **casinò ospitante** (secondo
casinò, mattone successivo con identità e decisioni ancora aperte — non anticipato). 311 test
verdi; Texas e Draw invariati. Niente TestFlight (nulla di giocabile da testare).

### D-065 — Generalizzazione del pattern casinò (Casino/CasinoTable/CasinoGame) — Riverwood invariato (M2 Skypool)
Con l'arrivo del **secondo casinò** il Riverwood, che era cablato come blocco specifico
(`RiverwoodView`, `AppState.Screen` con casi `.riverwood`/`.table(TableFormat)`/`.drawTable`,
metodi `openRiverwood`/`sitDownDraw`), non regge: due casinò copiati a mano. Estratto **ora**
(prima di duplicare) un **pattern riusabile** in `GameWorld`:
- **`CasinoGame`** = enum `texas(TableRules)`/`draw(DrawTableRules)`/`omaha(OmahaTableRules)`:
  ogni tavolo porta le regole complete del suo gioco (i tre tipi di regole restano distinti — i
  motori sono paralleli, D-038/D-061). `buyIn` è la sola barriera economica.
- **`CasinoTable`** = id stabile (anche identifier d'accessibilità e chiave di navigazione) +
  chiavi localizzate titolo/sottotitolo + `game`.
- **`Casino`** = id + displayName (nome proprio, non localizzato) + chiavi tagline/blurb/return + tavoli.
- **`Casinos`** registry: `riverwood`, `skypool`, `all`. Aggiungere un casinò è un **cambio di dati** qui.
- **UI generalizzata:** `CasinoLobbyView(casino:)` **generica** sostituisce `RiverwoodView` (una sola
  lobby per ogni casinò, tematizzata); `HomeView` elenca `Casinos.all`; `AppState.Screen` diventa
  `.home`/`.casino(Casino)`/`.table(CasinoTable)`; `AppRootView` costruisce la schermata giusta dal
  `game`; il ritorno dal tavolo va al casinò di provenienza (label per-casinò via `returnLabelKey`).
- **Tema per casinò** (`CasinoTheme`): palette + tipografia. Il Riverwood conserva **esattamente** la
  veste precedente (feltro verde, ottone, serif); lo Skypool ha la sua (pietra/blu, sans). Il feltro
  del tavolo resta verde (superficie di gioco condivisa) tranne la specialità Marble (feltro marmo).
**Vincolo assoluto RISPETTATO:** il Riverwood si comporta **esattamente come prima** — stessi tavoli,
buy-in (1000/1000/2000), personalità, determinismo. Test di regressione `CasinoTests` lo pinna; gli
identifier XCUITest (`home.casino.riverwood`, `riverwood.table.*`, `chrome.back`) sono preservati.
`AppStateTests` è stato **migrato alla nuova API** conservando **identiche** asserzioni di wallet/
navigazione (migrazione meccanica, non cambio di comportamento). Solo `GameWorld` + `UI`.

### D-066 — Skypool Casinò: identità, tre personalità urbane come entità proprie, Omaha giocabile, due categorie di voce (M2)
Secondo casinò: **Skypool**, cittadino e moderno — marmo, cemento, acqua (piscina), discoteca;
freddo e austero, l'**opposto** del Riverwood (non una sua versione più ricca). Specialità: **Omaha
Pot Limit** al tavolo **Marble** (nome deciso, non negoziabile). Ospita anche i due Texas generici
(Classico/Rapido) con i **suoi** bot. **Accesso puramente economico** (D-065): se hai i gettoni ti
siedi, nessuno sblocco narrativo. Buy-in ~**5×** i corrispondenti del Riverwood, in scala crescente:
**Fast 5000 < Classic 6000 < Marble 10000** (la specialità costa di più). Con `DEBUG_FREE_PLAY` ON i
buy-in sono invisibili; la logica economica è testata con il flag **OFF** (`CasinoTests`), spina
dorsale della progressione quando il flag sparirà.
- **Tre personalità urbane come ENTITÀ PROPRIE** (`WorldPersonalities.skypool`, + `skypoolFast` per
  il tavolo veloce), **non varianti parametriche** di quelle del Riverwood: literal completi.
  Motivazione: **continuità di carattere, cambio d'ambiente** — gli stessi tre archetipi trasferiti in
  città (rock urbano ancora più freddo/professionale ma con un filo d'affabilità; aggressivo urbano
  più avvezzo al rischio, denaro dietro; novizio urbano meno ingenuo ma poco oculato). Dichiararle
  come entità proprie è **deliberato**: possono divergere nel tempo senza toccare il Riverwood. Girate
  **solo leve esistenti** (incl. `omahaCoordination`/`omahaNuttiness` di D-063), nessuna nuova.
  **Retrocompatibilità additiva verificata** (girare le leve Omaha non cambia una decisione Texas) e
  comportamento **riconoscibilmente diverso** dalla frontiera (`SkypoolPersonalityTests`). Il
  **Riverwood NON è ricalibrato** — la calibrazione comparativa è un mattone successivo (giudizio del
  giocatore dopo aver giocato entrambi).
- **Omaha giocabile end-to-end** (`OmahaTableView` & c., specchio di Texas/Draw): stato/reduce puri
  (`OmahaTableState`/`OmahaTableReducer`), VM (`OmahaTableViewModel`), viste, tutto accessibile
  (identifier, focus landing D-057, ordine di lettura). **Quattro carte private**: la mano dell'umano è
  letta **raggruppata per seme** ("asso e re di picche; dieci di fiori; …", `OmahaSpeechMap.
  omahaHoleSpoken`), così il cieco coglie la **suitedness** (potenziale nut-flush, valore chiave di
  Omaha) senza affogare in quattro carte piatte. **Box raise Pot Limit** (`OmahaRaiseBoxView`):
  riusa `RaiseBoxState`/`RaiseCurve` su `min/maxTo` — dove `maxTo` è il **tetto pot-limit** che il
  motore riporta, spesso **sotto** lo stack. Conferma sempre `.bet/.raise(value)` (il motore rende
  all-in da sé se `value == stack`); **niente shove** quando lo stack supera il piatto: il pulsante
  massimo dice **"Piatto"** (non "All-in"), una caption mostra il tetto e VoiceOver lo annuncia — la
  distinzione PL resa comprensibile visivamente **e** acusticamente. Il tavolo usa la palette **marmo**
  fredda come firma. Cablato nel casinò via `CasinoGame.omaha` → `OmahaTableScreen`.
- **Due categorie di voce (novità architetturale, principio permanente in CONVENTIONS §4):** una
  voce parlata dichiara la sua **categoria** e ne eredita il **fallback** quando l'mp3 non è ancora
  prodotto. **Informativa** (croupier: stato di gioco che serve) → fallback a **sintesi VoiceOver**.
  **Ambientale** (commenti di colore dei bot, `vob_`) → fallback al **SILENZIO**, mai sintesi: un
  colore mancante non deve diventare un annuncio intrusivo che interrompe l'ascolto del cieco (colore
  ≠ informazione). Implementato su `SoundCategory.fallsBackToSynthesis` (true solo per `.croupier`),
  consultato dal `SpeechConductor`; testato (`AmbientVoiceFallbackTests`). Evita anche l'anti-pattern
  D-051 (mai `synthesis` **e** `croupierFallback` con lo stesso testo).
- **Audio Skypool: solo slot dichiarati, nessun file prodotto** (D-030). Croupier proprio dello
  Skypool (`vo_it_sky_*`, informativi → sintesi), ambient (`amb_skypool_*` → fallback lounge), e le
  **voci di colore dei tre bot urbani** (`vob_sky_*`, **ambientali → silenzio**). Il tavolo Omaha li
  usa già; i Texas dello Skypool per ora riusano il croupier/ambient condivisi (unificazione croupier
  per-casinò e cablaggio delle `vob_sky_*` = residui dichiarati in ROADMAP, da fare alla consegna dei
  file). Catalogo di produzione completo in `Skypool_audio_catalog.md`.
- **Fonetica di "Skypool" e "Marble"** (D-060): campioni Alice it-IT generati in
  `~/Desktop/lumar-phonetics/skypool-marble/` (grafia piana + varianti + IPA), da **ascoltare e
  approvare** prima di cablare qualcosa di diverso dalla grafia piana attuale (device-safe).
**Vincoli:** motori invariati; nessun import incrociato; eventi descrittivi; `BotContext` redatto;
nessun `UIAccessibility.post` diretto; ogni continuation con timeout (riuso `SpokenChannelPacing`);
cache dallo stato corrente; Personality additiva; determinismo dato seed, casuale in produzione (D-047).
**337 test verdi** (311 + 26 nuovi) + XCUITest Skypool/Omaha. Riverwood invariato.

**🏢 M2 — Skypool Casinò giocabile.** Girano end-to-end **tre giochi** in **due casinò**: Texas
(Classico/Rapido) e Five-Card Draw al Riverwood; Texas (Classico/Rapido) e **Omaha Pot Limit
(Marble)** allo Skypool. Il pattern casinò è generalizzato e riusabile. **Residui aperti (dichiarati
in ROADMAP):** calibrazione comparativa Riverwood↔Skypool; produzione dei file audio Skypool
(`Skypool_audio_catalog.md`) e cablaggio delle voci di colore urbane; NPC narrativi; piscina/discoteca
come luoghi; terzo casinò. **Nessuna anticipazione del terzo casinò.**

### D-067 — Il croupier (e l'ambient) è un attributo del CASINÒ, non del gioco (M2, chiude il debito D-066)
Debito dichiarato in D-066: il croupier era legato al **gioco**, non al casinò. I Texas dello
Skypool riusavano croupier e ambient del Riverwood → due terzi del casinò nuovo suonavano identici
al vecchio; solo Marble aveva voce propria (perché Omaha è un gioco nuovo con `SpeechMap` nuova).
**Perché conta (accessibilità):** il non vedente l'identità di un casinò non la **vede** (marmo,
blu, feltro), la **sente** — voce e aria. Se al Texas dello Skypool sente il croupier del Riverwood,
per lui è lo **stesso posto** e la progressione narrativa svanisce: è la perdita che "nessuno perde
niente" esiste per impedire. Criterio **invertito**: la palette audio (croupier + ambient + colore
bot) è attributo del **casinò**, uno solo per **tutti** i suoi tavoli.
- **`CasinoAudio` (UI):** la palette di un casinò — remap del croupier (SoundID di default del gioco
  → SoundID del casinò), **fallback di registro** per cue (chiave localizzata), `AmbientBeds`,
  `BotVoices`. `registry: [id: CasinoAudio]` + `of(casinoID:)` + `hosting(table:)` (via `Casinos`).
  **Aggiungere un casinò = aggiungere una voce al registry (dati);** SpeechMap/conductor/director
  **non si toccano** — il terzo casinò eredita il croupier **per costruzione**.
- **Il Riverwood È la palette IDENTITÀ/DEFAULT** (la chiave della regressione): remap **vuoto**
  (identità), override **vuoti** (usa i fallback propri delle SpeechMap), e **esattamente** i letti
  lounge + le `vob_` di oggi. Instradare il Riverwood attraverso il layer è **byte-identico per
  costruzione**. Pin di regressione: `CasinoAudioTests.testRiverwoodPaletteIsIdentity`.
- **Cosa ho toccato del percorso audio esistente (tutto ADDITIVO, default = Riverwood):** i tre VM
  (`TableViewModel`/`OmahaTableViewModel`, e il default per il Draw) risolvono il **lead croupier +
  fallback** via `casinoAudio.croupier(plan.croupier)` invece di passare il SoundID grezzo — per il
  Riverwood è l'identità (stesso SoundID, fallback della SpeechMap) → **stesse `conductor.say`**. Le
  SpeechMap (Texas/Draw/Omaha) **non cambiano output**. `AudioDirector`/`BotChatter` (e le versioni
  Omaha) prendono `ambient: AmbientBeds`/`voices: BotVoices` con **default Riverwood/Skypool** che
  riproducono il comportamento attuale. Il Texas dello Skypool ora usa croupier + ambient + colore
  bot **dello Skypool** (nessuna voce del Riverwood trapela più — anche i `vob_` diventano `vob_sky_`).
- **Il croupier cambia REGISTRO, non solo voce.** Ogni cue esiste in **due testi distinti**: il
  Riverwood **invariato** (validato all'orecchio, non toccato); lo Skypool **nuovo**, scritto nel
  registro **cittadino, cinico, tecnico, un po' verboso** (chiavi `skypool.croupier.*`, es. flop =
  "Flop sul tavolo. Leggi le carte."; your-turn = "Tocca a te. Il tavolo aspetta."; pot = "Il piatto
  cambia proprietario."), coerente col carattere del posto e delle tre personalità urbane.
- **Fallback (D-066) rispettato:** le voci Skypool sono slot **non prodotti** → il croupier
  (informativo) cade su **sintesi** (il testo di registro); i `vob_sky_*` (ambientali) cadono nel
  **silenzio**. Nessun anti-pattern D-051 (il fallback di registro ≠ la sintesi di contenuto).
- **Draw:** resta cablato al Riverwood (è **solo** al Riverwood → già corretto); il suo VM non è
  toccato. Quando un casinò ospiterà il Draw, gli si passa `casinoAudio` come per Texas/Omaha (stesso
  one-liner) — nessuna modifica al percorso audio.
**Test:** Riverwood identità (regressione centrale); Skypool usa la propria palette su **tutti e tre**
i tavoli (Texas + Omaha, via `hosting`); informativa→sintesi / ambientale→silenzio end-to-end col
conductor; **palette data-driven** → un casinò nuovo eredita il meccanismo senza toccare il percorso
audio. Catalogo `Skypool_audio_catalog.md` **rigenerato** contro l'architettura nuova. **343 test
verdi.** Solo `UI` (+ stringhe di registro). Motori/driver/flusso/`Audio` intatti.

### D-068 — Cablaggio dei file audio reali dello Skypool: lo Skypool prende voce (M2)
L'utente ha prodotto su ElevenLabs/StableAudio i file dello Skypool e li ha messi in Downloads;
questa sessione li cabla. **Il cablaggio NON ha richiesto modifiche alla logica** (come previsto da
D-030/D-067): gli slot esistevano già, `AudioEngine.isAvailable` rileva la presenza del file, e il
cablaggio è stato **deposito di asset + rinomine** in `Resources/Audio/` (gruppo sincronizzato →
auto-bundled). Nessun tocco a SpeechMap/conductor/CasinoAudio.
- **Riscontro catalogo↔Downloads:** **22 cablati** (12 croupier, 4 ambient, 6 colore bot), **1
  lasciato fuori** (ambiguo), **3 slot non prodotti** (fallback attivo). **Rinomine dichiarate:**
  `vo_it_sky_big_blind→blind_big`, `small_blind→blind_small`, `amb_skypool_tense→tense_01`,
  `water→water_01`, e per **tutti** i colore-bot rimozione dell'`it_` di troppo + normalizzazione
  `_01` (`vob_it_sky_*→vob_sky_*_01`). **Ambiguo, non indovinato** (regola del prompt): in Downloads
  `vob_it_sky_aggressor_nervous.mp3` non ha uno slot `aggressor_nervous`; **probabilmente** è
  `aggressor_bluff_giveaway` ("risatina nervosa") ma il nome non è *evidentemente* riconducibile →
  lasciato fuori, slot silenzioso, dichiarato. **Poi, su richiesta esplicita dell'utente,**
  `aggressor_nervous` **rinominato** `vob_sky_aggressor_bluff_giveaway_01` e cablato. **Non
  prodotti:** `vo_it_sky_hand_start` (chime → silenzio), `vo_it_sky_pot_limit` (riservato).
- **Wiring del bluff-giveaway (scelta dell'utente: "ovunque"):** lo slot `aggressor_bluff_giveaway`
  era **dichiarato ma mai innescato** dal chatter (l'aggressivo pescava solo `taunt`/`confident`),
  per **entrambi** i casinò. Attivato **ovunque**: aggiunto alla rotazione dell'aggressivo in
  `BotChatter`/`OmahaBotChatter` (~15% bluff-giveaway / 25% taunt / 60% confident quando parla).
  **Una sola `roll()`** come prima → stream RNG e decisione parla/tace **identici**: cambia solo
  *quale* battuta, non *se*. **Tocca anche il Riverwood** (accettato esplicitamente dall'utente): il
  suo `vob_aggressor_bluff_giveaway_01` (prodotto in M1.8, finora mai suonato) ora si sente
  occasionalmente — **unico** cambio deliberato all'esperienza del Riverwood; la palette identità
  (`CasinoAudioTests`) resta invariata.
- **D-051 verificato ora che i file esistono:** con l'mp3 presente il conductor **suona l'mp3 e
  ignora il fallback di registro** (la sintesi di contenuto — carte/vincitore — è separata e diversa,
  nessuna doppia riproduzione). Nessuna voce dichiara `synthesis` e `croupierFallback` con lo **stesso**
  testo (il registro è la "parola" del croupier, la sintesi è il contenuto). Test:
  `SkypoolAudioCablingTests` (mp3 presente → il fallback tace).
- **Coordinamento canale ambientale ↔ informativo (verificato + principio in CONVENTIONS §4):** ora
  che i colore-bot **suonano davvero**, verificato che (a) il colore va sul **canale audio** (`.botVoice`,
  `audio.play`) e **mai** in `AnnouncementQueue` come testo — solo l'**attribuzione informativa**
  ("giocatore N rilancia") è annuncio; (b) il colore d'azione passa dal `SpeechConductor` che, via
  `beginExternalSpeech`, **aspetta la fine di un annuncio in corso** prima di partire → **non copre né
  interrompe** l'informazione (le proprie carte, il turno). Test: il colore-bot suona come audio e
  **non** entra in coda. *Residuo dichiarato:* il colore di **fine-mano** (novice win/lose, in
  `AudioDirector`) è fire-and-forget (come al Riverwood, già validato) e può brevemente sovrapporsi
  alla conclusione del pot; **non toccato** perché è comportamento condiviso col Riverwood (che non si
  tocca) — eventuale rifinitura è per entrambi i casinò, fuori scope.
- **Ritmo con voci reali più lunghe (D-056):** il croupier Skypool è più verboso (linee 1.5–3.2 s;
  showdown/stakes-up ~3.16 s) e con la sintesi di contenuto un evento può arrivare a ~5–6 s. Il tetto
  di safeguard del ritmo adattivo (VoiceOver-ON) era **3 s** e sarebbe scattato **sistematicamente** a
  metà voce, desincronizzando occhio e orecchio. **Alzato a 8 s** (`SpokenChannelPacing.defaultMaxWait`):
  è un **backstop anti-freeze**, non un budget di parlato normale, e deve stare **sopra** la voce più
  lunga. Il freeze vero resta preso **prima** dal timeout di completamento per-clip dell'`AudioEngine`
  (durata + margine, D-056, già adattivo alla durata) e dal tetto della coda annunci — l'8 s scatta solo
  se **entrambi** falliscono. **VoiceOver-OFF (default) NON usa questo path** → ritmo invariato. Nessun
  tocco al produttore (`SessionDriver` non conosce il ritmo). I `CheckedContinuation` che attendono una
  riproduzione hanno il loro timeout (D-056), verificato adeguato alle durate reali.
- **Ambient reale:** i letti `amb_skypool_*` (loop da 3 minuti) sostituiscono i fallback lounge via
  `isAvailable` — lo Skypool ora ha **davvero** la sua aria; il crossfade dinamico (calm↔tense, hush
  allo showdown) è invariato. **NON sanata** l'incoerenza dichiarata dei letti Texas (lounge diretti)
  vs Draw (riverwood-preferred): resta residuo, e non produce sorprese (Draw è solo al Riverwood).
- **Riverwood:** **non toccato**. Nessuna voce del Riverwood tra i file consegnati; nessun suo slot
  cablato. La palette identità resta invariata (pin `CasinoAudioTests` verde). L'unico cambio
  trasversale è il tetto di safeguard 3→8 s, che agisce **solo** in VoiceOver-ON adaptive e **solo**
  come backstop anti-freeze (migliora la sincronia, non cambia il suono; VoiceOver-OFF invariato).
**347 test verdi** (343 + 4 nuovi di cablaggio/canale/anti-double). Solo `UI`/`Audio` + asset; motori/
driver/flusso intatti. **Lo Skypool ora parla con la sua voce vera; i bot urbani si sentono.**

### D-069 — Rifinitura livelli audio Skypool dopo l'ascolto: croupier normalizzato, water abbassato (M2)
Ascolto dell'utente sui file reali: (1) `amb_skypool_water` troppo alto; (2) alcune voci croupier più
basse di altre (in particolare i due `blind` e la `turn`; misurato: anche `role_button`). Fix a due
livelli, senza toccare la logica di gioco:
- **Croupier — normalizzazione di loudness sui FILE** (il livello è una proprietà del file, non del
  codice). I 12 `vo_it_sky_*` avevano uno spread enorme (~-16 dB i "buoni" vs ~-28 dB i "bassi", ffmpeg
  `volumedetect`). Riprocessati **dagli originali** con `acompressor` gentile (doma il crest dei file ad
  alto picco così arrivano al target senza clippare) + `loudnorm` EBU R128 **I=-18 LUFS, TP=-1.5 dBTP**:
  ora tutti in **~-18…-20.8 LUFS** (spread ~12 dB → ~2.8 dB), i `blind`/`turn` che l'utente segnalava
  allineati ai più forti, **nessun clipping** (picchi ≤ -1.8 dB), durate invariate. Backup degli
  originali nello scratchpad.
- **Water — abbassato via VOLUME DI LAYER** (è un letto di fondo, non un one-shot): nuovo
  `AmbientBeds.layerVolume` per-casinò; Skypool **0.18/0.2 → 0.05** (~-11 dB, "molto abbassato"),
  Riverwood **resta 0.2** (il suo layer è `amb_crowd_distant`, non consegnato → silenzioso: nessun
  cambio percepibile). Usato in `AudioDirector`/`OmahaAudioDirector` al posto del valore cablato.
- **Riverwood invariato:** solo dati/asset dello Skypool; `layerVolume` Riverwood = 0.2 come prima;
  nessun file del Riverwood toccato; palette identità (`CasinoAudioTests`) verde. 347 test verdi. Solo
  `UI` (`AmbientBeds`) + ri-encoding dei 12 mp3 croupier. **La conferma finale resta l'ascolto sul device.**
