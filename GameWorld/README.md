# GameWorld

Il **mondo attorno ai tavoli**: il cerchio intermedio dell'architettura.

## Filosofia

`GameWorld` conosce ciò che `GameEngine` ignora di proposito: il **giocatore** e
il suo stato, le **fiches** al tavolo, chi siede dove, chi busta, chi entra e chi
esce — e, in prospettiva, gli **NPC/avversari** con i loro caratteri, i
**gettoni** e la **progressione** tra casinò.

Può importare `GameEngine` e ne è **cliente puro**: non lo modifica e non ne
conosce l'interno. **Non** importa `UI` né `Audio`, né alcun framework
SwiftUI/UIKit: la direzione è `UI → GameWorld → GameEngine`, verificata dal
compilatore. È codice puro, testabile in isolamento.

## Cosa contiene oggi

### M1.4 — driver di sessione

Una **mano** è un episodio; una **sessione** è una serie di mani legate tra loro
allo stesso tavolo. Il driver è l'orchestratore che, mano dopo mano, prepara lo
stato per il motore di `GameEngine`, gli fa svolgere la mano, ne raccoglie il
risultato, aggiorna il tavolo e prepara la mano successiva.

| Tipo | Ruolo |
|---|---|
| `SessionDriver` | L'orchestratore multi-mano: crea una `HoldemHand`, la guida via `BotContext`/`apply`, aggiorna fiches, ruota il button (dead button, D-012), gestisce bust ed entrate/uscite tra le mani. Cliente puro di `GameEngine` (D-014). |
| `ActionProvider` | Interfaccia **uniforme** (async) con cui il driver chiede l'azione al seat di turno, indistintamente bot o umano (D-013). |
| `BotActionProvider` | Adatta un `PokerBot` (M1.3) a `ActionProvider`. |
| `HumanActionProvider` | Provider guidato da umano: `provideAction` si **sospende** finché la UI non chiama `submit(_:)` (continuation, nessun threading nostro). |
| `SessionPlayer` / `PlayerStatus` | Un giocatore seduto (id, fiches, posizione) e il suo stato (`active`/`bustedOut`). |
| `SeatAssignment` | L'assegnazione di un posto in fase di setup o ingresso. |
| `HandOutcome` | L'esito di una mano dal punto di vista della sessione (button, partecipanti, `HandResult`, bust, fiches aggiornate). |
| `SessionError` | Errori del driver (pochi giocatori, mano in corso, posto occupato, …). |

Punti fermi: **determinismo end-to-end** (stessa config + stessi seed + stesse
azioni → stesso risultato), **fiches conservate** a ogni mano, ingressi/uscite
**solo tra le mani**, e criterio di fine sessione **esterno** al driver (il
chiamante fa il loop su `playHand()`/`run(...)` e decide quando fermarsi).

### M1.5 — flusso di eventi osservabile

Il driver ha ora una **voce**: mentre fa quello che già faceva, **narra** ogni
momento significativo come `SessionEvent`, in ordine cronologico, su un canale
multicast a cui più consumatori possono iscriversi (in futuro UI, Audio,
VoiceOver). Chi non si iscrive non nota alcuna differenza rispetto a M1.4.

| Tipo | Ruolo |
|---|---|
| `SessionEvent` | Un evento: numero di sequenza + `audience` + `payload`. È un **valore** (sicuro tra contesti concorrenti, facile da testare). |
| `EventPayload` | La **tassonomia** dei momenti: `sessionBegan`/`sessionEnded`, `playerJoined`/`playerLeft`, `handBegan`, `blindPosted`, `holeCardsDealt` (pubblico) e `privateHoleCards` (privato), `playerActed`, `streetOpened`, `handShown`, `potAwarded`, `handEnded`, `playerBusted`. |
| `EventAudience` / `EventViewer` | Pubblico vs privato: un evento è per `everyone` o per `player(id)`; un iscritto guarda come `spectator` (solo pubblico) o `player(id)` (pubblico + il proprio privato, **mai** l'altrui). |
| `ActedAction`, `BlindKind`, `SeatSnapshot`, `SessionEndReason` | Descrittori di supporto, self-contained (portano gli importi concreti). |
| `EventHub` | L'`actor` interno che fa il fan-out a tutti gli iscritti (Swift Concurrency pura, niente lock né thread nostri). |

API: `events(as:) async -> AsyncStream<SessionEvent>` per iscriversi, e
`endSession(reason:)` che emette `sessionEnded` e **chiude** i flussi (così i
`for await` dei consumatori terminano). Gli eventi sono **descrittivi** (dicono
cosa è successo), mai **prescrittivi** (non dicono a nessuno cosa fare): UI e
Audio li interpreteranno come vorranno. Sequenza **deterministica** dato lo
stesso stato/seed/azioni. Nessun timing artificiale: il flusso va a velocità di
codice, il ritmo umano è responsabilità del consumatore. La privacy delle hole
card è garantita **per costruzione** dall'instradamento per audience (nello
spirito di D-009).

