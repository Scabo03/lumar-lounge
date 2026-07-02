# Audio

Il sistema di **suono e aptica**, trasversale a tutto il progetto.

## Filosofia

`Audio` è **generico e agnostico rispetto al gioco**: non sa nulla di poker,
blackjack o qualunque gioco specifico. Espone un'interfaccia (`AudioServicing`)
guidata da **identificatori opachi** (`SoundID`, `MusicID`, `HapticID`) che il
chiamante definisce e il modulo non interpreta mai. Non dipende da `GameEngine`,
`GameWorld` né `UI`.

L'approccio del progetto è **audio-first**: il suono veicola informazione di
gioco (utile anche e soprattutto per chi usa VoiceOver), non è decoro.

## Stato attuale

Interfaccia pronta ma senza riproduzione reale: esistono i tipi ID, il protocollo
`AudioServicing` e un `NullAudioService` che non fa nulla (default utile per
preview e test).

## Cosa sarà suo compito

L'implementazione reale su AVFoundation/CoreHaptics **dietro la stessa
interfaccia** — così i chiamanti non cambiano — e il set di suoni/aptica per le
azioni della mano di Hold'em. Mattoni M3.x in [`../ROADMAP.md`](../ROADMAP.md).
