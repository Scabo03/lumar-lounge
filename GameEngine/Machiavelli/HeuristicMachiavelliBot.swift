// HeuristicMachiavelliBot.swift
// =====================================================================
// A concrete Machiavelli bot whose character lives on TWO INDEPENDENT AXES (D-070):
//
//  • SEARCH DEPTH (`machiavelliSearchDepth`) — how far it explores recompositions.
//    It scales the search's node ceiling AND time budget. A shallow bot places what a
//    cheap greedy pass finds and returns almost immediately (the young player who just
//    glances); a deep bot runs a bounded exact-cover over the whole pool (table +
//    hand) to dismantle and rebuild combinations, finding placements the greedy pass
//    misses (the professor who reworks the table).
//
//  • PATIENCE (`machiavelliPatience`) — having found a placement, how readily it HOLDS
//    it and draws instead, betting on a better future move. Orthogonal to depth: a bot
//    can search deeply and still be greedy, or search deeply and be patient.
//
// INTERRUPTIBLE & NEVER OVERRUNS: the search is bounded by a `MachiavelliSearchBudget`
// (node ceiling and/or wall-clock cap). It always holds a valid best-so-far (a greedy
// baseline seeded first), checks the budget before every node, and returns the best
// found the instant the budget is hit — the depth is adaptive to the time available,
// never fixed a priori. Per-node work is bounded, so an overrun is at most microseconds.
//
// DETERMINISM: the only randomness is a SeededGenerator seeded from the bot's own seed
// mixed with the context fingerprint. Given a seed AND a node budget the plan is
// reproducible (tests pin the node budget); under a pure time cap the refinement count
// varies by machine, so the plan may vary — intended (D-070). Reads only public info +
// its own hand (D-009). Foundation only.

import Foundation

public struct HeuristicMachiavelliBot: MachiavelliBot {
    public let personality: Personality
    /// The bot's "soul seed": its identity for reproducible randomness.
    public let seed: UInt64
    /// An explicit search budget. When `nil`, the budget is DERIVED from the
    /// personality's search depth (production). Tests inject `.nodes(_)` for a fully
    /// deterministic, reproducible search.
    public let budget: MachiavelliSearchBudget?

    public init(personality: Personality, seed: UInt64, budget: MachiavelliSearchBudget? = nil) {
        self.personality = personality
        self.seed = seed
        self.budget = budget
    }

    /// How long this bot is EXPECTED to deliberate — its personality's wall-clock cap.
    /// Descriptive character info the driver forwards so a future UI/audio can fill the
    /// silence (D-070); it does not prescribe anything. ~10 s (student) … ~15 s (professor).
    public var expectedDeliberation: Duration { Self.timeCap(for: personality) }

    // MARK: - Budget derivation

    static func nodeCeiling(for personality: Personality) -> Int {
        // Exponential in depth: 0.2 → ~500 nodes (a glance), 1.0 → 60_000 (a full study).
        Int(150.0 * pow(400.0, personality.machiavelliSearchDepth))
    }
    static func timeCap(for personality: Personality) -> Duration {
        // 10 s (shallow) … 15 s (deep). The young lays down fast; the old takes its time.
        .milliseconds(10_000 + Int(5_000 * personality.machiavelliSearchDepth))
    }
    private func resolvedBudget() -> MachiavelliSearchBudget {
        budget ?? MachiavelliSearchBudget(maxNodes: Self.nodeCeiling(for: personality),
                                          maxTime: Self.timeCap(for: personality))
    }

    // MARK: - Planning a turn

    public func planTurn(_ context: MachiavelliBotContext) -> MachiavelliTurnPlan {
        var rng = SeededGenerator(seed: botMix64(seed ^ context.fingerprint))
        let clock = SearchClock(resolvedBudget())
        let handCount = context.hand.count

        // Search for the best arrangement (most hand cards placed). Always ≥ the greedy
        // baseline, which is itself always valid.
        let searched = search(hand: context.hand, table: context.table, clock: clock, rng: &rng)

        // Validate the chosen arrangement through the SAME predicate the UI uses
        // (single source of truth). Fall back defensively if anything is off.
        let ctx = MachiavelliTurnContext(playerID: context.heroSeatID, hand: context.hand, table: context.table)
        let proposal = ctx.evaluate(searched.arrangement)
        let placed = proposal.isLegal ? proposal.placedFromHand.count : 0
        guard proposal.isLegal, placed > 0 else {
            return .drawing(keeping: context.table)     // nothing placeable → draw
        }

        // Going out always wins → always play it.
        if placed == handCount {
            return MachiavelliTurnPlan(finalTable: searched.arrangement, terminal: .meld)
        }

        // PATIENCE: a partial placement may be held back to draw for something better.
        if shouldHold(placed: placed, handCount: handCount, stockCount: context.stockCount, rng: &rng) {
            return .drawing(keeping: context.table)
        }
        return MachiavelliTurnPlan(finalTable: searched.arrangement, terminal: .meld)
    }

