# Convenzioni — Lumar Lounge

Convenzioni **stabili e permanenti** del progetto, emerse nel lavoro con
l'utente. Ogni sessione futura le trova qui già formalizzate e non deve
riscoprirle dalla conversazione. Il riassunto operativo per Claude Code sta in
[`CLAUDE.md`](CLAUDE.md); questo file è il riferimento completo.

---

## 1. Architettura e dipendenze

- Quattro moduli Swift nel package `LumarKit`: `GameEngine`, `GameWorld`,
  `Audio`, `UI`.
- **Direzione delle dipendenze rigida:** `UI → GameWorld → GameEngine`, con
  `Audio` **trasversale** (non dipende da nessuno degli altri e nessuno dei
  moduli di gioco dipende da lui). La regola è **verificata dal compilatore**:
  importare un modulo non dichiarato come dipendenza non compila.
- **`GameEngine` importa SOLO `Foundation`.** Mai SwiftUI, UIKit, AVFoundation,
  CoreHaptics, Combine o altri framework di piattaforma. È puro e portabile.
- **Motori di gioco paralleli e indipendenti (D-038).** Ogni gioco (Texas Hold'em,
  Five-Card Draw, e i futuri) è un **motore autonomo** dentro `GameEngine`, in una
  sottocartella dedicata (`Draw/`; i file storici del Texas restano flat). I motori
  **non si conoscono**: nessun `import` incrociato, **nessun tipo di regole
  condiviso**. Condividono **solo** (a) i tipi fondazionali di M1.1
  (`Card`/`Rank`/`Suit`/`Deck`/`HandEvaluator`) e (b) l'**aritmetica dei chip
  game-agnostica** (`PotMath`/`Pot`), che è matematica pura dei pot, non regole di un
  gioco specifico. Ogni motore definisce i **propri** tipi speculari
  (seat/azione/risultato/mosse legali). Le astrazioni condivise dei bot
  (`Personality`) si estendono in modo **additivo** (nuovi dial con default), così un
  gioco non altera il comportamento di un altro.
- **Le dimensioni della `Personality` sono additive e retrocompatibili (D-038/D-048).**
  Aggiungere una nuova dimensione **non deve mai richiedere di modificare le personalità
  esistenti** oltre a fornire un **default sensato** che **riproduca il comportamento
  precedente** (es. `pressureResistance = 1.0` → nessuna penalità di pressione,
  `trashFoldTendency = 0.0` → nessun trash-fold). Una personalità che non imposta la nuova
  dimensione resta identica a prima; solo chi vuole il nuovo comportamento la valorizza.
  La logica che la legge non deve spostare lo stream RNG quando la dimensione è al default
  (pescare i valori extra solo nel ramo attivo), così i test deterministici esistenti non
  si rompono.
