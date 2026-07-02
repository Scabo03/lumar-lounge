# UI

Tutte le **viste SwiftUI** dell'app: il cerchio più esterno dell'architettura.

## Filosofia

`UI` è l'unico modulo che parla al giocatore. Può importare `GameWorld`,
`GameEngine` e `Audio`; nessuno importa `UI` tranne la thin shell dell'app.

Due principi non negoziabili, presenti fin dalla prima riga:

- **Accessibilità di prima classe.** Ogni vista imposta accessibility
  identifier e label; VoiceOver è una modalità piena, non un ripiego. Vale il
  principio **"nessuno perde niente"** tra vedenti e non vedenti. La pronuncia
  italiana per VoiceOver è curata tramite le accessibility label.
- **Nessuna stringa inline.** Ogni testo visibile viene dai file di
  localizzazione in `Resources/` (italiano principale, inglese seconda).

## Stato attuale

Scheletro. Contiene una `RootView` minimale con identifier e label già
impostati, e l'accesso centralizzato alle stringhe localizzate.

## Cosa sarà suo compito

Il **tavolo di Hold'em giocabile** (carte, board, stack, controlli d'azione) e
il contorno minimo di navigazione per arrivare dal lancio al tavolo. Mattoni
M4.x in [`../ROADMAP.md`](../ROADMAP.md).
