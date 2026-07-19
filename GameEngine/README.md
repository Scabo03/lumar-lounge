# GameEngine

Il **motore di regole puro** di Lumar Lounge: il cerchio più interno
dell'architettura.

## Filosofia

`GameEngine` è codice Swift puro, **matematico e testabile in isolamento**.
Dipende **solo da Foundation** — mai SwiftUI, UIKit, AVFoundation, CoreHaptics,
Combine o qualunque framework che lo leghi a una piattaforma. È autonomo e
teoricamente portabile.

Non sa che esiste un'app, una UI, un giocatore, una partita in corso. Conosce
soltanto gli oggetti e le regole astratte dei giochi: cos'è una carta, cos'è un
mazzo, cosa vale una mano. Tutto ciò che riguarda *chi* gioca, *quando* tocca a
qualcuno o *quanto* ha puntato vive più in alto (`GameWorld`, `UI`).

## Cosa contiene oggi

| Tipo | Ruolo |
|---|---|
| `Card`, `Rank`, `Suit` | La carta da gioco: valore (2→Asso) e seme. Confrontabile per rank, stampabile per debug (`A♠`, `10♣`). |
| `Deck` | Mazzo di 52 carte in ordine deterministico; `shuffle(seed:)` riproducibile; `draw()` che fallisce con `nil` a mazzo vuoto. |
| `SeededGenerator` | PRNG deterministico (SplitMix64) per mescolate riproducibili nei test. |
| `HandCategory` | Le dieci categorie di mano, in ordine crescente di valore. |
| `HandRank` | Il risultato di una valutazione: categoria + tie-breaker + le cinque carte. Confrontabile (categoria, poi valori, poi kicker; uguaglianza = split pot). |
| `HandEvaluator` | Trova la miglior mano di cinque su 5+ carte e confronta due insiemi di carte. |
| `Hand` | La mano *giocatore-centrica*: le due hole card di un seat durante una mano in corso. Distinta da `HandRank` (D-002). |
| `HoldemHand` | **Motore della mano di Texas Hold'em No Limit**: macchina a stati a turni che va dai blind allo showdown. Deterministica via seed. |
| `Seat` / `SeatState` | Configurazione di un posto (id + stack) e il suo stato dinamico durante la mano (hole, puntate, folded, all-in). |
| `Street`, `Action`, `ActionError`, `Pot`, `HandResult`, `LegalActions` | Street di puntata, le sei azioni con i vincoli di validità, i pot/side-pot, l'esito della mano e le mosse legali del seat di turno. |
| `PotMath` | Funzioni pure per side-pot e divisione (con chip di resto), testabili in isolamento. |
| `PokerBot` | **L'interfaccia del bot**: dato un `BotContext`, restituisce un'azione legale. Si aggancia al motore dall'esterno, come qualsiasi decisore. |
| `BotContext` | Vista **redatta e seat-relativa** della mano: solo stato pubblico (board, pot, stack, puntate, posizione) più le due carte del seat di turno. Costruita da `HoldemHand` senza mai esporre le carte coperte altrui (D-009). |
| `PublicSeat` | Lo stato pubblico di un posto (id, stack, puntate, folded, all-in) — **senza** hole card. |
| `Personality` | I "manopole" 0…1 che modulano il baseline matematico (tightness, aggression, bluff, riskTolerance, positionAwareness, rationality, tiltReactivity). Tre preset di partenza: `eagerNovice`, `conservativeRock`, `hotAggressor` (D-010). |
| `HeuristicBot` | Bot concreto: baseline matematico (forza mano + pot odds + posizione) **modulato** dalla personalità, deterministico via seed. |
| `HandStrength` | Stima della forza della mano dal punto di vista onesto del seat: euristica preflop (Chen normalizzato) + equity Monte Carlo postflop seedabile (D-011). |
| `FiveCardDrawHand` | **Motore di una mano di Five-Card Draw** ("Jacks or Better"): secondo motore di gioco, indipendente dal Texas (D-038). Ante, due giri di puntata **limit** (small/big bet, cap a tre raise), draw, apertura jacks-or-better sull'onore + verifica degli openers allo showdown (D-039), pass-and-out con pot progressivo (D-040). Vive in `Draw/`. |
| `DrawSeat`/`DrawSeatState`/`DrawPhase`/`DrawAction`/`DrawResult`/`DrawLegalActions`/`DrawOptions` | I tipi del motore Draw, distinti da quelli del Texas: configurazione e stato dinamico del posto (5 carte, openers snapshottati), fasi (firstBet/draw/secondBet/complete), azioni limit senza importo, esito (showdown/foldOut/passedIn + pot portato), mosse legali e opzioni di scarto. |
| `DrawBot`/`DrawBotContext`/`DrawDrawContext`/`HeuristicDrawBot` | Bot del Draw: decide **puntata** e **scarto** viste solo l'informazione onesta (proprie 5 carte + stato pubblico, incl. il numero di carte cambiate dagli avversari). Riusa le 3 personalità del Texas con i dial specifici del draw. |
| `OmahaHand` | **Motore di una mano di Omaha Pot Limit** (D-062): terzo motore, indipendente da Texas e Draw. Quattro carte private, quattro street comuni, **valutazione vincolata due-più-tre** (`HandEvaluator.evaluateOmaha`, D-061), **betting Pot Limit** (tetto = piatto, dal vivo, `PotMath.potLimitMax…`), side pot, determinismo via seed. Vive in `Omaha/`. |
| `OmahaSeat`/`OmahaSeatState`/`OmahaStreet`/`OmahaAction`/`OmahaResult`/`OmahaLegalActions` | I tipi del motore Omaha, distinti da Texas/Draw: posto con **quattro** carte private, azioni con semantica "to" e maxima già cappati al Pot Limit, esito con mano vincolata mostrata allo showdown. |
| `OmahaBot`/`OmahaBotContext`/`OmahaStrength`/`HeuristicOmahaBot` | Bot dell'Omaha: forza pre-flop **euristica sulle quattro carte** (coordinazione, nut) + equity **Monte Carlo vincolata** a costo contenuto (D-063). Due leve additive di `Personality` (`omahaCoordination`/`omahaNuttiness`). |
| `DrawStrategy` | Euristiche pure e testabili del draw: forza statica di 5 carte + scarto "da manuale" (stand pat sui punti fatti, tieni le forti, pesca ai progetti). |
| `MachiavelliRules` | **Il predicato di validità del Machiavelli** (D-070): unica fonte di verità sulla legalità. `classify(_:)` (una selezione è una combinazione legale? quale?), `isValidCombination`, `isValidTable`. Due decidono/tris con semi distinti, scale ≥3 stesso seme, asso ai due capi (mai wrap). Interrogato da due interfacce future (box del cieco / drag del vedente) → stesso gioco per entrambi. Vive in `Machiavelli/`, quarto motore indipendente. |
| `Meld`/`MeldForm`/`MachiavelliConstants` | Combinazione validata (sempre legale, ordine canonico) + forma (group/run) + costanti del ruleset (due mazzi/104 carte, mano 13, min 3). |
| `MachiavelliTurnContext`/`MachiavelliProposal` | **Il modello del turno** (D-070): il turno è una **sequenza** di trasformazioni chiusa da un terminale. Stato **ipotetico** — `evaluate(_:)` valuta una proposta di tavolo **senza applicarla**, `apply(_:)` la conferma; ogni proposta è validata contro lo **snapshot d'inizio turno**, così **la stessa carta può muoversi più volte** e solo lo stato finale deve essere valido. `canPass`/`mustDraw` = legalità del terminale. |
| `MachiavelliBot`/`MachiavelliBotContext`/`MachiavelliTurnPlan`/`MachiavelliSearchBudget` | L'interfaccia del bot: vista **redatta** (tavolo pubblico + conteggio mani avversarie, mai le loro carte, D-009) → un **piano di turno**; budget di ricerca a **nodi (deterministico) e/o tempo (produzione)**. |
| `HeuristicMachiavelliBot` | Bot su **due assi indipendenti** (D-070): `machiavelliSearchDepth` (quanto esplora le ricomposizioni; scala nodi+tempo) e `machiavelliPatience` (se trattiene una mossa trovata e pesca aspettando di meglio). Ricerca **interrompibile** (greedy + exact-cover limitato), mossa migliore entro il budget, **mai sforo**. Con i **punti** (D-071) è **score-aware**: la ricerca preferisce scaricare più **valore** e trattiene meno sotto minaccia (`machiavelliMalusAversion`). |
| `MachiavelliScoring` | **Il punteggio di una mano** (D-071), puro e nel motore: scala **imposta** (asso 10, figure 5, numerate 1), `score = outBonus·[out] + valore(calato) − valore(rimasto)`. La soglia e la struttura mano↔partita sono meccanica di **sessione** (GameWorld), non qui. |
| `StudHand` | **Motore di una mano di Seven-Card Stud Pot Limit** (D-077): **quinto** motore, indipendente. **Niente board comune**, cinque street (2 coperte + 1 scoperta in terza; 1 scoperta in quarta/quinta/sesta; 1 coperta in settima), **ante + bring-in** (carta scoperta più bassa, seme fiori-più-basso), apre poi il **punto scoperto più alto**, **Pot Limit** (tetto dal vivo, bring-in completabile), best-five-of-seven, esaurimento mazzo → carta **comune**. Vive in `Stud/`. |
| `StudSeat`/`StudSeatState`/`StudStreet`/`StudAction`/`StudResult`/`StudLegalActions`/`StudShowing` | I tipi del motore Stud, distinti dagli altri: posto con carte **coperte + scoperte**, azioni con semantica "to" cappate al Pot Limit, esito con le sette carte mostrate allo showdown; `StudShowing` = ordine seme del bring-in + chiave comparabile del punto scoperto (chi apre). |
| `StudBot`/`StudBotContext`/`StudStrength`/`HeuristicStudBot` | Bot dello Stud: vede le **scoperte di tutti** (pubbliche) ma **mai** le coperte altrui (D-009). Forza di terza strada + equity Monte Carlo **dead-card-aware** + **lettura dei tabelloni** (`studBoardReading`, dimensione additiva D-076, inerte negli altri giochi). |

