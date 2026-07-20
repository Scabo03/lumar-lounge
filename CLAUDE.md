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
- **`GameEngine`/`GameWorld` M?.? — Machiavelli (D-070):** **quarto motore**, il gioco italiano di
  **ricombinazione**, in `Machiavelli/`, **indipendente** (nessun import incrociato; solo i
  fondazionali). **Non è poker.** Regole canoniche fissate (2 mazzi/104 carte no jolly, group a semi
  distinti, run con asso ai due capi mai wrap, mano 13, pesca 1, vince chi svuota). Il **turno è una
  sequenza di trasformazioni** chiusa da un terminale (pass/draw); **stato ipotetico** (`evaluate` senza
  applicare, `apply` conferma) validato contro lo **snapshot d'inizio turno** → **la stessa carta si
  muove più volte**. Il **predicato di validità** (`MachiavelliRules`) è **unico e nel motore**,
  interrogato da due interfacce future (box del cieco / drag del vedente) → stesso gioco per entrambi.
  Bot su **due assi indipendenti** (`machiavelliSearchDepth`/`machiavelliPatience`, additivi) con tre
  archetipi (studente/adulto/professore); ricerca **interrompibile** (exact-cover limitato) che **non
  sfora mai** il budget (nodi=deterministico / tempo=produzione, ~10–15 s = carattere). `MachiavelliSessionDriver`
  in GameWorld con eventi propri e **attesa udibile** (`botThinkingBegan/Ended`), matchmaking progressivo
  a **partite giocate**. **Struttura mano↔partita a PUNTI (D-071):** ogni mano è **segnata** (asso 10,
  figure 5, numerate 1; bonus out, malus carte rimaste — puro, nel motore `MachiavelliScoring`), la
  **partita** finisce alla **soglia** (250 ≈ ~3 mani, in GameWorld); bot **score-aware** con la dimensione
  additiva `machiavelliMalusAversion` (il paziente scarica i pesi, non resta con l'asso). **Solo
  motore+bot+driver: nessuna UI, nessun audio, nessun casinò ospitante (terzo casinò non anticipato).**
  Giochi esistenti invariati.

**🏢 Fase 1 (M1) completa; Fase 2 (M2) in corso.** Girano end-to-end **sei giochi** in **tre
casinò** — al Riverwood e allo Skypool c'è ora anche il **Blackjack** (D-090/D-091), il primo gioco
della casa in cui si affronta **il banco** e non altri giocatori: niente bot al tavolo, niente
piatto, regole della casa fisse (banco fermo su ogni 17, blackjack 3:2, raddoppio, divisione, resa,
**nessuna assicurazione**) e un'unica differenza fra i due tavoli, il denaro. La sua sfida non erano
le regole ma la **velocità**: l'annuncio essenziale è compresso all'informazione minima per decidere
(**3,88 righe e 6,14 secondi parlati a mano, misurati**, contro le 20,44 righe di una mano di Stud),
col dettaglio spostato su elementi interrogabili. Il quadro completo: al **Riverwood** Texas Hold'em No Limit (Classico/Rapido) e **Five-Card Draw** (Sala
Whiskey); allo **Skypool** Texas (Classico/Rapido) e **Omaha Pot Limit** (Marble); al **ClockTower**
il **Machiavelli** (Sala degli Orologi) e il **Seven-Card Stud Pot Limit** (Sala delle Carte, D-077/
D-078). `GameEngine` contiene **cinque motori**, tutti e cinque ora con driver, UI e audio. Navigazione
Home → Casinò → Tavolo con gettoni persistenti e barriera economica (le poste del Machiavelli al
ClockTower sono **rimborsabili** — prestigio; il suo tavolo di **Stud** invece paga: buy-in 3000 + il
**Premio della Casa** — 1500 al cash-out **solo se il giocatore batte il tavolo** bustando entrambi gli
avversari, D-079). Il **ClockTower ha ora la sua voce vera** (custode anziano `vo_it_tower_*`/`vo_it_clock_*`)
e la sua **musica** (archi al poker, clockwork dosato al Machiavelli — D-080).

**Slot audio** (stato reale, dettaglio in `Skypool_audio_catalog.md`):
- **Skypool (D-068): file reali PRODOTTI e CABLATI** — croupier 12/14, ambient 4/4, colore-bot
  6/7. Lo Skypool **parla con la sua voce vera** e i bot urbani si sentono. Restano scoperti (col
  fallback): `vo_it_sky_hand_start` (chime→silenzio), `vo_it_sky_pot_limit` (riservato),
  `vob_sky_aggressor_bluff_giveaway_01` (file `aggressor_nervous` ambiguo, non cablato).
- **ClockTower (D-080): file reali PRODOTTI e CABLATI.** Ambient/musica 7/7 (archi poker + clockwork
  Machiavelli + orologio), custode Machiavelli `vo_it_clock_*` (your_turn, meld, match_end), croupier poker
  `vo_it_tower_*` (new_hand, showdown, pot, split, game_end). **Missaggio** per-tavolo (poker −20%,
  Machiavelli −35%) e **orologio dosato** (presenza occasionale, non continuo). **Scoperti col fallback (per
  minor verbosità voluta):** street/all-in Stud (registro silente, contenuto parla), `vo_it_tower_your_turn`/
  `_house_prize` (sintesi), colore bot `vob_clock_*` (silenzio, non prodotti). **Ambigui esclusi:**
  `vo_it_clock_opponent_shift`/`player_shift`. **Riservati (bundle, futuro Texas):** `vo_it_tower_big_blind`/
  `small_blind`/`flop`/`turn`/`river`/`role_button`/`stakes_rise`. Cataloghi aggiornati.
- **Storici ancora aperti:** mondo M2 (`amb_home_neutral`, `amb_riverwood_calm_*`,
  `vo_it_high_stakes`, `ui_navigation`), croupier Draw (`vo_it_ante`, `vo_it_draw_phase`,
  `vo_it_pass_and_out`, `vo_it_carried_pot`, `vo_it_openers_disqualified`, `vo_it_high_stakes_draw`),
  e i 2 storici (`amb_crowd_distant`, `fx_hand_neutral`).

**Sessione rifinitura Stud (D-089):** la mano del giocatore si legge come **un insieme unico**
(via il preambolo "viste da tutti", che ripeteva ciò che il giocatore sa per struttura del gioco e
spezzava in due una mano che il vedente coglie in un colpo d'occhio); la distinzione coperte/scoperte
resta su un **elemento proprio**. Layout reso **adattivo** (`FittedCardRow`/`ViewThatFits`): sbordava
di **+47%** dalla quarta strada, ora sta in schermo su ogni telefono e a ogni strada. 515 test verdi.

**Sessione ritmo + controllo della sessione (D-085/D-086/D-087):** ristrutturata la
sincronizzazione dei tre canali dopo **misure sul device reale** — il backlog non era nella coda
annunci ma nel `SpeechConductor` che la alimenta una voce alla volta, quindi la Strategy C di D-032
era scavalcata per costruzione; budget ora sull'**intero canale**, ordine **esplicito** fra effetto
di esito e annuncio (l'effetto non può più spoilerare), safeguard **adattivo** al posto del tetto
fisso. Il giocatore può **lasciare il tavolo quando vuole** (perdendo ciò che ha nel piatto), e dopo
il **fold** la mano **corre allo showdown** annunciando comunque tutte le mani. Cablata la resa
di **`fiches`** approvata all'orecchio (D-088: il difetto era ortografico — le stringhe dicevano
`fiche` al singolare in 18 punti). 507 test verdi.

**Sessione di calibrazione post-test reale (D-082/D-083/D-084):** corretta al fondo la **causa** del
fold precoce nel Draw (un **disallineamento di scala** — punteggio ordinale di categoria confrontato
con una barra di equity — non la taratura delle leve), che spiegava **anche** le squalifiche
dell'aggressivo; **separato** il badge avversario dello Stud in tabellone + identità (il cieco non
riascolta più nome e fiches a ogni lettura delle scoperte); **poste ricalibrate su curva misurata**
(non monotòna: la fascia intermedia peggiora) con lo **Stud del ClockTower accelerato via
`StakeEscalation` invece che alzando le poste**, per non snaturarne l'identità né gonfiare il tetto
pot-limit. 487 test verdi.

**Sessione Blackjack (D-090/D-091):** sesto motore in `GameEngine/Blackjack/` (sabot persistente a
sei mazzi, sbirciata del banco, divisione fino a quattro mani, pagamenti esatti in fiches intere),
driver di sessione con **due sospensioni** (la posta, poi le mosse), tavoli giocabili al **Riverwood**
(buy-in 1000, poste 20–200) e allo **Skypool** (buy-in 5000, poste 100–1000). **Il ClockTower non lo
riceve.** Nessun file audio prodotto: il croupier tace quasi sempre per scelta, e la presenza degli
altri avventori è solo effetto ambientale con fallback al silenzio. **Campioni fonetici dei termini
nuovi generati e in attesa dell'ascolto** in `~/Desktop/lumar-phonetics/blackjack/`. 574 test verdi.

**Sessione focus + canale parlato (D-092/D-093/D-094):** il focus VoiceOver non resta più **appeso
al nulla** quando un box modale si chiude — difetto che era in **tutti e sei i tavoli** (il contenuto
sotto un box non viene mai rimosso dall'albero, solo nascosto, quindi l'atterraggio su `onAppear`
non poteva ripartire), sanato con un hand-off dichiarato nel `didSet` della proprietà del box. Allo
Stud la mano di **terza strada** si legge finalmente come **una riga di tre carte** (diceva «le tue
coperte» elencandone due su tre). L'arricchimento delle scoperte avversarie **non è stato
implementato perché esiste già**: misurato **5,82 righe/mano**; il giocatore non le sentiva perché il
canale è saturo — **18,35 righe e 37,44 s parlati per mano** contro un budget di 6 s — e le scoperte
avevano la **stessa priorità** del chiacchiericcio, che è più numeroso e più lungo. Corretto
l'**ordine di cedimento** a costo zero, senza alzare il budget. 586 test verdi.

**Prossimo passo** (vedi [`ROADMAP.md`](ROADMAP.md)): **ascolto e approvazione dei campioni fonetici
del blackjack** (hit/stand/double/split/surrender: inglese o italiano — oggi sono cablate le parole
italiane, device-safe per costruzione); **produzione dei file audio del ClockTower**
(custode anziano — Machiavelli + **10 slot Stud** `vo_it_clock_poker_*`, D-077 — su ElevenLabs; ambient/
musica archi+clockwork su StableAudio) e dello **Skypool** (`vob_sky_*`); **calibrazione** dei bot dopo
il test reale (le personalità ClockTower poker D-078 e il **premio della Casa** sono leve non calibrate;
verificare che il premio 200 sia percepibile ma non rompa l'economia); calibrazione comparativa
Riverwood↔Skypool; cassa/DLC per ricarica gettoni; **NPC narrativi**; piscina/discoteca come luoghi.
**Nessun altro gioco né casinò anticipato** (il Seven-Card Stud era la specialità di poker prevista del
ClockTower, ora fatta).

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

### D-070 — Machiavelli: quarto motore (ricombinazione), regole canoniche, modello del turno, predicato unico, bot a due assi (M?, solo motore)
Apertura del motore del **Machiavelli** (gioco italiano di ricombinazione), destinato a un
terzo casinò **non ancora anticipato**. Sessione di **solo motore, bot e driver**: nessuna
UI, nessun audio, nessun casinò. Vive in `GameEngine/Machiavelli/`, **quarto motore
parallelo e indipendente** (nessun import incrociato con Texas/Draw/Omaha; condivide **solo**
`Card`/`Rank`/`Suit`/`Deck`). **Non è poker:** niente piatto, puntate, blind, bluff, showdown —
quindi **nulla** dell'infrastruttura poker (`BotContext`-con-equity, `Pot`, side pot, leve di
rischio/aggressione) è riusato; costruito come **animale nuovo**.
- **Regole canoniche fissate (dichiarate perché una sessione futura non le riscopra).** Due
  mazzi da 52 = **104 carte, nessun jolly** (l'assenza di wildcard rende la ricombinazione
  pura). **Group (tris/poker):** 3–4 carte stesso rango, **semi distinti** (con due mazzi due
  copie identiche non fanno gruppo). **Run (scala):** 3+ carte **stesso seme consecutive**;
  **asso ai due capi** (Q-K-A **oppure** A-2-3) ma **mai wrap** (K-A-2 illegale). **Mano 13
  carte**, resto = **stock**; si pesca **una** carta se non si cala. **Vince** chi svuota la
  mano. Nessuna soglia di apertura a punti (semplificazione deliberata: complicherebbe senza
  aggiungere alla ricombinazione). Su queste ho avuto **libertà di scelta** (come per Omaha) e
  ho preso le più diffuse.
- **Il modello del turno è la decisione architetturale centrale.** Il turno **non è una mossa**:
  è una **sequenza di trasformazioni** del tavolo chiusa da un **terminale esplicito** — *passare*
  (legale solo se si è calata ≥1 carta) o *pescare* (se non si è calato nulla). Le trasformazioni
  intermedie non chiudono il turno. Implementato in `MachiavelliTurnContext`.
- **La regola imposta (non negoziabile): la stessa carta può muoversi più volte nello stesso
  turno.** Realizzata validando **ogni proposta contro lo snapshot d'INIZIO turno** (tavolo bloccato
  + mano iniziale), non contro lo stato corrente: così una carta calata presto può essere ripresa e
  ricomposta quante volte si vuole, e **solo lo stato finale** deve essere valido. È **accessibilità
  travestita da regola**: un cieco che scopre una mossa migliore dopo venti swipe non è punito per la
  lentezza dell'esplorazione, solo per la qualità della mossa finale.
- **Stato ipotetico:** `evaluate(_:)` valuta una proposta di tavolo **senza applicarla** (nessuna
  mutazione, dice legalità + carte piazzate + mano risultante); `apply(_:)` conferma. È il cuore del
  "box come posto sicuro dove sbagliare". Conservazione enforced: le carte del tavolo a inizio turno
  devono **restare sul tavolo** (rimescolabili tra combinazioni, mai prese in mano); gli extra vengono
  dalla mano.
- **Il predicato di validità è l'UNICA fonte di verità, NEL MOTORE.** `MachiavelliRules.classify`
  (una selezione è una combinazione legale? quale?) e `isValidTable` (tutto il tavolo è valido?)
  vivono nel motore e **mai** nella UI, perché due interfacce future li interrogheranno da punti
  diversi: il **cieco** compone in un box (sblocca *Conferma* sulla **selezione**), il **vedente**
  trascina sul tavolo (sblocca *fine turno* sul **tavolo**). Un solo predicato ⇒ vedente e non vedente
  giocano lo **stesso** gioco; se vivesse nella UI, divergerebbero al primo bug. **Principio permanente
  in CONVENTIONS §4.**
- **Bot su DUE ASSI INDIPENDENTI (non tre gradi di una scala).** Due nuove dimensioni **additive** di
  `Personality` (default 0.5, inerti negli altri giochi — retrocompatibilità verificata):
  `machiavelliSearchDepth` (quanto esplora le ricomposizioni) e `machiavelliPatience` (se **trattiene**
  una mossa già trovata e pesca aspettando qualcosa di meglio). Sono ortogonali: un bot può cercare in
  profondità **ed** essere avido, o in profondità **ed** essere paziente. Tre archetipi:
  **studente** (profondità 0.2 / pazienza 0.15 — cala in fretta), **adulto** (0.70 / 0.80 — aspetta il
  meglio), **professore** (1.0 / 0.50 — rimaneggia il tavolo). Solo leve, **non** calibrate (taratura
  fine dopo il test reale). Il test di divergenza dimostra la **non-collinearità**: l'adulto, che cerca
  **più a fondo** dello studente, **cala meno spesso** perché più paziente — "più ricerca" ≠ "più giocate".
