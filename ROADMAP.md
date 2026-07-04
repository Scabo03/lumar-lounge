# Roadmap — Lumar Lounge

Sequenza dei **mattoni** previsti, dallo stato attuale fino alla prima versione
TestFlight con un gioco completo e giocabile: **Texas Hold'em No Limit contro
bot**. La sequenza segue l'architettura a cerchi concentrici del progetto
(`GameEngine` → `GameWorld` → `UI`, con `Audio` trasversale) e i principi già
stabiliti con l'utente (Hold'em come primo gioco, accessibilità come priorità
architetturale, approccio audio-first, bilinguismo it/en).

**Legenda stato:** ✅ fatto · 🔨 in corso · ⏭️ prossimo · 🔭 futuro

> Aggiornare questo file **ogni volta che un mattone cambia stato** o quando
> emerge un mattone nuovo non previsto. Non si stimano tempi.

---

## Fase 0 — Fondamenta (scatola vuota)

### ✅ M0.1 — Impalcatura architetturale
Quattro moduli Swift nel package `LumarKit` con direzione delle dipendenze
verificata dal compilatore (`UI → GameWorld → GameEngine`, `Audio` trasversale),
shell d'app con `RootView`, localizzazione bilingue it/en.
**Dipendenze:** nessuna.

### ✅ M0.2 — Infrastruttura di rilascio
Signing con Fastlane Match (repo certificati privato), pipeline
build → archive → upload TestFlight nelle lane `setup_signing` e
`testflight_upload`, set icone conforme.
**Dipendenze:** M0.1.

---

## Fase 1 — Motore di gioco puro (`GameEngine`)

### ✅ M1.1 — Carte, mazzo, valutazione mani
`Card`/`Rank`/`Suit`, `Deck` (52 carte, shuffle deterministico seedabile, draw),
`HandCategory`/`HandRank`/`HandEvaluator` (miglior mano di 5 su 5+ carte, dieci
categorie, confronto con kicker e split pot). 32 unit test.
**Dipendenze:** nessuna (solo Foundation).