Gestisce i casi particolari del poker: l'Asso che vale 1 nella scala minima
`A-2-3-4-5` (la *wheel*) o 14 nella scala massima, la distinzione tra scala
reale e scala colore, i kicker che rompono i pareggi. E, nel motore della mano:
min-raise del No Limit, all-in incompleto che non riapre l'azione, blind posti
short/all-in, side pot esatti con stack diversi, showdown con split e chip di
resto al seat alla sinistra del button (D-004).

### Filosofia del modulo bot

Un bot è un **decisore esterno**: legge `HoldemHand.legalActions()`, sceglie, e
chiama `apply(_:)` — il motore M1.2 non è stato toccato per accoglierlo. La
**forza matematica** (equity, pot odds, posizione) è comune a tutti; la
**personalità** è uno strato che modula *come* quella forza si esprime, non la
sostituisce (D-010). I bot sono **onesti**: vedono solo lo stato pubblico più le
proprie due carte, garantito dalla vista redatta `BotContext` (D-009). Nei
casinò iniziali i profili sono matematicamente semplici ma emotivamente caldi e
fallaci; salendo diventano più freddi e solidi. Tutto puro e deterministico via
seed. L'infrastruttura è **estensibile**: aggiungere una personalità è additivo
(un preset in più); un bot radicalmente diverso è un nuovo conforme a `PokerBot`.

