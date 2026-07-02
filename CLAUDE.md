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
  side pot esatti, showdown/split, deterministico via seed. 60 unit test verdi.

**Prossimo passo.** Mattone **M1.3 — intelligenza dei bot** dentro `GameEngine`
(policy che scelgono una mossa fra `HoldemHand.legalActions()`); in parallelo
`GameWorld` M2.1 inizia a orchestrare una partita contro bot su `HoldemHand`.
Dettaglio e sequenza completa in [`ROADMAP.md`](ROADMAP.md).

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
