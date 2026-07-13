# Skypool Casinò — catalogo audio da produrre (M2 / D-066 / D-067)

Catalogo **rigenerato** contro l'architettura nuova (D-067): il **croupier è un
attributo del CASINÒ, non del gioco**. Lo Skypool ha **un solo croupier**, valido per
**tutti e tre i suoi tavoli** — Texas Classico, Texas Rapido e Omaha Pot Limit
"Marble" — e per qualunque gioco futuro. Non si divide per tavolo, si divide per
casinò. (Il catalogo M2.5 precedente era scritto contro l'architettura vecchia, dove il
croupier del Texas era condiviso col Riverwood: è **obsoleto**, questo lo sostituisce.)

Per ogni file: **nome esatto atteso dal codice**, **categoria** (informativa o
ambientale), **testo esatto** (voci), **contesto**, **fonte** (ElevenLabs / StableAudio)
e — per l'ambient — il **carattere sonoro**. Deposita in `Resources/Audio/` con
**esattamente** questi nomi (consegna `.mp3`). Finché mancano, il gioco funziona coi
fallback descritti (nessuna regressione).

## Stato di cablaggio reale (D-068 — aggiornato dopo la consegna dei file)
L'utente ha prodotto e depositato i file; sono stati cablati in `Resources/Audio/`.
**Legenda:** ✅ prodotto e cablato · ⬜ non ancora prodotto (attivo il fallback).
- **Croupier:** ✅ 12/14 (`blind_small`, `blind_big`, `role_button`, `your_turn`, `flop`,
  `turn`, `river`, `showdown`, `action_all_in`, `pot_awarded`, `split_pot`, `stakes_up`).
  ⬜ `vo_it_sky_hand_start` (stacco/chime → resta silenzioso), ⬜ `vo_it_sky_pot_limit`
  (riservato/non cablato).
- **Ambient:** ✅ 4/4 (`calm_01`, `calm_02`, `tense_01`, `water_01`).
- **Colore bot:** ✅ 6/7 (`novice_excited`, `novice_disappointed`, `novice_nervous`,
  `rock_grunt`, `aggressor_confident`, `aggressor_taunt`). ⬜
  `vob_sky_aggressor_bluff_giveaway_01` — **non cablato**: in Downloads c'era
  `vob_it_sky_aggressor_nervous.mp3`, che **probabilmente** è questa battuta (la
  descrizione è "risatina nervosa"), ma il nome non è **evidentemente** riconducibile
  allo slot, quindi **non l'ho indovinato**: resta fuori (slot silenzioso). Rinominalo in
  Downloads come `vob_sky_aggressor_bluff_giveaway_01` (o confermami la corrispondenza) e
  lo cablo.
- **Rinomine fatte** (dichiarate): `big_blind→blind_big`, `small_blind→blind_small`,
  `amb_skypool_tense→tense_01`, `amb_skypool_water→water_01`, e per **tutti** i colore-bot
  la rimozione dell'`it_` di troppo e la normalizzazione del suffisso `_01`
  (`vob_it_sky_*→vob_sky_*_01`).

## Identità sonora dello Skypool
Casinò **cittadino, moderno, freddo**: marmo, cemento, **acqua** (una piscina), vetro,
**discoteca** in lontananza. L'opposto del Riverwood (legno, whiskey, calore rustico).
Palette **urbana, ampia, riverberante, notturna** — riverbero di superfici dure, un
basso ovattato da club lontano, acqua che scorre.

## Le due categorie di voce (principio permanente, D-066)
- **Informativa** (croupier): stato di gioco che serve. mp3 mancante → **fallback a
  sintesi VoiceOver**. Fonte: **ElevenLabs**.
- **Ambientale** (colore dei bot): atmosfera, non informazione. mp3 mancante →
  **SILENZIO** (mai sintesi). Fonte: **ElevenLabs**.

---