### ✅ M1.2 — Motore partita Texas Hold'em
La macchina a stati di una mano di Hold'em No Limit (`HoldemHand`): rotazione
del **button** e **blind** (con post short/all-in), distribuzione delle hole
card, quattro street, azioni **fold/check/call/bet/raise/all-in** con le regole
di min-raise del No Limit (compreso l'all-in incompleto che non riapre
l'azione), **pot** e **side pot** esatti, showdown con `HandEvaluator`, split e
chip di resto. Introduce il tipo `Hand` giocatore-centrico (D-002) e i tipi
`Seat`/`SeatState`/`Street`/`Action`/`Pot`/`HandResult`/`LegalActions`, più
`PotMath`. Deterministico via seed. 28 unit test (60 totali nel modulo).
**Dipendenze:** M1.1. **Note di design:** D-003…D-008 in `CLAUDE.md`.

### ✅ M1.3 — Intelligenza dei bot (base)
Infrastruttura estensibile per i bot: interfaccia `PokerBot` (dato un
`BotContext`, restituisce un'azione legale) che si aggancia al motore M1.2
dall'esterno via `legalActions()`/`apply(_:)`, senza modificarlo. Baseline
matematico (`HandStrength`: euristica Chen preflop + equity Monte Carlo
postflop) **modulato** da una `Personality` a 7 dimensioni. Tre profili di
partenza visibilmente diversi (`eagerNovice`, `conservativeRock`, `hotAggressor`).
Informazione onesta garantita dalla vista redatta `BotContext` (D-009);
deterministico via seed. 8 unit test (68 totali nel modulo).
**Dipendenze:** M1.1, M1.2. **Note di design:** D-009…D-011 in `CLAUDE.md`.

> **Rifiniture scoperte in corso d'opera** (rimandate, non nuovi mattoni): il
> salto dei seat bustati nella rotazione del button e la gestione dei giocatori
> che entrano/escono appartengono a `GameWorld` (D-006); il burn delle carte è
> stato omesso perché cosmetico (D-007); il narrowing del range per l'equity e
> il tilt cross-mano sono estensioni additive future. Diventeranno lavoro in
> M1.4/M2.1.

### ✅ M1.4 — Driver di sessione: prima integrazione GameEngine ↔ GameWorld
Primo codice reale di `GameWorld`: `SessionDriver` fa girare una **sessione
multi-mano**. Rappresenta un tavolo ad anello a capacità fissa, prepara i
partecipanti e il button per il motore M1.2, guida la mano chiedendo le azioni
via `BotContext`/`apply`, aggiorna le fiches (split e side pot già calcolati dal
motore), ruota il button per posizione con **dead button** (D-012), marca i
bustati (`.bustedOut`, rebuy futuro non implementato) e accetta ingressi/uscite
**solo tra le mani**. Bot e umano rispondono con la stessa interfaccia async
`ActionProvider` (D-013). Determinismo end-to-end, fiches conservate, fine
sessione decisa dal chiamante. 7 unit test.
**Dipendenze:** M1.2, M1.3. **Note di design:** D-012…D-014 in `CLAUDE.md`.

### ✅ M1.5 — Flusso di eventi osservabile del driver di sessione
Il `SessionDriver` ora **narra** lo svolgimento: un flusso multicast di
`SessionEvent` (valori) su `AsyncStream`, a cui più consumatori possono
iscriversi (futuri UI, Audio, VoiceOver) senza che il driver li conosca (D-015).
Tassonomia completa (sessione, mano, blind, distribuzione carte pubblica +
privata, azioni, street, showdown, pot, fine mano, bust, ingressi/uscite),
distinzione **pubblico/privato** con instradamento per audience (un giocatore
vede solo le proprie hole card), ordine cronologico deterministico, nessun
timing artificiale. Il driver resta cliente puro di `GameEngine`; le API M1.4
sono invariate e i loro test passano senza modifiche. La parte "pilotabile"
(stato, turno, mosse legali, attesa umana) era già coperta da M1.4
(`HumanActionProvider`, `BotContext.legal`, query di stato). 6 unit test (13 nel
modulo). **Dipendenze:** M1.4. **Note di design:** D-015 in `CLAUDE.md`.

### ✅ M1.6 — Prima schermata `UI`: tavolo dimostrativo che ascolta il flusso
Il primo codice di `UI`: `PokerTableView` si iscrive al flusso pubblico del
`SessionDriver` e mostra una sessione di Hold'em tra tre bot che si svolge
dall'inizio alla fine, a **ritmo umano** (il ritmo vive nella UI, il driver resta
a velocità di codice — D-018) e interamente **narrata a VoiceOver** con pronuncia
italiana fonetica dei termini poker (D-016). Tavolo ovale ad alto contrasto,
Dynamic Type, carte coperte durante la mano e rivelate allo showdown. Logica di
presentazione pura e testabile (`TableReducer`/`TableAnnouncer`, D-017); nessuna
logica di gioco in UI. 17 unit test + 1 XCUITest di accessibilità.
**Dipendenze:** M1.4, M1.5. **Note di design:** D-016…D-019 in `CLAUDE.md`.

### ✅ M1.7 — Il giocatore umano gioca davvero
Il tavolo è **giocabile**. Layout stratificato (umano protagonista in basso, bot
come badge in alto — D-022); barra azioni Check/Call (dinamica)/Fold/Raise attiva
solo al turno dell'umano; box **Raise a curva progressiva** con +/−, all-in,
conferma/annulla e annunci istantanei interrompenti (D-020). L'azione dell'umano
passa all'`HumanActionProvider` di M1.4; il turno umano si sincronizza col ritmo
del display via coda MainActor + provider in attesa (D-021). Il giocatore vede le
**proprie** carte (flusso come `player`). Fine partita al bust dell'umano o dei
bot, con schermata di esito e restart. Accessibilità di prima classe su ogni
controllo. 10 unit test (curva) + XCUITest di layout/interazione.
**Dipendenze:** M1.4, M1.5, M1.6. **Note di design:** D-020…D-022 in `CLAUDE.md`.

### ✅ M1.8 — Audio come consumatore parallelo del flusso
Il quarto cerchio è pieno. Il modulo `Audio` (`AudioEngine` su AVFoundation)
riproduce ambient in loop, effetti del tavolo, voci del croupier e dei bot,
feedback di esito — restando **neutro** (suoni opachi + categorie, nessuna
conoscenza del poker). La **mappatura evento→suoni** (`AudioScore`, pura) e il
**consumatore parallelo** del flusso (`AudioDirector`) vivono in `UI`, unico
strato che vede sia `SessionEvent` sia `Audio` (D-023). **Coordinamento con
VoiceOver** (D-024): i suoni parlati (croupier/bot) tacciono quando VoiceOver è
attivo, tutto il resto suona — l'accessibilità non è mai ridotta. Voci dei bot
**probabilistiche** e deterministiche via seed. Degradazione con grazia: file
mancanti → silenzio + log (D-025). 16 unit test.
**Dipendenze:** M1.5, M1.7. **Note di design:** D-023…D-025 in `CLAUDE.md`.
**Asset:** i 48 mp3 consegnati sono stati verificati contro il catalogo e
**integrati** (47 in `Resources/Audio/`, rinominati alla forma del catalogo su
scelta dell'utente; poi i 4 `tbl_chips_*` → **51/53**); 2 suoni non ancora
consegnati restano silenziosi. 126 unit test.

---

> **🏁 Fase 1 (M1) completata.** Il gioco base è funzionante **end-to-end**:
> motore Hold'em No Limit completo, bot credibili, sessione multi-mano, flusso di
> eventi osservabile, UI giocabile e accessibile, audio pieno. Il progetto è
> **pronto per un primo upload su TestFlight** (`bundle exec fastlane
> testflight_upload`) — basta aggiungere gli mp3 reali per l'audio non muto.
> La Fase 2 (`GameWorld` — il mondo attorno al tavolo) sarà definita nel dettaglio
> nella prossima conversazione con l'utente.

---

## Fase 2 — Mondo attorno al tavolo (`GameWorld`)

### 🔭 M2.1 — Giocatore, fiches e sessione al tavolo
Il **cuore di orchestrazione** (setup del tavolo, sessione multi-mano, fiches,
bust, rotazione, ingressi/uscite) è già stato consegnato da **M1.4**
(`SessionDriver`). Qui resta da costruire ciò che sta *attorno*: il **giocatore
come entità del mondo** (identità, profilo), i blind level che salgono, il
rebuy dopo bust, e l'aggancio verso la progressione. Si appoggia a M1.4.
**Dipendenze:** M1.4.

### 🔭 M2.2 — Avversari con caratteri
Gli NPC come entità del mondo: nome, personalità, stile di gioco, che mappano i
parametri della IA M1.3 su avversari riconoscibili e ricorrenti.
**Dipendenze:** M1.3, M2.1.

### 🔭 M2.3 — Progressione tra casinò
Gettoni, avanzamento e sblocco progressivo dei casinò; struttura pensata per
accogliere in seguito gli altri giochi. Per il primo TestFlight può essere
minimale (un solo casinò, un solo tavolo).
**Dipendenze:** M2.1.

---

## Fase 3 — Audio trasversale (`Audio`)

### 🔭 M3.1 — Motore audio e aptica
Implementazione reale di `AudioServicing` (oggi solo `NullAudioService`) su
AVFoundation/CoreHaptics, dietro la stessa interfaccia a identificatori opachi.
Approccio **audio-first**: il suono veicola informazione di gioco, non è decoro.
**Dipendenze:** M0.1 (indipendente dal resto; integrabile in qualsiasi momento).

### 🔭 M3.2 — Colonna sonora dei tavoli Hold'em
Set di suoni/aptica per le azioni della mano (carte, puntate, vittoria) mappati
dagli eventi del motore partita.
**Dipendenze:** M3.1, M1.2.

---

## Fase 4 — Interfaccia (`UI`)

### 🔭 M4.1 — Tavolo di Hold'em giocabile
Le viste SwiftUI del tavolo: carte, board, stack, controlli d'azione. Ogni vista
con accessibility identifier e label fin dall'inizio; **VoiceOver come modalità
di prima classe**, pronuncia curata in italiano, principio "nessuno perde
niente" tra vedenti e non vedenti.
**Dipendenze:** M2.1 (mondo), M3.2 (audio) opzionale ma auspicabile.

### 🔭 M4.2 — Contorno minimo (home, ingresso al tavolo)
Il minimo di navigazione per arrivare dal lancio dell'app al tavolo e tornare
indietro. Niente di più del necessario per il primo TestFlight.
**Dipendenze:** M4.1.

---

## Fase 5 — Primo rilascio giocabile

### 🔭 M5.1 — Hold'em No Limit contro bot su TestFlight
Integrazione end-to-end: una partita di Texas Hold'em No Limit completa e
giocabile contro bot, con audio e accessibilità, spinta su TestFlight con la
pipeline già pronta (M0.2). È il **traguardo** di questa roadmap.
**Dipendenze:** M4.1, M4.2, M2.2, M3.2.

---

## Oltre il primo rilascio (orizzonte)

Dopo Hold'em, il motore e il mondo si estendono agli altri giochi, riusando
`GameEngine` e `GameWorld`: **Omaha**, **Five-Card Draw**, **Seven-Card Stud**,
poi **Blackjack** e **Roulette**. Ogni nuovo gioco è un mattone `GameEngine`
(regole pure) più i relativi mattoni `GameWorld`/`UI`/`Audio`. Restano temi
trasversali e continui: ampliamento dei caratteri degli avversari, progressione
tra casinò, e cura costante di accessibilità e localizzazione.
