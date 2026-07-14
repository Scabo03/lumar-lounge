# ClockTower — catalogo VOCI da produrre (D-072/D-073, ElevenLabs)

**Secondo dei due cataloghi del ClockTower**, a UI finita. Il primo (ambient/musica,
StableAudio) è `ClockTower_audio_catalog_ambient.md`. Queste voci vanno su **ElevenLabs**.

---

## Il PERSONAGGIO (deciso, D-073)
La voce del ClockTower è **un uomo ANZIANO**, **una sola figura** per tutto il casinò: fa da
**croupier** ai (futuri) tavoli di poker e da **arbitro / maestro di gioco** al Machiavelli. **Non
due personaggi**: lo **stesso uomo**, con due insiemi di battute cablate su eventi diversi. È un
**custode della sala**, una **figura di casa** — non un professionista assunto: anziano, erudito,
misurato, un po' cerimonioso, che conosce il gioco da una vita.

Completa la **terna** che il giocatore non vedente riconosce in due secondi:
- **Riverwood** — voce **maschile di frontiera** (asciutta, calda).
- **Skypool** — voce **femminile e cinica** (urbana, fredda).
- **ClockTower** — voce **maschile anziana ed erudita** (colta, misurata).

## La LINGUA (regola rigorosa, D-073)
I testi del ClockTower **privilegiano l'ITALIANO** ed **evitano gli anglicismi ove possibile**.
Un professore anziano in una torre accademica dice **rilancio**, non *raise*; **piatto**, non
*pot*; **pesca dal tallone**, non *draw*. **Producili con un modello espressivo che rende bene in
italiano puro:** questo risolve alla radice il problema di pronuncia dei termini inglesi (il caso
*Raise*, tre sessioni), che esiste **solo** perché una voce italiana deve leggere parole inglesi.

### ⚠️ Confine da NON superare
Questa scelta riguarda **solo i testi parlati** del custode. **NON** tocca i **pulsanti d'azione**,
che restano **Raise / Fold / Call** in inglese (vocabolario del giocatore, resa fonetica validata e
cablata in D-060). Al ClockTower la **voce dice "rilancio"** mentre il **pulsante dice "Raise"**: non
è incoerenza, è la **stessa doppia lingua** che il progetto ha già (la narrazione dice "giocatore
due rilancia", il pulsante dice "Raise"). **Non uniformare.**

## Le due categorie di voce (principio permanente, D-066)
- **Informativa** (il custode): stato di gioco che serve. mp3 mancante → **fallback a sintesi
  VoiceOver** del testo indicato.
- **Ambientale** (colore dei bot): atmosfera, non informazione. mp3 mancante → **SILENZIO**.

---

## 1. Il custode al MACHIAVELLI — INFORMATIVA (cablata e ATTIVA ora)
Registro **erudito, misurato, colto, italiano**. Frasi brevi: per gli eventi con contenuto
specifico (combinazione, punteggi) l'mp3 è un breve **stacco** e la **sintesi** dice il dettaglio;
per gli eventi generici (inizio mano, il tuo turno) l'mp3 **è** la battuta (col testo come fallback).

| # | Nome file (esatto) | Testo (italiano erudito) | Contesto |
|---|---|---|---|
| 1 | `vo_it_clock_hand_start.mp3` | "Una nuova mano." | Inizio di ogni mano, dopo la distribuzione. |
| 2 | `vo_it_clock_your_turn.mp3` | "A te la mossa." | Comincia il turno del giocatore umano. |
| 3 | `vo_it_clock_meld.mp3` | "Una combinazione." | Stacco quando un avversario cala (la sintesi dice quali combinazioni). |
| 4 | `vo_it_clock_drew.mp3` | "Pesca." | Stacco quando un avversario pesca dal tallone (la sintesi dice chi). |
| 5 | `vo_it_clock_passed.mp3` | "Passa." | (Riservato) un giocatore passa senza calare. |
| 6 | `vo_it_clock_hand_end.mp3` | "La mano si conclude." | Stacco a fine mano (la sintesi elenca i punteggi). |
| 7 | `vo_it_clock_match_end.mp3` | "La partita è conclusa." | Stacco a fine partita (la sintesi dice chi ha vinto). |

**Sintesi di contenuto (già in italiano nel codice, fallback finché mancano gli mp3):** "Hai in
mano N carte."; "il Professore cala tris di assi."; "il Bibliotecario rimaneggia il tavolo e cala
scala di picche dal cinque al dieci."; "lo Studente pesca dal tallone."; "Fine mano. Tu 24 punti,
il Professore 15 punti."; "Hai vinto la partita." I **nomi** dei tre avversari sono **lo Studente**,
**il Bibliotecario**, **il Professore** (persone della torre, non numeri).

## 2. Il custode al SEVEN-CARD STUD del ClockTower — INFORMATIVA (cablata e ATTIVA ora, D-077/D-078)
Il primo tavolo di poker del ClockTower **esiste**: il **Seven-Card Stud Pot Limit** (D-077). Lo fa
lo **stesso uomo anziano custode**, ora nel ruolo di **croupier**, con le battute **in italiano
erudito** (niente anglicismi nel parlato — "rilancio", non *raise*; **i pulsanti** restano
Raise/Fold/Call, D-073). Ogni voce è **informativa** → **fallback a sintesi VoiceOver** (dichiarata in
`StudSpeechMap`) finché l'mp3 non è prodotto. **Nomi-file esatti, cablati** (deposita i `.mp3` in
`Resources/Audio/` con questi nomi):

