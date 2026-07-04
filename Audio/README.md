# Audio

Il sistema di **suono** del gioco: il quarto cerchio dell'architettura,
**trasversale** e **agnostico rispetto al gioco**.

## Filosofia

`Audio` non sa nulla di poker, eventi, seat o regole. Riproduce **suoni opachi**
(identificati dal nome del file) raggruppati in **categorie**, e possiede l'unica
regola di accessibilità che appartiene allo strato audio: **non parlare mai sopra
VoiceOver**. Può importare `AVFoundation` (la sua ragione d'essere) e, solo per il
rilevamento di VoiceOver, `UIKit` sotto `#if canImport(UIKit)`. **Non** importa
`GameEngine`, `GameWorld` né `UI`.

Chi conosce il gioco (la `UI`) mappa gli eventi su questi suoni opachi e guida il
modulo. Così `Audio` resta neutro e riusabile per giochi diversi.

## Cosa contiene oggi (M1.8)

| Tipo | Ruolo |
|---|---|
| `SoundID` / `SoundCategory` | Un suono opaco (nome file) e la sua categoria (`ambient`, `table`, `croupier`, `botVoice`, `effect`, `ui`), che decide volume di default e se è **parlato** (deve cedere a VoiceOver). |
| `AudioServicing` | L'interfaccia generica: `startAmbient`, `play(_:category:)`, `stopAll`, volume, mute. Guidata da suoni opachi. |
| `AudioEngine` | L'implementazione reale AVFoundation: un player ambient in loop + one-shot sovrapposti (buffer limitato), volumi per categoria, e la regola VoiceOver. **Degrada con grazia**: file mancante → silenzio, e all'avvio logga quali file mancano. |
| `NullAudioService` | Implementazione no-op per test/preview. |
| `AudioPolicy` | La regola pura `shouldPlay(category:voiceOverRunning:)` (D-024). |
| `SoundCatalog` | Il **manifesto**: nome logico → nome file + categoria. **Unico punto** di riconciliazione col catalogo reale dell'utente. |

La **mappatura evento → suoni** (`AudioScore`) e il **consumatore del flusso**
(`AudioDirector`) vivono in `UI`, non qui, perché servono `SessionEvent` (che
`Audio` non deve conoscere) — vedi D-023.

## Coordinamento con VoiceOver (D-024)

VoiceOver è già una voce che parla; le voci del croupier e dei bot sono un'altra
voce. Per non sovrapporle: **quando VoiceOver è attivo** (`UIAccessibility.isVoiceOverRunning`),
i suoni **parlati** (`croupier`, `botVoice`) restano **silenziati**; tutto il
resto (ambient, effetti fisici del tavolo, feedback UI, jingle di esito) continua
a suonare. VoiceOver resta la fonte di verità per l'informazione parlata:
**l'accessibilità non è mai ridotta**, l'audio arricchisce e basta. La sessione
audio è `.ambient` + `.mixWithOthers`, così i nostri suoni non "abbassano"
VoiceOver.

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
unici, volumi sensati); la **policy VoiceOver** silenzia i parlati e lascia il
resto; l'engine riporta i file mancanti e resta usabile senza crash. La mappatura
`AudioScore` e il consumo del flusso sono testati in `Tests/UITests/`
(`AudioScoreTests`: cue per ogni tipo di evento, determinismo, e il director che
reagisce a un'intera sessione).
