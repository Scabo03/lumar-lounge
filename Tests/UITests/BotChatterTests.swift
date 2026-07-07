import XCTest
@testable import UI
import GameWorld
import GameEngine
import Audio

/// The bots' action colour voicelines (D-031): deterministic given a seed, and
/// never voiced on two consecutive actions of the same bot.
@MainActor
final class BotChatterTests: XCTestCase {

    private func seats(_ ids: [Int]) -> [SeatSnapshot] {
        ids.map { SeatSnapshot(seatID: $0, position: $0, chips: 1000) }
    }
    private func raise() -> ActedAction { .raised(to: 60, amount: 40, isAllIn: false) }

    func testDeterministicGivenSeed() {
        func run() -> [String] {
            let chatter = BotChatter(heroSeatID: 0, characters: [1: .aggressor, 2: .novice, 3: .rock], seed: 7)
            chatter.handBegan(seats: seats([1, 2, 3]))
            var out: [String] = []
            for _ in 0..<15 {
                for seat in [1, 2, 3] {
                    if let v = chatter.actionVoice(seat: seat, action: raise()) { out.append("\(seat):\(v.rawValue)") }
                }
            }
            return out
        }
        XCTAssertEqual(run(), run())
        XCTAssertFalse(run().isEmpty, "over many raises at least some voicelines should fire")
    }

    func testNeverVoicedTwiceInARowForTheSameBot() {
        let chatter = BotChatter(heroSeatID: 0, characters: [1: .aggressor], seed: 3)
        chatter.handBegan(seats: seats([1]))
        var voiced: [Bool] = []
        for _ in 0..<50 { voiced.append(chatter.actionVoice(seat: 1, action: raise()) != nil) }
        for i in 1..<voiced.count {
            XCTAssertFalse(voiced[i] && voiced[i - 1], "bot voiced on two consecutive actions at index \(i)")
        }
    }

    func testHeroIsNeverVoiced() {
        let chatter = BotChatter(heroSeatID: 0, characters: [0: .aggressor], seed: 1)
        chatter.handBegan(seats: seats([0]))
        for _ in 0..<30 { XCTAssertNil(chatter.actionVoice(seat: 0, action: raise())) }
    }

    func testAggressorRaiseVoicelinesAreItsOwn() {
        let chatter = BotChatter(heroSeatID: 0, characters: [1: .aggressor], seed: 9)
        chatter.handBegan(seats: seats([1]))
        var seen: Set<String> = []
        for _ in 0..<60 { if let v = chatter.actionVoice(seat: 1, action: raise()) { seen.insert(v.rawValue) } }
        let allowed: Set = [SoundCatalog.vobAggressorConfident.rawValue, SoundCatalog.vobAggressorTaunt.rawValue]
        XCTAssertTrue(seen.isSubset(of: allowed), "aggressor used a non-aggressor voiceline: \(seen)")
    }
}