### Filosofia del modulo Five-Card Draw

Il secondo gioco del progetto vive **interamente** dentro `GameEngine`, in
`Draw/`, come **motore autonomo e parallelo** al Texas (D-038). I due non si
conoscono: nessun `import` incrociato, nessun tipo di regole condiviso. Condividono
**solo** i tipi fondazionali di M1.1 (`Card`/`Rank`/`Suit`/`Deck`/`HandEvaluator`)
e l'**aritmetica dei chip game-agnostica** (`PotMath`/`Pot`), che è matematica pura
dei pot, non regole del Texas. `FiveCardDrawHand` è, come `HoldemHand`, un value
type con transizioni `mutating`, sincrono e **deterministico via seed**.

### Filosofia del modulo Omaha (Pot Limit)

Il **terzo** gioco (D-061→D-064) vive in `Omaha/`, con lo **stesso rigore di
separazione**: nessun import incrociato con Texas o Draw, **nessun tipo di regole
condiviso** — anche se Omaha *assomiglia* al Texas (blind, quattro street comuni,
side pot) più di quanto gli assomigli il Draw. Proprio per questo la tentazione di
riusare il motore Texas è forte e va **respinta**: la somiglianza è superficiale e
la regola di composizione **due-più-tre** (esattamente due carte private + tre
comuni) la rompe alla radice. Condivide **solo** i fondazionali + `PotMath`/`Pot`.
`OmahaHand` è un value type `mutating`, deterministico via seed, con **betting Pot
Limit** (tetto = piatto, calcolato dal vivo). Il valutatore fondazionale è **esteso,
non sostituito**: `HandEvaluator.evaluateOmaha(hole:board:)` impone il vincolo
due-più-tre; Texas e Draw continuano a usare `evaluate` invariato. I bot
(`HeuristicOmahaBot`) hanno euristica pre-flop sulle quattro carte + equity Monte
Carlo **vincolata** (costo misurato, campioni ridotti per la parità col Texas), con
due leve additive di `Personality` (`omahaCoordination`/`omahaNuttiness`). **Solo
motore+bot**: driver, UI, audio e casinò ospitante sono fuori da `GameEngine`.

