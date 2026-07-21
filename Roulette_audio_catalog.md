# Catalogo audio — Roulette (D-102)

Stato: **nessun file prodotto.** Gli slot sono dichiarati col pattern di fallback
consolidato (D-030/D-066): le voci **informative** (croupier) cadono su **sintesi
VoiceOver**, le voci/effetti **ambientali** cadono sul **silenzio**. Nessuna voce
dichiara simultaneamente sintesi *e* fallback del croupier con lo stesso testo
(anti-pattern D-051): il croupier è la "parola" del posto, la sintesi è il
**contenuto** dell'esito, e sono distinti.

La palette è un attributo del **casinò** (D-067): Riverwood e Skypool useranno
ciascuno la propria voce/ambiente. Il ClockTower **non** riceve la Roulette.

> **Nota di stato:** questa sessione ha consegnato **motore + driver + slip + regole
> + speech map + catalogo**, non i tavoli giocabili. Il **cablaggio** di questi slot
> (SoundCatalog, CasinoAudio, AudioDirector) avverrà con la sessione dei tavoli UI.

---

## 1. Effetti del tavolo (ambientali → silenzio se assenti)

Condivisi tra i casinò (come per il Blackjack): non ci sono NPC che parlano, solo
la meccanica della ruota e la presenza degli altri avventori.

| File atteso | Categoria | Carattere |
|---|---|---|
| `fx_roulette_wheel_spin` | `.table` | La ruota che parte e gira: un fruscìo/ronzìo crescente, ~2–3 s, che **precede** l'annuncio dell'esito (l'ordine porta informazione, D-085 — il suono non deve anticipare il numero). |
| `fx_roulette_ball` | `.table` | La pallina che rimbalza e si posa: ticchettìo che rallenta fino allo stop. Chiude il giro della ruota. |
| `fx_roulette_win` | `.effect` | L'esito positivo: fiches raccolte. Sequenziato **dopo** la riga che spiega la vincita (D-085), mai in parallelo. |
| `fx_roulette_lose` | `.effect` | L'esito negativo, discreto. Sequenziato dopo l'annuncio. |
| `fx_roulette_chip_place` | `.ui` | Una fiche posata sul tappeto (tocco su una cella / swipe che aumenta). Breve. |
| `fx_roulette_chip_remove` | `.ui` | Una fiche tolta (swipe che azzera / rimozione dal simbolino). |
| `fx_roulette_presence_murmur` | `.botVoice` | Brusìo degli altri avventori nei momenti morti. **Ambientale → silenzio.** Condiviso tra i casinò. |
| `fx_roulette_presence_chips` | `.botVoice` | Fiches altrui in lontananza, tra un giro e l'altro. Ambientale → silenzio. |

## 2. Voci del croupier (informative → sintesi se assenti)

Poche e rade, come al Blackjack: la Roulette è rapida e il croupier **non** deve
riempire ogni giro. Due registri distinti per i due casinò (D-067): il Riverwood di
frontiera, lo Skypool cittadino e freddo. Testi da scrivere nel registro del posto
alla produzione; qui il **contenuto** dell'esito lo dice comunque la **sintesi**.

| Slot logico | Riverwood | Skypool | Momento |
|---|---|---|---|
| `vo_*_roulette_no_more_bets` | `vo_it_roulette_rien_ne_va_plus` | `vo_it_sky_roulette_rien_ne_va_plus` | Chiusura delle puntate, appena premuto Conferma, prima della ruota. «Non si accettano più puntate.» / registro cittadino. |
| `vo_*_roulette_spin` | `vo_it_roulette_spin` | `vo_it_sky_roulette_spin` | La ruota parte (facoltativo: il fx basta; se prodotto, una battuta breve). |

> Il **numero uscito**, il **colore**, **quali puntate hanno pagato** e la
> **restituzione sullo zero** NON sono voci del croupier: sono **sintesi** del
> contenuto (l'autorità è `RouletteSpeechMap`), rese device-safe in italiano.

## 3. Termini con pronuncia da verificare (D-060)

Le puntate hanno nomi in parte francesi. Le parole **italiane** sono cablate
direttamente (corrette per costruzione): `rosso`, `nero`, `pari`, `dispari`, `pieno`,
`cavallo`, `terzina`, `quartina`, `sestina`, `dozzina`, `colonna`. I **due termini
francesi** delle metà sono **da ascoltare prima di cablare la resa definitiva**:

| Termine | Uso | Campioni generati |
|---|---|---|
| **manque** (1–18) | nome della metà bassa | `manque_01_french`, `manque_02_grapheme_mank`, `manque_03_grapheme_manche`, `manque_04_italian_bassi` |
| **passe** (19–36) | nome della metà alta | `passe_01_french`, `passe_02_grapheme_pass`, `passe_03_grapheme_passe_accent`, `passe_04_italian_alti` |

Cablati **provvisoriamente** come `manque`/`passe` (grafia piana) nelle stringhe;
il guardiano `PhoneticsTests` li marca **NON verificati** finché l'utente non
approva un campione, dopodiché si promuove la resa udita all'àncora (metodo D-060).

Campioni in `~/Desktop/lumar-phonetics/roulette/`.
