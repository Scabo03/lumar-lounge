# Lumar Lounge

App iOS / iPadOS di giochi di carte e da casinò, scritta in Swift e SwiftUI.

> **Nuova sessione di Claude Code?** Parti da [`CLAUDE.md`](CLAUDE.md): è il
> punto d'ingresso che dice cosa è fatto, dove sta la documentazione, quali
> sono le convenzioni e qual è il prossimo passo. La sequenza dei mattoni è in
> [`ROADMAP.md`](ROADMAP.md), le regole del progetto in
> [`CONVENTIONS.md`](CONVENTIONS.md).

## ⚠️ Modalità di sviluppo attualmente attive

Flag temporanei attivi in questa build, **da rimuovere prima del rilascio pubblico**:

- **`DebugFlags.freePlay` — Gioco libero (D-050).** Attivo. Il **buy-in è ignorato**
  (ci si siede a qualsiasi tavolo a prescindere dal saldo), il saldo gettoni è
  **ripristinato a 5000 a ogni avvio** e non si muove giocando, così si può testare
  all'infinito. L'app mostra un badge arancione **"GIOCO LIBERO"** in alto in ogni
  schermata. Definito in [`GameWorld/DebugFlags.swift`](GameWorld/DebugFlags.swift);
  per disattivarlo, mettere `freePlay = false`. Introdotto per la fase di test post-M2.1
  (calibrazione delle personalità dei bot).

## Stato di sviluppo

Il progetto è passato dalla pura impalcatura ai primi contenuti reali, ma il
grosso del gioco è ancora davanti. Esiste una **scatola architetturale vuota ma
solida**: quattro moduli Swift (`GameEngine`, `GameWorld`, `Audio`, `UI`) con la
direzione delle dipendenze verificata dal compilatore, una shell d'app che
presenta una `RootView` minimale, e l'impianto di localizzazione bilingue
italiano/inglese già in piedi. Su questa scatola è montata tutta
l'**infrastruttura di rilascio**: signing con Fastlane Match su repo certificati
privato e pipeline di build → archive → upload verso TestFlight, collaudata e
guidata da due sole lane.

Dentro `GameEngine` sono stati posati i **primi tre mattoni del motore poker**.
Il primo: la rappresentazione di una carta (`Card`, `Rank`, `Suit`), un mazzo di
52 carte con mescolata deterministica e seedabile (`Deck`), e la **valutazione
delle mani** — dato un insieme di cinque o più carte, il sistema trova la miglior
mano di cinque, la classifica in una delle dieci categorie standard e la mette a
confronto con altre mani, kicker e split pot inclusi (`HandCategory`, `HandRank`,
`HandEvaluator`). Il secondo: il **motore di una mano di Texas Hold'em No Limit**
(`HoldemHand`) — una macchina a stati a turni che va dalla posta dei blind fino
all'assegnazione del pot, gestendo rotazione del button, distribuzione delle
carte, le quattro street, le sei azioni (fold/check/call/bet/raise/all-in) con le
regole di min-raise del No Limit, pot e side pot esatti anche con stack diversi,
showdown con split e chip di resto. Il terzo: l'**intelligenza dei bot** — un bot
(`PokerBot`/`HeuristicBot`) che, vista solo l'informazione onesta della mano
(`BotContext`: stato pubblico più le proprie due carte), unisce un baseline
matematico (forza mano, pot odds, posizione) a una **personalità** che ne modula
lo stile. Tre profili di partenza visibilmente diversi — principiante emotivo,
sasso conservativo, aggressivo caldo. Tutto puro su Foundation, deterministico
via seed, coperto da 68 unit test che passano.

Con il quarto mattone il progetto **esce per la prima volta da `GameEngine`** ed
entra in `GameWorld`: il **driver di sessione** (`SessionDriver`) fa girare una
serie di mani allo stesso tavolo — le fiches si accumulano e si perdono attraverso
le mani, il button ruota con la regola del dead button saltando i bustati, i
giocatori possono entrare e uscire tra una mano e l'altra. Bot e giocatore umano
rispondono alla stessa richiesta d'azione tramite un'interfaccia asincrona
uniforme: il bot risponde subito, l'umano quando la UI fornirà l'azione. Il
driver resta cliente puro del motore, deterministico e con le fiches sempre
conservate; quando finisce la sessione lo decide chi lo usa, non il driver.