Regole implementate — **versione tradizionale completa** (chiusa, non un MVP):

- **Quattro giocatori** tipici (2–7 supportati), **ante** da tutti prima della
  distribuzione (nessuna blind), cinque carte a testa.
- **Due giri di puntata** attorno a **un solo draw** (niente flop/turn/river):
  betting **limit** con **small bet** nel primo giro e **big bet** (doppio) nel
  secondo, **valori come parametri del tavolo** (non hardcoded); **cap a tre
  raise** per giro (bet + raise + re-raise + cap = 4 escalation, poi solo call/fold).
- **Jacks or better per aprire** *sull'onore* (D-039): chiunque può fare il primo
  bet, ma se apre **senza** almeno una coppia di jack "combinazioni superiori
  incluse", allo **showdown** non può dimostrare gli **openers** e **perde
  automaticamente**, comunque sia la sua mano finale; le sue fiches restano nel
  pot per gli altri. Se invece tutti foldano (bluff riuscito), **vince senza
  showdown**, nessuna prova richiesta. Gli openers sono **snapshottati al momento
  dell'apertura** e conservati anche se poi scartati nel draw.
- **Draw:** ogni seat ancora in gioco scarta **0–4** carte e ne pesca altrettante
  (nessun caso speciale sulla quinta). Turni uno alla volta a sinistra del button.
- **Pass-and-out con pot progressivo, variante B** (D-040): se **nessuno apre**, la
  mano è nulla, gli ante **restano** e il pot **cresce** nella mano successiva. La
  mano pura gestisce **un solo giro di distribuzione** ed espone `.passedIn` +
  `carriedPot`; il pot progressivo è passato in ingresso via `carryPot` e vive nel
  driver (futuro GameWorld). Il button **non ruota** sulle mani annullate.
- **Valutazione** con `HandEvaluator` su esattamente cinque carte; showdown, split
  e chip di resto al seat a sinistra del button come nel Texas (D-004).
- **Side pot** gestiti riusando `PotMath`: un giocatore può finire i soldi già
  sull'ante o su un raise che non copre, generando side pot esatti.