    // MARK: - Patience axis

    /// Whether to HOLD a found placement and draw instead. Independent of search depth.
    private func shouldHold(placed: Int, handCount: Int, stockCount: Int, rng: inout SeededGenerator) -> Bool {
        guard stockCount > 0 else { return false }      // can't draw → must play
        let fraction = Double(placed) / Double(handCount)   // how much of the hand it clears
        // Patient bots forgo SMALL placements; a placement clearing much is rarely held.
        let holdBias = personality.machiavelliPatience * (1.0 - fraction)
        return botUnit(&rng) < holdBias * 0.9
    }

    // MARK: - Search

    private struct Plan { var arrangement: [[Card]]; var placed: Int }

    private func search(hand: [Card], table: [Meld], clock: SearchClock, rng: inout SeededGenerator) -> Plan {
        let handCount = hand.count
        // Greedy baseline: keep table melds, place directly-fitting hand cards. Always
        // valid; this is essentially the shallow (young) bot's whole move.
        var best = greedy(hand: hand, table: table)
        if best.placed == handCount { return best }

        // Deeper: bounded exact-cover restarts over the whole pool, seeking to fold in
        // MORE hand cards (up to a go-out) by dismantling and rebuilding combinations.
        let handValues = Set(hand.map { $0.fingerprintCode })
        let tableBag = CardBag(table.flatMap { $0.cards })
        let poolBag = { () -> CardBag in var b = tableBag; for c in hand { b.add(c) }; return b }()

        while clock.hasRemaining && best.placed < handCount {
            let before = clock.nodesConsumed
            cover(available: poolBag, mandatory: tableBag, melds: [], handUsed: 0,
                  handValues: handValues, handCount: handCount, clock: clock, rng: &rng, best: &best)
            if clock.nodesConsumed == before { break }   // budget produced no progress
        }
        return best
    }

    /// Greedy placement: extend existing melds and form new hand-only melds until stuck.
    private func greedy(hand: [Card], table: [Meld]) -> Plan {
        var melds: [[Card]] = table.map { $0.cards }
        var remaining = hand.sorted(by: cardOrder)
        var placed = 0
        var progress = true
        while progress {
            progress = false
            // 1. Extend an existing meld with a single hand card.
            for i in melds.indices {
                if let used = extend(&melds[i], with: remaining) {
                    remaining.remove(at: used); placed += 1; progress = true; break
                }
            }
            if progress { continue }
            // 2. Form a brand-new combination purely from hand cards.
            if let (meld, indices) = findHandMeld(remaining) {
                melds.append(meld)
                for idx in indices.sorted(by: >) { remaining.remove(at: idx) }
                placed += indices.count; progress = true
            }
        }
        return Plan(arrangement: melds, placed: placed)
    }

    /// Try to grow `meld` by one card from `remaining`; returns the used index if so.
    private func extend(_ meld: inout [Card], with remaining: [Card]) -> Int? {
        for (i, card) in remaining.enumerated() {
            let candidate = meld + [card]
            if candidate.count > meld.count, let m = Meld(candidate) {
                meld = m.cards
                return i
            }
        }
        return nil
    }

    /// Find any minimal valid combination among `remaining` hand cards.
    private func findHandMeld(_ remaining: [Card]) -> ([Card], [Int])? {
        let bag = CardBag(remaining)
        // Groups: a rank with ≥3 distinct suits available.
        for rank in Rank.allCases {
            let suits = Suit.allCases.filter { bag.count(Card(rank, $0)) > 0 }
            if suits.count >= 3 {
                let cards = suits.prefix(3).map { Card(rank, $0) }
                if let idx = indices(of: Array(cards), in: remaining) { return (Meld(Array(cards))!.cards, idx) }
            }
        }
        // Runs: any consecutive triple in a suit.
        for suit in Suit.allCases {
            let runs = candidateRuns(suit: suit, containing: nil, from: bag)
            for run in runs where run.count == 3 {
                if let idx = indices(of: run, in: remaining) { return (Meld(run)!.cards, idx) }
            }
        }
        return nil
    }