## Cosa NON contiene (per scelta architetturale)

- **Nessun "casinò" né progressione tra casinò**: materia di mattoni futuri.
- **Nessun "gettone"**: qui siamo *dentro* il tavolo, quindi solo **fiches**. Il
  gettone è valuta del casinò esterno e vive altrove.
- **Nessuna ricompra dopo bust**: il seat bustato resta marcato `.bustedOut`
  (fiches 0), pronto a un futuro rebuy che non è implementato adesso.
- **Nessun NPC, dialogo o atmosfera**: questo è un driver puro; i caratteri e
  l'ambiente arrivano dopo.
- **Niente UI/Audio** e nessuna modifica a `GameEngine`.
- **Nessun timing/ritmo** negli eventi (nessun ritardo artificiale) e **nessuna
  persistenza/replay su disco**: il flusso è in memoria, a velocità di codice.
- Gli eventi sono **neutri**: nessun riferimento a suoni, viste o testi; UI e
  Audio arriveranno come *consumatori* in mattoni dedicati.

## Cosa sarà suo compito (prossimo)

Estendere la sessione verso M2.x: giocatore come persona, avversari con
personalità ricorrenti, rebuy, e la struttura per la progressione tra casinò.
Vedi [`../ROADMAP.md`](../ROADMAP.md).

## Test

`Tests/GameWorldTests/` (13 test, `swift test`).
- `SessionDriverTests` (M1.4, invariati): sessione a due bot fino al bust con
  fiches conservate; tre giocatori con uno che busta e la sessione prosegue;
  rotazione del button per posizione con seat bustati saltati; ingresso di un
  nuovo giocatore tra due mani; sospensione/ripresa dell'azione umana (con blocco
  degli ingressi a mano in corso); determinismo end-to-end.
- `SessionEventTests` (M1.5): ordine canonico degli eventi (blind prima delle
  carte, azioni in ordine di parlata, flop→turn→river, fine mano in coda); più
  iscritti ricevono la stessa sequenza; un giocatore vede le proprie hole card
  ma mai le altrui, lo spettatore nessuna; determinismo dell'intero flusso;
  narrazione di ingressi e bust.

## M2.1 — Il mondo attorno al tavolo (D-035/036/037)

| Tipo | A cosa serve |
|---|---|
| `PlayerAccount` + `ChipsStore` | Il conto **gettoni** persistente del giocatore (valuta esterna al tavolo, D-036), dietro un `ChipsStore` iniettabile (`UserDefaultsChipsStore`, `InMemoryChipsStore` per i test). Prima esecuzione: 5000. `buyIn`/`cashOut`/`canAfford`. |
| `TableFormat` / `TableRules` | La configurazione di un tavolo (D-035): stile (`classic`/`fast`), blind, buy-in, personalità dei bot, flag del boost. `.classic` e `.fast` come preset. Alimenta gli entry di config del `SessionDriver`, che **non è modificato strutturalmente**. |
| `WorldPersonalities` | Le personalità dei bot per stile di tavolo (definite **qui**, non nel motore): `classic` (roster M1) e `fast` (aggression/bluff/risk alzate, tightness abbassata — visibilmente più aggressive, D-037). |
| `DecisiveHandBoost` | Il contatore osservabile/testabile del **boost mano decisiva** (D-037): dopo 3 mani consecutive senza fold pre-flop, `isNextHandDecisive`; un fold azzera; `consumeDecisiveHand` riparte. Le blind della mano decisiva si raddoppiano via l'override additivo `SessionDriver.playHand(overrideSmallBlind:overrideBigBlind:)`. |

## M2.4 — Sessione di Five-Card Draw (D-042/043)

Un secondo driver di sessione, **dedicato e indipendente** dal Texas (il
`SessionDriver` non è toccato), per il gioco del Draw. Riusa la *forma provata*
del Texas (anello, dead button, fan-out eventi, cambi strutturali tra le mani) ma
con **tipi propri**, perché le regole differiscono troppo per condividere
un'astrazione senza rigidità (D-042).