**Tre nuovi dial di `Personality`** (additivi, D-038), inerti nel Texas:
`drawDiscipline` (scarto matematicamente corretto vs rumoroso), `drawBluffiness`
(cambiare poche carte per fingere forza / over-draw teatrale), `openingDiscipline`
(quanto rispetta strettamente il jacks-or-better: bassa = rischia di aprire su aria
e farsi scoprire). Valori scelti: **novice** discipline bassa / bluff bassa /
opening media; **rock** discipline alta / bluff quasi nulla / opening altissima;
**aggressor** discipline media / bluff alta / opening bassa.

### Filosofia del modulo Machiavelli (ricombinazione)

Il **quarto** gioco (D-070) vive in `Machiavelli/` ed è un **animale nuovo**: non è
poker. Niente piatto, puntate, blind, bluff, showdown. È un gioco di **ricombinazione**
— i giocatori calano scale e tris e possono **smontare e ricomporre** qualunque
combinazione già sul tavolo (propria o altrui), purché a fine turno tutto sia valido;
vince chi si libera per primo delle carte. Nessuna infrastruttura del poker
(`BotContext`-con-equity, `Pot`, leve di rischio/aggressione) è riusata: non c'entra.
Condivide **solo** i fondazionali `Card`/`Rank`/`Suit`/`Deck`. Nessun import incrociato.

Regole canoniche fissate (D-070), dichiarate perché una sessione futura non le
riscopra:

- **Due mazzi da 52 = 104 carte, nessun jolly.** L'assenza di wildcard è deliberata:
  rende la ricombinazione pura (ogni carta è sé stessa).
- **Group (tris/poker):** 3–4 carte dello **stesso rango**, semi **tutti distinti**.
- **Run (scala):** 3+ carte dello **stesso seme**, **consecutive**. L'**asso** sta a
  **entrambi i capi** — alto (Q-K-A) o basso (A-2-3) — ma **non wrappa** (K-A-2 illegale).
- **Mano di 13 carte**; il resto è **stock**. Si pesca **una** carta se non si cala nulla.
- **Turno = sequenza di trasformazioni** chiusa da un **terminale esplicito**: *passare*
  (legale solo se si è calata ≥1 carta) o *pescare* (se non si è calato nulla). Vince chi
  svuota la mano.

**Due pilastri, entrambi accessibilità travestita da architettura:**

1. **Il predicato di validità è l'UNICA fonte di verità, nel motore (mai nella UI).**
   `MachiavelliRules.classify`/`isValidTable` sono interrogati da **due interfacce**
   future indipendenti — il cieco compone in un box (sblocca *Conferma* quando la
   **selezione** è legale), il vedente trascina sul tavolo (sblocca *fine turno* quando
   il **tavolo** è valido). Un solo predicato ⇒ vedente e non vedente giocano lo **stesso**
   gioco; se la validazione vivesse nella UI, divergerebbero al primo bug.

2. **Stato ipotetico + la stessa carta si muove più volte.** `MachiavelliTurnContext`
   valuta una proposta **senza applicarla** (`evaluate`) e la conferma solo su richiesta
   (`apply`); ogni proposta è validata contro lo **snapshot d'inizio turno**, non contro
   lo stato corrente — così una carta calata presto può essere ripresa e ricomposta
   quante volte si vuole, e **solo lo stato finale** deve essere valido. Un esploratore
   lento non è mai punito per la lunghezza dell'esplorazione, solo per la qualità della
   mossa finale.

**Bot su due assi INDIPENDENTI** (non tre gradi di una scala, D-070):
`machiavelliSearchDepth` (quanto esplora le ricomposizioni — scala nodi **e** tempo) e
`machiavelliPatience` (se trattiene una mossa già trovata per pescare qualcosa di meglio).
Additivi, default 0.5, inerti negli altri giochi. Tre archetipi: **studente** (profondità
bassa, poca pazienza — cala in fretta), **adulto** (profondità alta, pazienza alta —
aspetta il meglio), **professore** (profondità massima, pazienza media — rimaneggia il
tavolo). La ricerca è **interrompibile** (greedy garantito + exact-cover limitato con
restart), tenuta da `MachiavelliSearchBudget` a **nodi** (deterministico, per i test) e/o
**tempo** (produzione, ~10 s studente → ~15 s professore): ritorna sempre la migliore
mossa trovata entro il budget, **profondità adattiva**, **mai uno sforo** (lavoro
per-nodo limitato). Il tempo del professore è **carattere**, non lag. **Solo
motore+bot**: driver, eventi, UI, audio e casinò ospitante sono fuori da `GameEngine`.