Il quinto mattone dà al driver una **voce**: un flusso di eventi osservabile.
Mentre svolge le mani, il `SessionDriver` **narra** ogni momento significativo
(inizio mano, blind, carte distribuite, azioni, flop/turn/river, showdown, pot,
bust, ingressi e uscite) come valori `SessionEvent` su un canale multicast a cui
più consumatori possono iscriversi. Gli eventi sono **descrittivi** (dicono cosa
è successo, non cosa fare) e distinguono **pubblico e privato**: un giocatore
riceve le proprie carte coperte ma mai quelle altrui.

Il sesto mattone è la **prima schermata reale**, ed entra per la prima volta in
`UI`: un tavolo da poker minimalista e ad alto contrasto che si iscrive al flusso
del driver e mostra una sessione tra tre bot svolgersi dall'inizio alla fine. Qui
il tempo umano incontra la velocità di codice del flusso: la schermata lo consuma
a **ritmo umano** (le carte del flop escono una alla volta, le azioni scorrono,
la fine mano respira), mentre il driver resta a velocità di codice. Soprattutto,
la partita è **interamente accessibile**, con pronuncia italiana curata dei termini
del poker. La divisione dei ruoli tra croupier e VoiceOver è stata poi affinata nel
fix post-M1.8 (vedi sotto, D-028), ma il principio resta: un non vedente segue tutto
senza perdere nulla rispetto a un vedente.

Il settimo mattone rende il tavolo **giocabile da una persona**. Il giocatore
umano entra al tavolo insieme a tre bot, in un layout stratificato dove è
protagonista in basso con le sue due carte grandi e scoperte, gli avversari sono
badge astratti in alto, e in mezzo il tavolo con le carte comuni e il pot. Quando
tocca a lui i tasti — Check/Call, Fold, Raise — si accendono; il Raise apre un box
per regolare la cifra con una curva progressiva (controllo fine vicino al minimo,
accelerazione verso l'all-in). La sua azione passa alla UI e da lì
all'infrastruttura di attesa già pronta nel driver. Tutto resta accessibile con la
stessa cura: annuncio affidabile del proprio turno, delle proprie carte, e di ogni
scatto del box Raise. La partita finisce quando l'umano busta o quando battono
tutti i bot, con una schermata di esito e un tasto per ricominciare.

L'ottavo mattone dà al tavolo una **voce**, e chiude la prima fase del progetto.
Il modulo `Audio` — l'ultimo dei quattro cerchi — riproduce l'atmosfera di
sottofondo, gli effetti di carte e fiches, le battute del croupier e dei bot, i
jingle di vittoria e sconfitta. Ascolta lo **stesso flusso di eventi** in
parallelo alla UI, senza che il driver sappia nulla, e resta neutro: non conosce
il poker, riproduce solo suoni per categoria. Il coordinamento con VoiceOver è la
cura chiave, **ripensato dopo il primo test reale** (D-028): non più
silenziamento, ma **domini separati** — il croupier suona sempre per i momenti
istituzionali (blind, flop/turn/river, showdown, pot), VoiceOver parla solo di ciò
che è **personale** al giocatore (le sue carte, il suo turno, la sua azione, il suo
esito), e le azioni degli avversari non le annuncia nessuno dei due. Se le due voci
cadono vicine, VoiceOver **aspetta** la fine di quella registrata, così non si
accavallano mai — l'audio arricchisce, ma VoiceOver da solo basta sempre. Il gioco
**degrada con grazia** se un suono manca: gira lo stesso e segnala all'avvio cosa
manca.

Dopo la prima fase, `GameEngine` ha guadagnato un **secondo motore di gioco**: il
**Five-Card Draw** tradizionale ("Jacks or Better"), completo e indipendente dal
Texas (M1.9). È una macchina a stati pura per una mano di draw — ante, due giri di
puntata a taglio fisso (*limit*, con un tetto di tre rilanci), lo scambio di 0–4
carte, e lo showdown a cinque carte — con le sue regole caratteristiche: si apre
solo con **almeno una coppia di jack**, ma **sull'onore**, e chi apre bluffando
senza averli **perde d'ufficio** se la mano arriva allo showdown (mentre se tutti si
ritirano il bluff riesce e vince); e il **pot progressivo**, per cui se nessuno può
aprire la mano è nulla e gli ante si accumulano nella mano successiva. Riusa le tre
personalità dei bot con tre nuove leve dedicate al draw. Non ha ancora né tavolo né
UI (arriveranno per rendere entrabile la "Sala Whiskey" del Riverwood); il motore è
coperto da 31 nuovi unit test, per un totale di **205 test verdi** nel package.

