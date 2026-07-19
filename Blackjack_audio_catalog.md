# Catalogo audio — Blackjack (D-090)

Stato: **nessun file prodotto.** Ogni slot qui elencato è **dichiarato e cablato**;
finché l'mp3 non è nel bundle il sistema degrada da solo secondo la regola di
categoria (D-030/D-066), e il gioco è **pienamente giocabile** così com'è.

I file vanno depositati in `Resources/Audio/` con **esattamente** il nome della
colonna *File*, estensione `.mp3`. Il gruppo `Resources` è sincronizzato: non
serve toccare il progetto Xcode.

---

## Perché il blackjack ha pochissima voce

È il gioco **veloce** della casa. Una mano è due carte e una decisione, e ogni
riga parlata è tempo che il giocatore passa ad aspettare invece che a giocare
(D-091). Il croupier qui **tace quasi sempre**: l'unica voce cablata è quella del
rimescolo, che capita all'incirca **una volta ogni sessanta mani** e spiega una
pausa reale.

Non ci sono **voci di NPC**: al tavolo il giocatore è solo contro il banco. La
presenza degli altri avventori è resa **solo** da effetti d'ambiente, e proprio
perché nessun personaggio parla, **un unico set serve tutti i casinò** — non
porta l'identità di un luogo, che continua ad arrivare dalla palette del casinò
(`CasinoAudio`, D-067).

---

## 1. Voce del croupier — informativa → fallback a SINTESI

Categoria `.croupier`. Se il file manca, il testo viene **sintetizzato** da
VoiceOver: è informazione di gioco e non può sparire (D-066).

| File | Casinò | Testo (italiano) | Carattere |
|---|---|---|---|
| `vo_it_bj_shuffle` | Riverwood (e default) | «Mazzo nuovo.» | Asciutto, di frontiera. Il croupier constata, non annuncia. |
| `vo_it_sky_bj_shuffle` | Skypool | «Carte nuove. Si ricomincia.» | Cittadino, un filo cinico, tecnico. Il registro dello Skypool (D-067). |

**Durata indicativa:** 1,0–1,8 s. Più lunghe di così pesano su un gioco rapido.

> Il ClockTower **non ospita il blackjack** e non ha quindi alcuno slot qui.

---

## 2. Presenza degli altri avventori — ambientale → fallback a SILENZIO

Categoria `.botVoice`. Se il file manca **non si sente nulla**, e va benissimo:
è colore, non informazione, e sintetizzarlo lo trasformerebbe in un annuncio
intrusivo sopra l'ascolto del giocatore cieco (D-066).

Vengono riprodotti **fra una mano e l'altra**, mai durante una decisione e mai
sopra un risultato, con probabilità ~28% e mai due volte di fila lo stesso.

| File | Carattere | Note di produzione |
|---|---|---|
| `fx_bj_presence_chips` | Un vicino di tavolo che impila o spinge fiches. | Secco, vicino ma non addosso; niente voce umana. |
| `fx_bj_presence_murmur` | Un mormorio basso del tavolo, una reazione trattenuta. | **Nessuna parola riconoscibile** — se si capisce una parola diventa informazione, e non lo è. |
| `fx_bj_presence_cards` | Carte sfregate o battute sul panno da un vicino. | Materico, breve. |

**Durata indicativa:** 0,8–2,0 s. **Livello:** sotto il letto ambientale, mai in
primo piano.

**Indicazione imposta:** questi tre suoni devono poter capitare **decine di volte
in una sessione** senza stancare. Vanno registrati con **variabilità interna**
(non un colpo identico ripetuto) e con **attacco e coda morbidi**, così non
tagliano mai un annuncio in corso.

---

## 3. Cosa il blackjack riusa senza chiedere nulla

Tutta la parte fisica viene dai suoni **neutri** già in casa, ed è il motivo per
cui il tavolo suona come il casinò che lo ospita senza un solo file nuovo:

| Momento | Suono riusato |
|---|---|
| Inizio sessione, rimescolo | `tbl_shuffle` |
| La puntata sul panno | `tbl_chips_single` |
| La distribuzione (due carte + la scoperta del banco, **un solo gesto**) | `tbl_cards_deal_flop` |
| Una carta chiesta | `tbl_card_deal_single` |
| Il banco gira la coperta | `tbl_card_flip_single` |
| Raddoppio | `tbl_chips_bet_large` + `tbl_card_deal_single` |
| Divisione | `tbl_chips_stack` + `tbl_cards_deal_flop` |
| Stare, ritirarsi | `tbl_muck` |
| Sballare | `fx_bust_player` |
| Mano vinta / persa / pari | `fx_win_hand` / `fx_lose_hand` / `fx_hand_neutral` |
| Fiches raccolte | `tbl_chips_pot_collect` |
| Letti ambientali | quelli del casinò ospitante (`CasinoAudio.ambient(forGame:)`) |

**Nota di sincronizzazione (D-085):** il colpo di vittoria/sconfitta **non** parte
in parallelo. È passato al `SpeechConductor` come `trailing:` e suona **alla fine
della riga che dice com'è andata**, così non anticipa mai il risultato. Se la riga
venisse scartata dal budget del canale, il colpo suona comunque.