- **Ricerca interrompibile, profondità adattiva, MAI uno sforo.** `HeuristicMachiavelliBot` tiene sempre
  una **baseline greedy valida** e la migliora con un **exact-cover limitato con restart** sull'intero
  pool (tavolo + mano) per smontare e ricomporre combinazioni (compresa la ricomposizione delle altrui).
  Bounded da `MachiavelliSearchBudget` a **nodi** e/o **tempo**: controlla il budget **prima di ogni
  nodo**, lavoro per-nodo limitato ⇒ overrun trascurabile (microsecondi). **Riconciliazione
  determinismo↔tempo:** il risultato è deterministico dato **seed + budget di NODI** (i test lo pinnano);
  sotto un puro tetto di **tempo** la profondità raggiunta varia per macchina, **intenzionale** (produzione
  adattiva, D-047 nello spirito). Il budget di tempo è **carattere**: ~10 s studente → ~15 s professore
  (derivato da `searchDepth`); il tetto di nodi (~500 → 60 000) fa sì che lo studente ritorni presto anche
  se avanza tempo (*glances*) e il professore studi (*studies*). Numeri **misurati**: exact-cover con MRV
  + branchCap 8; il test `testTimeBudgetNeverOverrunsOnAComplexTable` gira con budget 300 ms su un tavolo
  fitto + mano piena e ritorna **entro ~1 s** con un piano legale.
- **Driver di sessione + eventi + attesa udibile (GameWorld).** `MachiavelliSessionDriver`, sorella dei
  driver poker, con flusso `MachiavelliSessionEvent` proprio via `MachiavelliEventHub` (riusa solo
  `EventAudience`/`EventViewer`). Eventi **descrittivi non prescrittivi**; audience privata esplicita (la
  mano distribuita e la carta pescata solo al proprietario); il produttore non conosce il ritmo umano;
  bot via **contesto redatto** (tavolo pubblico + conteggio mani avversarie, **mai** le loro carte, D-009);
  ogni piano validato dallo **stesso predicato** del giocatore (un bot non può barare; un piano malformato
  è coerciato a una pescata, D-013). **Seed casuale in produzione / iniettabile nei test** (D-047, non
  riscoperto). **L'ATTESA È UDIBILE:** il driver emette `botThinkingBegan`(con la deliberazione attesa
  come *hint* di carattere)/`botThinkingEnded` attorno a ogni turno bot, così UI/audio futuri riempiono il
  silenzio; **nessun audio prodotto in questa sessione** — solo gli eventi.
- **Matchmaking progressivo (incontri, non livelli).** `MachiavelliMatchmaker` sceglie **1–2** avversari
  in base alle **partite giocate** (contatore, **mai** il tempo — regola D-064/D-070): primissime partite
  quasi sempre lo **studente**, poi studente/adulto, poi insieme, più avanti il **professore**, fino a
  partite col **solo professore**. Deterministico dato seed. Il giocatore non affronta una difficoltà,
  **incontra delle persone**.
- **Vincoli rispettati:** sottocartella dedicata, nessun import incrociato, predicato nel motore,
  `Personality` additiva, determinismo dato seed / casuale in produzione, **motori esistenti intatti**,
  **nessuna ricalibrazione** delle personalità esistenti. **382 test verdi** (347 + 35 nuovi); Texas/Draw/
  Omaha invariati. **Residuo dichiarato (esplicito):** mancano **UI**, **audio** e il **casinò ospitante**
  — Machiavelli è motore+bot+driver, **non giocabile**. Nessun TestFlight (niente di giocabile). Vedi
  `ROADMAP.md`.

### D-071 — Machiavelli: struttura mano↔partita a PUNTI (motore + driver, non giocabile)
Oggi una partita di Machiavelli era **una mano sola** (finisce quando qualcuno va out). Introdotta la
distinzione **mano ↔ partita** con **punteggio a fine mano** e **soglia di vittoria**, come il poker ha
già con la sessione multi-mano. **Solo motore e driver: nessuna UI/casinò/audio.**
- **Perché (game design, non solo durata).** Il punteggio dà **uno scopo a chi non sta vincendo la
  mano**: ogni carta calata prima che l'avversario chiuda vale punti, ogni carta rimasta in mano pesa. Il
  giocatore ha sempre qualcosa da fare anche in una mano che perde, e nasce la tensione tra **calare
  subito** per limitare il danno e **trattenere** per costruire qualcosa di più grande. E la singola mano
  non è più l'intera esperienza: una distribuzione sfortunata non decide la partita.
- **Sistema di punteggio (puro, NEL MOTORE — `MachiavelliScoring`).** Scala di valore **imposta**: asso
  **10**, figure (J/Q/K) **5**, numerate (2–10) **1**. Punteggio di una mano per giocatore =
  `outBonus·[è andato out] + valore(calato) − valore(rimasto in mano)`. **Valori scelti:** `outBonus = 20`
  (≈ due assi: andare out è un traguardo, ma non schiaccia il resto), pesi calato/rimasto **1/1** (una
  carta che parte in mano oscilla di **2× il suo valore** tra il calarla e il trattenerla → tensione senza
  affogare il bonus). La funzione è **pura e testabile** dato lo stato finale; il driver le passa
  (calato-per-mano, rimasto, out).
