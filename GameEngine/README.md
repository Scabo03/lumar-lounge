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

Con carte, motore della mano e bot, `GameEngine` ha tutto il necessario per
*giocare* una mano di Hold'em contro avversari. Il prossimo lavoro esce dal
motore puro: **`GameWorld` M1.4/M2.1** orchestra una sessione multi-mano
(giocatore umano + bot, rotazione button con salto dei bustati, gestione di chi
entra/esce). Il driver di orchestrazione — il loop che costruisce un `BotContext`
per il seat di turno, chiede l'azione al bot e la applica — vive lì, non in
`GameEngine`. Restano possibili raffinamenti additivi qui: nuove personalità,
equity con narrowing del range (D-011), tilt cross-mano.

## Test

Gli unit test stanno in `Tests/GameEngineTests/` e si eseguono con
`swift test` (68 test, tutti verdi). Coprono: mazzo (mescolata/pescata),
valutazione mani (dieci categorie, wheel, royal vs scala colore, kicker, split);
motore Hold'em (`HoldemHandTests`: blind, rotazione button, min-raise, all-in
incompleto che non riapre, side pot, showdown, fold-win, blind short, chip
conservati, determinismo); aritmetica dei pot (`PotMathTests`: side pot e chip
di resto); bot (`BotTests`: solo azioni legali, determinismo, personalità che
divergono, spot ovvi come AA/7-2o, tilt, informazione onesta, simulazione
multi-mano senza crash con fiches conservate).