**Punteggio mano↔partita (D-071).** Una partita non è più una mano sola: `MachiavelliScoring`
(puro, nel motore) segna ogni mano — asso 10, figure 5, numerate 1; `outBonus·[out] +
valore(calato) − valore(rimasto)` — e il driver (`GameWorld`) accumula i totali fino alla
**soglia di vittoria**. Il punteggio dà **scopo a chi perde la mano** (ogni carta calata conta,
ogni carta rimasta pesa) e rende `machiavelliPatience` un **rischio calcolato**. Terza dimensione
additiva `machiavelliMalusAversion` (default 0 = pre-punteggio): il bot **scarica il valore** e
**trattiene meno** quando un avversario è vicino a chiudere — così il paziente non resta con
l'asso in mano.

## Cosa NON contiene (per scelta architetturale)

Niente **giocatori**, **tavoli**, **partite** o **stato di gioco** in corso.
Niente concetto di **turno** o di **chi parla**, niente **blind**, **pot** o
**side pot**, niente fiches. Sono tutti concetti di *svolgimento* di una partita:
appartengono al motore della partita e al mondo, non alla rappresentazione pura
delle regole.

Il tipo `Hand` **giocatore-centrico** ora esiste (introdotto con `HoldemHand`, D-002)
ed è tenuto distinto da `HandRank`, che resta **valutazione-centrico**.
`HoldemHand` conosce seat, stack, pot e turni perché è il *motore di svolgimento*
della mano — ma continua a non sapere nulla di giocatori-persona, bot, timer, UI
o audio: quelli vivono in `GameWorld`/`UI`/`Audio` (D-006). Vedi il log delle
decisioni in [`../CLAUDE.md`](../CLAUDE.md).

## Prossimo pezzo previsto

`GameEngine` contiene ora **quattro motori di gioco** (Hold'em No Limit, Five-Card
Draw, Omaha Pot Limit, Machiavelli) più i loro bot. Il Machiavelli (D-070) ha già
il suo driver di sessione, gli eventi e il matchmaking progressivo in `GameWorld`,
ma **non è giocabile**: mancano **UI**, **audio** e il **casinò ospitante** (il terzo
casinò, non ancora anticipato). Il prossimo lavoro è dunque fuori dal motore puro:
`MachiavelliTableView` e la sua UII accessibile — box di composizione per il cieco,
drag per il vedente, entrambi sopra lo stesso predicato — e la voce che riempie
l'attesa udibile dei bot che pensano.

## Test

Gli unit test stanno in `Tests/GameEngineTests/` e si eseguono con
`swift test` (99 test, tutti verdi). Coprono: mazzo (mescolata/pescata),
valutazione mani (dieci categorie, wheel, royal vs scala colore, kicker, split);
motore Hold'em (`HoldemHandTests`: blind, rotazione button, min-raise, all-in
incompleto che non riapre, side pot, showdown, fold-win, blind short, chip
conservati, determinismo); aritmetica dei pot (`PotMathTests`: side pot e chip
di resto); bot Hold'em (`BotTests`: solo azioni legali, determinismo, personalità
che divergono, spot ovvi come AA/7-2o, tilt, informazione onesta, simulazione
multi-mano senza crash con fiches conservate); **motore Five-Card Draw**
(`FiveCardDrawTests`: distribuzione + ante + mazzo, rilevamento jacks-or-better,
pass-and-out con pot progressivo su più mani, small/big bet e cap dei raise,
draw con rimpiazzo carte, showdown corretto, openers da dimostrare
positivo/negativo + bluff riuscito su fold-out, determinismo, azioni illegali);
**bot Draw** (`DrawBotTests`: dial delle personalità, scarto da manuale, azioni e
scarti sempre legali e deterministici, disciplina di apertura, simulazione
multi-mano con fiches conservate); **motore Machiavelli** (`MachiavelliTests`:
predicato di validità su ogni frontiera — group a semi distinti, run con asso ai
due capi ma senza wrap, minimi, tavolo valido; modello del turno — valutazione
ipotetica senza mutazione, apply, terminale pass/draw; ricombinazione che tiene o
rompe il tavolo; **stessa carta mossa più volte**; i **due assi indipendenti** dei
bot; la ricerca che **non sfora mai** il budget di tempo; determinismo dato seed+nodi;
**retrocompatibilità additiva** — le dimensioni Machiavelli non cambiano Texas/Omaha).

