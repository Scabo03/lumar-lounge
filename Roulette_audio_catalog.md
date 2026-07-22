# Catalogo audio — Roulette (D-102 → D-104)

Stato: **file reali PRODOTTI e CABLATI** (D-104), con due eccezioni dichiarate:

- **`fx_roulette_win` non è stato prodotto** → il colpo di vincita cade sul generico
  `fx_win_hand` (preferito→fallback, così una vincita non è mai più silenziosa di una
  perdita). Se il file verrà prodotto, il test di cablaggio fallirà apposta per far
  rivedere il fallback in `RouletteTableViewModel.sting(for:)`.
- **Le voci del croupier sono state RIMOSSE** (decisione dell'utente, D-104): niente
  croupier alla Roulette per ora — né mp3 né fallback di sintesi. Gli slot
  `vo_*_roulette_rien_ne_va_plus` non esistono più nel `SoundCatalog`; l'attesa della
  ruota è riempita dal suono vero della ruota. Se un giorno le voci verranno prodotte,
  il cue si ri-aggiunge come dati (slot + `conductor.say` al `roundBegan`).

La palette resta un attributo del **casinò** (D-067). Il ClockTower **non** riceve la
Roulette.

---

## 1. Effetti del tavolo (tutti cablati salvo `win`)

Condivisi tra i casinò (come per il Blackjack): non ci sono NPC che parlano, solo la
meccanica della ruota e la presenza degli altri avventori. I file sono stati consegnati
in Downloads col prefisso `sfx_roulette_*` e importati in `Resources/Audio/` rinominati
alla forma del catalogo (D-025).

| File | Stato | Note |
|---|---|---|
| `fx_roulette_wheel_spin` | ✅ cablato (6,0 s) | **Governa l'attesa della ruota**: `audio.duration(of:) ?? spinFloor`. |
| `fx_roulette_ball` | ✅ cablato (5,6 s) | Parte sulla coda della ruota, calcolato per **finire con l'attesa**: la pallina si posa subito prima della riga d'esito (l'ordine porta informazione, D-085). |
| `fx_roulette_win` | ❌ NON prodotto | Fallback al generico `fx_win_hand` (vedi sopra). |
| `fx_roulette_lose` | ✅ cablato | Sequenziato **dopo** la riga d'esito (`say(trailing:)`, D-085). |
| `fx_roulette_chip_place` | ✅ cablato | Consegnato come `sfx_roulette_chips_place` → rinominato (singolare da catalogo). |
| `fx_roulette_chip_remove` | ✅ cablato | Consegnato come `sfx_roulette_chips_remove` → rinominato. |
| `fx_roulette_presence_murmur` | ✅ cablato (21 s) | Consegnato come `sfx_roulette_presence` → rinominato. Suona **tra i giri** (a `roundEnded`, mai durante una decisione né sopra un esito) via `TablePresence` (pattern Blackjack D-090, ~28%, mai due volte di fila lo stesso). |
| `fx_roulette_presence_chips` | ✅ cablato (21 s) | Idem, stesso repertorio di presenza. |

## 2. Voci del croupier — RIMOSSE (D-104)

Sezione svuotata: l'utente ha deciso di **non implementare** il croupier della Roulette
per ora. I due slot che questa sezione dichiarava (`vo_it_roulette_rien_ne_va_plus`,
`vo_it_sky_roulette_rien_ne_va_plus`) e il loro fallback di sintesi («Non si accettano
più puntate», chiave `roulette.no.more.bets`) sono stati **tolti dal codice e dalle
stringhe**. Il **numero uscito**, il **colore**, **quali puntate hanno pagato** e la
**restituzione sullo zero** restano **sintesi** del contenuto (autorità:
`RouletteSpeechMap`) — non erano voci del croupier e non sono toccati.

## 3. Set di fiches del casinò (D-104, trasversale a tutti i giochi)

Non è Roulette-specifico ma è arrivato con questa consegna: quattro suoni generici di
fiches mosse, **in pool** coi due storici (`tbl_chips_single`, `tbl_chips_stack`).

| File | Stato |
|---|---|
| `sfx_chips_shifted_01…04` | ✅ cablati (1,7 s l'uno, nomi dell'utente mantenuti) |

Meccanica (`TableChipSet`, UI): **ogni sessione** — Texas, Draw, Omaha, Stud, Blackjack —
sceglie **1–2 suoni dal pool** e li tiene per tutta la sessione (ruolo *light* = il
movimento leggero, ex `tbl_chips_single`; ruolo *heavy* = puntate/rilanci, ex
`tbl_chips_stack`; a due scelte il più «leggero» per ordine di pool prende il ruolo
light); **la sessione successiva ne sceglie altri** (i precedenti sono esclusi) → si
sente che il casinò dispone di più set di fiches. I momenti **semantici** non sono
sostituiti: `tbl_chips_bet_large` (all-in) e `tbl_chips_pot_collect` (piatto raccolto)
restano fissi. La Roulette non partecipa al pool: le sue fiches hanno i due suoni
dedicati place/remove appena prodotti (feedback UI, non movimento al tavolo).

## 4. Termini con pronuncia da verificare (D-060) — invariato

Le parole **italiane** sono cablate direttamente (corrette per costruzione): `rosso`,
`nero`, `pari`, `dispari`, `pieno`, `cavallo`, `terzina`, `quartina`, `sestina`,
`dozzina`, `colonna`. I **due termini francesi** delle metà restano **da ascoltare**:

| Termine | Uso | Campioni generati |
|---|---|---|
| **manque** (1–18) | nome della metà bassa | `manque_01_french`, `manque_02_grapheme_mank`, `manque_03_grapheme_manche`, `manque_04_italian_bassi` |
| **passe** (19–36) | nome della metà alta | `passe_01_french`, `passe_02_grapheme_pass`, `passe_03_grapheme_passe_accent`, `passe_04_italian_alti` |

Cablati **provvisoriamente** come `manque`/`passe` (grafia piana) nelle stringhe; il
guardiano `PhoneticsTests` li marca **NON verificati** finché l'utente non approva un
campione (metodo D-060). Campioni in `~/Desktop/lumar-phonetics/roulette/`.