Con il mattone successivo il Five-Card Draw diventa **giocabile end-to-end** (M2.4).
Un driver di sessione dedicato (`DrawSessionDriver`, indipendente da quello del
Texas) orchestra la sessione — ante, i due giri di puntata, lo scambio, e il **pot
progressivo** delle mani annullate — e la **narra** con un suo flusso di eventi.
Sopra ci sono il **tavolo giocabile** e, novità di questo gioco, un **box modale per
lo scambio delle carte**: le cinque carte si selezionano al tocco con un **doppio
segnale visivo** (bordo brillante e un segno scuro sulla faccia) e, per VoiceOver,
ogni carta annuncia il proprio stato ("asso di picche, selezionato per lo scarto");
un pulsante Conferma sempre attivo chiude lo scambio (zero carte = "stai pat"). La
"Sala Whiskey" del Riverwood è ora **entrabile** (buy-in 2000 gettoni). Il tavolo
riusa tutta l'infrastruttura trasversale (chrome, coda annunci, croupier↔sintesi,
modalità VoiceOver, ritmo adattivo); il motore e tutta la parte Texas restano
intatti. Cinque nuove voci di croupier del Draw sono predisposte con **fallback di
sintesi** finché gli mp3 non verranno prodotti. **234 unit test verdi** più gli
XCUITest del tavolo Draw e della navigazione.

Dopo altri test su iPhone reale (Tavolo Rapido con VoiceOver), una **rifinitura del
layer VoiceOver e audio** (D-054…D-058, tutta in `UI`/`Audio`): la pronuncia fonetica
ora è **garantita su ogni pulsante** da un test che scandisce i sorgenti (chiuso il
Check/Call idle); il turno umano è più asciutto (niente "per chiamare X" ridondante col
pulsante Call); il ritmo adattivo con VoiceOver ON ha una **salvaguardia anti-blocco** e
la voce del croupier ha la **completion garantita** (risolto il blocco pre-flop); ogni
schermata e modale **atterra il focus VoiceOver** sul primo elemento a ogni transizione;
e le voci dei bot **bustati** non si sentono più. **280 unit test verdi.**

**Terzo motore — Omaha Pot Limit (M1.10, motore ma non ancora giocabile).** `GameEngine`
contiene ora un terzo motore, l'**Omaha Pot Limit** (in `Omaha/`, indipendente da Texas e
Draw): quattro carte private, quattro street comuni, **regola due-più-tre** (valutatore
esteso, non sostituito), **betting Pot Limit** col tetto calcolato dal vivo, side pot e
determinismo; bot che lo giocano da Omaha (euristica a quattro carte + equity Monte Carlo
vincolata a costo misurato e contenuto) con due nuove leve di personalità; e un
`OmahaSessionDriver` in `GameWorld` con **accelerazione di sessione a conteggio-mani**
(blind escalation, mai a tempo — accessibilità). Mancavano UI, audio e il casinò ospitante,
tutti aggiunti in M2.5 (sotto). **311 unit test verdi**, Texas e Draw invariati.

**Skypool Casinò + Omaha giocabile; pattern casinò generalizzato (M2.5, D-065/D-066).** Con
l'arrivo del **secondo casinò** il pattern è stato **generalizzato**: un `Casino` ospita
`CasinoTable` che dichiarano gioco/buy-in/personalità/regole (`Casino`/`CasinoTable`/
`CasinoGame` + registry `Casinos`), con una **lobby generica** e temi per casinò — il
**Riverwood invariato** (regressione testata). Lo **Skypool** (cittadino, marmo/acqua/blu,
freddo) ospita Texas Classico/Rapido con **bot urbani** (tre personalità come **entità
proprie**) e la sua specialità **Omaha Pot Limit "Marble"**, ora **giocabile** (`OmahaTableView`:
quattro carte lette **per seme**, box raise **Pot Limit** senza shove). Accesso **solo
economico** (buy-in Skypool ~5×: Fast 5000 < Classic 6000 < Marble 10000; logica testata con
`DEBUG_FREE_PLAY` off). Novità audio: **due categorie di voce** — informativa (croupier) →
sintesi, ambientale (colore dei bot) → **silenzio** — con slot Skypool dichiarati ma **nessun
file prodotto** (catalogo in `Skypool_audio_catalog.md`). **337 unit test verdi** + XCUITest
Skypool/Omaha; motori invariati.

