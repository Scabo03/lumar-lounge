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

Gestisce i casi particolari del poker: l'Asso che vale 1 nella scala minima
`A-2-3-4-5` (la *wheel*) o 14 nella scala massima, la distinzione tra scala
reale e scala colore, i kicker che rompono i pareggi.

## Cosa NON contiene (per scelta architetturale)

Niente **giocatori**, **tavoli**, **partite** o **stato di gioco** in corso.
Niente concetto di **turno** o di **chi parla**, niente **blind**, **pot** o
**side pot**, niente fiches. Sono tutti concetti di *svolgimento* di una partita:
appartengono al motore della partita e al mondo, non alla rappresentazione pura
delle regole.

Nota di design già presa: **non** esiste (ancora) un tipo `Hand`. `HandRank`
incapsula già tutto ciò che serve per valutare e confrontare. Quando arriverà il
motore della partita si introdurrà un `Hand` **giocatore-centrico** (le due hole
card di un giocatore), distinto da `HandRank` che è **valutazione-centrico**.
Vedi il log delle decisioni in [`../CLAUDE.md`](../CLAUDE.md).

## Prossimo pezzo previsto

Il **motore della partita di Texas Hold'em** (mattone M1.2 in
[`../ROADMAP.md`](../ROADMAP.md)): la macchina a stati di una mano — street,
turni, azioni fold/call/raise, gestione di pot e blind, side pot, e la
determinazione del vincitore usando `HandEvaluator`. Resterà anch'esso puro:
Foundation soltanto, nessuna UI.

## Test

Gli unit test stanno in `Tests/GameEngineTests/` e si eseguono con
`swift test`. Coprono creazione/mescolata/pescata del mazzo, riconoscimento di
tutte e dieci le categorie, casi limite (wheel, royal vs scala colore) e
confronti (coppie, kicker, split pot).