## Dimensioni di fold della Personality (D-048)

Due dimensioni additive della `Personality` pesano i **segnali di pressione**
dell'avversario che la sola matematica di equity (D-011) ignora — così bluffare
diventa possibile. Default retrocompatibili (comportamento identico a prima):

| Dimensione | Cosa fa |
|---|---|
| `pressureResistance` (default 1.0) | Resistenza al fold di fronte a una **bet grossa** (> 60% del pot). Meccanica pura in `Personality.callThresholdMultiplier(betFraction:pressureResistance:)`: sopra il 60% del pot la **soglia di equity per chiamare** viene moltiplicata per `1 + min(0.8, betFraction·(1−pR)·0.9)`. Bet 70% del pot: pR 0.3 → +44% equity richiesta; pR 0.9 → +6%. Le mani forti chiamano/rilanciano comunque. |
| `trashFoldTendency` (default 0.0) | Probabilità di **foldare spazzatura** pre-flop (Texas, forza Chen normalizzata < 0.18) o al primo giro (Draw, `DrawStrategy.isPreDrawGarbage`), anche senza pressione. |

Entrambe valgono per Texas (`HeuristicBot`) e Draw (`HeuristicDrawBot`); non
spostano lo stream RNG per le decisioni non interessate (trashRoll pescato dopo il
roll e solo nel ramo garbage). I **valori Classico** vivono nei preset qui; i valori
**Rapido** in `GameWorld` (`WorldPersonalities.fast`).

---

## Blackjack (`Blackjack/`) — D-090

**Sesto motore, e il primo che non è un contesto fra giocatori.** Il giocatore
affronta **il banco**, non altri giocatori, e questo toglie di mezzo per
costruzione tre cose che tutti gli altri motori hanno:

- **niente `PotMath`** — non c'è un piatto conteso da spartire; il pagamento è
  un **moltiplicatore** su una posta;
- **niente bot e nessuna dimensione di `Personality`** — quelle leve descrivono
  un comportamento verso **avversari**, e il banco non è un avversario: è una
  **regola**, e vive qui dentro come tale;
- **niente anello di posti** — il giocatore risolve **le proprie** mani una a una
  (la divisione ne crea altre), poi il banco gioca **una volta sola**.

Resta lo scheletro provato degli altri motori: value type, `apply(_:)` che valida
e muta, e **tutta** la progressione in un solo `progress()`.

| Tipo | Cosa fa |
|---|---|
| `BlackjackValue` | L'aritmetica: punti per rango (asso 1 o 11, figure 10), totale **duro o morbido**, sballo, *natural*, divisibilità **per valore**. |
| `Shoe` | Il sabot **persistente** a più mazzi, col proprio generatore seedato e la carta di taglio. `draw()` è **totale**: un sabot esaurito si rimescola da sé, così la macchina a stati non ha rami di fallimento. |
| `BlackjackRules` | Le regole della casa, ogni variante un campo — così il contratto del tavolo si legge in un punto solo ed è testabile riga per riga. |
| `BlackjackRound` | Una mano, dalla distribuzione al conto saldato: sbirciata del banco, divisioni, raddoppio, resa, gioco del banco, pagamenti. |

**Ciò che NON contiene:** puntate di sessione (le decide il driver), il sabot fra
una mano e l'altra (entra ed esce da `BlackjackRound`), e **l'assicurazione**, che
è una scommessa perdente e non esiste nell'insieme chiuso delle azioni.
