# Skypool Casinò — catalogo audio da produrre (M2 / D-066)

Questo file elenca **tutti** i suoni dello Skypool Casinò da produrre. È
autosufficiente: per ogni file trovi il **nome esatto atteso dal codice**, la
**categoria** (informativa o ambientale), il **testo esatto** (per le voci), il
**contesto** in cui viene riprodotto, la **fonte prevista** e — per le tracce
ambientali — una **descrizione del carattere sonoro** coerente con l'identità del
posto.

I file vanno depositati in `Resources/Audio/` con **esattamente** questi nomi (senza
estensione nel codice; consegnare in `.mp3`). Finché non ci sono, il gioco funziona
con i fallback descritti sotto (nessuna regressione).

## Identità sonora dello Skypool
Casinò **cittadino, moderno, freddo**: marmo, cemento, **acqua** (una piscina), vetro,
una **discoteca** in lontananza. L'opposto del Riverwood (legno, whiskey, calore
rustico). La palette deve suonare **urbana, ampia, riverberante, un filo notturna** —
riverbero di superfici dure, un basso ovattato da club lontano, acqua che scorre.
Voce del croupier: **cittadina, controllata, professionale, un po' distaccata** — non
la calorosa voce di frontiera del Riverwood.

## Le due categorie di voce (principio permanente, D-066)
- **Informativa** (croupier): comunica **stato di gioco** che serve al giocatore. Se
  l'mp3 manca, **fallback a sintesi VoiceOver**. Fonte: **ElevenLabs**.
- **Ambientale** (commenti di colore dei bot): **atmosfera**, non informazione. Se
  l'mp3 manca, **fallback al SILENZIO** (mai sintesi). Fonte: **ElevenLabs**.

---

## 1. Croupier dello Skypool — VOCI INFORMATIVE (ElevenLabs)
Voce italiana, cittadina/fredda. Termini poker resi **foneticamente** come nel resto
del progetto (reis, blaind, bàtton, flop, tern, river, sciodaun, ol-in). Se manca →
sintesi VoiceOver (fallback indicato).

| File | Testo esatto | Contesto | Fallback sintesi |
|---|---|---|---|
| `vo_it_sky_hand_start` | *(stacco breve / "Nuova mano.")* | Inizio di ogni mano | — (silenzioso finché non prodotto) |
| `vo_it_sky_blind_small` | "Sei in smòl blaind." | Il giocatore umano è di piccolo buio | "sei in smòl blaind" |
| `vo_it_sky_blind_big` | "Sei in big blaind." | Il giocatore umano è di grande buio | "sei in big blaind" |
| `vo_it_sky_role_button` | "Sei sul bàtton." | Il giocatore umano ha il bottone | "sei sul bàtton" |
| `vo_it_sky_your_turn` | "È il tuo turno." | Tocca al giocatore umano | "è il tuo turno" |
| `vo_it_sky_flop` | "Flop." | Escono le tre carte del flop | "flop" |
| `vo_it_sky_turn` | "Tern." | Esce la carta del turn | "tern" |
| `vo_it_sky_river` | "River." | Esce la carta del river | "river" |
| `vo_it_sky_showdown` | "Sciodaun." | Showdown | *(dedup once-per-hand; nessun fallback testuale)* |
| `vo_it_sky_action_all_in` | "Ol-in!" | Un giocatore va all-in | *(la sintesi attribuisce il seat)* |
| `vo_it_sky_pot_awarded` | "Il piatto va al vincitore." | Assegnazione del piatto | *(la sintesi dice chi vince e con che mano)* |
| `vo_it_sky_split_pot` | "Piatto diviso." | Piatto spartito (pareggio) | *(idem, sintesi)* |
| `vo_it_sky_stakes_up` | "Le poste salgono." | Escalation delle blind (D-064) | "le poste salgono a N e M" |
| `vo_it_sky_pot_limit` | "Pot limit: puoi puntare al massimo il piatto." | *(opzionale)* promemoria del tetto al turno umano | *(non ancora cablato; slot pronto)* |

> Nota: showdown / pot / split sono **once-per-hand** (D-051): il croupier li dice
> una sola volta anche se l'evento arriva più volte (side pot).

---

## 2. Ambient dello Skypool — TRACCE AMBIENTALI (StableAudio)
Loop senza cuciture. Se mancano → fallback ai letti "lounge" esistenti (nessun
silenzio brusco).

