# ClockTower — catalogo AMBIENT & MUSICA (D-072, StableAudio)

> ## ✅ STATO REALE (D-080): tutte e 7 le tracce PRODOTTE e CABLATE.
> `amb_clocktower_calm_01/02`, `amb_clocktower_thinking_01` (poker: archi), `amb_clocktower_machiavelli_01/02`,
> `amb_clocktower_machiavelli_thinking_01` (clockwork), `amb_clocktower_clock_01` (orologio) sono in
> `Resources/Audio/` e attivi. *(Il file consegnato `…_machiavelli_thinking` senza `_01` è stato rinominato
> `…_machiavelli_thinking_01`.)* **Comportamento di riproduzione (D-080):** missaggio per-tavolo — poker a
> **0.80** (~−20% degli altri casinò), Machiavelli a **0.65** (~−35%); rotazione che **favorisce calm_02**;
> l'**orologio è DOSATO** (presenza occasionale ~4–12 s con pause ~30–70 s, **non** un letto continuo).
> Il ClockTower **suona con la sua vera aria vasta.**



**Questo è il PRIMO dei due cataloghi del ClockTower.** Contiene **solo** le tracce
**ambientali e musicali** — quelle che **non dipendono dalla UI** e che puoi cominciare a
produrre **subito** su **StableAudio**, in parallelo alla sessione di codice. Il **secondo
catalogo** (le **voci**, ElevenLabs) arriva a lavoro finito, quando saprò esattamente quali
voci servono davvero.

Per ogni traccia: **nome esatto atteso dal codice**, **contesto** (quando viene riprodotta) e
**carattere sonoro**. Deposita i file `.mp3` in `Resources/Audio/` con **esattamente** questi
nomi. Finché mancano, il gioco funziona con i **fallback** indicati (nessuna regressione): le
tracce del ClockTower cadono su un letto lounge esistente, quindi il tavolo è già giocabile —
questi file gli danno la sua **vera aria**.

---

## Identità sonora del ClockTower
Un casinò **piccolo, esclusivo, accademico**, ospitato in una **torre antica** legata
all'università. **Intellettuale, erudito, raffinato.** Pietra antica, legno nobile, **libri**,
**silenzio**, **orologi**. I giocatori sono anziani ed espertissimi; si gioca per **vanto**, non
per denaro.

