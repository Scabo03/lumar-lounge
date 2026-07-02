# GameWorld

Il **mondo attorno ai tavoli**: il cerchio intermedio dell'architettura.

## Filosofia

`GameWorld` conosce ciò che `GameEngine` ignora di proposito: il **giocatore** e
il suo stato, le **fiches** al tavolo e i **gettoni** del casinò esterno, gli
**NPC/avversari** con i loro caratteri, la **progressione** tra casinò, e
l'orchestrazione di una partita completa (setup del tavolo, posti, blind level,
stack).

Può importare `GameEngine` e ne usa le regole pure. **Non** importa `UI` né
`Audio`, né alcun framework SwiftUI/UIKit: la direzione è `UI → GameWorld →
GameEngine`, verificata dal compilatore.

## Stato attuale

Scheletro. Contiene solo il namespace `GameWorld` e la prova che la dipendenza
verso `GameEngine` compila.

## Cosa sarà suo compito

Modellare giocatore, fiches/gettoni, avversari con personalità, progressione tra
casinò, e far girare una vera partita di Hold'em contro bot appoggiandosi al
motore partita di `GameEngine`. Mattoni M2.x in [`../ROADMAP.md`](../ROADMAP.md).