**Il croupier è un attributo del casinò, non del gioco (D-067).** Chiuso il debito: i tavoli
Texas dello Skypool non suonano più come quelli del Riverwood. Una **palette per casinò**
(`CasinoAudio`: croupier + registro dei testi + ambient + colore dei bot) è risolta per dati
dal tavolo → il casinò che lo ospita; lo Skypool ha il **suo** croupier (registro cittadino,
cinico) e il **suo** ambient su **tutti** i suoi tavoli. Il **Riverwood è la palette
identità/default** → invariato per costruzione (regressione pinnata). Un casinò nuovo eredita
il croupier senza toccare il percorso audio. **343 unit test verdi.**

**Lo Skypool prende voce: file audio reali cablati (D-068).** L'utente ha prodotto i file su
ElevenLabs/StableAudio e sono stati **cablati senza toccare la logica** (solo deposito asset +
rinomine, `AudioEngine.isAvailable` fa il resto): croupier 12/14, ambient 4/4, colore-bot 6/7. Lo
Skypool ora **parla con la sua voce vera** e i bot urbani si sentono. Il colore dei bot resta sul
**canale ambientale** (audio, mai in coda annunci) e, coordinato dal conductor, non copre
l'informazione di gioco. Il ritmo adattivo (VoiceOver-ON) è stato rilassato (tetto safeguard 3→8 s)
perché le voci vere, più lunghe, non facessero scattare il backstop a metà parlato. Riverwood
invariato. **347 unit test verdi.**

**Quarto motore — Machiavelli (motore + bot + driver, non ancora giocabile, D-070).** `GameEngine`
contiene ora un **quarto motore**, il **Machiavelli** (in `Machiavelli/`, indipendente dai tre
poker): il gioco italiano di **ricombinazione** — si calano scale e tris e si possono **smontare e
ricomporre** le combinazioni già sul tavolo (proprie o altrui), purché a fine turno tutto sia valido;
vince chi svuota per primo la mano. Regole canoniche fissate (2 mazzi/104 carte no jolly, group a semi
distinti, run con asso ai due capi mai wrap). Il **turno è una sequenza di trasformazioni** con **stato
ipotetico** (si valuta senza applicare) validato contro lo snapshot d'inizio turno, così **la stessa
carta può muoversi più volte**; il **predicato di validità è unico e vive nel motore**, pronto per due
UI future (box del cieco / drag del vedente) che giocheranno lo **stesso** gioco. Bot su **due assi
indipendenti** (profondità di ricerca × pazienza) con tre archetipi (studente/adulto/professore) e una
ricerca **interrompibile** che non sfora mai il budget. `MachiavelliSessionDriver` in `GameWorld` con
eventi propri, **attesa udibile** dei bot che pensano, e **matchmaking progressivo** a partite giocate.
**Solo motore+bot+driver: manca UI, audio e casinò ospitante** (terzo casinò non anticipato). I tre
giochi esistenti invariati.

**Machiavelli a punti — struttura mano↔partita (D-071).** Una partita non è più una mano sola: ogni
**mano** è **segnata** (asso 10, figure 5, numerate 1; bonus per chi va out, malus per le carte
rimaste in mano) e la **partita** finisce alla **soglia di vittoria** (~3 mani). Il punteggio dà
**scopo a chi non vince la mano** e trasforma la pazienza dei bot in un **rischio calcolato**: una
nuova dimensione additiva (`machiavelliMalusAversion`) fa sì che il bot paziente **scarichi le carte
pesanti** e non resti con l'asso in mano quando un avversario sta per chiudere. Punteggio nel **motore**
(`MachiavelliScoring`), soglia/struttura in **GameWorld**. Ancora **non giocabile**. **389 unit test verdi.**