## 1. Croupier dello Skypool — VOCI INFORMATIVE (ElevenLabs)
**Un'unica voce per tutti e tre i tavoli.** Registro **cittadino, cinico, tecnico, un
po' verboso** — un professionista che ha visto passare molti soldi e non si emoziona
(l'opposto del croupier di frontiera del Riverwood: asciutto, caldo, poche parole). I
termini poker restano **fonetici** come nel resto del progetto (reis, blaind, bàtton,
flop, tern, river, sciodaun, ol-in). Se manca l'mp3, la colonna "fallback" è la sintesi
che parla (il testo è **già cablato** nelle stringhe `skypool.croupier.*`).

| File | Testo esatto (registro Skypool) | Contesto | Categoria |
|---|---|---|---|
| `vo_it_sky_hand_start` | *(stacco breve, nessun testo)* | Inizio di ogni mano (tutti i giochi) | informativa (nessun fallback: silenzio) |
| `vo_it_sky_blind_small` | "Sei in smòl blaind. Metti la piccola e stai sul pezzo." | Il giocatore umano è di piccolo buio | informativa |
| `vo_it_sky_blind_big` | "Big blaind è tuo. Difendi, se ne vale la pena." | Il giocatore umano è di grande buio | informativa |
| `vo_it_sky_role_button` | "Bàtton in mano. Ultima parola, usala bene." | Il giocatore umano ha il bottone | informativa |
| `vo_it_sky_your_turn` | "Tocca a te. Il tavolo aspetta." | Tocca al giocatore umano | informativa |
| `vo_it_sky_flop` | "Flop sul tavolo. Leggi le carte." | Esce il flop (Texas/Omaha) | informativa |
| `vo_it_sky_turn` | "Tern. La faccenda si complica." | Esce il turn | informativa |
| `vo_it_sky_river` | "River. Ultima carta, niente più scuse." | Esce il river | informativa |
| `vo_it_sky_showdown` | "Sciodaun. Carte sul marmo." | Showdown (once-per-hand) | informativa |
| `vo_it_sky_action_all_in` | "Ol-in. Tutto quanto." | Un giocatore va all-in | informativa |
| `vo_it_sky_pot_awarded` | "Il piatto cambia proprietario." | Assegnazione del piatto (once-per-hand) | informativa |
| `vo_it_sky_split_pot` | "Piatto diviso. Nessuno esce contento." | Piatto spartito | informativa |
| `vo_it_sky_stakes_up` | "Le poste salgono. Chi resta, fa sul serio." | Escalation blind (Omaha) / mano decisiva (Texas Rapido) | informativa |
| `vo_it_sky_pot_limit` | *(riservato, opzionale — non ancora cablato)* | Promemoria tetto Pot Limit al turno umano | informativa |

> La sintesi che **completa** ogni cue (le carte concrete del flop, la mano allo
> showdown, chi vince il piatto, l'attribuzione delle azioni avversarie, le proprie
> quattro carte in Omaha) è **contenuto**, non registro: è casino-neutra e già gestita
> dalle SpeechMap. Le voci del croupier qui NON la ripetono.

---

## 2. Ambient dello Skypool — TRACCE AMBIENTALI (StableAudio)
Loop senza cuciture. Manca → fallback ai letti "lounge" esistenti (nessun silenzio brusco).

| File | Carattere sonoro | Contesto | Fallback |
|---|---|---|---|
| `amb_skypool_calm_01` | Letto **calmo urbano**: riverbero ampio di marmo/vetro, basso da club molto lontano e ovattato, lieve scorrere d'acqua. Freddo, notturno, elegante. | Tavolo in stato normale | `amb_lounge_calm_01` |
| `amb_skypool_calm_02` | Variante del calmo (alternata a inizio mano) — stessa palette, movimento diverso. | Alternanza a inizio mano | `amb_lounge_calm_02` |
| `amb_skypool_tense_01` | Versione **tesa**: il basso del club più presente, l'acqua si increspa, tensione trattenuta. Urbano, non drammatico-western. | All-in / poste aumentate / mano decisiva | `amb_lounge_tense_01` |
| `amb_skypool_water_01` | **Layer continuo** a volume basso: acqua della piscina / riverbero liquido, sempre sotto tutto. | Layer di fondo per l'intera sessione | `amb_crowd_distant` |

Riuso condiviso: l'hush dello showdown usa `amb_silence_tension` (già esistente).

---

## 3. Effetti dello Skypool (StableAudio)
Gli **effetti fisici** (carte, fiche, muck, mescolata: `tbl_*`) e gli **stinger** di
esito (win/lose/bust/all-in/vittoria/sconfitta: `fx_*`) sono **condivisi e neutri** e
non richiedono nuovi file per lo Skypool. **Nessun effetto nuovo da produrre.**

---

## 4. Commenti al tavolo dei bot urbani — VOCI AMBIENTALI (ElevenLabs)
Colore, **non** informazione. Fallback = **SILENZIO** (D-066). Parlata **cittadina**,
fredda e sicura, diversa dal tono di frontiera. Battute brevi (0.5–2 s), tono più che
testo. Valgono per i bot urbani su **tutti** i tavoli dello Skypool (Texas e Omaha).

### Il Ragazzo (novizio urbano)
| File | Testo suggerito | Quando |
|---|---|---|
| `vob_sky_novice_excited_01` | "Andiamo, questa è mia!" | Apre/rilancia; o vince la mano |
| `vob_sky_novice_disappointed_01` | "Ma dai, ci credevo…" | Perde la mano |
| `vob_sky_novice_nervous_01` | "Uh… quanto vuoi?" | Deve chiamare una grossa puntata |

### Il Professionista (rock urbano)
| File | Testo suggerito | Quando |
|---|---|---|
| `vob_sky_rock_grunt_01` | *(mugugno controllato)* "Hm." / "Vediamo." | Occasionale, su un'azione |

### Lo Squalo (aggressivo urbano)
| File | Testo suggerito | Quando |
|---|---|---|
| `vob_sky_aggressor_confident_01` | "Metto pressione." | Apre/rilancia |
| `vob_sky_aggressor_taunt_01` | "Hai il fegato?" | Apre/rilancia (variante provocatoria) |
| `vob_sky_aggressor_bluff_giveaway_01` | *(risatina nervosa)* "…tutto sotto controllo." | Tell di bluff (slot pronto) |

---

## 5. Fonetica dei nomi propri (APPROVATA all'ascolto, D-060)
Campioni in `~/Desktop/lumar-phonetics/skypool-marble/`.
- **Marble** = grafia piana **"Marble"** (cablata).
- **Skypool** = **"Skai pul"** (la label VoiceOver del casinò è "Skai pul Casinò").

---

## 6. Quadro unico — voci del RIVERWOOD ancora non prodotte (per completezza)
Non fanno parte dello Skypool, ma restano da produrre; elencate qui per avere un quadro
unico. Categoria informativa → fallback di sintesi già dichiarato.

| File | Contesto | Nota |
|---|---|---|
| `vo_it_role_button` | Ruolo bottone del giocatore (Riverwood) | fallback "sei sul bàtton" |
| `vo_it_high_stakes` | Mano decisiva Texas Rapido (Riverwood) | fallback "mano decisiva…" |
| `vo_it_ante` | Ante (Five-Card Draw) | fallback sintesi |
| `vo_it_draw_phase` | Fase di scambio (Draw) | fallback sintesi |
| `vo_it_pass_and_out` | Pass-and-out (Draw) | fallback sintesi |
| `vo_it_carried_pot` | Pot progressivo (Draw) | fallback sintesi |
| `vo_it_openers_disqualified` | Squalifica openers (Draw) | fallback sintesi |
| `vo_it_high_stakes_draw` | Mano decisiva Whiskey (Draw) | fallback "mano decisiva" |
| `amb_home_neutral`, `amb_riverwood_calm_01/02` | Ambient mondo/Riverwood | fallback lounge |
| `ui_navigation` | Blip di transizione schermata | fallback silenzio |
| `amb_crowd_distant`, `fx_hand_neutral` | Storici mai consegnati | fallback silenzio |

---

### Riepilogo file da produrre per lo Skypool
- **14 voci croupier** (`vo_it_sky_*`, ElevenLabs; 1 opzionale `pot_limit`).
- **4 tracce ambient** (`amb_skypool_*`, StableAudio).
- **7 voci di colore dei bot** (`vob_sky_*`, ElevenLabs; ambientali → silenzio se mancano).
- **0 effetti nuovi** (riuso dei condivisi).
