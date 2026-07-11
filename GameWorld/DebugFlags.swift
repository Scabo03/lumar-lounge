// DebugFlags.swift
// =====================================================================
// ⚠️ TEMPORANEO — RIMUOVERE PRIMA DEL RILASCIO PUBBLICO. ⚠️
//
// Flag di modalità sviluppo/test attivi in questa build. Introdotti per la fase di
// test post-M2.1 (calibrazione delle personalità dei bot). Vanno tolti — o messi a
// `false` — in una sessione dedicata al rilascio. Finché sono attivi, sono elencati
// nella sezione "Modalità di sviluppo attualmente attive" del README principale, e
// mostrati con un badge visibile nel chrome dell'app (D-050).
//
// GameWorld only.

import Foundation

/// Development-only switches. **Temporary — remove before public release.**
public enum DebugFlags {

    /// ⚠️ TEMPORANEO (D-050) — **rimuovere prima del rilascio pubblico**.
    ///
    /// Modalità **gioco libero** per testare all'infinito senza esaurire i gettoni:
    /// quando `true`, il **buy-in è ignorato** (ci si siede a qualsiasi tavolo a
    /// prescindere dal saldo), il saldo è **ripristinato a 5000 a ogni avvio** e
    /// **non si muove** giocando (ogni test parte fresco). L'app mostra un badge di
    /// avviso in ogni schermata. Introdotto per la fase di test post-M2.1.
    public static let freePlay = true
}
