# Audio

Il sistema di **suono** del gioco: il quarto cerchio dell'architettura,
**trasversale** e **agnostico rispetto al gioco**.

## Filosofia

`Audio` non sa nulla di poker, eventi, seat o regole. Riproduce **suoni opachi**
(identificati dal nome del file) raggruppati in **categorie**. Le voci parlate
(croupier/bot) **suonano sempre** (D-028): il modulo non le silenzia più con
VoiceOver, si limita a **riferire quanto parlato è ancora in corso** così che lo
strato VoiceOver possa aspettarne la fine. Può importare `AVFoundation` (la sua
ragione d'essere). **Non** importa `GameEngine`, `GameWorld` né `UI` (né più `UIKit`).

Chi conosce il gioco (la `UI`) mappa gli eventi su questi suoni opachi e guida il
modulo. Così `Audio` resta neutro e riusabile per giochi diversi.

## Cosa contiene oggi (M1.8)

| Tipo | Ruolo |
|---|---|
| `SoundID` / `SoundCategory` | Un suono opaco (nome file) e la sua categoria (`ambient`, `table`, `croupier`, `botVoice`, `effect`, `ui`), che decide volume di default e se è **parlato** (croupier/bot — tracciato per il coordinamento, D-028). |
| `AudioServicing` | L'interfaccia generica: `startAmbient`, `play(_:category:)`, `stopAll`, volume, mute, e `spokenAudioRemaining()` (quanto parlato è ancora in corso). Guidata da suoni opachi. |
| `AudioEngine` | L'implementazione reale AVFoundation: un player ambient in loop + one-shot sovrapposti (buffer limitato), volumi per categoria. Traccia i player **parlati** per `spokenAudioRemaining()`. **Degrada con grazia**: file mancante → silenzio, e all'avvio logga quali file mancano. |
| `NullAudioService` | Implementazione no-op per test/preview (`spokenAudioRemaining` = 0 di default). |
| `SoundCatalog` | Il **manifesto**: nome logico → nome file + categoria. **Unico punto** di riconciliazione col catalogo reale dell'utente. |

La **mappatura evento → suoni** (`AudioScore`) e il **consumatore del flusso**
(`AudioDirector`) vivono in `UI`, non qui, perché servono `SessionEvent` (che
`Audio` non deve conoscere) — vedi D-023.

## Coordinamento con VoiceOver — "strategia C" (D-028, supera D-024)

VoiceOver e le voci pre-registrate (croupier/bot) sono **due sistemi che parlano**.
La vecchia regola (D-024) li faceva concorrere e silenziava il croupier quando
VoiceOver era attivo: al primo test reale questo faceva **sparire il croupier**
dopo i primi eventi (il flag `isVoiceOverRunning` all'avvio è `false` per qualche
ms, poi scatta e zittisce tutto). La regola nuova è **domini separati, mai
concorrenti**:

- **Il croupier suona sempre**, a prescindere da VoiceOver, per i soli eventi
  **istituzionali** (blind, flop/turn/river, showdown, pot, hand start). Nessuna
  policy di silenziamento: `AudioPolicy` e il rilevamento VoiceOver sono stati
  **rimossi** dal modulo.
- **VoiceOver** parla solo del **personale** del giocatore umano (proprie carte,
  proprio turno, propria azione, proprio esito). Le azioni degli avversari non le
  annuncia nessuno dei due (basta il suono fisico + eventuale voce del bot).
- **Coordinamento seriale con completion (D-029):** un unico `SpeechConductor`
  (in `UI`) possiede i due sistemi parlanti e riproduce un item per volta — prima
  l'mp3 croupier, poi la sintesi — usando il **completion handler** dell'engine
  (`play(_:category:completion:)`, via `AVAudioPlayerDelegate`), non un ritardo
  fisso. Così "flop" (mp3) → carte del flop (sintesi) è in ordine garantito e le
  due voci non si sovrappongono. Il conductor **de-duplica** le voci once-per-hand
  (showdown, pot, split): il driver emette un `potAwarded` per pot, ma la voce si
  dice **una volta sola** (fix del "disco rotto").
- **Ambient dinamico (D-029):** l'engine espone `crossfadeAmbient`,
  `startAmbientLayer` (layer continuo, es. folla lontana) e `setAmbientScale`
  (duck). Le **decisioni** (calm ↔ `tense` con l'all-in in gioco, duck +
  `amb_silence_tension` allo showdown, ritorno a calm dopo il pot) stanno in `UI`
  (`AudioDirector`), così `Audio` resta neutro (id opachi).

- **Fallback mp3→sintesi (D-030):** `isAvailable(_:)` dice se un file è nel bundle;
  se la mappatura chiede un mp3 mancante e dichiara un fallback, il conductor
  **sintetizza il fallback** invece dell'mp3, e passa automaticamente all'mp3 quando
  il file viene aggiunto. Serve alla **produzione audio graduale** (es.
  `vo_it_role_button`, non ancora consegnato → "sei sul bàtton").
- **Mappatura aggiornata (D-031):** a inizio mano si annuncia **solo il ruolo del
  giocatore umano** (non i blind generici); le **azioni degli avversari** hanno una
  sintesi attribuita col numero di seat ("giocatore N rilancia a X"), preceduta
  dalla `vob_` di colore se scelta.

La sessione audio resta `.ambient` + `.mixWithOthers`, così i nostri suoni non
"abbassano" VoiceOver.

### Debug del layer audio (D-030)

Due log gated su `#if DEBUG`, silenziosi in release ma nel repo per i prossimi giri:
- `AudioEngine.playbackLogging = true` → una riga per **ogni riproduzione reale**
  (`[AudioLog] <timestamp> PLAY <file> [categoria]`). Utile per cacciare un suono
  che parte due volte.
- `SpeechConductor.logging = true` → una riga per **ogni enqueue** con motivo e
  verdetto di deduplicazione (`[SpeechLog] say lead=… reason=… [deduped]`).
All'avvio un **self-check** verifica che le voci critiche siano presenti e
caricabili, loggando chiaramente in caso contrario.

## Struttura degli asset audio

Gli mp3 stanno in **`Resources/Audio/`** (vedi il README lì). Quella cartella è
dentro il gruppo `Resources` **sincronizzato** del target app: ogni file lì
finisce automaticamente nel bundle (verificato). L'engine li cerca per nome via
`Bundle.main`. I nomi combaciano con `SoundCatalog.swift`.

> **Stato M1.8:** **51 dei 53** suoni del catalogo sono integrati (i primi 47
> rinominati alla forma del catalogo su scelta dell'utente, poi i 4 `tbl_chips_*`
> aggiunti). Restano **2** suoni non ancora consegnati (`amb_crowd_distant`,
> `fx_hand_neutral`): silenziosi e loggati all'avvio, l'app funziona lo stesso
> (D-025).

## Cosa NON contiene ancora (per scelta)

- **Nessuna conoscenza del gioco**: nessun `SessionEvent`, nessuna logica poker.
- **Nessuna progressione tra casinò** (l'ambient del casinò sfarzoso arriverà con
  quel casinò).
- **Nessuna persistenza** delle preferenze audio (volume/mute tra sessioni).
- **Nessun audio spaziale / 3D**, nessuna cuffia spaziale.
- **Nessuna dipendenza esterna**, nessuna libreria di terze parti.

## Test

`Tests/AudioTests/` (`swift test`): il catalogo è ben formato (non vuoto, nomi
unici, volumi sensati); l'engine non ha più policy di silenziamento e
`spokenAudioRemaining()` riporta 0 a riposo; l'engine riporta i file mancanti e
resta usabile senza crash. La mappatura `AudioScore` e il consumo del flusso sono
testati in `Tests/UITests/` (`AudioScoreTests`: azioni **senza** voce croupier,
eventi istituzionali **sempre** col croupier, determinismo, director su un'intera
sessione); il coordinamento temporale in `SpeechCoordinatorTests`.

## Rifinitura Draw — nuovo slot croupier + dedup (D-051/D-053)

- **Nuovo slot non consegnato:** `vo_it_high_stakes_draw.mp3` — annuncio della **mano
  decisiva** al tavolo Whiskey (D-053). Coperto da **fallback di sintesi** "mano
  decisiva" (D-030) finché non viene prodotto e depositato in `Resources/Audio/`.
- **Deduplicazione once-per-hand consolidata (D-051):** la lista delle voci croupier
  deduplicate una-volta-per-mano è dichiarata in **un solo punto**
  (`SpeechConductor.oncePerHandVoices` in `UI`): showdown, pot, split, **openers
  squalificati**, **mano decisiva**. Le voci di questa natura vanno aggiunte lì.