    // MARK: - Bounded exact-cover recombination

    /// Cover all MANDATORY (table) cards with valid melds drawn from `available`
    /// (table + hand), placing as many hand cards as possible. Records improvements in
    /// `best`. Bounded by `clock`; deterministic ordering perturbed by `rng`.
    private func cover(available: CardBag, mandatory: CardBag, melds: [[Card]], handUsed: Int,
                       handValues: Set<UInt64>, handCount: Int, clock: SearchClock,
                       rng: inout SeededGenerator, best: inout Plan) {
        guard clock.consume() else { return }

        if mandatory.isEmpty {
            // Valid table (all table cards covered). Greedily add hand-only melds to
            // place still more, then record if it beats the incumbent.
            let (extraMelds, extraCount) = greedyHandMelds(from: available)
            let placed = handUsed + extraCount
            if placed > best.placed {
                best = Plan(arrangement: melds + extraMelds, placed: placed)
            }
            return
        }

        guard let target = chooseTarget(mandatory: mandatory, available: available) else { return }
        var candidates = candidateMelds(containing: target, from: available)
        guard !candidates.isEmpty else { return }     // dead branch: prune
        orderCandidates(&candidates, handValues: handValues, rng: &rng)

        for meld in candidates.prefix(branchCap) {
            let meldBag = CardBag(meld)
            guard let available2 = available.subtracting(meldBag) else { continue }
            let coveredMandatory = intersectionCount(meldBag, mandatory)
            let mandatory2 = subtractCovered(mandatory, by: meldBag)
            let handInMeld = meld.count - coveredMandatory
            cover(available: available2, mandatory: mandatory2, melds: melds + [meld],
                  handUsed: handUsed + handInMeld, handValues: handValues, handCount: handCount,
                  clock: clock, rng: &rng, best: &best)
            if best.placed == handCount { return }    // go-out found; stop
        }
    }

    /// Max melds explored per covered card. With MRV + restarts this bounds the tree.
    private let branchCap = 8

    /// The mandatory card with the FEWEST candidate melds (MRV) — prune hard branches.
    private func chooseTarget(mandatory: CardBag, available: CardBag) -> Card? {
        var bestCard: Card?
        var fewest = Int.max
        for card in mandatory.cards {
            let n = candidateMelds(containing: card, from: available).count
            if n < fewest { fewest = n; bestCard = card; if n == 0 { break } }
        }
        return bestCard
    }

    /// Order candidates so those incorporating more HAND cards come first (find go-outs
    /// faster), with an rng jitter so different bots explore differently.
    private func orderCandidates(_ candidates: inout [[Card]], handValues: Set<UInt64>, rng: inout SeededGenerator) {
        candidates.shuffle(using: &rng)
        candidates.sort { a, b in
            let ha = a.reduce(0) { $0 + (handValues.contains($1.fingerprintCode) ? 1 : 0) }
            let hb = b.reduce(0) { $0 + (handValues.contains($1.fingerprintCode) ? 1 : 0) }
            return ha > hb
        }
    }

    /// All valid combinations from `available` that contain `target`.
    private func candidateMelds(containing target: Card, from available: CardBag) -> [[Card]] {
        var result: [[Card]] = []
        // Groups: same rank, distinct suits, must include the target's suit.
        let suits = Suit.allCases.filter { available.count(Card(target.rank, $0)) > 0 }
        if suits.contains(target.suit) && suits.count >= 3 {
            let others = suits.filter { $0 != target.suit }
            for pair in combinations(others, choose: 2) {
                result.append(Meld(([target.suit] + pair).map { Card(target.rank, $0) })!.cards)
            }
            if others.count >= 3 {
                result.append(Meld(([target.suit] + others).map { Card(target.rank, $0) })!.cards)
            }
        }
        // Runs in the target's suit that include the target's rank.
        result += candidateRuns(suit: target.suit, containing: target.rank, from: available)
        return result
    }