> **🏁 La prima fase è completa.** Il gioco base è funzionante end-to-end — motore
> completo, bot credibili, sessione multi-mano, flusso di eventi, UI giocabile e
> accessibile, e **audio pieno**: i 47 file mp3 consegnati (atmosfera, carte,
> voce del croupier, voci dei bot, jingle di esito) più i 4 suoni delle fiches
> aggiunti dopo sono integrati nel bundle (51 su 53); restano silenziosi solo 2
> suoni non ancora prodotti (il brusio di sottofondo e la chiusura neutra di
> mano). Il progetto è **pronto per un
> primo upload su TestFlight** (`bundle exec fastlane testflight_upload`). 126
> unit test più un XCUITest, tutti verdi; l'app compila per iphoneos, gira sul
> simulatore con audio, e ha icone e `Info.plist` a posto. La fase successiva
> (`GameWorld`, il mondo attorno al tavolo) sarà definita nella prossima
> conversazione. Rotta completa in [`ROADMAP.md`](ROADMAP.md).

> Questa sezione va aggiornata quando si completa un **mattone significativo**
> (non a ogni commit). I parametri operativi e la pipeline di rilascio, invece,
> sono descritti qui sotto e cambiano di rado.

## Parametri operativi

| Parametro | Valore |
|---|---|
| Nome progetto | **Lumar Lounge** |
| Bundle identifier | `com.scabo.lumarlounge` |
| Repo progetto | https://github.com/Scabo03/lumar-lounge.git |
| Repo certificati Match | https://github.com/Scabo03/lumar-lounge-certs.git |
| Scheme Xcode | `LumarLounge` (condiviso) |
| Percorso project | `LumarLounge.xcodeproj` (alla radice del repo) |
| Linguaggi | Swift + SwiftUI |
| Deployment target | iOS 17.0 |
| Device family | iPhone + iPad (`1,2`) |
| Lingue supportate | **Italiano** (principale), **Inglese** (seconda) |

## Lingue e localizzazione

La lingua di sviluppo è l'**italiano** (`CFBundleDevelopmentRegion = it`);
l'inglese è la seconda lingua. Tutte le stringhe visibili all'utente passano
dai file di localizzazione in `Resources/` — **nessuna stringa utente è scritta
inline nel codice**.

- `Resources/it.lproj/Localizable.strings` — testi UI (italiano)
- `Resources/en.lproj/Localizable.strings` — testi UI (inglese)
- `Resources/it.lproj/InfoPlist.strings` / `en.lproj/InfoPlist.strings` — nome
  app e metadati localizzati del bundle

## Struttura delle cartelle

Il codice è organizzato in quattro moduli Swift separati (target del package
locale `LumarKit`, definito in `Package.swift`) più una cartella risorse. La
separazione in moduli rende la **direzione delle dipendenze verificata dal
compilatore**: importare un modulo che non è una dipendenza dichiarata non
compila.

```
lumar-lounge/
├── Package.swift              # definisce i 4 moduli e il grafo delle dipendenze
├── GameEngine/                # regole pure dei giochi (solo Foundation, portabile)
├── GameWorld/                 # giocatore, fiches, NPC, progressione (usa GameEngine)
├── Audio/                     # suono + aptica, generico e trasversale
├── UI/                        # tutte le viste SwiftUI (usa GameWorld, GameEngine, Audio)
├── Resources/                 # file di localizzazione it / en
├── App/                       # shell dell'app: @main, Info.plist, Assets.xcassets
└── LumarLounge.xcodeproj/     # progetto Xcode (target app `LumarLounge`)
```

### Direzione delle dipendenze (regola architetturale rigida)

```
            ┌─────────────┐
            │     UI      │  (SwiftUI)
            └──────┬──────┘
        ┌──────────┼───────────┐
        ▼          ▼           ▼
  ┌──────────┐ ┌───────┐  ┌─────────┐
  │ GameWorld│ │ Audio │  │GameEngine│
  └────┬─────┘ └───────┘  └─────────┘
       │                       ▲
       └───────────────────────┘
```

- **GameEngine** — non importa nessuno degli altri moduli. Solo `Foundation`.
  Niente SwiftUI / UIKit / AVFoundation / CoreHaptics. Autonomo e portabile.
