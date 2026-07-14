# ClockTower — catalogo VOCI da produrre (D-072, ElevenLabs)

**Questo è il SECONDO dei due cataloghi del ClockTower**, consegnato a UI finita: ora so
esattamente **quali voci servono**. Il primo (ambient/musica, StableAudio) è
`ClockTower_audio_catalog_ambient.md`. Queste voci vanno su **ElevenLabs**.

Per ogni file: **nome esatto atteso dal codice**, **categoria** (informativa/ambientale),
**testo esatto** (per le voci del "narratore") o **carattere** (per il colore dei bot), e il
**contesto**. Deposita i `.mp3` in `Resources/Audio/` con **esattamente** questi nomi. Finché
mancano, il gioco funziona coi **fallback** (informative → sintesi VoiceOver del testo qui
sotto; ambientali → **silenzio**): il tavolo è già giocabile, queste voci gli danno la voce vera.

---

## ⚠️ PRIMA DI PRODURRE: il PERSONAGGIO è da decidere (tuo)
Nel poker parla un **croupier** (annuncia flop, turn, river, il piatto). Nel Machiavelli **non
c'è niente di tutto questo**: niente piatto, niente puntate, niente showdown. La figura che parla
al ClockTower ha un **compito diverso** — **scandire i turni, dichiarare le combinazioni calate,
annunciare i punteggi di fine mano** — e quindi **probabilmente non è un croupier ma qualcun
altro**: un **maestro di gioco**, un **arbitro erudito**, il **custode della torre**, un
**anziano professore che presiede**… **decidi tu il personaggio e il genere.** Ho fissato solo
il **registro**: erudito, misurato, colto, mai concitato — coerente con la torre antica,
l'università, il silenzio, gli orologi. I **testi** qui sotto sono scritti in quel registro; puoi
rifinirli quando avrai scelto la persona (mantenendo il senso). **Non produrre le voci prima di
aver deciso il personaggio.**

## Le due categorie di voce (principio permanente, D-066)
- **Informativa** (il narratore): stato di gioco che serve. mp3 mancante → **fallback a sintesi
  VoiceOver** del testo indicato.
- **Ambientale** (colore dei bot): atmosfera, non informazione. mp3 mancante → **SILENZIO**
  (mai sintesi).

---

## 1. La voce del ClockTower — INFORMATIVA (una sola voce, il narratore)
Registro **erudito, misurato, colto**. Frasi brevi: sono **stacchi** prima che la sintesi
VoiceOver dia il contenuto specifico (la combinazione, il punteggio), quindi devono essere
**generiche e sobrie**, non ridondanti. (Nota tecnica: per gli eventi con contenuto specifico —
combinazione calata, punteggi — l'mp3 è un breve **stacco** e la **sintesi** dice il dettaglio;
per gli eventi generici — inizio mano, il tuo turno — l'mp3 **è** la battuta, col testo qui sotto
come fallback di sintesi.)

| # | Nome file (esatto) | Testo (registro erudito) | Contesto |
|---|---|---|---|
| 1 | `vo_it_clock_hand_start.mp3` | "Nuova mano." | Inizio di ogni mano, dopo la distribuzione. |
| 2 | `vo_it_clock_your_turn.mp3` | "Tocca a te." | Quando comincia il turno del giocatore umano. |
| 3 | `vo_it_clock_meld.mp3` | "Combinazione." | Stacco quando un avversario cala una o più combinazioni (la sintesi dice quali). |
| 4 | `vo_it_clock_drew.mp3` | "Pesca." | Stacco quando un avversario pesca (la sintesi dice chi). |
| 5 | `vo_it_clock_passed.mp3` | "Passa." | (Riservato) quando un giocatore passa senza calare. |
| 6 | `vo_it_clock_hand_end.mp3` | "Fine mano." | Stacco a fine mano (la sintesi elenca i punteggi). |
| 7 | `vo_it_clock_match_end.mp3` | "Partita conclusa." | Stacco a fine partita (la sintesi dice chi ha vinto). |

**Nota:** i testi 1, 2 sono anche il **fallback di sintesi** finché l'mp3 manca (sono l'intera
battuta). I testi 3, 4, 6, 7 sono **stacchi**: la sintesi che segue porta il contenuto specifico
(combinazione/punteggi/vincitore), quindi finché l'mp3 manca **non** si sente lo stacco, solo la
sintesi specifica — nessuna ridondanza (evita l'anti-pattern D-051).

## 2. Colore dei bot — AMBIENTALE (i tre archetipi del ClockTower)
Commenti di **colore** dei tre giocatori, coerenti col posto: anziani, espertissimi, si gioca per
**vanto**. **Non parole** necessariamente — versi, mugugni, brevi esclamazioni misurate. mp3
mancante → **silenzio** (mai sintesi). Uno per archetipo per "cala/rimaneggia" (act) e uno per
"soddisfazione/vittoria" (pleased).

| Nome file (esatto) | Archetipo | Carattere sonoro |
|---|---|---|
| `vob_clock_student_eager_01.mp3` | **Studente** (giovane, avido, cala in fretta) | Un'esclamazione **giovane ed entusiasta** ma sommessa, colta — "Ecco!" trattenuto. |
| `vob_clock_student_pleased_01.mp3` | Studente | Soddisfazione **ingenua e fresca** quando chiude o segna. |
| `vob_clock_adult_ponders_01.mp3` | **Bibliotecario** (adulto, paziente, metodico) | Un **mugugno riflessivo**, misurato, di chi valuta a lungo — "Hmm…" pacato. |
| `vob_clock_adult_pleased_01.mp3` | Bibliotecario | Compiacimento **contenuto, professionale**, senza enfasi. |
| `vob_clock_professor_masterstroke_01.mp3` | **Professore** (anziano maestro, smonta e ricompone il tavolo) | Un suono di **maestria compiaciuta** quando rimaneggia il tavolo altrui — un "Ah." erudito, quasi divertito. |
| `vob_clock_professor_pleased_01.mp3` | Professore | Soddisfazione **sorniona e magistrale** alla vittoria — mai sguaiata. |

---

## Riepilogo di cablaggio
- **Informative (narratore):** 7 slot `vo_it_clock_*` (categoria `.croupier` nel codice →
  fallback a sintesi). Voce **unica**, personaggio **da decidere**.
- **Ambientali (colore bot):** 6 slot `vob_clock_*` (categoria `.botVoice` → fallback silenzio).
- **Ambient/musica:** nel **primo** catalogo (StableAudio), 4 tracce `amb_clocktower_*`.

Tutti attivi coi fallback finché non consegni: il ClockTower è **giocabile ora**. Deposita i file
in `Resources/Audio/` (gruppo sincronizzato → auto-bundled), coi nomi esatti sopra.
