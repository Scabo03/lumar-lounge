import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// A busted bot must go acoustically silent (D-058). The reported bug: the novice's
/// "disappointed" voiceline kept firing in hands AFTER its elimination, because the
/// selector compared against a session-start snapshot — and `handEnded.chips` still
/// lists a busted seat (at 0) while `handBegan.seats` does not. The fix filters on
/// the live set of seats playing the current hand.
@MainActor
final class BustedBotVoiceTests: XCTestCase {

    private func seat(_ id: Int, _ chips: Int) -> SeatSnapshot {
        SeatSnapshot(seatID: id, position: id, chips: chips)
    }

    private func makeDirector(_ audio: RecordingAudioService, seed: UInt64) -> AudioDirector {
        AudioDirector(audio: audio, heroSeatID: 0,
                      characters: [1: .novice, 2: .rock, 3: .aggressor], seed: seed)
    }

    func testBustedNoviceEmitsNoVoicelinesInLaterHands() {
        let audio = RecordingAudioService()
        let director = makeDirector(audio, seed: 7)

        director.handle(.sessionBegan(seats: [seat(0, 1000), seat(1, 20), seat(2, 1000), seat(3, 1000)],
                                      smallBlind: 10, bigBlind: 20))
        // Hand 1: the novice (seat 1) plays and loses its last chips, then busts.
        director.handle(.handBegan(handNumber: 1, buttonPosition: 0, buttonSeatID: 0,
                                   smallBlindSeatID: 1, bigBlindSeatID: 2, smallBlind: 10, bigBlind: 20,
                                   seats: [seat(0, 1000), seat(1, 20), seat(2, 1000), seat(3, 1000)]))
        director.handle(.handEnded(handNumber: 1, wentToShowdown: true, board: [],
                                   payouts: [:], chips: [0: 1020, 1: 0, 2: 1000, 3: 1000]))
        director.handle(.playerBusted(playerID: 1))
        let afterBust = audio.botVoicePlays.count

        // Hands 2…12: the novice is gone from handBegan.seats, but handEnded.chips
        // still lists it at 0 (final < the stale start would have re-triggered the bug).
        for h in 2...12 {
            director.handle(.handBegan(handNumber: h, buttonPosition: 0, buttonSeatID: 0,
                                       smallBlindSeatID: 2, bigBlindSeatID: 3, smallBlind: 10, bigBlind: 20,
                                       seats: [seat(0, 1000), seat(2, 1000), seat(3, 1000)]))
            director.handle(.handEnded(handNumber: h, wentToShowdown: true, board: [],
                                       payouts: [:], chips: [0: 1000, 1: 0, 2: 1010, 3: 990]))
        }

        XCTAssertEqual(audio.botVoicePlays.count, afterBust,
                       "a busted novice emits no further voicelines in later hands (D-058)")
    }

    func testActiveNoviceStillReactsToLosingHands() {
        let audio = RecordingAudioService()
        let director = makeDirector(audio, seed: 7)
        director.handle(.sessionBegan(seats: [seat(0, 1000), seat(1, 1000), seat(2, 1000), seat(3, 1000)],
                                      smallBlind: 10, bigBlind: 20))
        // The novice stays in the game and loses many hands: over ~30 losses at ~0.4
        // probability it must react at least once (deterministic under a fixed seed).
        for h in 1...30 {
            director.handle(.handBegan(handNumber: h, buttonPosition: 0, buttonSeatID: 0,
                                       smallBlindSeatID: 1, bigBlindSeatID: 2, smallBlind: 10, bigBlind: 20,
                                       seats: [seat(0, 1000), seat(1, 500), seat(2, 1000), seat(3, 1000)]))
            director.handle(.handEnded(handNumber: h, wentToShowdown: true, board: [],
                                       payouts: [:], chips: [0: 1050, 1: 450, 2: 1000, 3: 1000]))
        }
        XCTAssertGreaterThan(audio.botVoicePlays.count, 0,
                             "an active novice still voices its reactions (no over-filtering)")
    }
}