- **GameWorld** — può importare `GameEngine`. Mai UI né Audio.
- **Audio** — trasversale e generico: non conosce poker, blackjack o alcun
  gioco specifico. Espone un'interfaccia (`AudioServicing`) guidata da
  identificatori opachi.
- **UI** — può importare `GameWorld`, `GameEngine`, `Audio`. Contiene tutte le
  viste; ogni vista imposta già accessibility identifier e label.
- **App** — shell minima che presenta `RootView` dal modulo UI.

## Ambiente di sviluppo

Lo sviluppo, la build, il signing e l'upload TestFlight avvengono su un
**MacBook Pro 14" (Apple Silicon M5 Pro, 24 GB RAM)** personale: ambiente
stabile, persistente e con pieni privilegi. `xcode-select` e `DEVELOPER_DIR` si
usano normalmente.

> **Nota storica.** Fino al commit iniziale il progetto è stato sviluppato su
> MacInCloud Pay-as-you-go, dove ogni sessione partiva da una macchina diversa,
> senza `sudo`, senza persistenza affidabile, e con accorgimenti specifici
> (path completo a `xcodebuild`, niente modifica di `xcode-select`, variabili
> d'ambiente da reimpostare ad ogni login, rituale Simulator per il logout
> pulito). **Quei vincoli non si applicano più** e sono stati rimossi da questa
> documentazione: restano qui solo come contesto.

Per fissare la versione di Xcode (una tantum):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# in alternativa, per sessione:
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Build

La build di archiviazione resta basata su `xcodebuild` diretto, **senza
`-destination`** e con la piattaforma device forzata (`SUPPORTED_PLATFORMS=iphoneos`,
`SUPPORTS_MACCATALYST=NO`): è la pipeline collaudata, ed è esattamente quella
incapsulata nella lane `testflight_upload` (vedi sotto). Su un Mac proprio
`xcodebuild` si invoca direttamente, senza path assoluto.

Build di verifica (compilazione, slice device):

```bash
xcodebuild \
  -project LumarLounge.xcodeproj \
  -scheme LumarLounge \
  -configuration Debug \
  SUPPORTED_PLATFORMS=iphoneos \
  SUPPORTS_MACCATALYST=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

Build + esecuzione nel simulatore (verifica runtime):

```bash
xcodebuild \
  -project LumarLounge.xcodeproj -scheme LumarLounge -configuration Debug \
  -sdk iphonesimulator26.5 SUPPORTS_MACCATALYST=NO CODE_SIGNING_ALLOWED=NO build

xcrun simctl install <SIMULATOR_UDID> <path-to>/LumarLounge.app
xcrun simctl launch  <SIMULATOR_UDID> com.scabo.lumarlounge
```

## Icona app

Set di icone placeholder (quadrato bordeaux scuro `#5E1020`, tema casinò) in
`App/Assets.xcassets/AppIcon.appiconset/`. Tutti i PNG sono **RGB senza canale
alfa** (requisito TestFlight) nelle dimensioni richieste da Apple: 1024, 180,
167, 152, 120, 87, 80, 76, 60, 58, 40, 29, 20. `CFBundleIconName` è impostato a
`AppIcon` nell'`Info.plist`.

## Build & Upload

Il signing è gestito con **Fastlane Match** (storage `git`, repo certificati
privato `lumar-lounge-certs`). Tutta l'infrastruttura vive in `fastlane/` e si
guida con due lane: `setup_signing` e `testflight_upload`.

Setup una tantum della toolchain (installa fastlane dal `Gemfile`):

```bash
bundle install
```

### Credenziali

I segreti **non** stanno nel repo. Su questa macchina vivono già in un file env
condiviso tra i progetti iOS:

```
~/Developer/private_keys/scabo_deploy.env      # MATCH_PASSWORD, key id/issuer, ecc.
~/Developer/private_keys/AuthKey_MGW9GC97HV.p8 # App Store Connect API key (.p8)
```

Il flusso è: **sourcare** quel file e lanciare la lane. L'identità del progetto
(`APP_IDENTIFIER` = `com.scabo.lumarlounge`, repo certificati = `lumar-lounge-certs`)
è **fissata nel codice Fastlane** (`Appfile`/`Matchfile`/`Fastfile`): così, anche
se il file condiviso porta i valori di un altro progetto, Match colpisce sempre
l'app e il repo giusti.

