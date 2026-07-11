import XCTest
@testable import GameWorld

/// Persistent chips, distinct from table fiches (D-036): first-launch grant, buy-in
/// deduction, cash-out on standing up, no credit on a bust, and persistence.
final class PlayerAccountTests: XCTestCase {

    private final class MemoryStore: ChipsStore {
        var value: Int?
        func loadChips() -> Int? { value }
        func saveChips(_ chips: Int) { value = chips }
    }

    func testFirstLaunchGrantsAndPersistsTheStartingChips() {
        let store = MemoryStore()
        let account = PlayerAccount(store: store, freePlay: false)
        XCTAssertEqual(account.chips, PlayerAccount.startingChips)  // 5000
        XCTAssertEqual(store.value, PlayerAccount.startingChips)    // persisted at once
    }

    func testRestoresTheSavedBalance() {
        let store = MemoryStore(); store.value = 1234
        XCTAssertEqual(PlayerAccount(store: store, freePlay: false).chips, 1234)
    }

    func testBuyInSubtractsAndPersists() {
        let store = MemoryStore()
        let account = PlayerAccount(store: store, freePlay: false)
        XCTAssertTrue(account.buyIn(1000))
        XCTAssertEqual(account.chips, 4000)
        XCTAssertEqual(store.value, 4000)
    }

    func testBuyInFailsWhenInsufficientAndChangesNothing() {
        let store = MemoryStore(); store.value = 500
        let account = PlayerAccount(store: store, freePlay: false)
        XCTAssertFalse(account.canAfford(1000))
        XCTAssertFalse(account.buyIn(1000))
        XCTAssertEqual(account.chips, 500)
    }

    func testCashOutCreditsRemainingFiches() {
        let account = PlayerAccount(store: MemoryStore(), freePlay: false)
        account.buyIn(1000)      // 4000
        account.cashOut(1500)    // won at the table → 5500
        XCTAssertEqual(account.chips, 5500)
    }

    func testBustCashesOutNothing() {
        let account = PlayerAccount(store: MemoryStore(), freePlay: false)
        account.buyIn(1000)      // 4000
        account.cashOut(0)       // busted → nothing back
        XCTAssertEqual(account.chips, 4000)
    }

    func testPersistenceAcrossInstances() {
        let store = MemoryStore()
        PlayerAccount(store: store, freePlay: false).buyIn(2000)   // 3000
        XCTAssertEqual(PlayerAccount(store: store, freePlay: false).chips, 3000)
    }

    // MARK: - ⚠️ TEMPORARY free-play test mode (D-050)

    func testFreePlayResetsToStartingChipsIgnoringSavedBalance() {
        let store = MemoryStore(); store.value = 100   // almost broke, mid-test
        let account = PlayerAccount(store: store, freePlay: true)
        XCTAssertEqual(account.chips, 5000, "free play resets to the starting stake every launch")
    }

    func testFreePlayIgnoresBuyInAndPinsTheBalance() {
        let account = PlayerAccount(store: MemoryStore(), freePlay: true)
        XCTAssertTrue(account.canAfford(999_999), "any table is affordable in free play")
        XCTAssertTrue(account.buyIn(2000), "the buy-in always succeeds…")
        XCTAssertEqual(account.chips, 5000, "…and never moves the balance")
        account.cashOut(0)                 // bust
        XCTAssertEqual(account.chips, 5000)
        account.cashOut(9999)              // a big "win"
        XCTAssertEqual(account.chips, 5000, "the balance stays pinned so every test starts fresh")
    }
}