**Il tratto sonoro distintivo del ClockTower è l'AMPIEZZA.** Riverwood è **caldo**, Skypool è
**freddo**, ClockTower è **vasto**: architettonico, di grandi distanze, quasi un **osservatorio**
o un **luogo ingegneristico**. Per un cieco l'ampiezza si **sente davvero**, attraverso il
**riverbero** e le **distanze**; per un vedente resta uno sfondo. Rendi lo spazio grande in tutte
le tracce (riverbero lungo, code, senso di volume d'aria).

## ⚠️ NOVITÀ ARCHITETTURALE: due letti distinti, per GIOCO (D-073)
Il ClockTower ha **due declinazioni** dell'ambiente, perché il **carico cognitivo** dei suoi
giochi è opposto, e il giocatore cieco gioca **sul canale audio**:

- **Tavoli di POKER** (futuri, non ancora costruiti): **archi, classica raffinata**, con
  **struttura, sviluppo tematico, variazione**. Il poker è fatto di **attese e decisioni brevi**:
  una musica che si sviluppa **riempie** quelle attese e non compete con nulla.
- **Tavolo di MACHIAVELLI** (attivo ora): **CLOCKWORK** — **ingranaggi, ritmico e ambientale**,
  che dà **presenza senza chiedere attenzione**. Il turno del Machiavelli è **lavoro cognitivo
  lungo e continuo**: il giocatore scorre decine di carte, tiene a mente combinazioni, cerca la
  carta che smonta la scala. Per il cieco è **ascolto puro** (ogni carta è un annuncio). Una
  musica con **sviluppo tematico** lì diventerebbe un **secondo pensiero** in concorrenza diretta
  sul canale che sta usando per giocare. Il clockwork dà atmosfera **senza** occupare la testa.

Nel codice questo è un **override per-gioco della palette** (`CasinoAudio.ambient(forGame:)`,
D-073): la palette resta un attributo del **casinò**, ma il **letto** può dipendere dal **gioco**.

---

## Come il codice usa queste tracce
Per **ciascun** letto (poker e Machiavelli) il motore incrocia due tracce `calm` per dare
**varietà** (non si ripete uguale), passa a una traccia `thinking` mentre un **bot riflette**
(l'attesa resa **udibile** senza rivelare cosa trovi, D-072), e tiene un **layer continuo** di
ticchettio d'orologio sotto tutto. Loop **lunghi** e **seamless**.

---

## A) Letto MACHIAVELLI — CLOCKWORK (attivo ora)

Le tracce clockwork del Machiavelli sono **DUE** (non una), perché **una partita è lunga** e un
loop breve e riconoscibile diventerebbe una **tortura**. Si alternano col crossfade dinamico già
supportato.

### ‼️ Indicazioni di produzione IMPOSTE per le due tracce clockwork (StableAudio)
1. **Variabilità interna, non ripetitività.** Il clockwork è materiale **perfetto** per questo:
   **ruote/ingranaggi che girano a periodi diversi** tornano in fase **raramente** e producono
   **ricorrenza senza ripetizione**. Sfrutta ritmi poliperiodici, non un pattern che si ripete
   ogni due battute.
2. **Giunzione NEUTRA (fondamentale).** Inizio e fine della traccia **senza un evento marcato**
   (nessun rintocco, nessun colpo, nessun accento) che faccia da **campanello**: altrimenti anche
   una traccia bella **tradisce il ciclo** ogni volta che riparte. La giunzione loop deve essere
   **impercettibile** — livello e densità costanti ai due estremi.
3. **Ampiezza architettonica:** riverbero lungo, grande volume d'aria, distanze — l'osservatorio.

| # | Nome file (esatto) | Contesto | Carattere sonoro |
|---|---|---|---|
| 1 | `amb_clocktower_machiavelli_01.mp3` | Letto principale al tavolo di Machiavelli. Traccia A. | **Clockwork ampio e architettonico**: ingranaggi, meccanismi, ritmico ma **ambientale**, presenza senza richiamo d'attenzione. Poliperiodico (ricorrenza senza ripetizione). Riverbero lungo, grandi distanze. Loop 2–3 min, **giunzione neutra**. |
| 2 | `amb_clocktower_machiavelli_02.mp3` | Alternata alla `_01` col crossfade (la partita è lunga). Traccia B. | Stesso mondo (clockwork ampio) della `_01`, **materiale/periodi diversi**, riconoscibilmente parente ma non identico. Poliperiodico, riverbero lungo. Loop 2–3 min, **giunzione neutra**. |
| 3 | `amb_clocktower_machiavelli_thinking_01.mp3` | Entra quando **un bot riflette** (fino a ~10–15 s); esce quando ha finito. **Attesa resa udibile** (D-072). | Clockwork **più fitto/intenso**: ingranaggi che **accelerano leggermente**, più moto — "qualcuno sta pensando a fondo". Stesso spazio, chiaramente distinguibile dai due `calm`. Loop 1–2 min, giunzione neutra. |

## B) Letto POKER — ARCHI / CLASSICA (per i tavoli di poker FUTURI del ClockTower)

I tavoli di poker del ClockTower **non esistono ancora** (nessun motore assegnato — vedi ROADMAP:
il **Seven-Card Stud** è la specialità futura). Ma il letto è **già previsto** nella palette
(default del casinò), così quando arriveranno erediteranno l'ambiente per costruzione. Produci
queste quando vuoi; per ora sono inattive (nessun tavolo le usa).

| # | Nome file (esatto) | Contesto (futuro) | Carattere sonoro |
|---|---|---|---|
| 4 | `amb_clocktower_calm_01.mp3` | Letto dei tavoli di poker del ClockTower + lobby. Movimento A. | **Classica da camera per archi**, colta, **con struttura e sviluppo tematico**, raffinata e variabile. Ampia (riverbero, distanze). Loop 2–3 min, seamless. |
| 5 | `amb_clocktower_calm_02.mp3` | Alternata alla `calm_01`. Movimento B. | Stessa opera/ensemble, altro movimento, riconoscibilmente parente. Loop 2–3 min, seamless. |
| 6 | `amb_clocktower_thinking_01.mp3` | Attesa udibile ai tavoli di poker (bot che riflette). | Archi **più cercanti**, contrappunto serrato, tensione trattenuta. Stesso mondo dei `calm`. Loop 1–2 min. |

## C) Layer condiviso (sotto entrambi i letti)

| # | Nome file (esatto) | Contesto | Carattere sonoro |
|---|---|---|---|
| 7 | `amb_clocktower_clock_01.mp3` | **Layer continuo** sotto tutto, volume molto basso (undertone). | **Ticchettio lento e regolare** di un grande orologio a pendolo + sala antica (pietra, legno, silenzio, distanze). Nessuna melodia — tempo e spazio. Loop lungo seamless. |

**Fallback attivi finché non consegni:** i `machiavelli_*` → `amb_lounge_calm_*`/`tense`; i
`calm_*`/`thinking` → idem; `clock_01` → il layer resta silenzioso. Il ClockTower è **già
giocabile** al Machiavelli; questi file gli danno la sua vera aria vasta.

---

## Cosa NON è in questo catalogo
Le **voci** — vedi `ClockTower_audio_catalog_voices.md` (ElevenLabs). Il **personaggio è ora
DECISO** (D-073): un **uomo anziano, custode della sala**, una **sola** figura per tutto il
casinò — croupier ai (futuri) tavoli di poker e arbitro/maestro di gioco al Machiavelli. Registro
**erudito, misurato, colto, in italiano** (privilegia l'italiano agli anglicismi). Completa la
terna riconoscibile in due secondi: Riverwood **maschile di frontiera**, Skypool **femminile
cinica**, ClockTower **maschile anziano ed erudito**.