| Tipo | A cosa serve |
|---|---|
| `DrawSessionDriver` | Orchestra una **sessione multi-mano** di Five-Card Draw: ante, due giri limit, draw, **pass-and-out con pot progressivo** (conserva il `carriedPot` e lo passa alla mano successiva; il **button non ruota** sulle mani annullate, D-040), dead button, bust, ingressi/uscite tra le mani. Cliente puro del motore, deterministico, fiches conservate. |
| `DrawActionProvider` | Interfaccia async uniforme bot/umano con **due** metodi: `provideAction` (puntata) e `provideDiscards` (scambio). `DrawBotActionProvider` avvolge un `DrawBot`; `HumanDrawActionProvider` è un actor con **due sospensioni nettamente separate** (puntata vs draw, mai entrambe pendenti). |
| `DrawSessionTypes` | `DrawSessionPlayer`, `DrawSeatAssignment`, `DrawHandOutcome` (con `wasPlayed`/`carriedPot`/`consecutivePassed`), `DrawSessionError`. |
| `DrawTableRules` | Configurazione del tavolo Draw: ante, small/big bet, buy-in, personalità. `.riverwoodWhiskey` (ante 10, 20/40, buy-in 2000). |
| `DrawSessionEvent` / `DrawEventPayload` | La **tassonomia di eventi propria** del Draw (D-043): ante, apertura dichiarata (con `hasOpeners`), pass-and-out, fase di draw + conteggio scarti, carte pescate (privato), squalifica openers, ecc. **Non unificata** con quella del Texas; riusa solo `EventAudience`/`EventViewer`. |
| `DrawEventHub` | Fan-out multicast speculare a `EventHub`, tipizzato su `DrawSessionEvent` (piccola duplicazione consapevole invece di un generico forzato). |

**Test** (`DrawSessionDriverTests`, `DrawSessionEventTests`): bot vs bot fino al
bust con fiches conservate; sessione a quattro con umano simulato; pass-and-out su
più mani con **pot progressivo** che si accumula e **button che non ruota**; mano
giocata che ruota il button e azzera il carry; determinismo; ordine canonico degli
eventi (mano giocata, pass-and-out, squalifica openers) e routing pubblico/privato.

## Fix produzione: seed casuale per-mano nei driver (D-047)

Il motore resta **deterministico dato un seed**; cambia **come i driver generano il
seed** che gli passano. `SessionDriver` e `DrawSessionDriver` hanno ora
`seed: UInt64? = nil` nell'init:

- **seed impostato** (test/replay): ogni mano deriva un seed **deterministico** dal
  base seed (come prima) → sessioni riproducibili.
- **seed `nil`** (produzione, default): ogni mano estrae un seed **fresco casuale** da
  `SystemRandomNumberGenerator` → carte sempre diverse, ogni mano e ogni sessione.

Prima il seed arrivava da una **costante cablata** nei view model della UI, quindi ogni
partita distribuiva le stesse identiche carte (bug scoperto al primo test su device). I
test unitari continuano a iniettare seed fissi e restano deterministici; nuovi test
(`SeedRandomizationTests`) verificano che in produzione (seed nil) sessioni successive
diano carte diverse e che una sessione lunga abbia mani e vincitori vari.

## Calibrazione delle personalità per tavolo (D-048)

I preset dei bot per stile di tavolo (`WorldPersonalities`) ora differenziano anche
la **propensione al fold** (dimensioni `pressureResistance`/`trashFoldTendency`,
definite in `GameEngine`, D-048). Il motore resta ignaro dei tavoli: riceve
personalità già calibrate.

| Archetipo | Classico (pR / tFT) | Rapido (pR / tFT) |
|---|---|---|
| Novice | 0.35 / 0.30 | 0.60 / 0.15 |
| Rock | 0.50 / 0.90 | 0.70 / 0.75 |
| Aggressor | 0.75 / 0.15 | 0.90 / 0.05 |

Al **Classico** rock e novice foldano visibilmente su una pressione forte (il bluff
funziona); al **Rapido** tutti più stubborn e propensi a giocare qualsiasi mano
(scontro drammatico, D-037). Il tavolo Whiskey del Draw usa i preset Classico.
Caratterizzato dai test in `FastTablePersonalityTests` (il Rapido folda meno del
Classico su pressione).

## Rifinitura Draw: ante progressivo + mani decisive al Whiskey (D-052/D-053)

Due meccaniche di ritmo, attive **solo** al tavolo Whiskey (flag di `DrawTableRules`),
tutte nel `DrawSessionDriver` come override contestuali — il motore riceve solo
parametri di config:

- **Ante progressivo (D-052):** ogni pass-and-out fa crescere l'ante della mano dopo
  del **20% composto** (base 20 → 24 → 29 → 35 → …); la mano giocata usa l'ante
  cresciuto, poi si torna al base. `currentAnte` cresce/reset nel driver; il valore è
  in `handBegan`/`DrawHandOutcome.ante`.
- **Mani decisive (D-053):** ogni **5–8 mani giocate** (soglia casuale per intervallo,
  deterministica coi test) — o **forzata** dopo **3 pass-and-out consecutivi** — una
  mano è decisiva: **bet ×2**, **cap raise 3→5** (via `FiveCardDrawHand.maxRaisesPerRound`,
  parametro additivo del motore), **bot boostati** (aggression +0.15, trashFold ×0.5)
  passati **via `DrawBotContext`** (mai modificando la `Personality`). Evento nuovo
  `decisiveHandStarted`; `DrawHandOutcome.wasDecisive`.

Coperto da `DrawDecisiveHandTests` (crescita ante e ritorno al base, forzatura dopo 3
pass, bet/cap raddoppiati, intervallo 5–8, disattivazione) e dal boost bot in
`DrawBotTests`.

## Pattern casinò + Skypool (M2.5, D-065/D-066)

- **`Casino`/`CasinoTable`/`CasinoGame` + registry `Casinos`.** Un casinò ospita tavoli;
  ogni tavolo dichiara il suo gioco (`.texas`/`.draw`/`.omaha` con le regole complete),
  buy-in e personalità. Aggiungere un casinò è un **cambio di dati** nel registry, non
  codice duplicato. Il **Riverwood è invariato** dopo la generalizzazione (`CasinoTests`).
- **Skypool** (`Casinos.skypool`): Texas Classico/Rapido con **bot urbani**
  (`WorldPersonalities.skypool`/`skypoolFast`, tre personalità come **entità proprie**, D-066)
  + la specialità **Omaha Pot Limit "Marble"** (`OmahaTableRules.skypoolMarble`). Buy-in ~5×
  il Riverwood, scala crescente Fast 5000 < Classic 6000 < Marble 10000. Accesso **solo
  economico** (testato con `DEBUG_FREE_PLAY` off in `CasinoTests`). Riverwood **non
  ricalibrato** (calibrazione comparativa = mattone successivo).

## Machiavelli: driver di sessione + eventi + matchmaking (D-070, solo motore)

Il **quarto gioco** (Machiavelli, la ricombinazione) ha in `GameWorld` la sua
sessione, **sorella** dei driver poker ma con vocabolario proprio. **Non è
giocabile** (mancano UI/audio/casinò): qui c'è solo l'orchestrazione.

- **`MachiavelliSessionDriver`** — gioca **una partita** a completamento (distribuisce
  il shoe da due mazzi, fa girare i turni in ordine, lascia ogni posto rimaneggiare il
  tavolo condiviso via il modello del turno del motore, finisce quando qualcuno svuota la
  mano; stallo → risolto al giocatore con meno carte / tetto turni configurabile per test).
  Cliente **puro** del motore: ogni piano validato dallo **stesso predicato**
  (`MachiavelliTurnContext`) del giocatore (un bot non può barare; piano malformato →
  pescata, D-013). **Seed casuale in produzione / iniettabile nei test** (D-047).
- **`MachiavelliSessionEvent`/`MachiavelliEventHub`** — flusso proprio (melds,
  ricomposizione, pescate, vittoria), **descrittivo non prescrittivo**, audience privata
  (mano distribuita + carta pescata solo al proprietario), riusa solo
  `EventAudience`/`EventViewer`. **Attesa udibile:** `botThinkingBegan`(con deliberazione
  attesa come *hint*)/`botThinkingEnded` attorno a ogni turno bot, così UI/audio futuri
  riempiono il silenzio dei bot che pensano.
- **`MachiavelliTurnProvider`** — facciata async uniforme bot/umano (D-013); lo scambio è
  un **piano di turno** (`MachiavelliTurnPlan`), non una singola azione, perché il turno è
  una sequenza di trasformazioni.
- **`MachiavelliMatchmaker`** — sistema di **incontri progressivi**: sceglie **1–2**
  avversari in base alle **partite giocate** (contatore, **mai** il tempo — D-064/D-070):
  primissime partite quasi solo lo **studente**, poi studente/adulto, poi insieme, più
  avanti il **professore**, fino a partite col **solo professore**. Deterministico dato
  seed. Il giocatore **incontra delle persone**, non un livello di difficoltà.
