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

## 5. Testabilità

- La logica pura (`GameEngine`, e in prospettiva `GameWorld`) deve essere
  testabile in isolamento, senza UI.
- I test del package stanno in `Tests/…` ed eseguono con `swift test`.
- Le sorgenti di casualità (es. mescolata del mazzo) devono essere
  **deterministiche e seedabili** per rendere i test riproducibili.

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
