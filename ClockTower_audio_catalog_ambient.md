# ClockTower — catalogo AMBIENT & MUSICA da produrre (D-072, StableAudio)

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

È il **primo casinò del progetto la cui musica ha una FORMA e non solo un'atmosfera**: non un
tappeto ambientale indistinto, ma **musica classica ed erudita** — **archi** (quartetto/ensemble
d'archi), **strutture contrappuntistiche complesse e articolate**, che si evolvono. Pensa a un
**adagio/andante** da camera, colto, misurato, di respiro lungo. Registro sobrio, mai
sentimentale: è un posto di **prestigio e intelletto**, non di lusso ostentato.

L'opposto sia del Riverwood (whiskey, legno, calore rustico di frontiera) sia dello Skypool
(marmo, acqua, freddo notturno urbano): qui è **caldo ma austero**, **erudito**, **silenzioso**,
scandito dal battito lento di un **orologio a pendolo**.

---

## Come il codice usa queste tracce (importante per la produzione)
Il motore audio incrocia due letti "calm" per dare **varietà** (la musica cambia movimento nel
tempo, non si ripete uguale), passa a un letto "thinking" mentre un **bot riflette** (l'attesa
del bot resa **udibile** senza rivelare cosa stia trovando, D-072), e tiene un **layer continuo**
di ticchettio d'orologio sotto tutto. Quindi:

- **`calm_01` e `calm_02`** sono **due movimenti/sezioni diversi** della stessa opera, entrambi
  in loop, incrociati nel tempo. Falli **coerenti tra loro** (stesso ensemble, stessa tonalità o
  tonalità vicine) ma **distinguibili** (materiale tematico diverso), così l'alternanza si sente
  come "la musica prosegue", non come un salto. Loop **lunghi** (2–3 min) e **senza cuciture
  evidenti**.
- **`thinking`** è la sezione **più intensa e cercante** — non drammatica, ma più fitta,
  contrappunto più serrato, tensione trattenuta: è ciò che si sente quando il professore medita
  a lungo prima di smontare mezzo tavolo. Deve **staccarsi con chiarezza** dai calm (così il
  giocatore cieco *sente* che qualcuno sta pensando) restando nello **stesso mondo sonoro**.
- **`clock`** è un **letto continuo** a volume molto basso (undertone), sotto la musica: il
  **ticchettio lento e regolare** di un grande orologio a pendolo, con l'ambiente della sala
  (pietra, legno, silenzio ovattato, qualche pagina lontana). **Nessuna melodia** — solo tempo e
  spazio. Loop lungo, seamless.

---

## Le tracce (StableAudio)

| # | Nome file (esatto) | Contesto nel gioco | Carattere sonoro |
|---|---|---|---|
| 1 | `amb_clocktower_calm_01.mp3` | Letto principale al tavolo di Machiavelli e nella lobby del ClockTower. Movimento A. | Musica **classica da camera per archi**, **adagio/andante**, contrappunto elegante e articolato, respiro lungo, colto e misurato. Caldo ma austero. Loop 2–3 min, seamless. |
| 2 | `amb_clocktower_calm_02.mp3` | Alternato al `calm_01` per dare varietà (la musica "prosegue" cambiando movimento). Movimento B. | Stessa opera/ensemble del `calm_01`, **materiale tematico diverso** (altra sezione), stessa tonalità o vicina; riconoscibilmente parente ma non identico. Loop 2–3 min, seamless. |
| 3 | `amb_clocktower_thinking_01.mp3` | Entra quando **un bot sta riflettendo** (la sua mossa può richiedere fino a ~10–15 s); esce quando ha finito. È l'**attesa resa udibile** (D-072). | Archi **più intensi e cercanti**: contrappunto più serrato, tensione trattenuta, moto più continuo — non drammatico, ma "qualcuno sta pensando a fondo". Stesso mondo sonoro dei calm, chiaramente distinguibile. Loop 1–2 min. |
| 4 | `amb_clocktower_clock_01.mp3` | **Layer continuo** sotto tutto, volume molto basso (undertone). | **Ticchettio lento e regolare** di un orologio a pendolo + ambiente di sala antica (pietra, legno, silenzio, rare pagine lontane). Nessuna melodia, solo tempo e spazio. Loop lungo seamless. |

**Fallback attivi finché non consegni:** `calm_01/02`→`amb_lounge_calm_*`, `thinking`→
`amb_lounge_tense_01`, `clock`→(il layer resta silenzioso). Il ClockTower è già giocabile; questi
file gli danno la sua identità.

---

## Cosa NON è in questo catalogo (arriva dopo)
Le **voci** — la figura che parla al ClockTower (scandisce i turni, dichiara le combinazioni
calate, annuncia i punteggi di fine mano) e i **commenti di colore** dei tre bot (studente,
adulto, professore). Sono su **ElevenLabs** e dipendono dalla UI, quindi te le consegno nel
**secondo catalogo** a fine sessione. Una nota importante fin d'ora: **il personaggio e il genere
della voce del ClockTower sono ancora da decidere** — deciderai tu prima di produrle. Nel poker
parla un *croupier*; qui non c'è né piatto né puntate né showdown, quindi la figura è **un'altra**
e ha un compito diverso. Il secondo catalogo avrà i **testi esatti** nel registro erudito del
posto, con il personaggio lasciato aperto.