- **Regole "sull'onore" enforced allo showdown, non a monte (D-039).** Quando una
  regola di un gioco è tradizionalmente sull'onore (es. *jacks or better* per aprire
  nel Draw), il motore **non** la blocca all'azione ma la **traccia** (snapshot della
  prova al momento del gesto) e la **verifica allo showdown**, punendo chi non può
  dimostrarla. Così restano modellabili sia il bluff riuscito (tutti foldano → vince)
  sia lo smascheramento (arriva allo showdown senza prova → perde d'ufficio).
- `GameWorld` può importare `GameEngine`, mai `UI` né `Audio`.
- `Audio` è agnostico rispetto al gioco: guida tutto tramite identificatori
  opachi, non conosce poker/blackjack.
- `UI` può importare tutto ciò che sta sotto; solo la thin shell dell'app
  importa `UI`.
- **Navigazione a tre livelli espliciti (D-035):** l'app è strutturata su **Home
  → Casinò → Tavolo**, e **ogni schermata principale è avvolta da `GameChrome`**
  per le funzionalità trasversali (Impostazioni, saldo gettoni, e future). Ogni
  nuovo casinò/gioco/schermata si aggancia a questa struttura.
- **Gettoni persistenti in GameWorld; fiches effimere al tavolo (D-036).** Il
  concetto di **gettoni** (valuta del giocatore fra le sessioni) è **persistito** e
  appartiene a **GameWorld** (`PlayerAccount`); le **fiches** sono valuta effimera
  che vive **solo** al tavolo. La UI li visualizza, non li possiede.
- **Meccaniche narrative di tavolo nel driver di GameWorld, trasparenti (D-037).**
  Quando un tavolo introduce meccaniche **non standard** rispetto al motore (boost,
  eventi speciali, blind dinamiche), queste vivono nel **driver di sessione di
  GameWorld** (non nel motore, che resta puro) e sono **trasparenti** al giocatore
  tramite **annunci espliciti** del croupier o della sintesi — mai regole nascoste.
- **Le meccaniche di accelerazione del ritmo vivono nel driver come override
  contestuali (D-037/D-052/D-053).** Mani decisive, boost di puntate, ante progressivo
  e simili vivono nel **driver di sessione** di GameWorld come **override contestuali
  della singola mano**, **mai** come modifiche al **motore** (che riceve solo parametri
  di config — ante, bet, cap raise — additivi e con default neutri) né alle
  **personalità permanenti** dei bot (il boost si passa **via contesto** al bot, non
  cambiando la sua `Personality`). Il default dei parametri additivi riproduce sempre il
  comportamento standard.

- **Una personalità si calibra NELL'ECONOMIA DEL SUO TAVOLO, mai in astratto
  (principio permanente, D-082).** Le leve di una `Personality` non sono giuste o
  sbagliate di per sé: lo stesso valore che rende un bot "prudente" a un tavolo lo rende
  **assurdo** a un altro, perché ciò che una leva *costa* dipende dalle poste e dalla
  struttura di puntata. Un `trashFoldTendency` alto è disciplina dove vedere la carta
  successiva è caro, ed è **fuga gratuita** a un tavolo limit dove proseguire costa una
  puntata piccola in un piatto già formato. Perciò: (a) un roster **riusato** da un gioco
  a un altro va **ricalibrato**, non copiato — i preset per tavolo vivono in `GameWorld`
  proprio per questo; (b) la calibrazione si valuta **dal comportamento osservato in
  quel contesto economico** (quanto folda, quanto mette in gioco), non dai numeri delle
  leve; (c) il **carattere** (le leve-firma: il rock non bluffa mai, l'aggressivo apre
  leggero) **non si smussa** per riparare un comportamento assurdo — se il comportamento
  è assurdo la causa è quasi sempre **strutturale**, e va corretta nella struttura.
- **Un vincolo di REGOLA non è una scelta strategica (D-082).** Quando il gioco impone un
  requisito (i jacks-or-better per aprire), una leva che ne modula la violazione deve
  pesare la **conseguenza della regola**, non solo il carattere: aprire senza requisito
  vince **solo** se tutti foldano, e arrivare allo showdown è una sconfitta d'ufficio.
  Una leva tarata ignorando questo produce un comportamento **perdente per costruzione**,
  che nessuna taratura del suo valore può salvare.

## 2. Lingua del codice e del dominio

- **Codice in inglese:** nomi di tipi, funzioni, variabili e **commenti** sono
  in inglese (`Card`, `Rank`, `Suit`, `Deck`, `HandEvaluator`, …).
- **Terminologia di dominio mista italiano-inglese**, secondo l'uso reale dei
  giocatori italiani:
  - **Inglese** per le **azioni** e i **ruoli** del poker: *fold, call, raise,
    check, bet, blind, button, dealer, all-in, pot, side pot*.
  - **Italiano** per le **entità comuni**: *carte, mazzo, tavolo, mano, seme,
    scala, colore, coppia, tris, full*.
- **Fiches vs gettoni:** al **tavolo** si gioca con le **fiches**; nel **casinò
  esterno** (progressione, economia del meta-gioco) si usano i **gettoni**. Sono
  due concetti distinti e non vanno confusi.
- **Precisazione (emersa in M1.2):** la regola mista italiano-inglese governa il
  **vocabolario di dominio rivolto all'utente** (label, VoiceOver, testi, docs),
  **non gli identificatori Swift**. Nel codice puro tutto è in inglese, incluse
  le entità comuni (`Card`, `Deck`, `Hand`, `Seat`, `board`, `pot`): lì vale la
  regola "codice in inglese". L'italiano per *carte/mazzo/tavolo/mano* riguarda
  ciò che il giocatore legge o sente, che in `GameEngine` non esiste.

## 3. Localizzazione e bilinguismo

- **Italiano lingua principale** (`CFBundleDevelopmentRegion = it`), **inglese
  seconda**. Architettura **bilingue fin dall'inizio**, non un ripensamento.
- **Nessuna stringa visibile all'utente scritta inline nel codice.** Tutti i
  testi passano dai file di localizzazione in `Resources/` (`it.lproj`,
  `en.lproj`).
- `GameEngine` non ha stringhe utente per definizione (non parla al giocatore).

## 3-bis. Eventi descrittivi, non prescrittivi (emerso in M1.5)

Il flusso di eventi che i livelli bassi (`GameWorld`) espongono ai livelli alti
(`UI`, `Audio`) deve essere **descrittivo** — dice *cosa è successo* ("il seat X
ha rilanciato a 40", "è uscito il flop") — e **mai prescrittivo** — non dice al
consumatore *cosa fare* ("suona questo", "mostra quella vista"). Così ogni
consumatore interpreta gli eventi come vuole, senza che il produttore ne conosca
o imponga il comportamento. Gli eventi sono **valori** (enum/struct `Sendable`),
neutri rispetto a UI/Audio. La distinzione **pubblico vs privato** si modella
con un'*audience* sull'evento e un *punto di vista* sull'iscrizione, così
l'informazione riservata (le hole card di un giocatore) è instradata solo a chi
ha diritto — coerente con la garanzia di informazione onesta di `GameEngine`.

## 4. Accessibilità (priorità architetturale)

- L'accessibilità **non è una feature finale ma un vincolo di progetto**, presente
  fin dalla prima vista.
- Principio guida: **"nessuno perde niente"** — l'esperienza per chi vede e per
  chi non vede deve essere piena per entrambi, senza che l'una penalizzi l'altra.
- **VoiceOver di prima classe:** ogni vista imposta accessibility identifier e
  label. La **pronuncia italiana** per VoiceOver è curata tramite le
  accessibility label.
- Approccio **audio-first:** il suono veicola informazione di gioco (non è
  decoro), a beneficio di tutti e in particolare di chi usa VoiceOver.
- **Pattern implementativi (emersi in M1.6):**
  - La **pronuncia fonetica italiana** dei termini poker inglesi vive nelle
    stringhe `it.lproj` ("reis", "blaind", "bàtton", "ol-in", "cek", "col",
    "tern"), non in codice: è la localizzazione a farla, e il TTS italiano li
    pronuncia correttamente. L'inglese `en.lproj` usa la grafia normale.
  - Gli **annunci VoiceOver dinamici** usano `UIAccessibility.post(.announcement)`
    avvolto in `#if canImport(UIKit)` (no-op sul host macOS, così il modulo `UI`
    compila per `swift test`).
  - **Annuncio con priorità: passare `NSAttributedString`, non `AttributedString`
    (lezione M-testing, D-027).** Per un annuncio interrompente si imposta
    `accessibilitySpeechAnnouncementPriority = .high` su un `AttributedString`, **ma
    l'argomento di `.announcement` va convertito con `NSAttributedString(...)`**:
    passando l'`AttributedString` Swift grezzo iOS lo **scarta in silenzio** e non
    si sente nulla (il bug che faceva pronunciare solo l'etichetta del bottone al
    tap). Utile anche differire il post di un runloop (`asyncAfter +0.1s`) quando
    parte dall'handler di un tap, mentre VoiceOver sta ancora processando
    l'attivazione.
  - **Non** applicare modificatori di accessibilità al contenitore più esterno di
    una schermata (`.accessibilityElement`/`.accessibilityIdentifier` su una
    ZStack/GeometryReader di root): collassa il sottoalbero in un solo elemento e
    nasconde gli identifier dei figli. Gli **identifier vanno sui leaf**.
  - **Gli annunci di showdown parlano di combinazioni e kicker rilevanti, mai di
    carte singole (D-045).** Allo showdown la sintesi VoiceOver comunica la
    **combinazione** ottenuta (più il **kicker** solo dove può decidere: coppia,
    doppia coppia, tris), **mai** l'elenco carta per carta — lo showdown è un momento
    drammatico, non una lezione di poker. Vale per **tutti i giochi**: una funzione
    pura condivisa (`SpeechMap.handDescription(category:bestFive:)`) rende la mano;
    le voci mp3 del croupier restano, cambia solo la sintesi che le segue.
  - **La selezione di un elemento in una griglia accessibile aggiorna lo stato ma non
    tocca il focus né la struttura del sottoalbero (D-046).** Selezionare/deselezionare
    un elemento navigabile (le carte del box di draw, e qualunque griglia futura)
    **aggiorna solo la sua accessibility label** (e annuncia il cambio come feedback
    interrompibile), **senza** spostare o intrappolare il focus e **senza** ristrutturare
    il sottoalbero: i segnali visivi di stato si commutano con `opacity`, non con
    inserimento/rimozione condizionale di viste, così l'elemento resta **un solo leaf
    stabile** e lo swipe VoiceOver scorre naturale come in una lista standard iOS.
  - **Una fase nuova di un gioco → interazione in un box modale con trappola
    d'accessibilità propria (D-044).** Quando un nuovo gioco introduce una **fase che
    il primo gioco non aveva** (come lo *scambio di carte* del Five-Card Draw), l'
    interazione dedicata a quella fase vive in un **box modale con la propria trappola
    di accessibilità** (sfondo `accessibilityHidden`, focus portato dentro all'apertura,
    ordine di lettura esplicito), **non** stipata nel layout principale del tavolo. Per
    una selezione multipla nel box (es. le carte da scartare): ogni elemento è un
    **pulsante VoiceOver** con label esplicita di contenuto **e stato** ("asso di picche,
    selezionato per lo scarto"), il tap **annuncia** il nuovo stato (interruzione
    deliberata via `announceLiveValue`), un limite superato è annunciato, e la conferma
    è **sempre attiva** con l'assenza di selezione come default sensato (niente
    "Annulla" ridondante se deselezionare tutto equivale).
  - **Un overlay modale deve intrappolare l'accessibilità (D-027).** Quando una
    finestra sovrapposta è aperta (box Raise, overlay di fine partita), il contenuto
    dietro va reso `.accessibilityHidden(true)`: altrimenti VoiceOver ci naviga
    sopra e confonde gli elementi di sfondo con quelli della finestra. Portare il
    **focus dentro** la finestra all'apertura (`@AccessibilityFocusState` +
    `onAppear`, deferito un runloop). Corollario: **non** risolvere un problema di
    annuncio *nascondendo controlli interattivi* a VoiceOver — un pulsante che serve
    all'utente deve restare agganciabile; si sistema l'annuncio, non si toglie il
    controllo.
  - La logica di presentazione (riduzione evento→stato, formattazione testo) va
    tenuta **pura** e fuori dalle viste SwiftUI, per essere unit-testabile.
  - **L'app espone una modalità VoiceOver propria, indipendente da iOS (D-034).**
    Uno stato osservabile (`AppVoiceOverMode`, persistito, default OFF) che l'utente
    controlla dalle impostazioni, **indipendente** dallo stato di iOS VoiceOver
    (attivabile a sistema spento, disattivabile a sistema acceso). Quando **ON**,
    **modula il ritmo di consumo del flusso di eventi lato UI**: il consumatore
    attende che il canale parlato (croupier + coda annunci) sia quieto prima di
    mostrare l'evento successivo, così occhio e orecchio camminano insieme. Quando
    **OFF**, ritmo interno veloce. **Mai** si modifica il produttore `SessionDriver`:
    la sincronizzazione è **solo lato consumatore** (il produttore resta puro).
  - **Chrome persistente riusabile (D-033).** Il pulsante Impostazioni e la
    schermata impostazioni vivono in un contenitore condiviso (`GameChrome`) che
    avvolge ogni schermata principale, non replicato per gioco/vista. La schermata
    impostazioni è una lista a sezioni pensata per **crescere**.
  - **Tutti gli annunci VoiceOver passano da una coda seriale con priorità e
    coordinamento (D-032).** Nel codice applicativo **nessuna chiamata diretta a
    `UIAccessibility.post`**: ogni annuncio passa dall'`AnnouncementQueue` (unico
    punto che posta, verificato da un test statico che scandisce i sorgenti). La
    coda **serializza senza troncare** (un annuncio iniziato finisce), assegna
    **priorità** (alta = personale/critico, mai droppato; media = info avversari;
    bassa = descrizione secondaria) e **droppa low/medium sotto backlog** per tenere
    l'alta puntuale, e si **coordina** con le sorgenti audio pre-registrate
    (`SpeechConductor`) come **un unico canale parlato** (la sintesi non parte mentre
    suona il croupier e viceversa). È **trasversale**: riusabile da ogni gioco e ogni
    parte parlata futura.
  - **mp3 previsto ma non ancora prodotto → fallback di sintesi dichiarato
    (D-030).** Quando la mappatura chiede un mp3 non ancora nel bundle, il sistema
    cade **automaticamente** su un **fallback di sintesi VoiceOver dichiarato nella
    mappatura stessa**, invece di tacere. Quando il file arriva, viene rilevato e
    usato, e il fallback si silenzia. Questo permette **produzione audio graduale**
    (nuove voci di croupier, nuove personalità di bot) senza rompere l'esperienza.
  - **Due categorie di voce → fallback diverso: informativa→sintesi, ambientale→
    silenzio (D-066).** Non tutte le voci sono uguali. Ogni voce parlata dichiara la
    sua **categoria**, che ne decide il fallback quando l'mp3 non è ancora prodotto:
    - **Informativa** (croupier: stato di gioco che il giocatore **deve** avere — turno,
      street, showdown, pot, ruolo, poste): fallback a **sintesi VoiceOver**, perché
      quell'informazione non può mancare.
    - **Ambientale** (commenti di colore dei bot, `vob_`: atmosfera, **non** informazione):
      fallback al **SILENZIO**, mai sintesi. Un colore mancante semplicemente non si sente;
      sintetizzarlo lo trasformerebbe in un **annuncio intrusivo** che interrompe l'ascolto
      del giocatore cieco. **Colore ≠ informazione.**
    La regola vive **sulla categoria** (`SoundCategory.fallsBackToSynthesis`, true solo per
    `.croupier`), così **ogni voce futura eredita il fallback giusto** dichiarando la sua
    categoria; il `SpeechConductor` la consulta. Vale per ogni voce futura del progetto.
  - **L'identità di un LUOGO, per il non vedente, vive nell'audio → ogni luogo nuovo ha la
    sua palette sonora PER COSTRUZIONE (D-067).** Il giocatore cieco l'identità di un casinò
    non la **vede** (marmo, feltro, colori): la **sente** — la voce del croupier e l'aria del
    posto. Perciò la **palette audio** (croupier + registro dei testi + ambient + colore dei
    bot) è un attributo del **LUOGO** (il casinò), **non del gioco**: un casinò ha **un solo**
    croupier, valido per **tutti** i suoi tavoli e ogni gioco futuro. Due luoghi diversi
    **devono** suonare diversi — stesse regole, voce e aria diverse — altrimenti per il non
    vedente sono lo stesso posto e la progressione narrativa svanisce ("nessuno perde niente"
    applicato all'identità). Implementazione: una **palette per casinò** (`CasinoAudio`)
    risolta **per dati** (registry per id, remap del croupier + fallback di registro + letti
    ambient + `vob_`); il **luogo di partenza è la palette IDENTITÀ/DEFAULT** (remap e override
    vuoti → comportamento invariato per costruzione, così la regressione è garantita), e un
    **luogo nuovo si aggiunge come dato** senza toccare le SpeechMap, il conductor o i director.
    Il croupier di un luogo nuovo cambia **voce E registro** (testi propri), non solo il file.
  - **Canale ambientale (colore dei bot) vs canale informativo: mai coprire l'informazione
    (D-068).** Il colore dei bot (`vob_`, categoria `.botVoice`, ambientale) e l'informazione
    di gioco (croupier + sintesi VoiceOver, informativa) sono **due cose diverse** e vanno
    tenute separate:
    - Il colore **non passa mai** dalla `AnnouncementQueue` come testo: è **audio**
      (`audio.play(.botVoice)`), non un annuncio. Solo l'**attribuzione informativa** di
      un'azione ("giocatore N rilancia") è annuncio.
    - Il colore **non deve sovrapporsi né interrompere** l'informazione **quando il giocatore
      sta ascoltando qualcosa che gli serve** (le proprie carte, il proprio turno, la
      conclusione del pot). Un colore che copre l'annuncio delle proprie carte è un **difetto
      grave di accessibilità**, non un dettaglio di missaggio. Il colore d'azione passa quindi
      dal `SpeechConductor`, che via `beginExternalSpeech` **attende la fine di un annuncio in
      corso** prima di suonare → serializzato con l'informazione, mai sopra.
    Regola: una voce ambientale che si accende vicino a informazione critica **cede il passo**
    (o tace); l'informazione non aspetta mai il colore.
  - **Annunci di ruolo personalizzati sul giocatore umano, non generici (D-031).**
    A inizio mano il croupier annuncia **solo il ruolo del giocatore umano** se ne ha
    uno (small blind / big blind / button), e resta **in silenzio** se non ne ha:
    parla solo se ha qualcosa da dire *specificamente a chi ascolta*, mai categorie
    astratte ("small blind, big blind") rivolte a nessuno.
  - **Più sorgenti vocali → per ogni evento UNA sola responsabile (D-029).** Quando
    coesistono più sorgenti che parlano (voci pre-registrate, sintesi VoiceOver,
    voci di caratteri), definisci una **mappatura autorevole** evento→sorgente come
    **funzione pura testabile** (`SpeechMap`) che dice, per ogni evento, chi parla:
    mp3 pre-registrato, sintesi, entrambi (mp3 **poi** sintesi per il contenuto non
    pre-registrabile), o nessuno. **Mai due sorgenti che dicono la stessa cosa.** Un
    unico **conduttore seriale** possiede le sorgenti parlanti e le riproduce una per
    volta (mp3 con completion reale → poi sintesi), così non si sovrappongono; e
    **de-duplica** le voci once-per-evento-logico (es. il pot: il produttore può
    emettere più `potAwarded` per i side pot — la voce va detta **una volta sola**).
  - **Voci semanticamente uniche per mano → deduplicate via lista dichiarata, non
    caso per caso (D-051).** La deduplicazione once-per-hand è una **regola generale**
    del `SpeechConductor`: una **lista dichiarata in un solo punto**
    (`SpeechConductor.oncePerHandVoices`) elenca le voci croupier che rappresentano un
    momento **semanticamente unico** della mano (showdown, pot, split, squalifica
    openers, mano decisiva, e ogni futura); il conductor le deduplica **automaticamente**
    (una ripetizione sopprime il lead croupier/fallback; una sintesi che varia per
    chiamata parla comunque). Per rendere una nuova voce once-per-hand la si **aggiunge
    alla lista** — niente logica ad hoc per evento. Corollario: un evento che ha **una
    sola** riga parlata dichiara croupier **+ fallback**, **non** anche una sintesi con
    lo stesso testo (o le due parlerebbero due volte — il bug di D-051).
  - **Due sistemi audio parlanti → domini separati, mai concorrenti (D-028,
    supera D-024).** Quando VoiceOver e voci pre-registrate (croupier/bot)
    coesistono, **non farli competere sullo stesso evento** e **non risolvere
    silenziandone uno** (fragile: `UIAccessibility.isVoiceOverRunning` all'avvio è
    `false` per qualche ms, poi scatta e zittisce definitivamente — così il
    croupier spariva a metà sessione). Assegna invece **domini di competenza
    disgiunti**: le voci pre-registrate coprono gli eventi **istituzionali** (e
    suonano sempre); VoiceOver copre il **personale del giocatore** e ciò che le
    prime non dicono. Nessun evento è annunciato da entrambi. Se possono cadere
    vicini nel tempo, **non sovrapporli**: una direzione sola (VoiceOver aspetta la
    fine della voce in corso), con un residuo tempo esposto dallo strato audio
    (`spokenAudioRemaining()`) e un ritardo puro/testabile (`SpeechCoordinator`).
    L'audio **non è mai indispensabile**: VoiceOver da solo deve sempre bastare per
    giocare (info coperte dal croupier restano leggibili on-demand dagli elementi
    accessibili). Come per il parlato (M1.6), la **mappatura evento→suoni è una
    funzione pura** separata dalla riproduzione; il modulo `Audio` resta neutro
    (suoni opachi + categorie), e la mappatura vive dove si vedono sia gli eventi
    sia `Audio` (cioè in `UI`), mai dentro `Audio`.
  - **Input numerico a incremento con annuncio istantaneo (pattern riusabile,
    emerso in M1.7 col box Raise, D-020).** Per un controllo che regola una cifra
    con `+`/`−` (rilancio a poker, ma anche puntata a blackjack/roulette in
    futuro): (a) la **curva di incremento è una funzione pura** separata e
    testabile; (b) lo stato tiene un **conteggio di step** come sorgente di
    verità, col valore derivato e clampato a un intervallo legale; (c) ogni
    pressione posta un annuncio VoiceOver del nuovo valore con **priorità alta
    interrompente** (via `NSAttributedString`, vedi la lezione sopra e D-027), così
    una raffica di clic annuncia solo l'ultimo valore senza accodarsi; (d) ordine di
    swipe esplicito
    (`−`, valore, `+`, all-in, poi conferma/annulla) e ogni elemento con
    identifier e label fonetica. Riusare questa forma per input analoghi.
  - **La pronuncia curata copre OGNI elemento UI accessibile, non solo le voci
    parlate (D-054).** La resa fonetica italiana dei termini poker vale per qualunque
    cosa VoiceOver legga: pulsanti, badge, etichette di stato, non solo le sintesi
    della `SpeechMap`. **Ogni accessibility label deve usare la chiave `.a11y`
    fonetica**, mai la stringa *visibile* inglese (che l'italiano leggerebbe male —
    "Raise"→"Ace"). `PhoneticsTests` non verifica solo il valore delle stringhe ma
    **scandisce i sorgenti UI** (guardiano statico sugli action bar) per assicurare che
    il codice cabli davvero le chiavi `.a11y` come label. Lista canonica dei termini in
    §4/D-049. È la seconda volta che lo stesso termine sfugge in un contesto diverso: il
    guardiano statico è la difesa strutturale contro il ripetersi.
  - **Pronuncia dei termini che contano: IPA, non grafemi indovinati (D-059).** Un grafema
    fonetico inventato (es. "reis" per *raise*) **non è una specifica affidabile di un suono**:
    la voce italiana di VoiceOver può leggerlo comunque sbagliato ("ace"), e **nessun test
    statico può *sentire* il TTS** — può solo verificare che *una* grafia sia presente (ecco
    perché "raise" ha attraversato tre sessioni). Per i termini la cui pronuncia conta e che
    falliscono sul device, si specifica la pronuncia con la **notazione IPA esatta**
    (`accessibilitySpeechPhoneticNotation` su un `AttributedString`, via il pattern
    `PokerSpeech`): l'IPA è la specifica standardizzata del suono, non può essere "indovinata
    sbagliata". Il guardiano allora pretende la **presenza dell'IPA** (cosa verificabile), non
    la plausibilità del grafema. **Catalogo canonico:** la pronuncia autorevole di *raise* è
    l'IPA **/ˈreɪz/** (`PokerSpeech.raiseIPA`); l'eventuale grafia `.a11y` ("reis") resta solo
    come fallback di spell-mode. **Diagnosi prima del fix:** se un termine legge male malgrado il
    verde, leggi `element.label` a runtime con un XCUITest per distinguere "label non applicata"
    da "grafia mispronunciata".
  - **Pulsante con termine parlato + valore dinamico: IPA sul termine, numero in un run a parte
    (D-059).** Quando la label di un pulsante mescola un termine da pronunciare via IPA e un
    valore dinamico (es. "Raise 40" → "reis a quaranta"), componi un `AttributedString` in **due
    run**: la parola con la notazione IPA, il valore come run **normale**. Così il numero è
    pronunciato dalla voce senza corrompere la pronuncia della parola, e l'IPA resta scoped al
    solo termine. Riusare questa forma per input analoghi con valore (blackjack, roulette).
  - **La resa fonetica NON si dichiara risolta senza verifica acustica sulla voce reale di
    destinazione (D-060).** Un test statico non può *sentire*: né un grafema inventato ("reis",
    "fould") né una notazione IPA vanno spediti perché "sembrano giusti a tavolino" — è così che
    lo stesso termine ha attraversato **tre** sessioni leggendo "ace"/"Fohold". Metodo canonico:
    **(1)** genera audio reale con la **voce di destinazione** (Alice it-IT, via
    `AVSpeechSynthesizer`) di più candidati (parola inglese piana, grafie, IPA); **(2)** fatti
    dire all'ascolto quale è giusto; **(3)** cabla la resa scelta; **(4)** rigenera il campione
    della label *così com'è nel codice* e conferma **byte-identità** al candidato approvato;
    **(5)** solo dopo l'OK acustico → rilascio. Preferire una **grafia piana verificata**
    all'IPA quando riproduce lo stesso suono (device-safe: nessuna dipendenza dal fatto che
    VoiceOver onori l'attributo IPA lungo il percorso SwiftUI). Il guardiano **pinna solo rese
    udite** (asserite esatte, byte-identiche al campione approvato); per i termini non ancora
    ascoltati fa da **rilevatore di modifica** senza dichiararli corretti, così un cambio
    costringe a ri-ascoltare. Diagnosi: se un termine legge male malgrado il verde, prima
    `element.label` a runtime (label applicata?), poi l'ascolto del campione (grafia giusta?).
    **Avvertenza sull'IPA (misurata, D-060 chiusura):** l'attributo IPA
    (`accessibilitySpeechPhoneticNotation` / `AVSpeechSynthesisIPANotationAttribute`) **è
    onorato dalla sintesi e ne cambia davvero la pronuncia** (verificato: `T` piano ≠ `T`+IPA;
    il contenuto dell'IPA conta; vale anche per termini nuovi tipo "Skypool") — **non** è
    indistinguibile dal testo piano. Ciò che **non** è mai stato verificato end-to-end è se
    **iOS VoiceOver sul telefono** onori quell'attributo quando arriva da una
    `.accessibilityLabel(Text(AttributedString))` di SwiftUI (il ponte app→VoiceOver, non l'IPA
    in sé). Perciò: **preferire sempre una grafia piana verificata all'orecchio** (device-safe);
    ricorrere all'IPA solo se nessuna grafia piana dà il suono voluto, e **verificarlo sul device
    reale** prima di considerarlo affidabile.
  - **Un annuncio contestuale dinamico non deve duplicare un pulsante visibile (D-055).**
    Se un controllo mostra e pronuncia già un'informazione (il pulsante "Call X" dice la
    cifra da chiamare quando VoiceOver ci arriva), **non** ripeterla in una sintesi
    contestuale: è ridondante e rischia di interrompere l'utente mentre esplora altro
    (es. le proprie carte). Il pulsante parla da sé; la sintesi tace su ciò che è già
    sullo schermo e agganciabile.
  - **Il ritmo adattivo con VoiceOver ON ha un timeout di salvaguardia (D-056).** Quando
    la UI attende la fine del canale parlato prima di avanzare (modalità VoiceOver
    dell'app ON, D-034), l'attesa **non è mai illimitata**: un tetto cumulativo
    (`SpokenChannelPacing.awaitQuiet`, ~3 s) fa **procedere comunque** la UI se il canale
    non si quieta (una completion audio persa, una notifica che non arriva). **L'usabilità
    reale ha precedenza sulla perfezione della sintesi**: meglio un breve sovrapporsi di
    annunci che una UI congelata che ruba una scelta all'utente. In parallelo, lo strato
    audio **garantisce** che una completion (di cui un consumatore attende la sequenza)
    scatti sempre — delegate di fine, `play()` fallito, o timeout — così la causa a monte
    non si presenta.
  - **Ogni schermata e ogni modale dichiara il proprio primo elemento di focus VoiceOver
    (D-057).** A ogni cambio significativo di visualizzazione (schermata o modale/overlay)
    il focus VoiceOver **atterra esplicitamente** sul primo elemento, così non resta
    stranito su un elemento della schermata precedente (swipe → "tonk" di fine corsa).
    Pattern riusabile `.voiceOverFocusLanding()`: `.screenChanged` per ri-scansionare +
    `@AccessibilityFocusState` per portare il focus (deferito un runloop). Il
    `.screenChanged` è **instradato dalla `AnnouncementQueue`** (unico punto che posta a
    VoiceOver, D-032). Va **prima** degli eventuali annunci contestuali della coda (canale
    separato: non competono).
  - **Le voci caratteriali dei bot si scelgono dallo stato ATTUALE del tavolo, mai da uno
    snapshot congelato (D-058).** Le `vob_` (e ogni voce/reazione di un partecipante) sono
    selezionate **a ogni scelta** consultando i posti realmente in gioco nella mano
    corrente (`handBegan.seats`) e quelli bustati (`.playerBusted`), **non** una lista
    calcolata all'inizio della sessione: `handEnded.chips` continua a elencare i bustati a
    0, quindi un confronto con uno start stantio li farebbe "reagire" per sempre. **Un bot
    bustato non emette più alcuna voce.**
  - **Ogni meccanica di accelerazione/progressione di sessione scatta sul CONTEGGIO DELLE
    MANI GIOCATE, MAI su un cronometro (regola permanente, D-064).** Blind escalation, ante
    progressivo, mano decisiva, e qualunque meccanica futura che dipenda dal "quanto è durata"
    la sessione, deve chiavizzarsi sul **numero di mani giocate**, non sui minuti trascorsi.
    Motivazione di **accessibilità**: un giocatore cieco (VoiceOver, audio-first) impiega più
    **tempo reale** per la stessa quantità di gioco; una soglia a tempo lo punirebbe per la
    sua velocità di ascolto invece che per le sue scelte al tavolo. È il principio "nessuno
    perde niente" applicato al **tempo**. Le meccaniche di sessione vivono in **GameWorld**
    (non nel motore) come **parametri configurabili del tavolo**, riusabili da ogni gioco
    (es. `StakeEscalation`, D-064), non feature prigioniere di un singolo gioco.
  - **Il PUNTEGGIO è logica di gioco (nel motore, puro); la STRUTTURA di partita è meccanica di
    sessione (in GameWorld) (regola permanente, D-071).** Come il poker distingue *mano* e *sessione*,
    un gioco a punti distingue *mano* e *partita*: **calcolare i punti di una mano dato lo stato finale**
    è una funzione **pura e testabile** che vive nel `GameEngine` (es. `MachiavelliScoring`), mentre la
    **soglia di vittoria**, l'accumulo dei totali e la sequenza di mani sono una **meccanica di sessione**
    che vive nel driver di `GameWorld` (accanto a boost/ante/`StakeEscalation`). La soglia è un **parametro
    configurabile del tavolo**. Motivazione di game design: il punteggio dà **uno scopo a chi non vince la
    mano** (ogni progresso conta, ogni carta rimasta pesa) e toglie a una singola distribuzione il peso di
    decidere tutto; va calibrato per una partita **breve e densa** (poche mani), su **dati misurati**, non
    a intuito.
  - **Un solo PREDICATO di legalità, nel motore, interrogato da interfacce diverse
    (regola permanente, D-070).** Quando un gioco ammette due modi di esprimere la stessa
    mossa — tipicamente uno pensato per il **cieco** (comporre in un box, sbloccare
    *Conferma* quando la selezione è valida) e uno per il **vedente** (trascinare sul
    tavolo, sbloccare *fine turno* quando il tavolo è valido) — la **validità deve vivere
    in un unico predicato puro nel `GameEngine`**, mai duplicata nella UI. Motivazione di
    accessibilità, non di eleganza: due implementazioni della stessa regola **divergono al
    primo bug**, e il vedente e il non vedente finirebbero a giocare due giochi
    leggermente diversi. Il motore non deve sapere **chi** gioca né **come** esprime la
    mossa. (Machiavelli: `MachiavelliRules.classify`/`isValidTable`.)
  - **Lo stato di lavoro di una mossa è IPOTETICO finché non confermato (D-070).** Se la
    UII permette di costruire una mossa per gradi (selezionare/deselezionare, comporre,
    rimaneggiare), il motore deve saper **valutare una trasformazione proposta senza
    applicarla** e applicarla **solo su conferma** (`evaluate` vs `apply`). È ciò che rende
    il box "un posto sicuro dove sbagliare", e vale **molto più per un cieco** che esplora
    a swipe che per un vedente che trascina. Corollario: quando una regola ammette di
    **cambiare idea nello stesso turno** (rimuovere una carta già calata e ricomporla),
    la validazione va fatta contro lo **snapshot d'inizio turno**, non contro lo stato
    corrente, così **la stessa carta può muoversi più volte** e **solo lo stato finale**
    conta. Un esploratore lento non è mai punito per la lentezza dell'esplorazione, solo
    per la qualità della mossa finale — accessibilità travestita da regola di gioco.
  - **La ricerca dei bot deve essere INTERROMPIBILE e a profondità ADATTIVA, mai a
    profondità fissa che possa sforare (D-070).** Un bot con un budget di riflessione
    (di tempo e/o di nodi) deve tenere sempre una **mossa migliore valida** e restituirla
    **nell'istante** in cui il budget scade, con lavoro **per-nodo limitato** così l'overrun
    è trascurabile. Il **budget di tempo può essere un tratto di CARATTERE** (uno pensa in
    fretta, un altro medita): la differenza va **resa**, non nascosta. Determinismo e tempo
    si riconciliano così: il risultato è deterministico dato **seed + budget di nodi** (i
    test pinnano i nodi); sotto un puro tetto di tempo la profondità raggiunta varia per
    macchina ed è **intenzionale** (produzione adattiva).
  - **L'attesa deve essere UDIBILE (D-070).** Se un bot può deliberare per secondi, per un
    cieco quel silenzio è indistinguibile da un gioco bloccato. Il motore/driver deve
    emettere un **evento esplicito** che dichiara che un bot **sta pensando** (e uno che ha
    finito), **descrittivo non prescrittivo** (dichiara il fatto + una durata attesa come
    *hint* di carattere, non ordina un suono), così UI e audio futuri possano riempire il
    silenzio. È lo stesso spirito dei safeguard sulle continuation del poker (D-056).
    **Realizzazione (D-072):** l'attesa udibile va riempita sul **canale AMBIENTALE**
    (es. la musica che passa a una sezione "thinking" e torna), **mai** con un annuncio
    della `AnnouncementQueue` che interromperebbe l'ascolto del cieco; e il segnale
    dichiara "sta pensando" **senza rivelare cosa il bot stia trovando**.
  - **Il sistema DESCRIVE lo stato, non CONSIGLIA la mossa (regola permanente, D-072).**
    Ogni lettura dinamica che accompagna la costruzione di una mossa (il pool di una
    selezione, un contatore, uno stato parziale) deve dare al non vedente **esattamente
    ciò che il vedente vede**, e **nulla di più**. "Quattro carte selezionate, scala di
    cuori incompleta" è **descrizione** (il vedente lo vede nel pool). "Manca il sette per
    completarla" è **suggerimento**: giocherebbe la partita **al posto** del giocatore,
    cosa che al vedente non capita. Quando lo stato diventa un **fatto compiuto** (la
    selezione è una combinazione legale, il pulsante si sblocca) l'annuncio va dato senza
    esitazione ("scala di cuori dal cinque al nove, valida") — è la stessa informazione
    che il vedente riceve dal pulsante. Il confine è: **descrivere sì, consigliare no.**
  - **Il letto AMBIENTALE può dipendere dal CARICO COGNITIVO del gioco, non solo
    dall'identità del luogo (regola permanente, D-073).** La palette sonora resta un
    attributo del **casinò** (D-067), ma il **letto** può essere declinato **per gioco**
    quando i giochi di uno stesso posto hanno carico cognitivo opposto. Motivazione
    **funzionale, non estetica, e di accessibilità**: il giocatore non vedente gioca
    **sul canale audio**, e un gioco di **lavoro cognitivo lungo e continuo** (comporre,
    scorrere decine di carte, tenere a mente combinazioni — es. Machiavelli) usa
    l'**ascolto** come strumento di gioco; una **musica strutturata** (sviluppo tematico,
    variazione) sotto quel lavoro non è atmosfera ma **concorrenza diretta** sul canale
    che sta usando. Un gioco di **attese brevi** (es. poker) invece la accoglie. Il letto
    "cognitivo" giusto è **ambientale e ritmico** (dà presenza senza chiedere attenzione).
    Implementazione: un **override per-gioco** della palette (`CasinoAudio.ambient(forGame:)`),
    default = letto del casinò; i casinò che non lo dichiarano restano invariati.
  - **Uno STALLO deve sempre dichiarare la propria ragione al non vedente (regola
    permanente, D-073).** Quando un'azione (un terminale, un pulsante) è **bloccata** da
    uno stato che il vedente **vede** ma il cieco no, il sistema deve rendere quella
    ragione **udibile** — sul punto in cui il giocatore scopre di essere fermo (la hint
    del pulsante quando ci arriva a swipe, e/o un annuncio quando lo tocca). Vale il
    confine **descrivi-non-consigliare**: dichiarare *cosa* non sta in piedi ("il tavolo
    ha una combinazione incompleta: scala di picche") è descrizione (la stessa cosa che
    il vedente vede); dire *come* ripararlo (quale carta manca, dove prenderla) è
    consiglio, e non si dà. Un pulsante bloccato preferibilmente **non si disabilita**
    (resta agganciabile e, toccato, spiega): un pulsante disabilitato che "non fa niente"
    è la **peggior forma di stallo** per il cieco, che non sa nemmeno cosa cercare.
  - **Il costo di un turno per un non vedente si misura in LAVORO DI NAVIGAZIONE, non in
    eventi (regola permanente, D-075).** In un gioco a forte carico cognitivo per turno
    (es. Machiavelli: scorrere una catena di decine di carte, selezionare, comporre,
    confermare), un turno umano navigato con VoiceOver costa in **tempo reale** molte
    volte un turno di un gioco a decisione breve (poker). Contare i turni li tratta tutti
    uguali; il **tempo** no. Perciò: **non stimare la durata di un gioco contando gli
    eventi/turni**, e **non fidarsi delle misure tra BOT** (che ignorano il costo di
    navigazione umano). Stimare in **lavoro di navigazione reale** e **convalidare con un
    test umano** prima di consolidare una meccanica che dipende dalla durata. È il motivo
    per cui la struttura mano↔partita del Machiavelli (D-071), calibrata tra bot, è stata
    **ribaltata** dopo il primo test reale (D-075): una mano sola non era poco, era già
    lunga. È "nessuno perde niente" applicato alla **stima della durata**.
  - **Per chi naviga a SWIPE, una struttura LINEARE è più leggibile di una griglia
    (regola permanente, D-074).** Il gesto di VoiceOver è **lineare** (swipe avanti/
    indietro lungo una sequenza); quando il contenuto è una **griglia** (righe che
    entrano ed escono dalla vista mentre si scorre), il giocatore deve **tradurre** tra
    un gesto lineare e una struttura bidimensionale, e in uno stato grande (decine di
    carte) **si perde**. Preferire una **sequenza pura** (un nastro): il gesto e la
    struttura coincidono, nessuna traduzione. E la sequenza può **portare la struttura
    con sé** intercalando **divisori titolati** (es. nel box del Machiavelli: mano →
    divisore "tavolo" → per ogni combinazione il suo divisore col titolo, poi le sue
    carte), così l'organizzazione **arriva mentre si scorre** invece di doverla
    ricostruire a memoria. Vale con la stabilità del sottoalbero (D-052): la struttura
    del nastro sia **fissa** e la selezione commuti per opacity, mai per inserimento.
  - **Layout come ACCESSIBILITÀ, non solo estetica (D-074).** L'**ordine di lettura** di
    VoiceOver segue le **posizioni sullo schermo**: allineare elementi affini su **una
    linea** (es. i knob di bordo tavolo, tutti in fondo) li rende **consecutivi** nella
    navigazione a swipe e **vicini** a ciò che sta loro accanto (i pulsanti d'azione), così
    il non vedente li raggiunge **subito** invece di attraversare mezza interfaccia.
    Verticalizzare in colonne per allineare i knob è quindi una scelta di **accessibilità
    che passa dal layout**, non dagli annunci.
  - **Marcatore di ZONA per stati grandi navigati a swipe (pattern accessibilità, D-072).**
    Quando un'interfaccia ha due zone tra cui il non vedente si muove a lungo (es. la metà
    "catena" e la metà "pool" del box di composizione), **una zona marca esplicitamente lo
    stato dei suoi elementi e l'altra no**, così dopo decine di swipe il giocatore sa **in
    quale zona è** senza doverlo ricordare (nel box: le carte del pool si annunciano
    "selezionata", quelle della catena no). Il vedente ottiene la stessa informazione dalla
    **posizione sullo schermo**: è **parità, non aiuto**. Vale con la stabilità del
    sottoalbero (D-046/D-052): il marcatore sta nella zona-pool, **non** nella label della
    catena, che resta costante così la selezione non ristruttura né sposta il focus.
  - **Interrogazione A COMANDO di uno stato pubblico troppo grande da ricordare (pattern
    permanente, D-078).** Quando lo stato pubblico rilevante è **troppo esteso** per tenerlo
    a mente (le carte scoperte di **ogni** avversario nello Stud: due avversari × fino a
    quattro carte + le proprie, molto più del board condiviso del Texas), il vedente lo tiene
    **con lo sguardo**, tutto insieme, a colpo d'occhio. Per dare al non vedente la stessa
    presa, **due meccanismi complementari**: (a) **si ANNUNCIA ogni cambiamento mentre
    avviene** (ogni carta scoperta è annunciata quando è distribuita — parità col vedente che
    la **vede apparire**); (b) lo **stato corrente è INTERROGABILE A COMANDO** su un elemento
    accessibile dedicato (nello Stud, il badge di ogni avversario legge, allo swipe, il suo
    **tabellone corrente**: "il Professore, scoperte: re di cuori, dieci di picche"), che è la
    **memoria** che il vedente ha con lo sguardo — restituita su richiesta, così non serve
    ricordare. La label si **deriva dallo stato corrente**, mai da uno snapshot congelato
    (spirito D-058). E vale il confine inviolabile: **si DESCRIVE lo stato pubblico, non si
    CONSIGLIA la mossa** — "ha scoperti re, dieci e sette di cuori" è descrizione (ciò che il
    vedente vede); "potrebbe avere un colore" è suggerimento e non si fa mai. Senza questa
    interrogazione il non vedente giocherebbe uno Stud **mutilato**: è la condizione di
    esistenza del gioco, non una rifinitura.

- **Un elemento accessibile espone PER PRIMO ciò che serve più spesso (principio
  permanente, D-083).** Quando un elemento raccoglie più informazioni, l'ordine non è
  neutro: chi naviga a swipe **paga il preambolo a ogni interrogazione**. Se un dato è
  consultato molte volte per mano (le carte scoperte di un avversario nello Stud: è il
  cuore strategico del gioco) e un altro serve di rado (nome, fiches, stato), fonderli in
  un unico elemento significa far riascoltare il secondo ogni volta che serve il primo —
  una tassa che il vedente non paga, perché lui **coglie con lo sguardo** solo ciò che gli
  interessa. **Regola:** separa in elementi distinti e **ordina per frequenza d'uso**
  (`.accessibilitySortPriority`), mettendo davanti l'informazione ad alta frequenza.
  L'**identità** (di chi è questo dato) non è un preambolo e può restare in testa quando
  senza di essa il dato è inutile; **stato, quantità ed etichette descrittive** sono
  preambolo e vanno nell'elemento secondario. Vale per ogni gioco presente e futuro; il
  criterio è "quante volte per mano viene letto", non "quanto è importante".

- **Quando l'ORDINE fra canale audio e canale parlato porta informazione, va reso ESPLICITO —
  mai affidato al tempo (principio permanente, D-085).** Un effetto sonoro che rivela un esito
  (il colpo di vittoria/sconfitta, un jingle di fine partita) **non è missaggio: è informazione**.
  Se lo suona un consumatore parallelo con orologio proprio mentre la riga che dice *cosa è
  successo* è in coda, l'effetto **spoilera il risultato** — e nessuna taratura di volumi o ritardi
  lo risolve, perché i due canali non sono ordinati fra loro. **Regola:** un cue il cui significato
  dipende dall'ordine va **sequenziato sullo stesso canale** dell'annuncio a cui si riferisce (nel
  progetto: `SpeechConductor.say(trailing:)`, che lo suona alla completion della riga), così
  l'ordine è garantito **per costruzione**. Corollario: se la riga viene droppata, **il cue suona
  comunque** — nessuno resta senza. Un cue puramente atmosferico (ambient, colore) non ha questo
  vincolo e può restare parallelo.
- **Chi governa una coda deve governarla DOVE il backlog si forma davvero (D-085).** Priorità e
  drop su una coda servono a nulla se un anello **a monte** la alimenta un elemento alla volta: la
  coda resta vuota, sembra sana, e l'accumulo avviene nell'anello a monte, invisibile e illimitato.
  **Regola:** il budget si misura e si applica sul **canale intero** (tutti gli anelli in serie),
  non sull'ultimo. E attenzione a **riusare la regola di drop di un anello in un altro senza
  ricontrollarne l'INVARIANTE**: "non droppare mai la testa" è giusto dove la testa è l'elemento in
  riproduzione, ed è **sbagliato** dove l'elemento in riproduzione è già stato rimosso — lì rende
  quasi tutto non droppabile e il budget non morde (successo davvero, misurato).
- **Un tetto di attesa fisso non può distinguere narrazione onesta da un blocco (D-085).** Lo stesso
  numero deve servire due scopi opposti — coprire il parlato legittimo più lungo e liberare presto
  la UI se qualcosa si è piantato — e non può. **Regola:** dimensionare l'attesa su **quanto il
  canale dichiara di dovere ancora** (con pavimento e tetto duro): la narrazione vera viene attesa
  perché la stima è grande, un canale piantato — che non dichiara nulla — scatta subito. Resta
  fermo che l'attesa è un **backstop anti-freeze, non un budget di parlato**, e che **la
  possibilità di agire del giocatore batte la perfezione della sintesi**.
- **Abbandonare deve essere possibile e avere un COSTO, non essere impedito (D-086).** Un'azione di
  uscita (alzarsi dal tavolo) non si differisce alla fine di un'unità di gioco: si concede subito,
  con le conseguenze naturali dell'abbandono. Se le conseguenze cadono già fuori dal motore — le
  fiches impegnate sono **già** dedotte dallo stack, un premio è **già** condizionato a un traguardo
  non raggiunto — allora **l'economia si concilia da sola** e non serve alcun caso speciale: prima
  di aggiungerne uno, verificare se la regola esistente non produca già l'esito giusto.
- **Un numero detto ad alta voce dev'essere quello VERO, o non va detto (D-087).** In un annuncio
  accessibile un importo sbagliato è peggio di un importo assente: il giocatore non vedente non ha
  modo di correggerlo con lo sguardo. Prima di leggere una cifra presa da un evento, verificare che
  quell'evento porti davvero la grandezza che il giocatore capirà (nel progetto: un piatto è
  spezzato in un evento **per livello di contribuzione**, quindi nessun singolo `potAwarded` è "ciò
  che hai vinto" — la cifra giusta è la variazione reale dello stack).

- **Prima di indagare la PRONUNCIA di una parola, verificare la sua ORTOGRAFIA (D-088).** "Viene
  letta male" ha due cause possibili con soluzioni opposte: la stringa contiene la parola sbagliata,
  oppure la voce pronuncia male la parola giusta. La prima si accerta con un `grep` e si corregge in
  un minuto; la seconda costa un giro completo di campioni, ascolto e cablaggio (D-060). **Ordine
  obbligatorio: (1) la stringa dice la parola giusta? (2) solo allora, la voce la pronuncia bene?**
  Corollario: quando la grafia approvata all'orecchio risulta essere **la parola corretta**, è
  l'esito migliore — piana, device-safe, senza dipendere dal percorso IPA→VoiceOver mai verificato.

- **Un annuncio non ripete ciò che il giocatore sa PER STRUTTURA DEL GIOCO, e non spezza un
  insieme che il vedente percepisce unitariamente (principio permanente, D-089).** Due prove da
  fare su ogni riga parlata: *(1)* **lo sta già sapendo?** — se l'informazione discende dalle regole
  (nello Stud una carta scoperta è scoperta; una carta comune è di tutti), ribadirla a ogni lettura
  è verbosità, non accessibilità; *(2)* **sta spezzando un insieme?** — se il vedente coglie qualcosa
  *in un colpo d'occhio* (la propria mano), la resa parlata dev'essere **una sola lettura continua**,
  non blocchi separati da preamboli. Un preambolo si paga a **ogni** interrogazione, e la parità
  vedente/non vedente si misura sull'esperienza, non sul contenuto trasmesso. **Corollario:** una
  distinzione tolta dalla lettura principale non va **soppressa** ma **spostata** su un elemento
  proprio, raggiungibile a richiesta (D-083) — si separa per frequenza d'uso, non si butta.
- **Quando il contenuto CRESCE durante la partita, la dimensione deve seguire lo spazio (D-089).**
  Un layout a carte di dimensione fissa è corretto finché il numero di elementi è fisso; in un gioco
  dove cresce (Stud: quattro scoperte per avversario più sette carte proprie) sborda **con
  certezza**, e su un telefono prima di quanto si stimi. **Regola:** usare un contenitore che prova
  dimensioni decrescenti (`ViewThatFits`) con **un'ultima candidata piccola e non scalata**, così il
  contenimento è **strutturalmente garantito** e non affidato alla taratura. E quando si esce dallo
  scaling automatico per ottenere l'adattamento, **ripristinare esplicitamente il Dynamic Type**
  (candidate scalate + pavimento fisso): riparare il layout non deve costare l'accessibilità che il
  layout serviva.

- **In un gioco VELOCE, la compattezza dell'annuncio è un requisito di accessibilità, non una
  rifinitura (principio permanente, D-091).** Il costo di un annuncio non si giudica in assoluto ma
  **contro il ritmo del gioco**: lo stesso carico che va benissimo in una mano di poker — decine di
  righe, decine di secondi — trasforma un gioco da pochi secondi a mano (blackjack, e domani la
  roulette) in una **versione lenta del gioco veloce**, dove il vedente corre e il non vedente
  cammina. È "nessuno perde niente" applicato al **ritmo**. Regole operative:
  *(a)* **definisci l'annuncio essenziale come l'informazione MINIMA PER DECIDERE** (al blackjack:
  il proprio totale e la scoperta del banco — una riga breve), e sposta tutto il resto su
  **elementi interrogabili** (D-083/D-078), che è la memoria che il vedente ha con lo sguardo;
  *(b)* **ciò che il vedente coglie in un colpo d'occhio arriva come UN SOLO evento**, non come una
  coda (la distribuzione di due carte più la scoperta del banco è un fatto, non quattro);
  *(c)* **non pronunciare ciò che non può cambiare una decisione** — al blackjack il **seme** non
  influenza né un totale né un pagamento né una mossa legale, quindi non viaggia nella riga che si
  sente a ogni mano, pur restando visibile e interrogabile;
  *(d)* **misura, non stimare** (D-075/D-084), e tieni il risultato con un test che pinna sia il
  **rapporto** contro un gioco già esistente sia un **tetto assoluto**.
- **Una misura di ciò che il giocatore SENTE va fatta sul testo reso davvero (D-091).** Sotto
  `swift test` non esiste bundle e la localizzazione **ricade sulla chiave**: una misura di lunghezza
  del parlato fatta così misura i **nomi degli identificatori**, non l'italiano, e può sbagliare di
  molto (successo davvero: 8,36 s/mano contro i 6,14 reali). Regola: dare alla funzione di rendering
  una **cucitura di localizzazione** iniettabile e far rendere al test le stringhe **lette da disco**;
  e quando una metrica non si può rendere onesta, misurarla in un'unità che **non dipende dal
  bundle** (le righe, non i caratteri).
- **Il sistema descrive lo stato anche quando esiste una strategia ottimale NOTA (D-091).** Il
  confine descrivi-non-consigliare (D-072) è più esposto in un gioco che ha una soluzione pubblicata
  e banale da implementare: al blackjack la strategia di base è tabellare, e sussurrarla al non
  vedente sarebbe costato tre righe. Non si fa. «Sedici, il banco mostra dieci» è descrizione;
  «conviene chiedere carta» è consiglio, e il vedente non riceve alcun suggerimento. Difesa
  strutturale: un **guardiano che scandisce le stringhe spedite** cercando il lessico del consiglio,
  e un secondo che scandisce le **righe rese davvero**.
- **Un gioco contro il BANCO non riusa le astrazioni pensate per un contesto fra giocatori (D-090).**
  Quando il giocatore affronta la casa e non altri giocatori, cadono per costruzione: la matematica
  del piatto conteso (`PotMath` — non c'è nulla da spartire, il pagamento è un moltiplicatore), i
  **bot** e le dimensioni di `Personality` (che descrivono un comportamento verso **avversari**: al
  banco non c'è nessuno da leggere, e il banco non è un avversario ma una **regola** nel motore), e
  l'anello di posti che ciclano. Resta invece lo scheletro provato — value type, `apply` che valida e
  muta, **tutta** la progressione in un solo punto. Riusare per abitudine un'astrazione il cui
  soggetto non esiste è il modo più rapido di portarsi dietro complessità senza valore.
- **Un elemento che SCOMPARE per effetto di un'azione deve dichiarare dove va il focus (D-092).**
  L'atterraggio del focus (`voiceOverFocusLanding()`, D-057) copre l'**apparizione**, ed è tutto ciò
  che può coprire: vive su `onAppear`. Ma tutti i tavoli presentano i loro box **sopra** un contenuto
  che non viene mai rimosso dall'albero — è solo `accessibilityHidden` — quindi alla **chiusura** del
  box non appare nulla, non riparte nulla, e il cursore resta su un pulsante che non esiste più. Il
  vedente non se ne accorge (guarda altrove); il non vedente è **bloccato nel vuoto** e deve
  rifocalizzare a mano. Regola: ogni percorso di chiusura dichiara la destinazione, e la dichiara
  nel `didSet` della proprietà del box, così un percorso aggiunto domani (annulla, tap sullo sfondo)
  non può dimenticarsene. La destinazione è l'elemento che **serve subito dopo**, non il primo della
  schermata. Si posta `.layoutChanged`, **non** `.screenChanged`: la schermata non è cambiata, ne è
  cambiata una parte — un re-scan completo ri-annuncerebbe il tavolo a ogni mano.
- **Il canale parlato ha un budget: aggiungere annunci a un canale saturo non aggiunge informazione,
  la SCAMBIA (D-094).** Oltre il budget (D-085) il canale scarta per priorità, quindi una riga in più
  ne fa cadere un'altra. Perciò, prima di arricchire la narrazione di un tavolo, **misurare il carico
  attuale** in righe e secondi parlati per mano — e misurarlo **reso davvero** (D-093). Se il canale
  è già oltre budget, la leva giusta non è il budget (tarato su misure reali sul device) né una nuova
  riga, ma l'**ordine di cedimento**: dare priorità più bassa a ciò che è rumoroso, ripetitivo,
  visibile a schermo e ri-derivabile, e più alta a ciò su cui il gioco si decide. È l'unico
  intervento a **costo zero**: nessuna riga aggiunta, nessun secondo in più.
- **La priorità di una riga la decide la MAPPA, non il punto di consegna (D-094).** La mappa
  evento→voce è l'autorità (D-029); un `priority:` cablato al call site la scavalca in silenzio e
  rende inerte ogni futura ricalibrazione. Se una riga ha bisogno di una priorità diversa, si cambia
  nella mappa.
- **Due canali che parlano nello stesso istante danno MENO di uno (D-096).** Ci sono tre modi di far
  arrivare una parola: l'**annuncio** in coda, la **lettura dell'elemento su cui atterra il focus**, e
  il **suono**. D-055 vietava già a un annuncio di duplicare un pulsante che parla da sé; la stessa
  regola vale sull'asse del **tempo**: due canali che dicono cose **diverse** nello stesso istante non
  danno due informazioni, la seconda **tronca** la prima. Quando si aggiunge un atterraggio di focus o
  un annuncio, chiedersi sempre **cosa altro sta parlando in quel momento**. In particolare:
  `.screenChanged` **interrompe** il parlato in corso, `.layoutChanged` no (D-092) — quindi una
  modale che si apre con focus landing va aperta **solo a canale quieto**, o taglierà a metà frase
  ciò che stava spiegando il momento precedente.
- **L'ordine di lettura di una schermata si DICHIARA (D-096).** Lasciato alla geometria, un contenuto
  di chrome in cima (badge, impostazioni, uscita) si infila **in mezzo** al percorso di gioco: il non
  vedente attraversa mezza interfaccia tra il sapere cosa ha in mano e il poterci fare qualcosa. Ogni
  schermata di gioco assegna priorità esplicite a **tutti** i suoi elementi, nell'ordine in cui il
  giro si gioca. Le priorità vanno sui **leaf** (D-019): applicarle a un contenitore che non è esso
  stesso un elemento non è garantito propagarsi, e collassare il contenitore per forzarlo è la
  trappola di D-019.

## 5. Testabilità

- La logica pura (`GameEngine`, e in prospettiva `GameWorld`) deve essere
  testabile in isolamento, senza UI.
- I test del package stanno in `Tests/…` ed eseguono con `swift test`.
- Le sorgenti di casualità (es. mescolata del mazzo) devono essere
  **deterministiche e seedabili** per rendere i test riproducibili.
- **Il motore è deterministico rispetto al seed; i test iniettano seed fissi; la
  produzione genera seed casuali reali a ogni nuova mano (D-047).** La regola di
  cui sopra vale per il **motore** e per i **test**. In **produzione**, però, il
  seme di ogni mano va **rigenerato da una fonte di sistema reale**
  (`SystemRandomNumberGenerator` / `UInt64.random(...)`) **a livello di driver di
  sessione** (`SessionDriver`/`DrawSessionDriver` con `seed: UInt64? = nil` →
  casuale per-mano), così ogni partita, ogni mano e ogni sessione sono diverse. Un
  seed **costante cablato** propagato in produzione (tipicamente da un view model o
  una schermata) è un bug **silenzioso**: i test — che *devono* usare seed fissi —
  restano verdi e lo mascherano. Verificare sempre che ogni `seed:` non-di-test sia
  genuinamente casuale.

## 6. Domini di gioco (ordine previsto)

Il primo gioco è **Texas Hold'em No Limit**. A seguire: **Omaha**, **Five-Card
Draw**, **Seven-Card Stud**, poi **Blackjack** e **Roulette**. Temi trasversali
e continui: avversari con **caratteri**, **progressione tra casinò**,
accessibilità e localizzazione. Vedi [`ROADMAP.md`](ROADMAP.md).

## 7. Git e rilascio

- Si lavora su `main`. Commit/push solo quando richiesto dall'utente.
- Messaggi di commit chiusi con la riga di co-autore Claude come da prassi della
  sessione.
- Il signing e l'upload TestFlight passano da Fastlane Match e dalle lane
  `setup_signing` / `testflight_upload` (dettagli in [`README.md`](README.md)).
- **Ogni flag di modalità test/debug deve essere ben visibile, temporaneo e tracciato
  fino alla rimozione (D-050).** Un flag che altera il comportamento per il testing (es.
  `DebugFlags.freePlay`) va: (a) definito in un punto **evidente** con intestazione/commenti
  che lo marcano "⚠️ TEMPORANEO — rimuovere prima del rilascio pubblico"; (b) reso **visibile
  a runtime** con un indicatore non invasivo quando attivo (badge nel chrome, con label
  VoiceOver); (c) **elencato nel README** nella sezione "Modalità di sviluppo attualmente
  attive" **finché non viene rimosso**. I test che coprono il comportamento **reale** (non
  quello di debug) devono disattivare esplicitamente il flag, così restano validi dopo la
  rimozione.

## 8. Economia di sessione

- **Abbandonare un tavolo di POKER in anticipo forfeita parte dello stack; il BLACKJACK no (D-099).**
  Un tavolo di poker ha una fine naturale — bustare tutti gli avversari vince la partita — quindi
  alzarsi prima è lasciare una partita non finita e costa: si tiene una **frazione** dello stack in
  base a **quanto bene** si stava andando (rapporto tra il proprio stack e quello degli avversari vivi;
  pavimento del 50% se se n'è eliminato almeno uno; 100% se si domina ≥2×). Il Blackjack **non** ha una
  fine del genere (si gioca contro il banco finché si vuole), quindi alzarsi è il modo normale di
  smettere e si tiene **tutto**. La regola vive in GameWorld (`EarlyLeaveRetention`), è pura e
  **casino-agnostica** (una frazione, non un valore assoluto → le poste dei casinò non cambiano nulla),
  e si applica **solo** all'abbandono volontario (`requestLeave`), mai alla fine naturale. Il
  Machiavelli ha la sua regola propria (rimborso, D-075) e non usa questa.

- **Un'iniezione economica DENTRO una sessione di poker non è mai neutra (principio
  permanente, D-079).** Aggiungere fiches a un giocatore *durante* la partita — un premio,
  un bonus, un rimborso in-play — cambia il suo **stack**, e lo stack è una **leva
  strategica**, non un semplice contatore: **i bot lo vedono** (il `BotContext` redatto porta
  gli stack pubblici), e nei tavoli a struttura di puntata dipendente dallo stack o dal
  piatto (**Pot Limit** su tutti) il tetto di puntata **dipende** dagli stack e dal piatto.
  Perciò un premio erogato per-mano diventa un **moltiplicatore di vantaggio strutturale** —
  chi vince presto gioca il resto da una posizione migliore, e si innesca una **valanga** —
  invece di un riconoscimento. **Regola:** un premio/bonus/rimborso deve vivere **fuori dalla
  sessione** — calcolato da una funzione pura in `GameWorld` e applicato al **cash-out** (il
  confine dei gettoni persistenti), **mai** aggiunto a uno stack al tavolo. L'invariante da
  proteggere e testare: **le uniche fiches che entrano in un tavolo sono i buy-in.** È così
  che funzionano il **premio della Casa** dello Stud (D-079, pagato solo a fine sessione, solo
  se il giocatore ha battuto il tavolo) e il **rimborso** del Machiavelli (D-075).

- **L'effetto delle poste sulla durata NON è monotòno: va MISURATO (D-084).** Alzare i
  minimi di puntata per accorciare una sessione è un'intuizione che **si rovescia** in una
  fascia intermedia: bui più alti comprano più **fold pre-flop**, quindi piatti più
  piccoli, quindi fiches che passano da uno stack all'altro **più lentamente** — e la
  sessione richiede **più** mani, non meno (misurato: Skypool Texas 10/20 → 50/100 = **+75%**
  di decisioni; solo a 100/200 scende sotto il punto di partenza). **Regole:** (a) misurare
  sempre prima/dopo su una **curva** di più valori, mai su un singolo salto; (b) misurare il
  **lavoro** (decisioni, annunci) e non il **numero di mani** — una mano che folda pre-flop
  costa al giocatore cieco una frazione di una mano giocata (D-075); (c) a un tavolo la cui
  identità sono le **poste basse**, o in **Pot Limit** dove il tetto di puntata è il piatto
  (alzare i minimi rende il gioco più *violento*, non solo più rapido), la leva giusta non è
  alzare le poste ma **`StakeEscalation`** (D-064): la mano uno resta esattamente com'è —
  identità e tetto intatti — e la sessione stringe solo andando avanti (misurato allo Stud
  del ClockTower: **−52%** di mani, piatto massimo **invariato**).