| # | Nome file (esatto) | Testo (italiano erudito) | Contesto |
|---|---|---|---|
| 1 | `vo_it_clock_poker_hand_start.mp3` | "Nuova mano, signori." | Inizio di ogni mano. |
| 2 | `vo_it_clock_poker_your_turn.mp3` | "A te la parola." | Comincia il turno del giocatore umano. |
| 3 | `vo_it_clock_poker_fourth.mp3` | "Quarta strada." | Apertura della quarta strada. |
| 4 | `vo_it_clock_poker_fifth.mp3` | "Quinta strada." | Apertura della quinta strada. |
| 5 | `vo_it_clock_poker_sixth.mp3` | "Sesta strada." | Apertura della sesta strada. |
| 6 | `vo_it_clock_poker_seventh.mp3` | "Ultima carta, coperta." | Apertura della settima (l'ultima, coperta). |
| 7 | `vo_it_clock_poker_showdown.mp3` | "Si mostrano le carte." | Showdown. |
| 8 | `vo_it_clock_poker_pot.mp3` | "Il piatto va al vincitore." | Assegnazione del piatto. |
| 9 | `vo_it_clock_poker_all_in.mp3` | "Il resto sul tavolo." | Un giocatore va all'incontro (all-in). |
| 10 | `vo_it_clock_poker_house_prize.mp3` | "La Casa premia il vincitore." | **Premio della Casa** (D-078): distintivo di questo tavolo — la Casa aggiunge un premio al piatto vinto dal giocatore. |

**Sintesi di contenuto (già in italiano nel codice, fallback finché mancano gli mp3):** le carte
scoperte di ciascuno (**"il Professore riceve il re di cuori scoperta."**), le proprie coperte, le
azioni degli avversari (**"lo Studente rilancia a 200."** / "passa" / "chiama" / "punta tutto"),
l'obbligata (bring-in: **"lo Studente apre con l'obbligata di 25."**), lo showdown (mano + kicker), il
premio (**"La Casa aggiunge 200 fiche al tuo piatto."**). I **nomi** dei due avversari sono **lo
Studente** e **il Professore** (gli stessi regolari della torre).

*(Nota: **niente carte comuni** nello Stud — ogni giocatore ha le proprie scoperte, annunciate a una a
una man mano che arrivano, e interrogabili a comando dai badge degli avversari. Il custode parla
**italiano**; i **pulsanti** restano Raise/Fold/Call.)*

## 3. Colore dei bot al Machiavelli — AMBIENTALE (i tre archetipi del ClockTower)
Commenti di **colore** (versi/mugugni/brevi esclamazioni misurate), coerenti col posto. mp3
mancante → **silenzio** (mai sintesi).

| Nome file (esatto) | Archetipo | Carattere sonoro |
|---|---|---|
| `vob_clock_student_eager_01.mp3` | **lo Studente** (giovane, avido, cala in fretta) | Esclamazione **giovane, entusiasta ma sommessa**, colta — un "Ecco!" trattenuto. |
| `vob_clock_student_pleased_01.mp3` | lo Studente | Soddisfazione **ingenua e fresca** quando chiude o segna. |
| `vob_clock_adult_ponders_01.mp3` | **il Bibliotecario** (adulto, paziente, metodico) | **Mugugno riflessivo**, misurato — "Hmm…" pacato di chi valuta a lungo. |
| `vob_clock_adult_pleased_01.mp3` | il Bibliotecario | Compiacimento **contenuto, professionale**. |
| `vob_clock_professor_masterstroke_01.mp3` | **il Professore** (anziano maestro, smonta e ricompone il tavolo) | **Maestria compiaciuta** quando rimaneggia il tavolo altrui — un "Ah." erudito, quasi divertito. |
| `vob_clock_professor_pleased_01.mp3` | il Professore | Soddisfazione **sorniona e magistrale** alla vittoria — mai sguaiata. |

---

## Riepilogo
- **Custode Machiavelli (informativo, ATTIVO):** 7 slot `vo_it_clock_*` → fallback a sintesi.
- **Custode poker / Seven-Card Stud (informativo, ATTIVO, D-077):** 10 slot `vo_it_clock_poker_*` →
  fallback a sintesi (incluso il cue distintivo del **premio della Casa**).
- **Colore bot Machiavelli (ambientale):** 6 slot `vob_clock_*` → fallback silenzio. (I due bot dello
  Stud — Studente e Professore — riusano il colore Machiavelli `vob_clock_student_*`/`vob_clock_professor_*`.)
- **Voce unica:** lo stesso uomo anziano per **tutti** i ruoli (arbitro Machiavelli + croupier Stud).
  Registralo **una volta** per tutto.

Deposita i `.mp3` in `Resources/Audio/` coi nomi esatti. Finché mancano, il Machiavelli è
**giocabile** coi fallback (sintesi italiana del custode; silenzio per il colore).