    /// Valid runs of the given suit, optionally required to contain `rank`.
    private func candidateRuns(suit: Suit, containing rank: Rank?, from available: CardBag) -> [[Card]] {
        var present = Set<Int>()
        for r in Rank.allCases where available.count(Card(r, suit)) > 0 { present.insert(r.rawValue) }
        guard !present.isEmpty else { return [] }
        var line = present
        if present.contains(14) { line.insert(1) }     // ace may also play low

        // Which numeric anchors must the run pass through?
        let anchors: [Int]
        if let rank {
            guard present.contains(rank.rawValue) else { return [] }
            anchors = rank == .ace ? [14, 1] : [rank.rawValue]
        } else {
            anchors = Array(line)
        }

        var runs: [[Card]] = []
        var seen = Set<String>()
        for anchor in anchors where line.contains(anchor) {
            var lo = anchor; while line.contains(lo - 1) { lo -= 1 }
            var hi = anchor; while line.contains(hi + 1) { hi += 1 }
            for a in lo...anchor {
                for b in anchor...hi where b - a + 1 >= 3 {
                    if a == 1 && b == 14 { continue }   // no wrap: ace can't be both ends
                    let key = "\(a)-\(b)"
                    if seen.contains(key) { continue }
                    seen.insert(key)
                    let cards = (a...b).map { v -> Card in
                        Card(v == 1 ? .ace : Rank(rawValue: v)!, suit)
                    }
                    runs.append(Meld(cards)!.cards)
                }
            }
        }
        return runs
    }

    /// Greedily form hand-only combinations from a leftover bag (all hand cards once
    /// the mandatory table cards are covered), returning the melds and how many placed.
    private func greedyHandMelds(from bag: CardBag) -> ([[Card]], Int) {
        var remaining = bag.cards
        var melds: [[Card]] = []
        var placed = 0
        var progress = true
        while progress {
            progress = false
            if let (meld, indices) = findHandMeld(remaining) {
                melds.append(meld)
                for idx in indices.sorted(by: >) { remaining.remove(at: idx) }
                placed += indices.count; progress = true
            }
        }
        return (melds, placed)
    }

    // MARK: - Small helpers

    private func intersectionCount(_ a: CardBag, _ b: CardBag) -> Int {
        a.counts.reduce(0) { $0 + Swift.min($1.value, b.count($1.key)) }
    }
    private func subtractCovered(_ mandatory: CardBag, by meld: CardBag) -> CardBag {
        var m = mandatory
        for (card, n) in meld.counts { m.remove(card, Swift.min(n, mandatory.count(card))) }
        return m
    }
    /// Distinct indices in `remaining` occupied by the given card values, or `nil` if
    /// they are not all present.
    private func indices(of values: [Card], in remaining: [Card]) -> [Int]? {
        var used: [Int] = []
        for value in values {
            guard let idx = remaining.indices.first(where: { !used.contains($0) && remaining[$0] == value }) else {
                return nil
            }
            used.append(idx)
        }
        return used
    }
}

// MARK: - Combinations helper

/// All size-`k` combinations of `items`, in deterministic order.
func combinations<T>(_ items: [T], choose k: Int) -> [[T]] {
    guard k >= 0, k <= items.count else { return [] }
    if k == 0 { return [[]] }
    if k == items.count { return [items] }
    var result: [[T]] = []
    func recurse(_ start: Int, _ current: [T]) {
        if current.count == k { result.append(current); return }
        for i in start..<items.count {
            recurse(i + 1, current + [items[i]])
        }
    }
    recurse(0, [])
    return result
}

// MARK: - Search clock

/// Bounds a search by a node ceiling and/or a monotonic wall-clock deadline. Checked
/// before every node so the search returns its best-so-far the instant the budget is
/// hit and never overruns by more than one bounded node's work (D-070).
final class SearchClock {
    private var nodesLeft: Int
    private let deadline: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private(set) var nodesConsumed = 0

    init(_ budget: MachiavelliSearchBudget) {
        nodesLeft = budget.maxNodes ?? Int.max
        deadline = budget.maxTime.map { ContinuousClock().now + $0 }
    }

    /// Spend one node if the budget allows; returns `false` when exhausted.
    func consume() -> Bool {
        guard hasRemaining else { return false }
        nodesLeft -= 1
        nodesConsumed += 1
        return true
    }

    var hasRemaining: Bool {
        if nodesLeft <= 0 { return false }
        if let deadline, clock.now >= deadline { return false }
        return true
    }
}