> Il certificato di distribuzione è **condiviso** con l'altro progetto
> (`Apple Distribution: Luca Scabini`, id `JJ47RUK3DJ`): l'account aveva già
> raggiunto il numero massimo di certificati di distribuzione, quindi invece di
> crearne uno nuovo è stato riusato. Lumar Lounge ha comunque il **suo**
> provisioning profile App Store (`match AppStore com.scabo.lumarlounge`).

### Riallineare i certificati su una macchina nuova

Recupera dal repo `lumar-lounge-certs` il certificato di distribuzione e il
provisioning profile App Store, decifrandoli con `MATCH_PASSWORD` e
installandoli nel keychain:

```bash
source ~/Developer/private_keys/scabo_deploy.env
bundle exec fastlane setup_signing
```

Da quel momento qualsiasi macchina con le credenziali corrette ottiene i
certificati con questo solo comando.

### Upload su TestFlight

Build → archive → export → upload, in un colpo solo (la lane usa `xcodebuild`
diretto per archive/export — senza `-destination`, `SUPPORTED_PLATFORMS=iphoneos`,
`SUPPORTS_MACCATALYST=NO` — e `xcrun altool` per l'upload):

```bash
source ~/Developer/private_keys/scabo_deploy.env
bundle exec fastlane testflight_upload
```

Il **build number** è automatico e monotòno crescente (epoch Unix in secondi,
iniettato all'archive come `CURRENT_PROJECT_VERSION`; nell'`Info.plist`
`CFBundleVersion = $(CURRENT_PROJECT_VERSION)`): ogni upload ne ha uno più alto,
niente rifiuti per build duplicato, nessun numero da bumpare a mano. L'app
dichiara `ITSAppUsesNonExemptEncryption = false`, quindi TestFlight non chiede la
conformità crittografia a ogni build. La **app record** su App Store Connect va
creata una tantum a mano (`produce` non supporta la sola API key). Vedi D-026.

### Variabili d'ambiente

Chiavi lette dall'ambiente (i valori segreti restano fuori dal repo). Le prime
sei sono fornite dal file `scabo_deploy.env`; `APP_IDENTIFIER` e `MATCH_GIT_URL`
sono invece **pinnate nel codice** e non vanno passate da env.

| Chiave | A cosa serve | `setup_signing` | `testflight_upload` | Dove si trova |
|---|---|:---:|:---:|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID dell'API App Store Connect | ✓ | ✓ | App Store Connect → Users and Access → Integrations (`MGW9GC97HV`) |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | Issuer ID dell'API | ✓ | ✓ | Stessa pagina (`eb059a17-…`) |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Contenuto del `.p8` (PEM o base64) — alternativa al file | ○ | ○ | Il file `AuthKey_MGW9GC97HV.p8` |
| `APPLE_TEAM_ID` | Apple Developer Team ID | ✓ | ✓ | `D2KQYQ8YU8` |
| `APPLE_ID` | Apple ID dell'account | ✓ | ✓ | `scabo@icloud.com` |
| `MATCH_PASSWORD` | Passphrase di cifratura dei certificati Match | ✓ | ✓ | `scabo_deploy.env` (condivisa con gli altri progetti) |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Auth base64 `user:token` per il repo certs in CI | ○ | ○ | PAT GitHub con accesso a `lumar-lounge-certs` |
| `APP_IDENTIFIER` | Bundle id — **pinnato in `Appfile`/`Fastfile`** | — | — | `com.scabo.lumarlounge` |
| `MATCH_GIT_URL` | Repo certificati — **pinnato in `Matchfile`/`Fastfile`** | — | — | `https://github.com/Scabo03/lumar-lounge-certs.git` |

✓ = richiesta · ○ = opzionale · — = non da env (pinnata nel codice)

Note: in alternativa al contenuto, le lane accettano `APP_STORE_CONNECT_API_KEY_PATH`
(path al `.p8`; default `~/AuthKey.p8`, qui sovrascritto da `scabo_deploy.env`).
In locale `MATCH_GIT_BASIC_AUTHORIZATION` non serve: il push verso il repo
certificati passa per il credential helper `osxkeychain`. Per saltare il
`source` ad ogni lancio si può creare un `fastlane/.env` locale (gitignorato);
vedi `fastlane/.env.example`.