- **Struttura di partita (meccanica di SESSIONE — in GameWorld, come boost mano decisiva / ante progressivo
  / `StakeEscalation`).** `MachiavelliSessionDriver` ora gioca una **partita** = sequenza di **mani**:
  `playHand()` distribuisce/gioca/**segna** una mano ed accumula i totali; `playMatch()` ripete finché un
  giocatore **supera la soglia**. Il primo di mano **ruota** tra le mani (equità). Eventi nuovi:
  `handEnded(handScores, cumulativeScores)` e `matchEnded(winnerID, finalScores)`; `gameBegan/Ended`→
  `handBegan`/`handEnded`, `playerWon`→`playerWentOut`. Descrittivi, non prescrittivi.
- **Soglia (D-071), calibrata su dati misurati.** `defaultVictoryThreshold = 250` in GameWorld. Misura
  (bot 13 carte): il **leader di una singola mano segna ~90–120 punti**, quindi 250 fa durare la partita
  **~3 mani** — "breve e densa, non lunga e diluita". "Bassa" = **poche mani**, non un numero piccolo in
  assoluto: la lunghezza dipende dal rapporto soglia/punti-per-mano. La singola mano resta ~65–75 turni
  (leggermente **più corta** delle ~77 pre-punteggio, perché i bot scaricano di più); una partita è ~3
  mani ≈ ~200 turni — più lunga in totale di prima (1 mano), **come voluto**: l'esperienza è distribuita e
  densa, non decisa da una distribuzione.
- **Bot consapevoli del punteggio — nuova dimensione `machiavelliMalusAversion` (additiva, default 0).**
  `machiavelliPatience` diventa un **rischio calcolato**: trattenere è pericoloso perché le carte pesanti
  rimaste diventano malus se l'avversario chiude. Ho aggiunto una **leva propria** (motivazione: il
  rischio-malus è distinto dalla pazienza — "aspetta il meglio" ≠ "non farti trovare con l'asso in mano") —
  quanto il bot è **avverso a trattenere carte pesanti**. Due effetti: (1) la **ricerca** ora preferisce
  piani che **scaricano più VALORE** (non solo più carte): `planScore = carte + malusAversion·valore·0.1`,
  così un bot averso cala l'**asso** invece di due carte basse; (2) la decisione di **trattenere** è
  ridotta quando la mano è pesante **e** un avversario è **vicino a chiudere** (conteggio carte pubblico).
  **Default 0 = comportamento pre-punteggio identico** (nessun RNG extra, `planScore` = solo conteggio →
  retrocompatibilità additiva verificata). **Preset ricalibrati solo per la consapevolezza:** studente 0.30
  (naïf), **adulto 0.85**, professore 0.90. Effetto sull'**adulto paziente**: prima tratteneva
  indefinitamente; ora, sotto minaccia di chiusura con mano pesante, **trattiene molto meno** (test:
  `averseHolds < obliviousHolds`) — esattamente il "bot paziente che non ignora il rischio" richiesto.
- **Vincoli rispettati:** punteggio (logica di gioco) **nel motore**, soglia/struttura (sessione) **in
  GameWorld**; `Personality` additiva (default riproduce il pre-punteggio); determinismo dato seed **su
  tutta la partita** (test); nessun import incrociato; motori esistenti intatti; predicato di validità e
  modello del turno **non toccati**. **Ancora non giocabile** (manca UI/audio/casinò). **389 test verdi**
  (382 + 7 nuovi: punteggio, malus-awareness, accumulo scores, eventi fine mano/partita);
  Texas/Draw/Omaha invariati. Nessun TestFlight.

### D-072 — ClockTower (terzo casinò) + Machiavelli GIOCABILE, con la UI di ricombinazione accessibile
Costruito il **ClockTower**, terzo casinò, e reso il **Machiavelli giocabile** end-to-end fino a
TestFlight — la sessione UI più impegnativa finora, perché la UI del Machiavelli **non assomiglia a
nessuna** delle altre: non è un tavolo da poker, è uno **spazio di ricombinazione**.
- **Identità del ClockTower.** Casinò piccolo, esclusivo, **accademico**, in una **torre antica** legata
  all'università: erudito, raffinato, si gioca per **vanto non per denaro**. **Terzo ASSE**, non un
  gradino sopra lo Skypool: Riverwood = frontiera, Skypool = denaro, ClockTower = **prestigio** — e,
  essendo le poste **rimborsabili** (buy-in 1200 restituito all'uscita), il posto **più accessibile
  economicamente**. Palette: pietra antica, legno nobile, bronzo, pergamena, serif. **Primo casinò la
  cui musica ha una FORMA**: classica ed erudita (archi, contrappunto articolato), non solo atmosfera.
  Ospita **un solo tavolo** (Machiavelli); il Seven-Card Stud è futuro (**non anticipato**, nessun
  placeholder).
- **Aggiungere il casinò è costato poco (la generalizzazione D-065/D-067 ha retto).** Nuovo caso
  `CasinoGame.machiavelli(MachiavelliTableRules)`, una voce nel registry `Casinos.clockTower`, un tema
  `CasinoTheme.clockTower`, una palette `CasinoAudio.clockTower` (ambient) + gli slot audio: **cambio di
  DATI**, nessuna riscrittura della lobby, del percorso audio, dei conductor/director. Test:
  `testAddingTheClockTowerNeededNoAudioPathChange`. Riverwood/Skypool **invariati** (test).
- **L'invariante architetturale centrale: DUE INTERFACCE, UN SOLO PREDICATO.** Il non vedente compone in
  un **box** (sblocca *Conferma* quando la **selezione** è una combinazione legale); il vedente
  **trascina** sul tavolo (sblocca i terminali quando il **tavolo** è valido). Entrambi interrogano lo
  **stesso predicato PURO del motore** (`MachiavelliRules.classify`/`isValidTable`); **nessuna logica di
  validazione nella UI**, in nessuna delle due modalità. Il substrato comune è `MachiavelliWorkspace`
  (UI): **puro bookkeeping** per indice di istanza (gestisce i duplicati dei due mazzi e il riuso di una
  carta nello stesso turno), che **non giudica mai** la legalità — la chiede al motore. Test:
  `testBoxGateIsExactlyTheEnginePredicate`, `testBoxAndDragReachTheSameValidStateViaTheSamePredicate`.
- **Stato IPOTETICO + turno ripetibile.** Il box seleziona un **pool** che non tocca il tavolo finché non
  si conferma; deselezionare è gratis. Confermata una combinazione il turno **continua** (si riapre
  Piazza, si riprende una carta appena calata). Il workspace è **transitoriamente invalido** consentito
  (rubare una carta e lasciare un'altra combinazione rotta, da sistemare dopo): solo il **terminale**
  (Passa) è gated sulla validità dell'intero tavolo; **Piazza/Conferma** sono gated sulla combinazione
  selezionata. Il turno si chiude **solo** con Passa/Pesca. Test: hypothetical, riuso carta, terminale,
  carta di tavolo mai in mano (conservazione).
- **La catena e i knob di bordo tavolo.** Il box è diviso in due metà: **bassa** = catena scorribile
  (mano · divisore "tavolo" · carte calate), **alta** = pool. **Distinzione acustica IMPOSTA
  (non negoziabile):** le carte della metà **bassa NON annunciano stato**, ogni carta della metà **alta
  si annuncia "selezionata"** — così dopo decine di swipe il cieco sa **in quale zona è** senza doverlo
  ricordare (il vedente lo sa dalla posizione: parità, non aiuto). Sul **bordo inferiore** di ogni
  combinazione un **knob**: decorazione per il vedente, per il cieco un elemento swipe-navigabile che
  annuncia il **titolo** della combinazione (`MachiavelliSpeechMap.meldTitle`: "scala di picche dal
  cinque al dieci", "tris di assi") con **azioni personalizzate** per navigare verticalmente le sue
  carte. È il **colpo d'occhio** che il vedente ha gratis, restituito al cieco.
- **DESCRIVE lo stato, non CONSIGLIA la mossa (principio permanente, CONVENTIONS §4).** La lettura in
  cima al box dà **quante** carte e **cosa** è la selezione ("quattro carte, scala di cuori incompleta") —
  descrizione, esattamente ciò che il vedente vede nel pool. **Mai** "manca il sette" (sarebbe giocare al
  posto del giocatore). Quando la selezione diventa **valida** l'annuncio è dato subito ("scala di cuori
  dal cinque al nove, valida"): è la stessa informazione che il vedente riceve dal pulsante che si
  sblocca — un **fatto compiuto**, non un consiglio. Test:
  `testSelectionReadOutDescribesStateWithoutAdvising` (usa solo le 6 chiavi dichiarate, nessuna nomina una
  carta mancante).
- **Attesa del bot UDIBILE, sul canale AMBIENTALE.** I bot pensano fino a ~10–15 s (D-070). Il motore
  emette già `botThinkingBegan/Ended`; il `MachiavelliAudioDirector`, su thinking, **crossfada** la musica
  erudita alla sua sezione **"thinking"** (archi più cercanti) e torna al calm alla fine: dichiara "sta
  pensando" **senza rivelare cosa trova** e **senza mai** un annuncio della coda VoiceOver che
  interromperebbe l'ascolto. Slot ambient dichiarati (`amb_clocktower_*`), fallback lounge.
- **La voce del ClockTower: figura NON croupier, personaggio da definire.** Nel Machiavelli non c'è
  piatto/puntate/showdown: la figura che parla **scandisce i turni, dichiara le combinazioni, annuncia i
  punteggi**. Registro **erudito, misurato, colto** scritto nei testi; **personaggio e genere lasciati
  APERTI** (li decide l'utente prima di produrre le voci). Slot `vo_it_clock_*` (informativi → sintesi
  fallback, D-030), colore bot `vob_clock_*` (ambientali → silenzio, D-066), attributi del **casinò** via
  la palette (D-067). Nessun anti-pattern D-051 (contenuto specifico → solo sintesi; generico → solo
  fallback di registro, mai entrambi con lo stesso testo).
- **Sistema di incontri progressivo (D-070) cablato.** `MachiavelliMatchmaker` sceglie **1–2** avversari
  per **partite giocate** (`MachiavelliProgressStore` persistente): prima lo **Studente**, poi
  Studente/Bibliotecario, poi insieme, più avanti il **Professore**, fino al solo Professore. Il giocatore
  **incontra persone**, non un livello.
- **Stabilità del sottoalbero d'accessibilità (D-046/D-052).** Nel box il giocatore fa decine di
  selezioni: le carte NON ristrutturano il sottoalbero allo stato — la selezione commuta un overlay per
  **opacity** (sempre presente) e la label della carta-catena è **costante** (nessuno stato → nessun
  re-atterraggio del focus). Lo stato vive nella metà alta (pool), non nella label della catena.
- **Vincoli rispettati:** direzione dipendenze UI→GameWorld→GameEngine; **motore Machiavelli non
  toccato** (una sola aggiunta al DRIVER GameWorld: `matchEnded` emesso da `playHand`/`endSession` così
  una UI guida le mani a una a una col gate); predicato di validità **unica fonte** per entrambe le
  modalità; nessun import incrociato; eventi descrittivi; `BotContext` redatto; **nessun
  `UIAccessibility.post` diretto** (tutto via `AnnouncementQueue`); ogni `CheckedContinuation` col suo
  timeout (riuso `SpokenChannelPacing`); cache dallo stato corrente; `.voiceOverFocusLanding()` su
  schermata, hero, e box. **Riverwood e Skypool intatti.** **405 test verdi** (389 + 16 nuovi); app iOS
  compila. **TestFlight caricato: build 1784038459** (upload riuscito).

### D-073 — Rifiniture ClockTower: letto ambientale per-gioco, voce decisa (italiano), tavolo rotto dichiarato
Sessione breve di completamento del ClockTower: tre decisioni prese in chat + un buco di
accessibilità nel diff di D-072.
- **Il letto ambientale può dipendere dal GIOCO, non solo dal casinò (novità architetturale).** La
  palette resta attributo del **casinò** (D-067), ma al ClockTower serve una **declinazione per
  gioco**, per ragione **funzionale non estetica**: il poker è fatto di **attese e decisioni brevi**,
  e una musica classica **con struttura/sviluppo tematico** le riempie senza competere; il Machiavelli
  è l'opposto — il turno è **lavoro cognitivo lungo e continuo**, e il non vedente lo gioca **sul canale
  audio** (ogni carta è un annuncio, la catena è ascolto puro), quindi una musica che si sviluppa
  diventa un **secondo pensiero in concorrenza diretta** sull'orecchio che serve a giocare. Perciò due
  letti: **poker = archi/classica** (default del casinò, per i tavoli futuri), **Machiavelli =
  CLOCKWORK** (ingranaggi, ritmico/ambientale, presenza senza richiamo). Implementato come
  **override per-gioco della palette**: `CasinoAudio.ambient(forGame:)` (default = letto del casinò;
  Riverwood/Skypool non dichiarano override → **invariati**). Il clockwork rende il ClockTower il posto
  **più VASTO** dei tre (Riverwood caldo, Skypool freddo, ClockTower vasto): ampiezza architettonica,
  riverbero, distanze — un'ampiezza che il cieco **sente** e il vedente ha come sfondo. **Due** tracce
  clockwork (una partita è lunga: un loop breve sarebbe tortura), alternate col crossfade; nel catalogo
  ambient indicazioni di produzione **imposte**: variabilità interna (ingranaggi a periodi diversi →
  ricorrenza senza ripetizione) e **giunzione neutra** (inizio/fine senza evento marcato, altrimenti il
  loop si tradisce a ogni ripartenza). Nuovi slot `amb_clocktower_machiavelli_*`.
- **La voce del ClockTower è decisa: uomo ANZIANO, custode della sala, UNA figura per tutto il casinò**
  — croupier ai (futuri) tavoli di poker **e** arbitro/maestro al Machiavelli (non due personaggi: lo
  stesso uomo, due insiemi di battute su eventi diversi). Completa la terna riconoscibile in due secondi:
  Riverwood **maschile di frontiera**, Skypool **femminile cinica**, ClockTower **maschile anziano
  erudito**. **Lingua: privilegia l'ITALIANO, evita gli anglicismi** — un professore in una torre
  accademica dice **rilancio** non *raise*, **tallone** non *stock*. Questo **risolve alla radice** il
  problema di pronuncia dei termini inglesi (il caso *Raise*, tre sessioni): esiste solo perché una voce
  italiana legge parole inglesi. Testi del custode **riscritti** in registro erudito ("Una nuova mano.",
  "A te la mossa.", "%@ pesca dal tallone."). **Confine rispettato:** riguarda **solo il parlato**; i
  **pulsanti d'azione** restano **Raise/Fold/Call** in inglese con la resa fonetica di D-060 (la stessa
  doppia lingua già nel progetto: la voce dice "rilancia", il pulsante dice "Raise" — **non uniformato**).
- **Buco di accessibilità chiuso: il tavolo rotto ora si DICHIARA (D-073).** Conferma è vincolata alla
  **selezione** (non al tavolo), quindi si può calare una combinazione che ruba una carta e ne rompe
  un'altra, lasciando il tavolo **invalido** — è ciò che il Machiavelli **è**, e il vincolo vive
  giustamente sul **terminale** (Passa si sblocca solo a tavolo valido). Ma questo creava uno **stallo
  cieco**: il vedente vede il tavolo scomposto e capisce; il cieco preme Passa, non succede niente, e
  **resta senza informazione**. Risolto **senza sconfinare nel suggerimento**: (1) un **knob** la cui
  combinazione è rotta la **dichiara** ("scala di picche incompleta", "combinazione incompleta di
  sette") — `MachiavelliSpeechMap.brokenTitle`, pura **descrizione** (la stessa cosa che il vedente
  vede), **mai** cosa manca né dove prenderla; (2) il pulsante **Passa non è più disabilitato**: quando
  è bloccato, toccarlo **annuncia la ragione** (nominando la combinazione rotta) e la sua **hint**
  la porta — così chi ci arriva a swipe la scopre. `passBlockedReason` (VM) descrive lo stato: "non hai
  calato nulla" oppure "il tavolo non è valido: [combinazione rotta]". **Nessun giocatore può restare
  bloccato senza sapere perché e dove.** Guardiano test: la dichiarazione usa **solo** le 3 chiavi
  `machiavelli.broken.*`, nessuna nomina una carta mancante; e ogni tavolo invalido-con-piazzamento
  espone **sempre** una combinazione rotta da nominare. **Stabilità del sottoalbero** preservata: il
  knob commuta **colore e label** (proprietà), non aggiunge/rimuove sottoviste (D-052).
- **Vincoli:** motore Machiavelli e altri motori **non toccati**; predicato di validità **unica fonte**
  (il knob e `passBlockedReason` interrogano `MachiavelliRules`, non re-implementano); nessuna logica di
  validità nella UI; nessun `UIAccessibility.post` diretto; Riverwood/Skypool invariati; nessun tavolo di
  poker costruito al ClockTower (solo letto previsto nel catalogo); pulsanti d'azione non uniformati.
  **411 test verdi** (405 + 6). **TestFlight caricato: build 1784043541.**

### D-074 — Correzione UI Machiavelli dopo il primo test reale: nastro, colonne, ritmo
Tre correzioni dopo il primo test dell'utente sul telefono (il gioco funziona; queste tre cose
andavano riviste). Il primo punto nasce da un malinteso nel prompt di D-072, non da un mio errore: la
struttura qui è quella che l'utente aveva in mente dall'inizio.
- **Il box di composizione è un NASTRO ORIZZONTALE unico, non una griglia.** La metà bassa scorreva
  verticalmente su più righe: difetto **fatale** per il cieco emerso solo giocando — le combinazioni
  **escono dalla vista** mentre si scorre e la navigazione diventa caotica. Un **nastro orizzontale
  unico** è una **sequenza pura**, senza strati né righe che entrano/escono: la struttura più leggibile
  per chi naviga a swipe, perché **il gesto è lineare e la struttura è lineare** (nessuna traduzione tra
  i due — principio permanente in CONVENTIONS §4). Struttura del nastro: **carte in mano ordinate** →
  **divisore verticale "tavolo"** → per ogni combinazione un **proprio divisore TITOLATO** (stesso
  titolo e stesso tipo di annuncio dei knob: "scala di picche dal cinque al dieci", "tris di assi")
  seguito dalle **sue carte**. Così scorrendo il giocatore incontra titolo → carte → titolo → carte, e
  **la struttura del tavolo gli arriva mentre scorre**, senza ricostruirla a memoria. La metà alta (il
  **pool**) e la **distinzione acustica imposta** restano invariate: le carte del nastro **non** hanno
  annuncio di stato, ogni carta del pool si annuncia **"selezionata"** (marcatore di zona). **Nessuna
  azione di salto** tra i divisori (l'utente vuole prima la struttura pura; non anticipato). La
  **stabilità del sottoalbero** è preservata: la struttura del nastro è **fissa** per la vita del box
  (selezionare cambia solo il pool, mai il tavolo), la label di una carta è **costante**, la selezione
  commuta un overlay per **opacity** — nessun add/remove di sottoviste (cruciale con decine di selezioni
  consecutive).
- **Il tavolo dispone le combinazioni in COLONNE.** Ogni combinazione è una **colonna** (carte impilate
  verticalmente, **più strette** per far stare le colonne), e i **knob** sul bordo inferiore risultano
  **tutti allineati su UNA linea** in fondo, **vicini ai pulsanti d'azione**. Non è estetica: allineati e
  in fondo significa **consecutivi nell'ordine di lettura di VoiceOver** (stessa y → una riga letta dopo
  le carte) e **a un passo** dai tasti — così il cieco che vuole il **quadro del tavolo** lo raggiunge
  **subito** invece di attraversare mezza interfaccia. **È accessibilità che passa dal LAYOUT, non dagli
  annunci.** Realizzazione: `HStack` orizzontale di colonne, ciascuna `frame(maxHeight: .infinity)` con
  la knob spinta in fondo dallo `Spacer` → knob su una linea. **Le carte della colonna sono
  `accessibilityHidden`**: il cieco legge **solo i knob** (uno per colonna) e ne percorre le carte con le
  **azioni personalizzate** (o col nastro del box) — niente clutter, i knob sono il quadro. **Sacrificio
  per far stare le colonne:** le carte sono rese **slim** (34×46) impilate a ventaglio verticale con
  offset calcolato per stare in un'area fissa (così colonne di lunghezza diversa restano alte uguali e i
  knob restano allineati); mostrano il simbolo **in alto** per restare leggibili nel ventaglio.
- **Trascinamento con carte strette (vedente):** le colonne sono **drop target** (trascini una carta di
  mano nella combinazione), le carte slim del ventaglio sono **draggabili** dalla loro striscia visibile,
  e **toccando una colonna** questa si **espande** in un overlay orizzontale a grandezza piena per
  afferrarle comodamente. Tutto **sighted-only** e `accessibilityHidden`: **nessun effetto** sul cieco
  (che raggiunge le carte via knob + nastro).
- **Ritmo degli annunci: applicata la disciplina che il Machiavelli aveva saltato.** Al tavolo gli
  annunci si **troncavano** l'un l'altro. Causa: in modalità VoiceOver-app **OFF** il `pace` usava una
  **pausa fissa breve** anche dopo un evento **parlato**, così l'annuncio successivo si accodava mentre
  il precedente parlava (i tavoli di poker **aspettano** il canale parlato). Fix: `pace(_:spoke:)` —
  dopo un evento che ha **parlato**, la UI **attende il canale parlato quieto** (conductor + coda) prima
  di avanzare **in ENTRAMBE le modalità**, così annunci ravvicinati (es. più combinazioni in sequenza)
  **non si sovrappongono né si troncano**; gli eventi **muti** mantengono la pausa fissa fluida (OFF) o
  l'attesa adattiva (ON). L'attesa è **limitata dal safeguard anti-freeze** di `SpokenChannelPacing`
  (backstop **sopra** la voce più lunga, **non** un budget di parlato — D-056/D-068). Tutto passa già
  dalla `AnnouncementQueue` (serializzata, priorità, drop) col `SpeechConductor`; nessuna
  `UIAccessibility.post` diretta; ogni continuation ha il suo timeout. Le voci di fine mano/partita
  arrivano una volta (nessuna dedup necessaria).
- **Vincoli:** motore Machiavelli e altri **non toccati**; predicato **unica fonte** per box e drag;
  nessuna logica di validità nella UI; **stabilità del sottoalbero** rigorosa; focus-landing sul box;
  la dichiarazione dello **stallo del tavolo rotto** (D-073) resta e funziona (il Passa bloccato resta
  agganciabile e spiega); descrivi-non-consigliare inviolato; Riverwood/Skypool intatti. **413 test verdi** (411 + 2). **TestFlight caricato: build 1784047983.**

### D-075 — Machiavelli: dietrofront su mano↔partita (una mano sola), il punteggio diventa RIMBORSO, gesto di salto nel nastro
Correzione dopo il **test reale con VoiceOver**: il campo ha **rovesciato** una decisione presa in
astratto (D-071) e confermato un'aggiunta rimandata (D-074).
- **DIETROFRONT: la partita è UNA MANO SOLA.** Con D-071 avevo introdotto la struttura mano↔partita a
  soglia di punti perché "una mano sola sembrava troppo poco" — ma la **misura era fatta tra BOT**. Con
  la partita giocata **davvero, a mano, con VoiceOver**, il rapporto si è **ribaltato**: una mano sola
  **non è poco, è già lunga**, e tre mani sono **~un'ora** — troppo per una partita di carte su un
  telefono. **La lezione (permanente, in CONVENTIONS §4):** un turno di poker è una **decisione**, un
  turno di Machiavelli è **lavoro**. Contando i turni tra bot li contavo tutti uguali, ma un turno umano
  di Machiavelli con VoiceOver — scorrere una catena di decine di carte, selezionare, comporre,
  confermare — vale in **tempo reale** dieci turni di poker. **Il costo di un turno per un non vedente
  non si misura in EVENTI ma in LAVORO DI NAVIGAZIONE**, e ogni stima di durata deve tenerne conto.
  Rimossa la soglia e la sequenza di mani: **chi va out vince la partita**, la fine della mano è la fine
  della partita. `MachiavelliSessionDriver` gestisce **una mano** (via GameWorld, non il motore).
- **Il PUNTEGGIO sopravvive ma cambia funzione: RIMBORSO parziale del buy-in.** Il calcolo dei punti
  (`MachiavelliScoring`, nel motore) **NON è toccato** — asso 10, figure 5, numerate 1, bonus out, punti
  per il calato, malus per il rimasto; cambia solo **cosa ne fa il driver**. Non più una soglia da
  superare in più mani, ma: **chi va out vince e tiene il pieno buy-in** (il vanto è il premio — al
  ClockTower si gioca per il prestigio, non per il denaro, D-072); **chi perde recupera una percentuale
  del proprio buy-in proporzionale a quanto bene ha giocato** (misurato dal punteggio finale). La
  meccanica (`MachiavelliRefund`, in **GameWorld** — economia di sessione) fa un **lavoro doppio**: dà
  **scopo a chi perde la mano** (ogni carta calata prima che l'avversario chiuda ripaga, ogni carta
  pesante rimasta costa) **senza allungare la partita di un turno**, e tiene viva la leva
  `machiavelliMalusAversion` con una **ragione economica** concreta (il bot che tiene l'asso quando
  l'avversario è a due carte dall'out ha un interesse **vero** a scaricarlo). **Coerenza narrativa** (che
  orienta la calibrazione): è la **prima volta** nel progetto in cui l'economia di un tavolo **esprime il
  carattere del casinò** invece di scalare i numeri — un luogo dove perdere non ti rovina e dove **come
  hai giocato conta più dell'esito** è esattamente il ClockTower; il rimborso è un **gesto di riguardo**
  verso chi ha giocato bene, non un paracadute che annulla la sconfitta.
- **La CURVA del rimborso (calibrata sui punteggi reali misurati — il leader di una mano segna ~100).**
  Lineare: **0%** fino a un `scoreFloor = 20` (chi non ha calato quasi nulla e siede su una mano quasi
  intatta — se anche lui recuperasse, la meccanica non punirebbe niente e sarebbe inutile), sale fino al
  **20%** a un `scoreCeiling = 90` (chi ha giocato bene e perso di poco, appena sotto il ~100 del
  vincitore), lineare in mezzo. Buy-in 1200 → un forte perdente recupera **240**, un perdente medio
  (score 55) **120**, uno scarso **0**.
- **DA TESTARE CON `DEBUG_FREE_PLAY` SPENTO (il test che conta).** Col flag ON la meccanica è **invisibile**
  (buy-in ignorato, saldo pinnato): l'utente non la vedrà finché non cade. Costruita e testata con il
  flag **OFF**, sul **movimento reale dei gettoni**: chi vince incassa il pieno buy-in (netto zero), chi
  perde incassa il rimborso corretto, il saldo si aggiorna (`PlayerAccount`).
- **Gesto di SALTO tra i divisori del nastro (D-074 → richiesto dal campo).** In D-074 l'utente aveva
  chiesto di provare **la struttura pura** senza salto; il campo ha risposto: in una partita avanzata il
  nastro è lungo e raggiungere l'ultima combinazione carta-per-carta è **una maratona di swipe**. Aggiunta
  un'**azione personalizzata** su ogni divisore (tavolo = ancora 0, combinazioni = 1…n) che sposta il
  focus VoiceOver al divisore **successivo/precedente** (via `@AccessibilityFocusState`), **clampata** ai
  due estremi. La logica delle ancore è **pura e testabile** (`MachiavelliBoxState.nextDivider/
  previousDivider`), la view la applica. **Scopribile** via l'**hint** di ogni divisore ("scorri in su o in
  giù per saltare tra le combinazioni"): un gesto che il cieco non sa che esiste non serve. **Sottoalbero
  stabile:** il salto è un **modificatore** (focus + azioni + hint), non aggiunge/rimuove sottoviste.
- **Vincoli:** motori **non toccati** (rimossa solo la struttura multi-mano, che vive in **GameWorld**;
  la funzione pura di punteggio è intatta); `machiavelliMalusAversion` resta additiva; predicato **unica
  fonte** per box e drag; nessuna logica di validità nella UI; nessun `UIAccessibility.post` diretto;
  distinzione acustica nastro↔pool intatta; **stallo del tavolo rotto (D-073)** funzionante; descrivi-non-
  consigliare inviolato; Riverwood/Skypool intatti. **Rimosso** il test che pinnava l'accumulo tra mani
  (dichiarato). **420 test verdi** (413 + 7 nuovi, −1 multi-hand). **TestFlight caricato: build 1784055333.**

### ⚠️ Lezione per sessioni future — misurare la durata col LAVORO, non con gli eventi
Per un gioco a forte **carico cognitivo per turno** (Machiavelli), **non stimare la durata contando i
turni/eventi**: un turno umano navigato con VoiceOver costa in **tempo reale** molte volte un turno di
poker (scorrere/selezionare/comporre/confermare su decine di elementi). Le misure **tra bot** ignorano
questo costo e portano a decisioni sbagliate (è successo con la soglia mano↔partita di D-071, ribaltata
in D-075). **Regola:** stima la durata in **lavoro di navigazione reale**, non in numero di eventi, e
convalida sempre con un **test umano** prima di consolidare una meccanica che dipende dalla durata.
### D-076 — `studBoardReading`: dimensione additiva per la lettura delle carte scoperte (Stud)
Lo Stud ha un'abilità **assente in ogni altro gioco**: leggere le **carte scoperte** degli avversari
(pubbliche) — foldare quando il tabellone avversario è minaccioso, inseguire quando le carte che servono
sono ancora vive, abbandonare un progetto le cui *out* sono morte nelle scoperte altrui. Nuova
**dimensione additiva** di `Personality` (in `GameEngine`, dove vive `Personality`): `studBoardReading`
(0…1). Solo il bot dello Stud la legge, quindi il default (0.5) è **libero** e non tocca gli altri giochi
(retrocompatibilità additiva **verificata**: cambiare `studBoardReading` non muove una decisione Texas —
`StudBotTests.testStudBoardReadingDoesNotAffectTexas`). È una **leva, non un valore calibrato** (taratura
dopo il test reale). Meccanica: l'equity Monte Carlo dello Stud rimuove **già** dal mazzo tutte le carte
visibili (le *dead cards* riducono onestamente l'equity per costruzione, D-011); `studBoardReading`
modula in più la **risposta** a un tabellone minaccioso — `StudStrength.boardThreat` (coppia/tris
scoperti, tre-o-più a colore/scala) penalizza la forza percepita in proporzione a quanto il bot legge. È
la seconda leva di fold (con `pressureResistance`/`trashFoldTendency`, D-048), su un asse ortogonale (la
lettura del tabellone, non la pressione della puntata).

### D-077 — Seven-Card Stud Pot Limit: quinto motore + driver, regole canoniche fissate
**Quinto motore** del progetto, in `GameEngine/Stud/`, **parallelo e indipendente** da Texas/Draw/Omaha/
Machiavelli (nessun import incrociato; condivide **solo** i fondazionali `Card`/`Rank`/`Suit`/`Deck`/
`HandEvaluator` e l'aritmetica chip game-agnostica `PotMath`/`Pot`). Lo Stud è **strutturalmente diverso**
da tutti: **nessun board comune** (ogni giocatore ha le sue carte, scoperte e coperte), **cinque giri di
puntata**, **ante + bring-in** invece delle blind, "il tabellone scoperto più forte apre" — quindi motore
proprio (D-077).
- **Regole canoniche FISSATE (dichiarate perché una sessione futura non le riscopra), con libertà di
  giudizio come per Omaha:** un mazzo da 52. **Best five of seven** non vincolato (`HandEvaluator.evaluate`,
  a differenza del 2+3 di Omaha). **Ante** da ogni seat prima della distribuzione. **Distribuzione/street:**
  terza strada = **2 coperte + 1 scoperta** (giro 1); quarta/quinta/sesta = **1 scoperta** l'una (giri 2–4);
  settima ("river") = **1 coperta** (giro 5) → 3 coperte + 4 scoperte = 7 carte. **Chi apre:** terza strada
  la **carta scoperta più BASSA** posta il **bring-in** (obbligata parziale forzata; parità di rango rotta
  dal seme, **fiori il più basso**: ordine bring-in fiori<quadri<cuori<picche); quarta–settima apre il
  **punto di poker SHOWING più alto** nelle scoperte. **Betting POT LIMIT** (imposto): ogni bet/raise
  cappato alla dimensione del piatto (`PotMath.potLimitMax…`, riuso concettuale da Omaha, **nessun import
  incrociato**); una sola misura minima di puntata `bet` (lo split small/big-bet del limit è **caduto**: in
  Pot Limit il tetto del piatto governa la crescita); il bring-in è **minore** di `bet`, un giocatore lo
  **completa** rilanciando a `bet`; **nessun cap** al numero di raise (il Pot Limit si autolimita, come
  Omaha). **Esaurimento del mazzo:** con molti giocatori il mazzo può finire in settima (7×8=56>52) →
  canonicamente **una sola carta COMUNE scoperta** condivisa da tutti come settima (`communityCard`); coi 3
  giocatori del ClockTower non scatta mai, ma il motore la gestisce e la testa.
- **`StudHand`** value type con transizioni `mutating`, sincrono, deterministico via seed. La macchina di
  betting **riusa la forma provata di Omaha** (currentBet/lastRaiseSize/actionReopened/tetti pot-limit,
  side pot), estesa con: ante, bring-in come posta parziale con **completamento** (`betComplete`),
  first-to-act per **carta più bassa** (terza) / **showing più alto** (dopo), distribuzione up/down per
  street, `StudShowing` (ordine seme del bring-in + chiave comparabile del punto scoperto). **Nessun button**
  (lo Stud non ne ha): ordine di distribuzione fisso su mazzo mescolato.
- **Bot onesto (`HeuristicStudBot` + `StudStrength`):** vede le **scoperte di tutti** (pubbliche) + le
  proprie 7-in-corso, **mai** le coperte altrui (`StudBotContext`/`StudPublicSeat` con `upCards`, redazione
  **verificata** — `StudBotTests`). Forza: euristica di terza strada (tris "rolled up", coppie, tre a
  colore/scala, carte alte) + equity Monte Carlo che completa ogni mano a 7 rimuovendo dal mazzo le carte
  viste (dead-card aware). Modulato da `studBoardReading` (D-076) e dalle leve di fold esistenti.
- **`StudSessionDriver`** (GameWorld): sorella dei driver poker con flusso `StudSessionEvent`/`StudEventHub`
  proprio (riusa solo `EventAudience`/`EventViewer`), eventi **descrittivi non prescrittivi**, audience
  privata esplicita (coperte solo al proprietario; **scoperte pubbliche**), bot via contesto redatto, seed
  **casuale in produzione / iniettabile nei test** (D-047, non riscoperto), narrazione della distribuzione
  street-per-street (ogni scoperta annunciata a chi ascolta). Supporto `StakeEscalation` (default `.none`).
  Cliente puro del motore; chip conservati (invariante testato).
- **Vincoli:** sottocartella dedicata, nessun import incrociato, `Personality` additiva, determinismo dato
  seed, **motori esistenti intatti** (Texas/Draw/Omaha/Machiavelli invariati, test verdi), **nessuna
  ricalibrazione** delle personalità esistenti.

### D-078 — ClockTower Stud GIOCABILE: interrogazione delle carte scoperte + Premio della Casa
Lo Stud diventa **giocabile end-to-end** al **ClockTower** (il casinò esisteva già — solo un tavolo nuovo,
la generalizzazione D-065/D-067 ha retto: un caso `CasinoGame.stud`, una voce nel registry, palette e slot
audio ereditati per **dati**). Buy-in **3000** (il più alto del ClockTower: qui il registro è il **denaro**,
non il prestigio), due avversari.
- **Personalità del posto per il poker (in GameWorld, `WorldPersonalities.clockTower*`):** i tre regolari
  della torre costruiti come **giocatori di poker** con le leve del poker (prima esistevano solo con le
  dimensioni del Machiavelli). **lo Studente** (brillante ma inesperto: gioca troppo, aggressivo, legge male
  i tabelloni — `studBoardReading` 0.35), **il Bibliotecario** (adulto metodico, di mezzo — definito per un
  terzo seggio futuro), **il Professore** (vecchio maestro: paziente, selettivo, imperturbabile, il miglior
  lettore — `studBoardReading` 0.95). Il tavolo siede **Studente + Professore**: un **MIX deliberato** — lo
  studente è un punto morbido battibile (così il **premio della Casa è davvero guadagnabile**), il professore
  è il muro. Sono **leve non calibrate**; nessuna ricalibrazione degli altri casinò.
- **IL PREMIO DELLA CASA (meccanica economica nuova, D-078, in GameWorld — `HousePrize`).** Ogni volta che il
  **giocatore vince una mano**, la Casa **aggiunge** un premio **piatto** (200) al piatto vinto. **Non è un
  rake né una tassa:** è un **incentivo** che riconosce chi vince il gioco più difficile e dà al tavolo un
  carattere **competitivo e legato al denaro** (a differenza del Machiavelli, cerebrale, dove il vincitore non
  guadagna nulla): il ClockTower resta un casinò, **qui si può guadagnare col proprio intelletto**. Vive nel
  **driver** (`housePrize` + `prizeRecipientID`), **non nel motore** (`StudHand` lo ignora): a fine mano, se
  il destinatario è tra i vincitori del piatto, il driver **aggiunge** il premio alle sue fiches e emette
  `housePrizeAwarded`. **Calibrazione (200 su buy-in 3000, ante 25/bring-in 25/bet 50):** ~alcuni giri d'ante,
  una piccola frazione di un piatto conteso — **percepibile** ma non una macchina da soldi. **Testato col
  movimento reale dei gettoni, `DEBUG_FREE_PLAY` OFF** (buy-in dal `PlayerAccount` → sessione con vincite →
  cash-out: il premio **arriva davvero** al saldo persistente; il premio è l'**unica** iniezione di chip nella
  sessione — invariante testato). Con free-play ON è invisibile (come da D-050), perciò i test lo esercitano
  **spento**.
- **L'INTERROGAZIONE DELLE CARTE SCOPERTE (la sfida vera del gioco, D-078).** Nel Texas le 5 comuni le vedono
  tutti; nello Stud ogni avversario ha scoperte **diverse**, e leggerle è il cuore strategico — il vedente le
  ha tutte davanti agli occhi, il cieco non può tenerle a mente (2 avversari × fino a 4 carte + le proprie).
  Soluzione a **due meccanismi** (ora principio permanente in CONVENTIONS §4): (a) **ogni scoperta è
  annunciata mentre viene distribuita** (parità col vedente che la vede apparire — "il Professore riceve il re
  di cuori scoperta"); (b) **lo stato corrente è interrogabile a comando** — ogni **badge avversario** è un
  elemento accessibile la cui label legge, allo swipe, il suo **tabellone corrente** ("il Professore,
  scoperte: re di cuori, dieci di picche"), la memoria che il vedente ha con lo sguardo. **Descrive, non
  consiglia** ("ha scoperti X, Y" — mai "potrebbe avere un colore"): guardiano di test che scandisce le
  stringhe Stud e **vieta** il linguaggio consultivo (`StudSpeechMapTests`). La label si deriva dallo **stato
  corrente**, mai da uno snapshot (spirito D-058). Senza questa interrogazione il non vedente giocherebbe uno
  Stud **mutilato** — viola il principio fondativo.
- **UI (`StudTableView` & c.):** stato/riduzione puri dedicati (`StudTableState`/`StudTableReducer`, con le
  scoperte **per-seat** che alimentano l'interrogazione), VM (`StudTableViewModel`) speculare a Omaha, box
  raise **Pot Limit** riusato (max = tetto del piatto, pulsante "Piatto" quando lo stack supera il piatto —
  niente shove, D-066); zona umana che **distingue** le proprie coperte (private, mostrate a faccia in su al
  giocatore) dalle scoperte (pubbliche). Palette bronzo/pergamena del ClockTower. Riuso di tutta
  l'infrastruttura trasversale (chrome, coda annunci, conductor, modalità VoiceOver + ritmo adattivo,
  focus-landing D-057, `HandGate`, `EndOverlay`).
- **Audio:** croupier = **lo stesso uomo anziano custode** del Machiavelli, ora al poker, **italiano erudito**
  (niente anglicismi nel parlato — "rilancio"; i **pulsanti** restano Raise/Fold/Call, D-073). **10 slot nuovi**
  `vo_it_clock_poker_*` (informativi → **fallback a sintesi**, D-030), incluso il **cue distintivo del premio
  della Casa**; nessun file prodotto (giocabile coi fallback). Letto ambientale = quello **classico** di
  default del ClockTower (archi), non il clockwork del Machiavelli (D-073): al poker le attese sono brevi e una
  musica strutturata le riempie. Colore bot: riuso degli slot Machiavelli `vob_clock_*` (ambientali → silenzio,
  D-066). Nessun anti-pattern D-051 (contenuto → sintesi; registro → fallback, mai entrambi lo stesso testo).
  Catalogo `ClockTower_audio_catalog_voices.md` aggiornato (§2 cablata).
- **Vincoli rispettati:** direzione dipendenze; motore Stud e altri **non toccati** dall'UI; `BotContext`
  redatto; eventi descrittivi; nessun `UIAccessibility.post` diretto (tutto via `AnnouncementQueue`); ogni
  `CheckedContinuation` col timeout (riuso `SpokenChannelPacing`); cache dallo stato corrente; Riverwood/
  Skypool/Machiavelli invariati. **460 test verdi** (420 → +40) + XCUITest del tavolo Stud. **Caricato su
  TestFlight (build 1784060127).** **Girano ora QUATTRO giochi di poker + il Machiavelli in TRE casinò.**

### D-079 — Premio della Casa dello Stud: da per-mano a traguardo di fine partita (correzione)
Il premio della Casa (D-078) era erogato **a ogni mano vinta** dal giocatore, aggiunto alle sue fiches al
tavolo. **Perché era sbagliato (motivazione onesta).** Nel diff di D-078 avevo *notato* che il premio
perturbava il gioco più del previsto (aggiungere fiches cambia lo stack, i bot vedono gli stack, e in Pot
Limit il tetto dipende da stack e piatto) e l'avevo trattato come una **curiosità tecnica**. Era invece il
**sintomo che il design era sbagliato**: il premio stava diventando un **moltiplicatore di vantaggio dentro
la partita** (chi vince la prima mano gioca la seconda da posizione migliore → **valanga**) invece di un
**riconoscimento dopo la partita**. Il prompt originale ("ogni volta che il giocatore vince una mano") era
formulato male; l'intento era **vincere la PARTITA**.
- **Correzione:** il premio **non si eroga mai durante la sessione**, non tocca gli stack, non entra nel
  piatto, non è visibile al tavolo, i bot non ne vedono nulla. È pagato **solo al cash-out di fine
  sessione**, e **solo se il giocatore ha eliminato TUTTI gli avversari** (bustati entrambi). Chi si alza
  in attivo senza aver bustato il tavolo tiene le fiches vinte e **nient'altro**. È il riconoscimento di
  **aver battuto il tavolo** (compreso il Professore), non un cashback proporzionale.
- **Dove vive:** `HousePrize.beatTheTable(heroChips:opponentChips:)` e `cashOut(...)` — funzioni **pure in
  GameWorld** che il **view model** invoca al cash-out (identico pattern del `MachiavelliRefund`, D-075). Il
  **motore e il driver (il tavolo) non sanno nulla**: dal driver è stato rimosso ogni `housePrize`/
  iniezione. **Invariante ripristinato e testato:** *le uniche fiches che entrano in un tavolo sono i
  buy-in* (`testTableChipsAlwaysConserved`). Il vecchio test "il totale al tavolo cresce dei premi" **non
  ha più ragione di esistere** ed è stato rimosso (dichiarato).
- **Ricalibrazione:** 200 (per erogazione frequente per-mano) → **1500** (metà del buy-in di 3000).
  Erogazione **unica e rara** (bustare due avversari, incluso il paziente Professore): 1500 è un
  riconoscimento reale sopra i ~6000 netti già vinti prendendo tutto il tavolo, senza rendere il tavolo una
  macchina da soldi (scatta al più una volta, solo su vittoria del tavolo). Il custode annuncia il premio
  **una volta**, a fine partita (voce).
- **Testato col movimento REALE dei gettoni, `DEBUG_FREE_PLAY` OFF:** il premio arriva al saldo persistente
  **se e solo se** entrambi gli avversari sono eliminati; **mai** per chi si alza in attivo senza bustare;
  **mai** su bust. **Principio permanente in CONVENTIONS §8:** un'iniezione economica dentro una sessione di
  poker non è mai neutra — gli stack sono leva strategica e i bot li vedono.

### D-080 — Cablaggio audio del ClockTower + missaggio per-tavolo + dosatura dell'orologio
L'utente ha prodotto i file audio del ClockTower (ElevenLabs/StableAudio) e li ha depositati. Cablati; il
cablaggio **non ha richiesto modifiche alla logica** (gli slot esistevano già), salvo il **comportamento
nuovo** esplicitamente richiesto: missaggio e dosatura. Riscontro catalogo↔pool: **22 file cablati, 2
ambigui esclusi**.
- **Convenzione di naming (dell'utente, rispettata):** `vo_it_tower_*` = croupier ai tavoli di **poker**;
  `vo_it_clock_*` = arbitro al **Machiavelli**. È **lo stesso custode anziano**, due insiemi di battute.
  Perciò gli slot `vo_it_clock_poker_*` (miei, D-078) sono stati **rinominati `vo_it_tower_*`**.
- **Riscontro completo:**
  - *Ambient (7/7 presenti):* i sei nomi esatti + `amb_clocktower_machiavelli_thinking` **rinominato**
    `…_thinking_01` (mancava `_01`). Tutti cablati.
  - *Machiavelli (`vo_it_clock_*`):* `your_turn` esatto; `combination` **rinominato** `vo_it_clock_meld`
    (semantica = la combinazione calata); `game_end` **rinominato** `vo_it_clock_match_end` (fine partita,
    D-075). **Ambigui, NON indovinati (lasciati fuori, segnalati):** `vo_it_clock_opponent_shift`,
    `vo_it_clock_player_shift` — nessuna mappatura chiara a un evento (turno? attesa?). **Non prodotti (per
    minor verbosità, ok):** `hand_start`, `drew` ("pesca"), `passed` ("passa") → il contenuto informativo
    (conteggio carte / "il Professore pesca") parla comunque; il **registro** tace.
  - *Poker croupier (`vo_it_tower_*`):* l'utente ha prodotto un set **generico/Texas** (blind, flop/turn/
    river, button). Il solo tavolo di poker del ClockTower è lo **Stud**, che ne usa: `new_hand`→hand start,
    `showdown`, `pot_awarded`, `split_pot`, `game_end`→fine sessione. **Cablati.** Gli altri sette
    (`big_blind`/`small_blind`/`flop`/`turn`/`river`/`role_button`/`stakes_rise`) **non mappano** su eventi
    dello Stud (niente blind/comuni/button): **depositati** in `Resources/Audio` (bundle) ma **non
    catalogati né cablati** — riservati a un **futuro tavolo Texas** del ClockTower.
- **Minor verbosità del custode (scelta dell'utente, D-080):** "ciò che non c'è nel pool va escluso del
  tutto." Applicato al **registro del croupier**: gli eventi Stud senza file (apertura strada, all-in) sono
  **SILENZIOSI** (nessun fallback di sintesi del registro), ma il **CONTENUTO** informativo (carte scoperte
  annunciate a una a una, azione dell'avversario "punta tutto", vincitore, mano allo showdown) **parla
  sempre** — è informazione di gioco, non verbosità (accessibilità preservata). **Eccezioni tenute come
  sintesi (funzionali/rare, segnalate):** il **"tuo turno"** (segnale essenziale per il cieco) e il **premio
  della Casa** (ricompensa rara). Nessun anti-pattern D-051 (con i file presenti l'mp3 suona e il fallback è
  soppresso; nessuna voce dichiara sintesi + fallback dello stesso testo — verificato).
- **Missaggio per-tavolo (comportamento nuovo, D-080):** attributi **dati** sui letti (`AmbientBeds.bedVolume`,
  applicato come scala base del bed): poker del ClockTower a **0.80** (~−20% degli altri casinò), Machiavelli
  a **0.65** (~−35%, perché il turno è lungo lavoro cognitivo sul canale audio e la musica non deve
  competere). Riverwood/Skypool restano a **1.0** (invariati, testato). Rotazione che **favorisce calm_02**
  (`ClockAmbientRotation`, ~2/3).
- **Dosatura dell'orologio (comportamento nuovo, D-080):** `amb_clocktower_clock` **non** è più un letto
  continuo. È una **presenza occasionale** (`ClockChime`: pause silenziose ~30–70 s, apparizioni ~4–12 s,
  la pausa **sempre** maggiore dell'apparizione), dosata dai director via il nuovo `AudioServicing.
  setAmbientLayerVolume` (fade del layer già avviato, senza riavviarlo). Così l'orologio della torre si fa
  sentire **ogni tanto**, mai un ticchettio costante (tortura in partite lunghe). Gli altri casinò tengono il
  loro layer **continuo** (`layerIsOccasional` default false).
- **Ritmo con voci reali (D-056/D-068 verificato):** la voce cablata più lunga è ~3.4 s (showdown) + il
  contenuto (~2–3 s) ≈ ≤6 s; il tetto anti-freeze del ritmo adattivo (VoiceOver-ON) è **8 s**, sopra la voce
  più lunga (backstop, non budget di parlato); i timeout di completamento per-clip dell'`AudioEngine`
  (durata + margine) reggono le durate reali.
- **Vincoli:** motore Stud e altri **non toccati**; `Audio` resta trasversale (aggiunta solo una primitiva di
  fade del layer); nessuna iniezione di fiches al tavolo; nessun `UIAccessibility.post` diretto; eventi
  descrittivi; Riverwood/Skypool **invariati** (palette identità pin verde); rimborso Machiavelli non toccato.
  **472 test verdi** (+6 dal cablaggio/missaggio/dosatura). Cataloghi audio aggiornati allo **stato reale**.
  **Caricato su TestFlight (build 1784066297).**

### D-081 — Machiavelli: cue di RIMANEGGIAMENTO del tavolo (opponent_shift / player_shift)
Chiarito dall'utente cosa fossero i due file lasciati ambigui in D-080: **`vo_it_clock_opponent_shift`** e
**`vo_it_clock_player_shift`** scattano quando un turno **altera combinazioni GIÀ ESISTENTI** sul tavolo
(rimaneggiamento), **non** quando si aggiunge soltanto una nuova combinazione. Corrisponde **esattamente** al
flag `rearrangedExisting` dell'evento `tableChanged`, distinto per **chi** l'ha fatto:
- **opponent_shift** — un **avversario** rimaneggia (`tableChanged`, `rearrangedExisting == true`, non hero):
  sostituisce il cue `meld` come **lead** (il contenuto dice già "rimaneggia il tavolo e cala…").
- **player_shift** — il **giocatore umano** rimaneggia: prima il suo turno che rimaneggiava era **muto**
  (solo il box confermava); ora un **cue di conferma udibile** ("Hai rimaneggiato il tavolo") — utile al
  cieco. Il meld semplice dell'umano resta muto (il box conferma).
Solo `UI`/`Audio`/localizzazione: due slot `SoundCatalog`, due `Cue` in `MachiavelliSpeechMap`, selezione
per-seat nel VM, stringhe it/en. I due file **cablati** (erano gli unici "ambigui" di D-080). **472 test
verdi.** **Caricato su TestFlight (build 1784067206).**

### D-082 — La causa reale del fold precoce nel Draw: un DISALLINEAMENTO DI SCALA, non la taratura delle leve
Dai test dell'utente sul telefono: nel Five-Card Draw il rock foldava **prima ancora della fase
di cambio**, e l'aggressivo apriva senza jacks-or-better venendo squalificato di continuo. Il
prompt poneva due ipotesi alternative (taratura delle leve *oppure* valutazione che ignora il
costo reale di restare). **Misurato, non assunto** — 4000 mani simulate per personalità al tavolo
Whiskey: rock **96%** di fold pre-cambio (**98%** delle coppie, **93%** delle doppie coppie),
1148 squalifiche su 4800 mani, e **nessuna sessione che converge** (400 mani su 400, 12 seed su 12).
- **La causa reale è la seconda ipotesi, ma più precisa di come era formulata.** Non è che il costo
  di restare non fosse contato (le **pot odds sono nella formula**): è che i due lati del confronto
  **stanno su scale incompatibili**. `DrawStrategy.strength` restituiva un punteggio **ORDINALE DI
  CATEGORIA** (misurato: coppia max **0.20**, doppia coppia **0.30**, tris **0.40** — letteralmente
  `categoria/9 × 0.9`), mentre `continueBar`/`callBar` sono costruite su scala **equity/pot-odds**
  (≈**0.39** per il rock a quelle poste). Mele contro pere: una coppia d'assi vince ~65% delle volte
  ma "vale" 0.20, quindi folda. **Il rock foldava tutto sotto il tris.**
- **Verificato il contrasto con gli altri tre motori:** Texas, Omaha e Stud alimentano la **stessa
  identica formula di barra** con una **equity Monte Carlo reale** (0…1). **Solo il Draw** usava una
  scala di categoria. Non era una scelta di design condivisa: era un difetto **isolato** in un solo
  file. Aggravante: `strength` escludeva **per progetto** il potenziale di pesca ("There is no draw
  potential here"), quindi **prima del cambio** ogni progetto valeva ~0.1 — mentre il primo giro è
  esattamente il momento in cui nessuno sta puntando una mano finita.
- **La STESSA causa spiega le squalifiche dell'aggressivo** (il prompt le trattava come problema
  separato). Misurato: apriva **36%** delle volte **senza** requisito e solo **3%** delle volte in cui
  **ce l'aveva** — l'esatta inversione. Perché il ramo di apertura legittima richiedeva
  `perceived >= valueBar` (0.43 → su quella scala "una scala o meglio", quindi mai con una coppia di
  donne), mentre il ramo bluff-open era **puro dado, senza alcun gate di forza**.
- **Correzione (nel LAYER BOT di `GameEngine/Draw/`, dichiarata e approvata prima di procedere; le
  REGOLE — `FiveCardDrawHand` — non sono state toccate):**
  - **`DrawStrategy.equity(cards:opponents:drawToCome:samples:using:)`** — Monte Carlo seedato sulla
    **stessa scala** degli altri tre giochi. Con `drawToCome` (primo giro) **gioca lo scambio in
    avanti**: l'eroe pesca le sue carte da manuale e **anche gli avversari**, e il confronto avviene
    sulle **cinque carte che ciascuno terrà davvero** — così un four-flush vale ciò che vale invece
    di essere "carta alta". Onesto per costruzione (avversari uniformi, D-011), deterministico.
    `strength` **resta** ma solo per **ordinare** mani tra loro, con un commento che ne vieta l'uso
    contro una barra di pot odds.
  - **Gate di apertura.** Ramo con requisito: tenere i jacks-or-better **è** la licenza di puntare,
    quindi una mano decente apre a frequenza normale (`perceived >= continueBar`), non solo a
    `valueBar`. Ramo senza requisito: la frequenza è pesata da `foldOutChance = 0.45^avversari`,
    perché un'apertura su aria vince **solo** se tutti foldano e allo showdown è **sconfitta
    d'ufficio** — resta un'arma **heads-up**, diventa la mossa perdente che era in multi-way.
  - **Il carattere NON è stato smussato:** `openingDiscipline` dell'aggressivo resta **0.20** (test
    che lo pinna). La correzione è **strutturale**, non una lobotomia.
- **Costo MISURATO (precedente D-063), con sorpresa:** l'equity del Draw a 160 campioni costa
  **10.5 ms/decisione** contro i **121.8 ms** del Texas a 200 — è **12× più economica**, perché una
  valutazione a cinque carte è molto più leggera di una a sette. Nessun compromesso necessario.
- **Ricalibrazione nei preset di GameWorld** (`WorldPersonalities.riverwoodWhiskey`, nuovo roster
  dedicato: il Whiskey usava il roster condiviso **tarato per il Texas**). `trashFoldTendency` era
  diventato **ridondante e dannoso** (l'equity già declina le mani senza speranza; lasciato alto
  sparava un **secondo** fold cieco prima del cambio che poteva salvarle): rock 0.90→**0.20**,
  novice 0.30→**0.08**, aggressivo 0.15→**0.05**. Rock `tightness` 0.90→**0.68**. **Leve-firma
  intatte:** il rock non bluffa (0.03) e non apre senza requisito (0.95); il novice resta
  bullizzabile (`pressureResistance` 0.35); l'aggressivo resta l'aggressivo.
- **Risultato misurato:** rock, fold di doppia coppia pre-cambio **93% → 0%**, di jacks-or-better
  **<25%**; aggressivo, aperture su aria **36% → 3%** e legittime **3% → 82%**; squalifiche
  **−84%**. Sessioni: **452 → 230** mani (−49%) con le poste nuove (sotto).
- **Il rock è di nuovo ELIMINABILE senza diventare un altro animale:** le sue fiches ora circolano
  (misurato ~45 fiches lorde per mano contro un'ante di 25) e busta in 2 sessioni su 12 bot-vs-bot,
  dove prima **non bustava mai**. Un avversario che non può perdere non è difficile, è un muro.

### D-083 — Un elemento accessibile espone per primo ciò che serve più spesso (badge avversario dello Stud)
Nello Stud il badge di un avversario era **UN SOLO** elemento accessibile che leggeva "nome, fiches,
stato, **scoperte: …**". Ma leggere i tabelloni scoperti è il **cuore strategico** dello Stud e si fa
**molte volte per mano**, mentre nome e fiches servono di rado: il giocatore cieco pagava il preambolo
**a ogni singola interrogazione** — una tassa che il vedente non paga, perché con lo sguardo coglie
solo ciò che gli interessa.
- **Separato in DUE elementi fratelli**, col tabellone **ordinato per primo** dentro il badge
  (`.accessibilitySortPriority`): `opponent.N.board` → "il Professore, re di cuori, dieci di picche";
  `opponent.N` → "il Professore, 3000 fiches, sta agendo". Il **nome resta in testa alla riga del
  tabellone**: con due avversari il dato è inutile senza sapere di chi è — quella è **identità, non
  preambolo**. Ciò che è stato tolto è fiches, stato e l'etichetta "scoperte:".
- **Stabilità del sottoalbero preservata:** il badge diventa un `children: .contain` con due foglie
  fisse; nessun costrutto aggiunge o rimuove sottoviste in base allo stato — **cambia solo la label**
  (pattern D-046). Le due label vivono in un tipo **puro** (`StudBoardReadout`, D-017) così sono
  testabili senza SwiftUI.
- **Descrive, non consiglia** (invariante): il tabellone dice le carte come stanno, mai cosa
  potrebbero significare. Test-guardiano che vieta il linguaggio consultivo nelle righe prodotte.
- **Il difetto esisteva altrove? Verificato: no, non in questa forma.** Texas e Omaha **non hanno
  carte pubbliche per-avversario** (il board è comune), quindi nel loro badge non c'è alcuna
  informazione ad alta frequenza sepolta dietro un preambolo — nulla da separare. Il **Draw** è una
  forma **lieve** dello stesso difetto (il conteggio degli scarti è il suo dato di gioco): lì il dato
  è stato **spostato in testa** subito dopo il nome, ma **non** separato in un elemento proprio —
  si legge ~una volta per mano ed è già annunciato dal vivo, quindi una fermata di swipe in più
  sarebbe rumore. Il criterio è **quante volte per mano viene letto**, non quanto è importante.

### D-084 — Ritmo: l'effetto delle poste sulla durata è NON MONOTÒNO, e al ClockTower la leva giusta è l'escalation
Le sessioni erano troppo lente. La leva attesa era il raddoppio dei minimi. **Misurato prima e dopo,
contando le DECISIONI totali** (proxy onesto del tempo reale e degli annunci che un cieco deve
ascoltare — lezione D-075: misurare il **lavoro**, non gli eventi) — e il risultato ha **rovesciato**
l'assunto:

| Texas Riverwood | 10/20 | 20/40 | 40/80 |
|---|---|---|---|
| decisioni/sessione | 438 | 400 (−9%) | 230 (−47%) |

| Texas Skypool | 10/20 | 50/100 | 100/200 |
|---|---|---|---|
| decisioni/sessione | 254 | **444 (+75%)** | 161 (−37%) |

- **La relazione ha una BUCA.** Bui di taglia intermedia comprano più **fold pre-flop**, quindi piatti
  più piccoli, quindi fiches che passano da uno stack all'altro **più lentamente**: servono **più**
  mani, non meno. Solo oltre la buca alzare le poste accorcia davvero. Corollario che conferma
  l'intuizione dell'utente: **ridurre il fold accorcia le sessioni** più di quanto faccia alzare le poste.
- **Poste applicate:** Riverwood Texas 10/20 → **20/40** (25 BB; guadagno modesto ma allinea la
  profondità); Skypool Texas 10/20 → **100/200** (25–30 BB; **il 50/100 intermedio è stato misurato e
  scartato perché peggiorava del 75%**) — lo Skypool aveva buy-in 5–6× il Riverwood con bui
  **identici**, cioè stack profondi **250–300 BB**: era un errore di scala, non dei bot. Draw Whiskey
  ante 10→**25**, bet 20/40→**50/100** (**452 → 230** mani, −49%). Omaha Marble 25/50 → **40/80**.
- **ClockTower — NON toccato, per identità (la cautela richiesta).** È **Pot Limit**: il tetto di
  puntata **è** il piatto, quindi alzare ante/bet non renderebbe il gioco solo più rapido ma più
  **violento** (piatti più grossi ⇒ puntate massime più grosse), e le poste basse sono parte di cosa
  quel posto **è**. Usata invece `StakeEscalation` (D-064, meccanica già esistente e riusabile):
  **la mano uno resta esattamente com'è oggi** e la sessione stringe solo andando avanti. **Misurato:
  44 → 21 mani (−52%) con il piatto massimo osservato INVARIATO (8805 → 8904)** — cioè velocità
  comprata senza gonfiare di una fiche il tetto pot-limit. È la prova che al ClockTower era la leva
  giusta.
- **Non toccati:** premio della Casa (D-079), rimborso Machiavelli (D-075), boost mano decisiva,
  ante progressivo. **487 test verdi** (472 + 15 nuovi comportamentali). Un test preesistente
  (`testSecondRoundBigBetPressureFoldsMoreForShyBots`) **pinnava la vecchia calibrazione** — sceglieva
  un **tris** come "mano modesta", vero solo sulla scala ordinale rotta; su equity reale vale ~85% e
  nessuno lo folda, quindi confrontava 0 con 0. **Riscritto (dichiarato)** con un progetto fallito
  (equity **misurata** 0.37, tra le due barre reali 0.28/0.41). Il meccanismo di pressione (D-048) è
  **intatto**.

### D-085 — Sincronizzazione dei tre canali: il backlog non era dove la sorvegliavamo (misurato SUL DEVICE)
Quattro sintomi riportati dal test con VoiceOver, che si sono rivelati **facce dello stesso
problema strutturale**. Misurato **sul telefono reale via cavo** con un banco dedicato
(`PacingBench`, lanciato con `-pacingBench`, file audio veri nel bundle) — perché sul simulatore
le completion arrivano sempre e i tempi sono altri (lezione D-056).
- **Numeri misurati.** *(a)* **Latenza clip play→completion: da +0.078 s a +0.127 s** su nove voci
  croupier ⇒ **la garanzia di completion di D-056 FUNZIONA**, l'ipotesi "callback perse" è **morta**.
  *(b)* **Ritmo di parlato reale** 1.17–5.02 s per riga; la stima `speakTime` sbaglia tra **−1% e
  +27%**, sempre per eccesso ⇒ è conservativa e resta valida come euristica di drop. *(c)* **Una
  raffica di showdown a quattro elementi impiega 18.30 s a drenare**, e — il dato decisivo — **la
  profondità della coda annunci non ha MAI superato 1** in tutti quei secondi.
- **LA CAUSA REALE, comune ai sintomi 1, 3 e 4.** La Strategy C di D-032 (priorità + drop) governa
  la `AnnouncementQueue`, ma il `SpeechConductor` — diventato in D-032 l'**unico alimentatore** della
  coda — le passa le voci **una alla volta**, aspettando ogni mp3. Quindi la coda non vede mai un
  backlog da governare: **il backlog si forma nel conductor**, che era una **FIFO ILLIMITATA, senza
  priorità né drop**. Tutto il meccanismo di D-032 era scavalcato **per costruzione**. Non era una
  taratura sbagliata: era il governo applicato nel posto sbagliato.
- **Sintomo 2 (l'effetto di vittoria anticipa l'annuncio) — causa distinta ma imparentata.**
  `AudioDirector.heroChipDeltaFeedback` suonava `fx_win_hand`/`fx_lose_hand` **direttamente** su
  `handEnded`, da **consumatore parallelo con orologio proprio** (D-023), mentre la riga "hai vinto
  con…" era in coda dietro il backlog. Nessun ordinamento fra i due canali: l'effetto **spoilerava
  il risultato**. È un difetto di **informazione**, non di missaggio.
- **Correzioni.**
  1. **Il budget è del CANALE INTERO** (`SpeechConductor.channelBudget` = 6 s): conductor +
     coda, con lo stesso drop per priorità, applicato **dove il backlog si forma davvero**.
     ⚠️ **Trappola in cui sono caduto e che vale registrare:** ho copiato dalla coda la regola
     "non droppare mai la testa" (`dropFirst()`), ma **l'invariante è diverso** — nel conductor
     `pump()` ha già **rimosso** l'elemento in riproduzione, quindi ogni elemento in `pending` è in
     attesa ed è droppabile. Con `dropFirst()` non c'era quasi mai nulla da droppare e **il budget
     non mordeva**: misurato, la raffica restava a **18.26 s**. Codice identico, invariante diverso.
  2. **Ordine esplicito suono↔annuncio:** il conductor accetta un `trailing:` sequenziato **dopo**
     che la riga è stata detta (via la nuova completion per-elemento della coda). L'effetto di
     esito **non può più anticipare il risultato per costruzione**, non per taratura. Se la riga
     viene droppata il cue **suona lo stesso** (nessuno resta senza).
  3. **Il RISULTATO non si droppa mai:** le mani rivelate allo showdown passano da `.medium` a
     `.high`. Il budget può sacrificare il chiacchiericcio, **mai** l'esito della mano.
  4. **Safeguard ADATTIVO** al posto del tetto fisso di 8 s: dimensionato su quanto il canale
     dichiara di dovere (`adaptiveMaxWait`), con pavimento 2 s e tetto duro 25 s. **Un tetto fisso
     non poteva fare entrambi i lavori:** 8 s scattava **in mezzo** a uno showdown onesto, ma
     alzarlo avrebbe congelato altrettanto un freeze vero. Con la stima, la narrazione legittima
     viene attesa e un canale piantato (che non dichiara nulla) scatta in 2 s.
- **Effetto misurato dopo (device).** Raffica di **chiacchiericcio** (10 azioni ravvicinate): il
  canale resta a **4.7 s**, **8 righe droppate**, drenato in **6.8 s** (prima sarebbe cresciuto
  senza limite). **Showdown a tre completamente preservato: 21.69 s**, nulla droppato — il costo
  onesto dell'informazione, ora **atteso** dalla UI invece che troncato a 8 s. Il drop parte dalle
  righe **più vecchie**, così ciò che sopravvive è lo stato attuale del tavolo, non la cronaca stantia.
- **Vincolo rispettato:** il **produttore non è stato toccato**. `SessionDriver` continua a emettere
  a velocità di codice; tutta la soluzione vive nei **consumatori** (`UI`/`Audio`), come da D-015/D-018.

### D-086 — Lasciare il tavolo è una DECISIONE, non una richiesta
Alzarsi era differito a fine mano ("nessuno abbandona una mano a metà"): irritante al poker e
**assurdo al Machiavelli**, dove la mano È la partita e aspettare significa aspettare tutto.
Ora `requestLeave()` **esce subito**, sempre, con le **conseguenze naturali dell'abbandono**.
- **Meccanica:** i provider umani hanno `abandon()`; il turno sospeso **in questo momento** e ogni
  turno ancora a venire si risolvono all'istante (fold; al Draw anche stand-pat sullo scambio; al
  Machiavelli "pesca"), così il driver **finisce la mano a velocità di codice** e la sessione chiude
  pulita senza fiches orfane. Il consumatore smette di narrare e non offre più turni.
- **Costo dell'abbandono, per gioco.** **Poker:** si incassa lo **stack**, e le fiches già spinte
  nel piatto sono **perse** — e questo **non ha richiesto alcuna modifica al motore**, perché lo
  stack è già **al netto** di tutto ciò che è stato puntato: incassarlo **È** la confisca.
  **Machiavelli:** il buy-in **è** la posta e il rimborso (D-075) si **guadagna giocando la mano
  fino in fondo** — si misura su un punteggio finale che una partita abbandonata non ha. Quindi
  abbandonare **perde l'intera posta**: analogo fedele del piatto perso, e **non sfruttabile** (non
  si può uscire al momento giusto per incassare un rimborso parziale). **Stud:** il **premio della
  Casa non ha richiesto alcun caso speciale** — si paga solo a chi **batte il tavolo** (D-079), e
  abbandonare lascia gli avversari vivi, quindi semplicemente non è guadagnato. **Le tre economie si
  conciliano da sole; nessuna meccanica economica è stata toccata nella sostanza.**
- Testato col **movimento reale dei gettoni**, `DEBUG_FREE_PLAY` **spento**.

### D-087 — Fast-forward dopo il fold: toglie l'attesa, non l'informazione
Chi folda non deve più ascoltare i giri di puntata a cui non partecipa. Premuto **fold**, la mano
**corre allo showdown**: gli eventi dei giri non vengono né narrati né pausati (`isPayoff` decide),
mentre **tutti** gli eventi di esito restano **integralmente narrati** — ogni mano superstite, poi
chi ha vinto e con cosa. **Automatico, non opzionale.** Non toglie nulla alla lettura degli
avversari: elimina l'attesa, non l'informazione (test-guardiano esplicito su questo).
- **Fiches vinte: incluse, ma NON dall'evento `potAwarded`.** Un piatto è spezzato in un evento
  **per livello di contribuzione** — anche una mano non contesa ne genera due (D-031) — quindi
  l'importo di un singolo evento **non è** ciò che il giocatore ha vinto, e **un numero sbagliato
  detto ad alta voce è peggio di nessun numero**. La riga (`heroNetWin`, priorità alta) riporta il
  **guadagno netto reale**, dal cambiamento effettivo dello stack fra inizio e fine mano.
- Applicato a Texas, Draw, Omaha e Stud.

### D-088 — "fiches": il difetto era ORTOGRAFICO, non fonetico (e la grafia giusta è la parola giusta)
L'utente riferiva che Alice leggeva "fiches" come **"fiche"**, al singolare. Prima di generare
qualunque campione, la lettura del codice ha mostrato la causa: **le stringhe italiane dicevano già
`fiche`**, al singolare, in **18 punti** (`"seat.chips" = "%d fiche"`, `pot.a11y`, `hero.stack.a11y`,
…). **La sintesi non stava sbagliando la pronuncia di una parola giusta: stava pronunciando
correttamente una parola sbagliata.** Il difetto era di **ortografia**, non di fonetica.
- **Metodo D-060 applicato comunque** (non si dichiara una resa senza ascoltarla): generati **18
  campioni** con la voce di destinazione (Alice it-IT) — parola sola e frase in contesto — su nove
  candidati (`fiche` attuale, `fiches`, `fisc`, `fisch`, `fisce`, `fisci`, `fish`, `fiscia`, e il
  ripiego `chips`). **L'utente ha approvato il 02 = `fiches`**, cioè **il plurale italiano corretto**
  (secondo accettabile: `fish`; tutti gli altri "tremendamente sbagliati").
- **È l'esito migliore possibile secondo D-060:** una **grafia piana che è anche la parola giusta** —
  nessun grafema inventato, nessun IPA, quindi **device-safe per costruzione** (nessuna dipendenza
  dal percorso SwiftUI→VoiceOver mai verificato end-to-end). **Il ripiego pre-approvato (`chips`
  anche in italiano) NON è servito** e non è stato cablato.
- **Verifica di byte-identità (passo 4 del metodo D-060):** rigenerata la resa **così com'è nelle
  stringhe spedite** (`fiches`; `"il tuo stack: 1200 fiches"`) e confrontata coi campioni approvati:
  **md5 identici** su entrambi (`0d1073d7…` = campione 02, `adfc5a22…` = campione 11).
- **Guardiano** (`PhoneticsTests.testEarVerifiedChipWordRendering`): pinna la resa udita su tutte le
  chiavi che nominano le fiches **e vieta il ritorno del singolare** in qualunque stringa italiana —
  cioè esattamente la regressione riportata. Coerente col principio di D-060: **si asserisce solo
  ciò che un umano ha udito.**

### ⚠️ Lezione per sessioni future — prima di indagare la PRONUNCIA, verificare l'ORTOGRAFIA
Quando una parola "viene letta male", **leggere prima la stringa**. Tre sessioni (D-049/D-054/D-059)
sono state spese a inseguire grafie fonetiche per *Raise* perché il problema era davvero di
pronuncia; qui il sintomo era identico ma la causa era banale — la parola era scritta al singolare.
Il costo di controllare è un `grep`; il costo di non controllarlo è un giro di campioni, di ipotesi
e di cablaggi su un problema che non esiste. **Ordine corretto: (1) la stringa dice la parola
giusta? (2) solo allora, la voce la pronuncia bene?**

### D-089 — Stud: la mano si legge come UN INSIEME, e il tavolo sta nello schermo
Due correzioni dal test sul telefono, entrambe al solo tavolo di Seven-Card Stud.
- **L'annuncio della propria mano.** Diceva *"Le tue coperte: … . Scoperte, VISTE DA TUTTI: … ."*
  Due difetti in una riga: (a) **superfluo** — nello Stud una carta scoperta è scoperta, e il
  giocatore lo sa per **struttura del gioco**; (b) **dannoso** — spezzava in **due blocchi con un
  preambolo in mezzo** una mano che il vedente coglie **in un solo colpo d'occhio**. Ora è **una
  sola riga continua**: *"Le tue carte: …"*, un unico elenco (guardiano: **un solo segnaposto**
  nella stringa; due significherebbero che è di nuovo spezzata).
- **Nulla è andato perso.** La distinzione coperte/scoperte resta **disponibile a richiesta** su un
  **elemento proprio** (`hero.board` → *"Le tue scoperte: …"*), accanto alla mano e ordinato **dopo**
  di essa. È lo stesso criterio di D-083 applicato al giocatore invece che agli avversari: separare
  per **frequenza d'uso**, non sopprimere. Sapere cosa gli altri leggono di te è informazione
  strategica vera dello Stud, quindi **doveva restare raggiungibile** — solo non in mezzo alla mano.
- **Altri preamboli dello stesso genere, cercati e trovati:** `stud.community.a11y` diceva *"Carta
  comune, PER TUTTI: …"* — una carta comune è per tutti **per definizione**. Rimosso. Nella passata
  sono emerse anche **due stringhe morte**: `stud.seat.upcards.a11y` (sostituita da `stud.board.a11y`
  in D-083 e mai cancellata) e `stud.hero.noup`. Rimosse — e un test **puntava** sulla prima, quindi
  **sorvegliava una stringa che nessuno più rendeva**: riagganciato alla chiave viva.
- **Il layout usciva dallo schermo — misurato, non stimato.** Larghezza utile su iPhone 15: **369 pt**.
  Banda avversari con carte fisse da 40 pt: **372 pt alla QUARTA strada** (non alla sesta come
  ipotizzato) e **544 pt alla sesta** (+47%); zona hero alla settima strada **486 pt** (+32%).
- **Soluzione: la carta segue lo spazio, non il contrario.** Nuovo `FittedCardRow` costruito su
  `ViewThatFits`, che prova larghezze decrescenti e prende la prima che entra — niente aritmetica di
  geometria, e si adatta **al dispositivo e al Dynamic Type** da solo. L'ultima candidata è un
  **pavimento non scalato (20 pt)**, quindi lo sbordamento è **strutturalmente impossibile**, non
  soltanto improbabile. Aggiunta a `CardView` la taglia additiva `.exact(w,h)`, **non** scalata dal
  Dynamic Type (ri-scalarla vanificherebbe l'adattamento); gli altri tavoli usano le loro taglie e
  **non cambiano**.
- **Cosa ho sacrificato per farci stare tutto.** *(1)* I **due dorsi** delle coperte degli avversari:
  non portavano informazione — un dorso è un dorso — ma costavano **un terzo** della riga; senza di
  essi le **quattro scoperte**, che sono il cuore strategico dello Stud (D-078), restano abbastanza
  grandi da leggersi. Che un posto abbia ancora carte è già detto a parole (fould/eliminato).
  *(2)* Nella zona hero, nome e fiches sono passati **sopra** le carte invece che di fianco: la
  colonna laterale rubava ~90 pt proprio alla mano da sette carte. Verificato **iPhone SE, 15 e Pro
  Max**, ogni strada: tutto dentro.
- **Dynamic Type — attenzione a non regredire mentre si ripara.** `.exact` esclude lo scaling, quindi
  candidate costanti avrebbero fatto **smettere di crescere** le carte di un ipovedente: regressione
  reale introdotta *dalla* correzione. Perciò le candidate sono **scalate**, con in coda il pavimento
  **non** scalato: il Dynamic Type è onorato **finché onorarlo non spinge la mano fuori dallo
  schermo**, e lì vince restare visibili — lo stesso compromesso di D-056 sul ritmo.
- **Accessibilità:** identifier conservati (`hero.cards`, `opponent.N`, `opponent.N.board`, …) più il
  nuovo `hero.board`; elementi degli avversari **ancora separati** (D-083); focus-landing (D-057)
  invariato; le righe di carte vivono **dentro elementi collassati**, quindi la scelta di candidata
  di `ViewThatFits` **non tocca l'albero d'accessibilità** — resta una foglia stabile la cui *label*
  cambia (pattern D-046/D-083). Canale parlato, budget e sincronizzazione (D-085) **non toccati**.


### D-090 — Blackjack: sesto motore, il primo che NON è un contesto fra giocatori
**Sesto motore** del progetto, in `GameEngine/Blackjack/`, **parallelo e indipendente**
(nessun import incrociato; condivide **solo** i fondazionali `Card`/`Rank`/`Suit`). È il primo
gioco della casa in cui il giocatore **non affronta altri giocatori ma il banco**, e questo ha
conseguenze architetturali reali, non cosmetiche:
- **Niente `PotMath`.** L'intero soggetto di quel file — dividere un piatto conteso — **non
  esiste** qui. Ogni mano è un conto a due fra il giocatore e la casa, e il pagamento è un
  moltiplicatore, non una spartizione. Riusarlo per abitudine sarebbe stato un errore.
- **Niente bot e niente nuove dimensioni di `Personality`** (scelta dell'utente). Le leve del
  progetto — aggressività, bluff, disciplina d'apertura, lettura del tabellone — descrivono il
  comportamento verso **avversari**, e al banco non c'è nessuno da leggere. Il banco non è un
  avversario: è una **regola**, e vive nel motore come tale.
- **Un tipo di mazzo proprio, `Shoe`.** Il `Deck` condiviso è 52 carte ricostruite a ogni mano —
  giusto per il poker, sbagliato qui, dove il sabot **persiste fra le mani** e il suo consumo è
  parte del gioco. `Shoe` porta il proprio generatore seedato, quindi una sessione è riproducibile
  **rimescoli compresi**, e `draw()` è **totale** (un sabot esaurito si rimescola da sé) così la
  macchina a stati non ha rami di fallimento da modellare.
- **Il turno non è un anello.** Gli altri motori ciclano su `actingIndex` fra i posti; qui il
  giocatore risolve **le proprie mani una a una** (la divisione ne crea altre) e **poi** il banco
  gioca una volta sola contro ciò che resta. Resta però lo scheletro provato: `apply` valida e muta,
  e **tutta** la progressione passa da un solo `progress()`.

**Regole della casa — imposte dall'utente:** il banco **si ferma su ogni diciassette**, morbido
compreso; il blackjack paga **3:2**; **raddoppio** con una sola carta e stop obbligato; **divisione**
su carte di **pari valore** (un re accanto a un dieci si divide) con raddoppio consentito dopo;
**resa** subito dopo la distribuzione per **metà** posta. **L'assicurazione non esiste e non è stata
implementata**: è una scommessa perdente, e il progetto non offre al giocatore una mossa perdente.
Un test **strutturale** pinna l'insieme chiuso delle azioni, così una sessione futura non può
reintrodurla di soppiatto.

**Regole di dettaglio scelte (libertà di giudizio, come per Omaha), col criterio:** sempre la
variante **più diffusa**, e a parità di diffusione quella **più favorevole al giocatore**, perché
il banco ha già il vantaggio strutturale e non serve accentuarlo.
- **Sei mazzi**, taglio al **75%**: lo standard dei casinò; il rimescolo è controllato **fra** le
  mani, mai dentro una, così nessuna mano è distribuita da due mescolate diverse.
- **Il banco sbircia** sotto un asso o un dieci e chiude subito la mano se ha blackjack. È la
  variante che **protegge i soldi di raddoppio e divisione** del giocatore, e rende la narrazione
  più semplice (la mano finisce prima che il giocatore impegni altro).
- **Assi divisi: una carta ciascuno**, poi fermi, e **non si ridividono**. Standard.
- **Ventuno dopo una divisione è un ventuno ordinario, non un blackjack** — paga alla pari. È la
  regola universale; il contrario sarebbe un regalo.
- **Fino a tre divisioni, quattro mani.** Standard.
- **Resa tardiva** (dopo la sbirciata) e **solo sulla mano distribuita**: chi ha già chiesto carta o
  diviso non può più ritirarsi.
- **Le poste minime sono PARI e ogni puntata è un multiplo intero del minimo.** Non è un dettaglio
  estetico: è ciò che rende **esatti in fiches intere** sia il 3:2 sia la metà della resa. Un test
  lo verifica su ogni valore che la cassa può offrire.

**Due tavoli, stesse regole, economie diverse (D-065/D-067 hanno retto):** aggiungerli è costato un
caso di `CasinoGame`, due righe di `CasinoTable`, un ramo in `AppRootView` e le stringhe — **nessuna
riscrittura** di lobby, conductor, director o percorso audio, e la palette del casinò arriva **per
dati**. **Riverwood** «Tavolo del Saloon»: buy-in **1000**, poste **20–200**. **Skypool** «Tavolo
Vetrata»: buy-in **5000** (il ×5 di casa), poste **100–1000**. Poiché non ci sono bot, ciò che
distingue i due tavoli è **solo** il denaro e il suono del posto. **Il ClockTower non riceve il
blackjack**: resta il luogo speciale del Machiavelli e dello Stud (test esplicito).

**Economia:** invariante di §8 rispettato senza casi speciali — **le uniche fiches che entrano al
tavolo sono il buy-in**; nessun premio, comp o bonus in sessione. **Lasciare il tavolo** (D-086) non
ha richiesto alcuna meccanica nuova: la posta è **già** uscita dalle fiches del giocatore quando la
mano è cominciata, quindi incassare ciò che resta **È** la confisca. Perché regga, però,
`playerActed` porta le fiches **residue** a ogni mossa, altrimenti un raddoppio o una divisione
lascerebbero il numero stantio e l'uscita pagherebbe troppo. Testato col movimento **reale** dei
gettoni, `DEBUG_FREE_PLAY` **spento**.

**Determinismo (D-047), con una differenza dichiarata:** i driver di poker riseminano **per mano**
perché ogni mano nasce da un mazzo nuovo; qui il sabot **persiste davvero**, quindi il seme è **uno
per sessione** — casuale dal generatore di sistema in produzione, fisso nei test. Il risultato è
esattamente ciò che D-047 chiede (ogni sessione e ogni mano diverse) **modellando il sabot
onestamente** invece di fingere un mazzo nuovo ogni volta.

**574 test verdi** (515 → +59). Motori esistenti, Riverwood, Skypool e ClockTower **invariati** nei
loro tavoli (tre test di regressione aggiornati da lista esatta a **prefisso**, per pinnare ciò per
cui erano stati scritti senza congelare la crescita della casa).

### D-091 — La RAPIDITÀ come problema di accessibilità: l'annuncio essenziale, e il dettaglio a richiesta
Il blackjack ha un carattere che nessun gioco precedente aveva: **è veloce**. Una mano è due carte e
una decisione, e un vedente ne gioca decine in pochi minuti. Con il carico di annunci di una mano di
poker, il non vedente si sarebbe ritrovato una **versione lenta del gioco veloce** — il vedente
rapido, lui al passo d'uomo. È "qualcuno perde qualcosa" nel punto in cui è più facile perderlo, e
andava progettato **dal motore**, non aggiunto dopo.

**Il criterio: l'annuncio essenziale è l'informazione MINIMA PER DECIDERE.** Il tuo totale, e la
carta scoperta del banco. Una riga sola e breve. Tutto il resto è **dettaglio interrogabile**.

**Tre scelte, e la terza è quella che ha sorpreso:**
1. **La distribuzione è UN evento, non quattro.** Il vedente coglie le proprie due carte e la
   scoperta del banco **in un colpo d'occhio**: il non vedente le riceve come **un fatto solo**
   (`dealt`), non come una coda di quattro annunci. Stessa logica per il banco che gioca: gira la
   coperta e pesca in **un** evento, non uno per carta.
2. **Si tace tutto ciò che il giocatore sa per struttura** (D-089). Con una mano sola non gli si
   dice di chi è il turno (lo sa); dopo una divisione sì, perché lì le mani vanno distinte davvero.
   La puntata appena scelta non gli viene ripetuta (l'ha appena premuta, D-055). Con una mano sola
   non c'è riepilogo di fine mano, perché la riga del risultato ha già dato la cifra.
3. **IL SEME NON SI PRONUNCIA.** Nel blackjack il seme **non può influenzare nulla** — non un
   totale, non un pagamento, non una mossa legale. Dire «dieci di fiori» invece di «dieci» spende
   ogni mano, per sempre, un pezzo di secondo su un'informazione che non può cambiare **nessuna**
   decisione. Il seme resta **visibile** sul tavolo e resta **sugli elementi interrogabili** per chi
   lo vuole; semplicemente non viaggia nella riga che il giocatore sente a ogni mano. Stessa
   ragione per cui la riga del banco dice **il totale** e non l'elenco delle sue carte: era la riga
   più lunga della mano, misurata, e il totale è tutto ciò su cui l'esito si decide.

**Il dettaglio non è soppresso, è SPOSTATO** (D-083/D-089): la mano del giocatore e il banco sono
**elementi accessibili** che allo swipe leggono lo stato corrente — **totale prima, carte dopo**,
perché il totale è ciò che si consulta più spesso. È la stessa memoria che il vedente ha guardando,
restituita a richiesta invece che imposta.

**MISURATO, non stimato** (`BlackjackAnnouncementLoadTests`, 60 mani reali contro 40 mani di Stud):

| | righe parlate | secondi parlati |
|---|---|---|
| **Blackjack** | **3,88 / mano** | **6,14 / mano** |
| Seven-Card Stud | 20,44 / mano | — |

Una mano di blackjack chiede all'orecchio **poco meno di un quinto** di una mano di Stud. Il test
tiene **due** sbarre: il rapporto contro lo Stud (in **righe**, l'unica unità che non dipende dal
bundle) e un tetto assoluto in secondi, così la garanzia sopravvive a una futura modifica del tavolo
di Stud.

**Trappola trovata strada facendo, che vale registrare:** la prima misura diceva 8,36 s/mano ed era
**falsa**. Sotto `swift test` non c'è bundle, quindi `uiLocalized` restituisce **la chiave**: stavo
misurando la lunghezza degli identificatori, non dell'italiano. Corretto dando a
`BlackjackSpeechMap.text` una **cucitura di localizzazione** (come già `BlackjackReadout`) e
rendendo le righe dal file `it.lproj` letto da disco. **Regola generale: una misura di ciò che il
giocatore SENTE va fatta sul testo reso davvero, mai su quello che il test riesce a risolvere.**

**Il confine descrivi-non-consigliare, qui più che altrove.** Il blackjack ha una strategia di base
**ottimale e nota**, e sarebbe stato banale sussurrarla. Non se ne dà **nessuna** traccia: «sedici, il
banco mostra dieci» è descrizione, «conviene chiedere carta» è consiglio, e il vedente non riceve
alcun suggerimento. Due guardiani lo tengono: uno scandisce **tutte** le stringhe `blackjack.*`
spedite cercando il lessico del consiglio, l'altro le **righe rese davvero**. L'unico aggettivo
concesso è **«morbido»**, che è un fatto sulle carte (un asso che conta undici) e non un'opinione su
cosa farne.

**Termini nuovi — campioni generati, NON cablati a indovinare (metodo D-060).** Hit, stand, double,
split e surrender finiscono in label accessibili. Provvisoriamente le label VoiceOver usano le
**parole italiane** — *carta, stai, raddoppia, dividi, resa* — che sono **parole vere nella lingua
che la voce parla** e quindi corrette **per costruzione**, senza il rischio che ha fatto attraversare
tre sessioni a «raise» con una grafia inventata. **16 campioni** con la voce di destinazione (Alice
it-IT) — candidati inglesi, italiani e grafemici per ogni termine — sono in
`~/Desktop/lumar-phonetics/blackjack/` **in attesa dell'ascolto dell'utente**: se preferisce
l'inglese, cambiano **solo** le stringhe `.a11y`, niente codice.

**Audio: nessun file prodotto, tutto degrada da sé.** Il croupier del blackjack **tace quasi sempre**
— l'unica voce cablata è il **rimescolo** (~una volta ogni sessanta mani, e spiega una pausa vera),
in due registri per i due casinò (D-067). La presenza degli altri avventori è **solo** effetti
ambientali (`fx_bj_presence_*`), categoria `.botVoice` → **fallback al silenzio** (D-066), suonati
**fra** le mani con probabilità ~28% e mai due volte di fila lo stesso: mai durante una decisione,
mai sopra un risultato. Poiché **nessun NPC parla**, un solo set serve tutti i casinò. Il colpo di
vittoria/sconfitta passa da `SpeechConductor.say(trailing:)` (D-085), quindi **non può anticipare**
il risultato. Catalogo completo in [`Blackjack_audio_catalog.md`](Blackjack_audio_catalog.md).

### D-092 — Un elemento che scompare deve dichiarare dove va il focus (il difetto era in TUTTI e sei i tavoli)
Il sintomo era al Blackjack: premuto **Conferma** nel box della puntata, il pulsante cessa di
esistere e il focus VoiceOver **resta appeso al nulla**, costringendo a rifocalizzare a mano —
e lì pesa il doppio, perché **ogni singola mano comincia così** e le mani si susseguono a raffica.
- **La causa reale, verificata nel codice (e diversa da quella che l'atterraggio del focus già
  copre).** `voiceOverFocusLanding()` (D-057) vive su `onAppear`: copre l'**apparizione** di una
  schermata o di un box, ed è tutto ciò che può coprire. Ma il box non è una schermata nuova — è un
  overlay, e il contenuto sotto **non viene mai rimosso dall'albero**: è solo
  `.accessibilityHidden(model.betBox != nil)`. Alla chiusura, quindi, **non appare nulla e non
  riparte nulla**: nessun `onAppear`, nessun re-scan, e il cursore resta dove il pulsante era. Non
  era il caso "cambio schermata" (che funziona), era il caso "elemento svanito **dentro** la stessa
  schermata" — che nessun meccanismo copriva. D-057 lo aveva peraltro già dichiarato come *limite
  noto* ("al dismiss di una modale il focus non viene ancora riportato esplicitamente sul tavolo");
  questa voce lo paga.
- **Il difetto esisteva altrove: SÌ, in tutti e sei i tavoli** — Texas, Omaha, Stud, Draw,
  Machiavelli e Blackjack usano la stessa forma (overlay condizionale sopra contenuto
  `accessibilityHidden`), e **nessuno** ripristinava il focus. Peggio al Blackjack solo per
  frequenza. I percorsi di **annulla** e di **tap sullo sfondo** (Texas/Omaha/Stud) erano colpiti
  allo stesso modo, e il tap sullo sfondo è il caso peggiore: l'elemento toccato è una decorazione
  nascosta. **Non** colpiti: l'overlay di fine partita (naviga via, la schermata di destinazione
  monta e atterra da sé) e il foglio Impostazioni (una `.sheet` vera, dove UIKit riporta il focus
  sul controllo presentante).
- **Il meccanismo, in due forme perché le destinazioni hanno due forme.**
  `voiceOverFocusClaim(onChangeOf:)` per una destinazione **già presente** (i cinque tavoli: la zona
  eroe non se ne va mai) — il view model **incrementa un token** alla chiusura del box, e il token
  è bumpato nel **`didSet` della proprietà del box**, così **ogni** percorso di chiusura — conferma,
  annulla, tap sullo sfondo, e qualunque percorso aggiunto domani — è coperto **per costruzione**,
  con una sola riga per view model. E `voiceOverFocusClaim(_:)` per una destinazione **appena
  inserita**: al Blackjack la mano non esiste ancora quando il box si chiude (le carte arrivano
  subito dopo), quindi è la mano stessa a reclamare il focus mentre appare. Reclama **solo la prima**
  mano: una divisione non deve strappare il cursore da una mano ancora in gioco.
- **Perché la destinazione è la MANO e non altro** (richiesta esplicita, e ha una ragione di ritmo):
  mentre l'annuncio della carta scoperta del banco scorre, il focus è **già arrivato**, così quando
  la sintesi finisce il giocatore è già sull'elemento che gli serve — e quell'elemento legge **il
  totale prima delle carte** (D-091). **Zero swipe** tra la decisione di puntata e l'informazione per
  decidere.
- **Si posta `.layoutChanged`, non `.screenChanged`** (nuovo `AnnouncementQueue.postLayoutChanged`):
  la schermata **non** è cambiata, ne è cambiata una parte, e un re-scan completo ri-annuncerebbe
  l'intero tavolo **a ogni mano**. Il posting resta **in un solo file** (regola D-032, guardiano
  statico verde).
- **Vincoli:** solo `UI`; nessun motore toccato; nessun `UIAccessibility.post` diretto; sottoalbero
  d'accessibilità stabile (i modificatori non aggiungono né rimuovono sottoviste). Principio
  permanente in CONVENTIONS §4.

### D-093 — Una tabella di stringhe sostituibile per l'intero modulo UI (il seme della misura)
D-091 aveva misurato il carico del blackjack **sbagliato** — 8,36 s/mano invece di 6,14 — perché
sotto `swift test` non c'è bundle e `uiLocalized` restituisce **la chiave**: si stava misurando la
lunghezza degli identificatori, non dell'italiano. Il rimedio di allora fu una cucitura di
localizzazione **su una sola funzione** (`BlackjackSpeechMap.text`). Non basta: la stessa misura
sullo Stud attraversa `StudSpeechMap`, `CardText.spoken` e `SpeechMap.handDescription`, e infilare
un parametro localizer in ognuna sarebbe stato un refactoring invasivo per una necessità di test.
Introdotto invece `UIStrings.override`: una tabella **sostituibile una volta sola** che
`uiLocalized` consulta per prima. La misura inietta il vero `it.lproj` letto da disco e **l'intero
modulo rende italiano reale**, senza cuciture da propagare. Non impostata nell'app, dove il bundle
è la verità. **Regola (CONVENTIONS §5):** una misura di ciò che il giocatore **sente** si fa sul
testo reso davvero, mai su quello che il test riesce a risolvere.

### D-094 — Stud: la mano di terza strada era spezzata; l'arricchimento NON serviva perché ESISTE già, e il canale è saturo
Due domande sullo Stud, una confermata e corretta, l'altra rovesciata dalla misura.
- **PRIMA PARTE — confermata e corretta: la terza carta.** Il sospetto era che all'apertura venissero
  annunciate solo le due coperte. **Verificato: le tre carte erano tutte annunciate, ma in DUE righe**
  — `privateDownCards` diceva *«Le tue **coperte**: X, Y.»* e la scoperta arrivava subito dopo come
  frase separata *«Ricevi Z scoperta.»* Quindi la riga che presenta la mano ne elencava **due su
  tre**, e la terza non suonava come parte della mano. È **esattamente la spaccatura che D-089 aveva
  tolto**, sopravvissuta **un evento più a monte**: D-089 aveva unificato l'*elemento* interrogabile
  (`stud.hero.cards.a11y` = «Le tue carte») ma non l'*annuncio*. **Correzione:** il view model
  **trattiene** le due coperte e le pronuncia **insieme alla scoperta** come **una riga di tre**
  (`StudSynthLine.heroCards`, rinominata da `heroDownCards` perché ora è la mano, non le coperte);
  la stringa passa da «Le tue coperte» a «Le tue carte». L'ultima coperta di **settima** strada
  conserva la sua riga: non c'è nulla a cui unirla. La distinzione coperte/scoperte resta
  **interrogabile** su `hero.board` (D-089/D-083): spostata, non soppressa.
- **SECONDA PARTE — la diagnosi ha rovesciato la premessa: l'arricchimento È GIÀ IMPLEMENTATO.**
  `StudSpeechMap` pianifica `upCardDealt` **per ogni posto a ogni strada**, terza compresa, e il
  view model lo pronuncia. **Misurato: 5,82 righe/mano di carte scoperte avversarie, 11,06 s/mano** —
  se si fermassero alla terza strada sarebbero ~2. Non c'era niente da aggiungere.
- **Il carico dello Stud, misurato** (40 mani reali al ClockTower, rese dal vero `it.lproj` via
  D-093): **18,35 righe/mano** e **37,44 secondi parlati/mano**, contro le **3,88 righe e 6,14 s**
  del Blackjack. Composizione, che è il dato che ha deciso tutto:

  | | righe/mano | s/mano |
  |---|---|---|
  | **azioni avversarie** | **7,00** | **15,96** |
  | **carte scoperte avversarie** | **5,82** | **11,06** |
  | piatto | 2,00 | 3,50 |
  | scoperta dell'eroe | 1,12 | 2,51 |
  | obbligata | 1,00 | 1,97 |
  | mani allo showdown | 0,94 | 1,39 |
  | carte dell'eroe | 0,47 | 1,04 |

  E il momento peggiore: una **raffica di showdown a tre vale 8,36 s contro un budget di canale di
  6,0 s** — il payoff **da solo** sfora già.
- **Costo dell'arricchimento proposto, nelle due forme, se fosse mancato:** forma **completa** (una
  riga per avversario a ogni strada) ≈ **+8 righe e +15 s/mano**, cioè **+44% righe e +40 secondi**
  su un canale già oltre budget; forma **economica** (una riga sola per strada che copre tutti gli
  avversari, solo la carta nuova) ≈ **+4 righe e +7,5 s/mano**, ancora **+22%**. Entrambe
  insostenibili — ma la questione è accademica, perché **l'informazione c'è già**.
- **Perché il giocatore non la sentiva, e cosa ho fatto invece.** Con 37,44 s di parlato per mano
  contro un budget di 6 s, il canale **scarta** (D-085) — e scarta la priorità più bassa fra le
  righe in attesa. Le carte scoperte erano `.medium`, **esattamente come le azioni avversarie**,
  che sono **più numerose e più lunghe** (7,00 righe / 15,96 s contro 5,82 / 11,06): il
  chiacchiericcio stava **evincendo la cosa su cui lo Stud si gioca**. Correzione a **costo zero**:
  le azioni avversarie scendono a `.low`, le carte scoperte restano `.medium`. **Nessuna riga
  aggiunta, nessun secondo aggiunto, budget del canale intatto a 6,0 s** (test che lo pinna):
  cambia solo **l'ordine in cui il canale cede**. Ciò che il giocatore perde sotto pressione è
  l'informazione che può meno usare — una chiamata è di routine, visibile a schermo e ri-derivabile
  dal piatto — e ciò che tiene è la carta appena scesa, che non lo è.
- **Un buco trovato strada facendo, senza cui il cambio sarebbe stato inerte:** `speakAction` nel
  view model passava `priority: .medium` **cablato**, scavalcando in silenzio la mappa che è
  l'autorità (D-029) — e le azioni avversarie sono consegnate **solo** da lì. La demozione non
  avrebbe avuto **alcun effetto**. Ora la priorità viene dalla mappa. Principio in CONVENTIONS §4.
- **Nota onesta sul residuo:** anche con l'ordine corretto, un canale a 37,44 s/mano contro 6 s
  **scarta molto**; la priorità decide *cosa*, non *quanto*. Se le carte scoperte dovessero ancora
  risultare rade al test sul device, la leva successiva è **potare** (accorciare le righe di azione,
  o pronunciarle solo quando cambiano il piatto), **non** alzare il budget, che è tarato su misure
  reali sul telefono. Il tabellone di ogni avversario resta comunque **interrogabile a comando**
  (D-078/D-083): l'annuncio automatico è un guadagno di ritmo, non l'unica via all'informazione.
- **Vincoli:** motori intatti; eventi descrittivi (la coalescenza della terza strada vive nel
  **consumatore**, dove vive il ritmo umano — D-018); nessun `UIAccessibility.post` diretto;
  budget del canale **non alzato**; nessun suggerimento di mossa aggiunto.

### D-095 — Blackjack: le rese fonetiche dei cinque movimenti, ascoltate e cablate (verdetto MISTO)
Chiusura del residuo dichiarato in D-090: i 16 campioni Alice it-IT in
`~/Desktop/lumar-phonetics/blackjack/` sono stati **ascoltati e approvati** dall'utente. Il verdetto
non è stato "tutto inglese" né "tutto italiano" ma **misto**, e la scelta è per parola, non per
principio:
- **Hit → «carta»** e **Surrender → «resa»** (equivalenti **italiani**, `hit_02` / `surrender_02`);
- **Stand → «Stand»**, **Double → «Double»**, **Split → «Split»** (parola **inglese** piana,
  `stand_01` / `double_01` / `split_01`);
- **il termine «blackjack» → parola inglese piana** (`blackjack_01`), che era **già** ciò che le
  righe parlate dicevano (`blackjack.announce.deal.natural`, `…dealer.natural`) → nessun cambio.
**Ogni resa è una grafia PIANA di una parola reale** — nella lingua che la voce parla, o in inglese
letto da Alice — quindi **device-safe per costruzione** (D-060): nessun grafema inventato, nessun
IPA, nessuna dipendenza dal percorso SwiftUI→VoiceOver mai verificato end-to-end.
- **Verifica di byte-identità (passo 4 del metodo D-060), fatta e superata su tutte e sei le rese:**
  rigenerata la stringa **così com'è spedita** e confrontata col campione approvato →
  md5 **identici** (`carta` = `a8e2f55e…`, `resa` = `d9c9bf05…`, `Stand` = `207a8ca0…`,
  `Double` = `5ac01ee2…`, `Split` = `7a3fbb8f…`, `blackjack` = `4ec1387b…`).
- **Fatto misurato utile per il futuro:** la **maiuscola non cambia il suono** — "Blackjack" e
  "blackjack" producono audio **byte-identico** su Alice, così come Stand/stand, Double/double,
  Split/split. Quindi una resa approvata su una parola capitalizzata **vale anche** per le sue
  occorrenze minuscole dentro una frase, senza doverla ri-ascoltare.
- **Confine rispettato (D-073):** cambiano **solo** le label `.a11y` dei pulsanti. La **narrazione**
  resta ai verbi italiani ("Raddoppi.", "Dividi. Ora hai %d mani.") — è la stessa doppia lingua già
  nel progetto: la voce racconta in italiano, il pulsante dice il termine del gioco. La tabella
  `en.lproj` non è toccata (parole inglesi per una voce inglese).
- **Guardiano** (`PhoneticsTests.testEarVerifiedBlackjackMoveRenderings`): pinna le cinque rese udite
  e **vieta il ritorno** delle tre italiane scartate ("stai", "raddoppia", "dividi"), coerente col
  perno di D-060 — **si asserisce solo ciò che un umano ha udito**. Lo strumento per rigenerare i
  campioni è ricostruito nello scratchpad (`render1.swift`); **nota operativa nuova**: su riga di
  comando macOS il processo deve **pompare il run loop**, non bloccarsi su un semaforo, altrimenti
  la callback di `write` non scatta mai e non esce audio.
