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
- `GameWorld` può importare `GameEngine`, mai `UI` né `Audio`.
- `Audio` è agnostico rispetto al gioco: guida tutto tramite identificatori
  opachi, non conosce poker/blackjack.
- `UI` può importare tutto ciò che sta sotto; solo la thin shell dell'app
  importa `UI`.

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
  - **Non** applicare modificatori di accessibilità al contenitore più esterno di
    una schermata (`.accessibilityElement`/`.accessibilityIdentifier` su una
    ZStack/GeometryReader di root): collassa il sottoalbero in un solo elemento e
    nasconde gli identifier dei figli. Gli **identifier vanno sui leaf**.
  - La logica di presentazione (riduzione evento→stato, formattazione testo) va
    tenuta **pura** e fuori dalle viste SwiftUI, per essere unit-testabile.
  - **Audio mai sopra VoiceOver (emerso in M1.8, D-024).** L'audio arricchisce ma
    **non è mai indispensabile**: VoiceOver da solo deve sempre bastare per
    giocare. Quando VoiceOver è attivo, i suoni **parlati** (voci di croupier e
    bot) tacciono, mentre quelli **non parlati** (ambient, effetti, feedback UI)
    restano. Come per il parlato (M1.6), la **mappatura evento→suoni è una
    funzione pura** separata dalla riproduzione; il modulo `Audio` resta neutro
    (suoni opachi + categorie), e la mappatura vive dove si vedono sia gli eventi
    sia `Audio` (cioè in `UI`), mai dentro `Audio`.
  - **Input numerico a incremento con annuncio istantaneo (pattern riusabile,
    emerso in M1.7 col box Raise, D-020).** Per un controllo che regola una cifra
    con `+`/`−` (rilancio a poker, ma anche puntata a blackjack/roulette in
    futuro): (a) la **curva di incremento è una funzione pura** separata e
    testabile; (b) lo stato tiene un **conteggio di step** come sorgente di
    verità, col valore derivato e clampato a un intervallo legale; (c) ogni
    pressione posta **subito** un annuncio VoiceOver del nuovo valore con
    **priorità alta interrompente**, così una raffica di clic annuncia solo
    l'ultimo valore senza accodarsi; (d) ordine di swipe esplicito
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
