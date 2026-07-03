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
