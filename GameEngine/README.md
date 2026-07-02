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

Gestisce i casi particolari del poker: l'Asso che vale 1 nella scala minima
`A-2-3-4-5` (la *wheel*) o 14 nella scala massima, la distinzione tra scala
reale e scala colore, i kicker che rompono i pareggi. E, nel motore della mano:
min-raise del No Limit, all-in incompleto che non riapre l'azione, blind posti
short/all-in, side pot esatti con stack diversi, showdown con split e chip di
resto al seat alla sinistra del button (D-004).

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

L'**intelligenza dei bot** (mattone M1.3 in [`../ROADMAP.md`](../ROADMAP.md)):
policy di decisione che, dato lo stato della mano e le mosse legali esposte da
`HoldemHand.legalActions()`, scelgono un'azione valida. Resterà puro: Foundation
soltanto, nessuna UI. In parallelo, `GameWorld` (M2.1) inizierà a consumare
`HoldemHand` per orchestrare una partita contro bot.

## Test

Gli unit test stanno in `Tests/GameEngineTests/` e si eseguono con
`swift test` (60 test, tutti verdi). Coprono: mazzo (mescolata/pescata),
valutazione mani (dieci categorie, wheel, royal vs scala colore, kicker, split);
motore Hold'em (`HoldemHandTests`: blind, rotazione button, min-raise, all-in
incompleto che non riapre, side pot, showdown, fold-win, blind short, chip
conservati, determinismo); aritmetica dei pot (`PotMathTests`: side pot e chip
di resto).