| File | Carattere sonoro | Contesto | Fallback |
|---|---|---|---|
| `amb_skypool_calm_01` | Letto **calmo urbano**: riverbero ampio di marmo/vetro, un basso da club molto lontano e ovattato, un lieve scorrere d'acqua. Freddo, notturno, elegante, non invadente. | Lobby e tavolo in stato normale | `amb_lounge_calm_02` |
| `amb_skypool_calm_02` | Variante del calmo (per crossfade a inizio mano) — stessa palette, movimento leggermente diverso. | Alternanza a inizio mano | `amb_lounge_calm_02` |
| `amb_skypool_tense_01` | Versione **tesa**: il basso del club si fa più presente, l'acqua si increspa, tensione trattenuta. Urbano, non drammatico-western. | All-in in gioco / mano con poste aumentate | `amb_lounge_tense_01` |
| `amb_skypool_water_01` | **Layer continuo** a basso volume: acqua della piscina / riverbero liquido. Va sotto tutto, sempre. | Layer di fondo per tutta la sessione | `amb_crowd_distant` (o silenzio) |

Riuso: l'hush dello showdown usa `amb_silence_tension` (già esistente, condiviso).

---

## 3. Effetti dello Skypool (StableAudio)
Gli **effetti fisici** (carte, fiche, muck, mescolata) e gli **stinger** di esito
(win/lose/bust/all-in/vittoria/sconfitta finale) sono **condivisi e neutri** e non
richiedono nuovi file per lo Skypool: il tavolo Omaha riusa `tbl_*` e `fx_*` esistenti.
Se in futuro si vorrà un colore percussivo più urbano, si potranno aggiungere slot
dedicati; **per ora nessun effetto nuovo da produrre**.

---

## 4. Commenti al tavolo dei bot urbani — VOCI AMBIENTALI (ElevenLabs)
Colore, **non** informazione. Fallback = **SILENZIO** (D-066): se mancano, semplicemente
non si sentono. Sono legati al **casinò**, non solo all'archetipo: parlata **cittadina**,
fredda e sicura, diversa dal tono di frontiera del Riverwood. Battute brevi (0.5–2 s),
tono più che testo. Testi **suggeriti** (adattabili):

### Il Ragazzo (novizio urbano) — giovane di città, poco oculato
| File | Testo suggerito | Quando |
|---|---|---|
| `vob_sky_novice_excited_01` | "Andiamo, questa è mia!" | Apre/rilancia; o vince la mano |
| `vob_sky_novice_disappointed_01` | "Ma dai, ci credevo…" | Perde la mano |
| `vob_sky_novice_nervous_01` | "Uh… quanto vuoi?" | Deve chiamare una grossa puntata |

### Il Professionista (rock urbano) — freddo, professionale, con un filo d'affabilità
| File | Testo suggerito | Quando |
|---|---|---|
| `vob_sky_rock_grunt_01` | *(mugugno controllato)* "Hm." / "Vediamo." | Occasionale, su un'azione |

### Lo Squalo (aggressivo urbano) — rischia, sicuro, denaro dietro
| File | Testo suggerito | Quando |
|---|---|---|
| `vob_sky_aggressor_confident_01` | "Metto pressione." | Apre/rilancia |
| `vob_sky_aggressor_taunt_01` | "Hai il fegato?" | Apre/rilancia (variante provocatoria) |
| `vob_sky_aggressor_bluff_giveaway_01` | *(risatina nervosa)* "…tutto sotto controllo." | Tell di bluff (slot pronto, non ancora cablato) |

---

## 5. Fonetica dei nomi propri (APPROVATA all'ascolto, D-060)
`Skypool` e `Marble` finiscono nelle label accessibili lette da Alice it-IT. Campioni in
`~/Desktop/lumar-phonetics/skypool-marble/`. **Esito ascolto dell'utente:**
- **Marble** = grafia piana **"Marble"** (approvata, cablata).
- **Skypool** = **"Skai pul"** (la grafia piana "Skypool" leggeva male): label VoiceOver del
  casinò "Skai pul Casinò", ritorno "Torna allo Skai pul". Il nome **visibile** resta "Skypool
  Casinò". Àncora in `PhoneticsTests.testEarVerifiedCasinoNameRenderings`.

---

### Riepilogo file da produrre
- **14 voci croupier** (`vo_it_sky_*`, ElevenLabs, 1 opzionale).
- **4 tracce ambient** (`amb_skypool_*`, StableAudio).
- **7 voci di colore dei bot** (`vob_sky_*`, ElevenLabs, ambientali → silenzio se mancano).
- **0 effetti nuovi** (riuso dei condivisi).
