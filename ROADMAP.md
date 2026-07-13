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
VoiceOver:** originariamente D-024 (silenziamento dei parlati), poi **ripensato in
D-028** (vedi sotto). Voci dei bot **probabilistiche** e deterministiche via seed.
Degradazione con grazia: file mancanti → silenzio + log (D-025).
**Dipendenze:** M1.5, M1.7. **Note di design:** D-023…D-025 in `CLAUDE.md`.
**Asset:** i 48 mp3 consegnati sono stati verificati contro il catalogo e
**integrati** (47 in `Resources/Audio/`, rinominati alla forma del catalogo su
scelta dell'utente; poi i 4 `tbl_chips_*` → **51/53**); 2 suoni non ancora
consegnati restano silenziosi. 126 unit test.

### ✅ Fix post-M1.8 — Coordinamento audio↔VoiceOver ripensato dopo il primo test reale (D-028)
Non un mattone nuovo, ma un **fix architetturale importante** emerso al primo test
su iPhone reale con VoiceOver dopo l'upload TestFlight di M1.8. Due sintomi legati:
gli annunci VoiceOver si accavallavano in cascata, e le voci del croupier
**sparivano** dopo i primi eventi. Cause reali (verificate nel codice): la strategia
D-024 **silenziava** i parlati con VoiceOver attivo (e la latenza di
`isVoiceOverRunning` all'avvio lasciava passare solo i primissimi), mentre `present()`
annunciava **ogni** evento del flusso. Sostituita dalla **"strategia C" (D-028):
domini separati, mai concorrenti** — il croupier suona sempre per gli eventi
istituzionali, VoiceOver solo per l'informazione personale del giocatore, le azioni
degli avversari non annunciate, e un coordinamento temporale a una direzione
(VoiceOver aspetta la voce in corso via `spokenAudioRemaining()`/`SpeechCoordinator`).
Cambi solo in `UI` e `Audio`, nessuna modifica a `GameEngine`/`SessionDriver`/flusso.
131 unit test verdi. **Note di design:** D-028 in `CLAUDE.md`.

### ✅ Fix post-M1.8 (2) — Mappatura autorevole evento→sorgente vocale e fix "disco rotto" (D-029)
Secondo giro di test reale. D-028 era giusta nei principi ma ancora approssimativa:
annunci sovrapposti, **voci ripetute in loop** (il `vo_it_pot_awarded` 3-4 volte) e
sintesi ridondante dove esiste già un mp3 ("è il tuo turno"). Radice: mp3 e sintesi
mappati **separatamente**. Rifatto con **una sola fonte di verità** — `SpeechMap`
(funzione pura event→sorgente) + `SpeechConductor` (seriale: mp3 croupier con
completion **poi** sintesi; **de-dup once-per-hand** di showdown/pot → fix del disco
rotto, causa vera: `SessionDriver` emette un `potAwarded` per pot). Il turno umano
ora **suona** `vo_it_your_turn.mp3`; la sintesi copre solo ciò che l'mp3 non può dire
(carte, mani allo showdown, conclusione pot). Aggiunti **ambient dinamico** (tense su
all-in, hush allo showdown) e **voci bot** deterministiche per carattere con
anti-ripetizione. Solo `UI` + `Audio`, nessuna modifica al motore/flusso. 132 test
verdi. **Note di design:** D-029 in `CLAUDE.md`.

### ✅ Fix post-M1.8 (3) — Ruolo personale, azioni avversari, fallback mp3→sintesi, pot loop residuo (D-030/D-031)
Terzo test reale. **Pot ancora sdoppiato:** causa vera = la **sintesi** di conclusione
non era deduplicata (l'mp3 sì) e `PotMath` genera legittimamente più pot per mano →
ora la conclusione è once-per-hand. **Turno via sintesi:** l'mp3 c'è ed è richiesto;
era **timing** (coda seriale occupata) → cue del turno reso time-critical con flush.
**Blind generici → annuncio del solo ruolo del giocatore umano** (o silenzio, D-031).
**Vuoto acustico avversari riempito:** sintesi attribuita col numero di seat, con la
`vob_` (spostata in `BotChatter`) come lead prima della sintesi. Nuovo **pattern
riusabile fallback mp3-mancante→sintesi** (D-030), per la produzione audio graduale
(introdotto col ruolo `button`). Aggiunti log DEBUG di riproduzione e self-check
all'avvio. Solo `UI` + `Audio`. 143 test verdi. **Note di design:** D-030, D-031.

### ✅ Fix post-M1.8 (4) — Coda seriale degli annunci VoiceOver (Strategia C, D-032)
Quarto test reale: il croupier ottimo, ma la **sintesi VoiceOver** si accavallava
(il `.announcement` di default interrompe → annunci troncati in raffica). Problema
**strutturale e trasversale** a tutto il progetto. Decisione A vs C presa **dai dati**:
una simulazione di 8 mani ha misurato **saturazione 147%** del canale seriale (medium/
low dominano) e fino a **~50 s di ritardo** sotto FIFO stretta, mentre l'high è il
**2%** → **Strategia C**. Costruita l'`AnnouncementQueue` (UI, `@MainActor`,
game-agnostica): unico punto che posta a VoiceOver (guard statico), serializza senza
troncare, priorità+drop di low/medium, completamento via
`announcementDidFinishNotification` + tetto 1 s, e **coordinamento come unico canale**
col `SpeechConductor` (blocco reciproco croupier↔sintesi). `Announcer` rimosso, log
unificato in `SpokenLog`. Solo `UI` + `Audio`. 146 test verdi. **Note di design:** D-032.

### ✅ Impostazioni permanenti + modalità VoiceOver dell'app + ritmo adattivo (D-033/D-034)
L'utente ha notato uno **sfasamento occhio-orecchio** a fine mano (la sintesi parla del
passato mentre il visivo è già avanti). Introdotti: un **chrome persistente**
(`GameChrome`) con pulsante Impostazioni riusabile per tutto il progetto e una
**schermata impostazioni** che crescerà (D-033); una **modalità VoiceOver dell'app**
(`AppVoiceOverMode`, osservabile, persistita, **indipendente** da iOS, default OFF) che
quando **ON** fa **attendere alla UI** il canale parlato (croupier + coda sintesi)
prima di mostrare l'evento successivo — occhio e orecchio insieme — e quando OFF tiene
il ritmo veloce (D-034). Cambio modalità a **effetto immediato**. `SessionDriver` **non
toccato** (sincronia solo lato consumatore). Solo `UI`. 157 test + XCUITest impostazioni.
**Note di design:** D-033, D-034.

### ✅ M1.9 — Motore di Five-Card Draw ("Jacks or Better")
Il **secondo motore di gioco** del progetto, interamente in `GameEngine/Draw/`,
**indipendente** dal Texas (nessuna dipendenza incrociata; condivisi solo i tipi
fondazionali M1.1 e l'aritmetica `PotMath`/`Pot`, D-038). `FiveCardDrawHand` è una
macchina a stati pura e deterministica per **una mano** di draw tradizionale
completa: quattro giocatori tipici, **ante** (niente blind), **due giri di puntata
limit** (small/big bet come parametri del tavolo, cap a tre raise), **draw** 0–4
carte, valutazione a cinque carte con `HandEvaluator`. Regole distintive:
**jacks-or-better per aprire sull'onore** con **verifica degli openers allo
showdown** (apre chi vuole, ma senza i jack allo showdown perde d'ufficio; bluff
riuscito su fold-out invece vince, D-039); **pass-and-out con pot progressivo,
variante B** (nessuno apre → mano nulla, ante che si accumulano nel `carryPot`
della mano successiva, D-040). Bot dedicati (`HeuristicDrawBot` + `DrawStrategy`
pura) che riusano le tre personalità del Texas con **tre nuovi dial** additivi
(`drawDiscipline`/`drawBluffiness`/`openingDiscipline`, inerti nel Texas). Nessun
driver di sessione né UI del Draw (mattoni futuri). Solo `GameEngine`. 31 unit test
(99 nel modulo). **Dipendenze:** M1.1. **Note di design:** D-038…D-041 in `CLAUDE.md`.

> Numerato M1.9 (motore puro, Fase 1) anche se realizzato dopo M2.1: è un mattone
> `GameEngine`, non del mondo. Rende concreto il gioco già previsto per la "Sala
> Whiskey" del Riverwood (D-035); mancano ancora il suo driver in `GameWorld` e la
> sua UI perché la sala diventi entrabile.

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

### ✅ M2.1 — Struttura del mondo: Home, Riverwood Casinò, gettoni, tavolo Rapido
Il primo mattone di M2. L'app apre su **Home** e ha una **navigazione a tre livelli**
Home → Riverwood Casinò → Tavolo (D-035, `AppState`+`AppRootView`, `GameChrome`
trasversale). **Gettoni persistenti** del giocatore in GameWorld (`PlayerAccount`),
distinti dalle **fiches** al tavolo: buy-in, cash-out, bust, saldo mostrato in Home/
Casinò (D-036). **Lascia il tavolo** a fine mano. Il **Riverwood** (estetica rustica,
SwiftUI+serif, nessuna texture ancora) elenca tre tavoli: Hold'em **Classico** (=M1),
Hold'em **Rapido** (bot più aggressivi + **boost mano decisiva**: 3 mani senza fold
pre-flop → blind raddoppiate + annuncio croupier + ambient teso, D-037), e Five-Card
Draw **visibile ma non entrabile**. `SessionDriver` non modificato strutturalmente
(override blind additivo). Solo `GameWorld`+`UI`+`Audio`(catalogo). 174 test + 3 XCUITest.
**Note di design:** D-035, D-036, D-037. **Slot audio M2 predisposti** (fallback):
`amb_home_neutral`, `amb_riverwood_calm_01/02`, `vo_it_high_stakes`, `ui_navigation`.

### ⏭️ Prossimi sotto-mattoni M2 (proposti)
- **M2.2 — Cassa / DLC:** ricarica dei gettoni quando finiscono (acquisti, bonus).
- **M2.3 — Ambient Riverwood:** produzione e integrazione dei file audio dedicati
  (chitarra/piano rustici) al posto dei fallback.
- **M2.5 — Secondo casinò lussuoso** (es. Velvet Palace) con estetica opposta.
- **M2.6 — NPC narrativi:** avversari ricorrenti con nome/carattere/storia.

### ✅ M2.4 — Five-Card Draw giocabile fino a TestFlight (D-042/043/044)
Il secondo gioco diventa **giocabile end-to-end**. Driver di sessione dedicato
`DrawSessionDriver` in GameWorld (speculare a M1.4 ma indipendente: ante, due giri
limit, draw, **pass-and-out con pot progressivo** — button che non ruota sulle mani
annullate, D-040; **due sospensioni** del provider umano puntata/scambio, D-042), con
**flusso eventi proprio** `DrawSessionEvent` sulla stessa infrastruttura EventHub
(D-043). **UI del tavolo Draw** `DrawTableView` (stato/riduzione puri dedicati, barra
limit a importi fissi, cinque carte dell'umano) con il **box modale di scambio**
accessibile (cinque carte selezionabili, **doppio segnale visivo**, ogni carta pulsante
VoiceOver con stato, Conferma sempre attivo, focus intrappolato — D-044). **Cablaggio
Riverwood:** la "Sala Whiskey" (buy-in 2000) da slot "in arrivo" diventa **entrabile**.
Riuso di tutta l'infrastruttura trasversale (chrome, coda annunci, conductor, modalità
VoiceOver, ritmo adattivo). Layer parlato dedicato (`DrawSpeechMap`) con **5 nuovi slot
croupier** non ancora prodotti → **fallback di sintesi** (D-030). Motore/Texas non
toccati. 234 unit test + XCUITest del tavolo Draw + navigazione aggiornata.
**Dipendenze:** M1.9, M2.1. **Note di design:** D-042, D-043, D-044 in `CLAUDE.md`.

### ✅ Rifinitura post-M1.9 — ritmo del Whiskey + dedup vocale (D-051/052/053)
Dopo il test reale: (1) fix della **squalifica per openers ripetuta** con
**consolidamento** della deduplicazione once-per-hand come lista dichiarata unica del
`SpeechConductor` (D-051); (2) **ante progressivo** (+20% per pass-and-out, ritorno al
base dopo una mano giocata, D-052) e (3) **mani decisive** ogni 5–8 mani (o forzate dopo
3 pass-and-out) con bet ×2, cap raise 3→5 e boost contestuale dei bot (D-053), tutto solo
al tavolo Whiskey e tutto nel driver (motore ricevi parametri additivi). Nuovo slot audio
`vo_it_high_stakes_draw` (fallback sintesi). 272 test verdi.

### ✅ Rifinitura post-M2 — layer VoiceOver + audio dopo il test reale (D-054…D-058)
Cinque fix dal test su iPhone (build 1783771001, Tavolo Rapido con VoiceOver), tutti in
`UI`/`Audio`: (1) **copertura fonetica estesa ai pulsanti** — chiuso il buco del Check/Call
idle, `PhoneticsTests` ora scandisce i sorgenti degli action bar (D-054); (2) rimosso
l'**annuncio contestuale "per chiamare X"** al turno umano — il pulsante lo dice già
(D-055); (3) **salvaguardia temporale del ritmo adattivo** (tetto ~3 s) + **completion del
croupier garantita** in `AudioEngine`, che chiudono il **blocco pre-flop** con VoiceOver ON
(D-056); (4) **pattern di atterraggio del focus VoiceOver** a ogni cambio schermata/modale
(`.voiceOverFocusLanding()`, D-057); (5) **voci dei bot bustati filtrate** dallo stato
attuale del tavolo (D-058). 280 test verdi. Motore/driver/flusso non toccati.

> Prossimi sotto-mattoni M2 (residui): cassa/DLC per ricarica gettoni, produzione dei
> file audio predisposti (ambient Riverwood + voci croupier del Draw), secondo casinò.

### ✅ M1.10 — Motore di Omaha Pot Limit (motore + bot + driver, NON giocabile) (D-061…D-064)
Terzo motore di `GameEngine`, in `Omaha/`, **indipendente** da Texas e Draw. `OmahaHand`:
quattro carte private, quattro street comuni, **valutazione vincolata due-più-tre** (esteso
additivamente `HandEvaluator.evaluateOmaha`, D-061), **betting Pot Limit** col tetto calcolato
dal vivo (`PotMath.potLimitMax…`, D-062), side pot, determinismo via seed. `HeuristicOmahaBot`
gioca Omaha da Omaha (euristica pre-flop a quattro carte + equity Monte Carlo **vincolata**,
costo **misurato** ~3×/campione → ~⅓ dei campioni per la parità di risposta col Texas) con due
leve additive di `Personality` (`omahaCoordination`/`omahaNuttiness`, D-063). `OmahaSessionDriver`
in `GameWorld`, sorella di `SessionDriver`/`DrawSessionDriver` con flusso eventi proprio, seed
casuale per mano in produzione (D-047), e **accelerazione di sessione riusabile a
conteggio-mani** (`StakeEscalation`: blind escalation stile torneo, **mai a tempo** —
accessibilità, D-064; rifiutata la mano decisiva No-Limit dentro il Pot Limit). 311 test verdi;
Texas e Draw **invariati**. Niente TestFlight (nulla di giocabile).

> **Residuo aperto per Omaha (esplicito):** è **motore ma non giocabile**. Mancano la **UI**
> (`OmahaTableView`, viste, box), l'**audio** (voce croupier, file mp3, estensione `SpeechMap`)
> e il **casinò ospitante** — Omaha sarà la specialità di un **secondo casinò** che non esiste
> ancora e la cui identità/decisioni sono un mattone successivo, non anticipato qui.

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
