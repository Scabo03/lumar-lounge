// Personality.swift
// =====================================================================
// A bot's personality: a set of tuning knobs that MODULATE how the shared
// mathematical baseline is expressed, rather than replacing it. Two bots with
// the same cards and the same maths can act very differently depending on their
// personality (see D-010).
//
// The dimensions here are a sensible starting subset; adding more later is
// purely additive (a new stored property with a neutral default plus its use in
// the decision logic). Foundation only.
//
// NOTE: `name` is an English debug identifier, never shown to the player. Any
// user-facing personality label will come from localized strings in UI.

import Foundation

/// How a bot colours its decisions. Every value is a 0…1 dial.
public struct Personality: Equatable, Sendable {
    /// Debug identifier (English, non-user-facing).
    public let name: String
    /// How strong a hand the bot needs to enter/continue. High = folds a lot.
    public let tightness: Double
    /// Tendency to bet/raise rather than call/check when it does play.
    public let aggression: Double
    /// How often it fires a bet/raise with a weak hand (a bluff).
    public let bluffFrequency: Double
    /// Willingness to commit chips on uncertain equity (loosens pot-odds).
    public let riskTolerance: Double
    /// How much position shifts its thresholds. Low = ignores position.
    public let positionAwareness: Double
    /// How closely it follows the maths. Low = noisy, fallible perception.
    public let rationality: Double
    /// How much a recent swing (tilt) pushes it off its baseline.
    public let tiltReactivity: Double

    // MARK: Fold-propensity dimensions (D-048)
    //
    // These two make bluffing possible: they weight the opponent's PRESSURE
    // signals that the pure equity-vs-uniform-range maths (D-011) ignores. Both
    // apply to Texas and to Five-Card Draw. Their defaults reproduce the previous
    // behaviour exactly (no pressure fold, no trash fold), so adding them never
    // changes a personality that doesn't set them (CONVENTIONS §4-bis).

    /// How much the bot resists folding to a BIG bet (> ~60% of the pot, a strong
    /// representation of a made hand). 1 = stubborn, calls big bets on mediocre
    /// equity (the old behaviour); low = with marginal equity it folds to heavy
    /// pressure. Modulates the extra equity a big bet demands to call.
    public let pressureResistance: Double
    /// How readily the bot folds a clearly weak hand pre-flop (Texas) / in the
    /// first round (Draw), even without a bet. 0 = plays any garbage; high = folds
    /// trash with this probability. 0 by default = never trash-folds (old behaviour).
    public let trashFoldTendency: Double

    // MARK: Five-Card Draw dimensions
    //
    // These three dials only bite in the Five-Card Draw engine (opening, the
    // card exchange). In Texas Hold'em there is no draw and no jacks-or-better
    // opening, so `HeuristicBot` never reads them — the Texas personalities keep
    // sensible values here purely so the same presets behave well at a draw table.

    /// How mathematically correct the card exchange is: 1 = keeps the strong
    /// cards and draws to the best hand, 0 = discards emotionally / noisily.
    public let drawDiscipline: Double
    /// How theatrically the exchange misrepresents the hand: high = stands pat or
    /// draws few cards on a weak hand to fake strength (or over-draws to deceive).
    public let drawBluffiness: Double
    /// How strictly it respects "jacks or better to open": 1 = opens only when it
    /// can prove openers at showdown, 0 = may open on air and risk being exposed.
    public let openingDiscipline: Double

    // MARK: Omaha dimensions (D-063)
    //
    // These two dials only bite in the Omaha engine; the Hold'em and Draw bots never
    // read them. Omaha value is NOT the strength of the best two cards (that's Texas
    // thinking) — with four hole cards almost everyone flops *something*, so the edge
    // lives in (a) how COORDINATED the four cards are (suited, connected, pairs that
    // can make the nuts) and (b) NUT DISCIPLINE: chasing/holding the nuts and folding
    // dominated second-best hands, because in Pot Limit the second nut flush is a
    // trap that pays off the nut flush. The two levers express exactly that. Neutral
    // defaults (0.5) so adding them never changes a personality that doesn't set them
    // (additive principle, CONVENTIONS §4-bis). They are LEVERS, not tuned values —
    // calibration is a later cross-casino exercise (D-063).

    /// How much the bot demands its four hole cards be COORDINATED to play pre-flop:
    /// 1 = only coherent, double-suited/connected holdings (folds dangly cards);
    /// 0 = plays any four cards. Raises the pre-flop entry bar with coordination.
    public let omahaCoordination: Double
    /// NUT DISCIPLINE: how much the bot values nut potential and distrusts a merely
    /// "made" non-nut hand under heavy Pot Limit pressure. 1 = folds dominated hands,
    /// commits big only near the nuts; 0 = pays off with second-best made hands.
    public let omahaNuttiness: Double

    // MARK: Machiavelli dimensions (D-070)
    //
    // Machiavelli personalities are NOT three difficulty levels — they are attitudes
    // toward the table, expressed on TWO INDEPENDENT AXES (D-070). Modelling them as
    // one scale would give three copies of the same bot with a different number.
    // Neither axis is read by any poker bot, so their defaults are free; 0.5 is
    // neutral and keeps Texas/Draw/Omaha behaviour untouched (additive, CONVENTIONS
    // §1). They are LEVERS, not tuned values — calibration comes after real play.

    /// SEARCH DEPTH — how far the bot explores the space of possible recompositions.
    /// Low = glances and lays down what it plainly sees; high = dismantles and rebuilds
    /// the table (its own and others') to place more cards. Also scales the bot's time
    /// budget: a deep searcher is allowed to deliberate longer (D-070).
    public let machiavelliSearchDepth: Double
    /// PATIENCE — the propensity to HOLD a placement it has already found and draw
    /// instead, waiting to draw something that makes a better move. Independent of
    /// depth: a bot can search deeply yet be greedy, or search deeply yet be patient.
    /// 0 = lays down whatever it found immediately; 1 = often forgoes small placements.
    public let machiavelliPatience: Double
    /// MALUS AVERSION (D-071) — how strongly the bot fears being caught HOLDING heavy
    /// cards when an opponent goes out (each stranded card is a penalty, aces worst).
    /// It turns `machiavelliPatience` from pure character into a CALCULATED risk: a
    /// malus-averse bot sheds high-value cards and holds far less when an opponent is
    /// close to closing. 0 (default) = ignores scoring entirely, i.e. the pre-scoring
    /// behaviour (additive back-compat); higher = plays ever more score-aware.
    public let machiavelliMalusAversion: Double

    // MARK: Seven-Card Stud dimension (D-076)
    //
    // Stud's defining edge, absent in every other game here, is READING OPPONENTS' UP
    // CARDS: they are public, so a good player folds when a foe's board is scary, chases
    // when the cards they need are still live, and abandons a draw whose outs are dead in
    // opponents' up cards. Only the Stud bot reads this dial, so its default is free; 0.5
    // is neutral and keeps every other game's behaviour untouched (additive, CONVENTIONS
    // §1). It is a LEVER, not a tuned value — calibration comes after real play (D-076).

    /// UP-CARD READING — how much the bot factors opponents' visible up cards into its
    /// decision: dead outs shrink its draws, and a threatening opposing board (a pair
    /// showing, three to a flush/straight) makes it demand more to continue. 0 = ignores
    /// the boards entirely (plays its own cards blind); 1 = a sharp board reader.
    public let studBoardReading: Double

    public init(name: String,
                tightness: Double,
                aggression: Double,
                bluffFrequency: Double,
                riskTolerance: Double,
                positionAwareness: Double,
                rationality: Double,
                tiltReactivity: Double,
                pressureResistance: Double = 1.0,
                trashFoldTendency: Double = 0.0,
                drawDiscipline: Double = 0.5,
                drawBluffiness: Double = 0.3,
                openingDiscipline: Double = 0.7,
                omahaCoordination: Double = 0.5,
                omahaNuttiness: Double = 0.5,
                machiavelliSearchDepth: Double = 0.5,
                machiavelliPatience: Double = 0.5,
                machiavelliMalusAversion: Double = 0.0,
                studBoardReading: Double = 0.5) {
        self.name = name
        self.tightness = tightness.clamped01
        self.aggression = aggression.clamped01
        self.bluffFrequency = bluffFrequency.clamped01
        self.riskTolerance = riskTolerance.clamped01
        self.positionAwareness = positionAwareness.clamped01
        self.rationality = rationality.clamped01
        self.tiltReactivity = tiltReactivity.clamped01
        self.pressureResistance = pressureResistance.clamped01
        self.trashFoldTendency = trashFoldTendency.clamped01
        self.drawDiscipline = drawDiscipline.clamped01
        self.drawBluffiness = drawBluffiness.clamped01
        self.openingDiscipline = openingDiscipline.clamped01
        self.omahaCoordination = omahaCoordination.clamped01
        self.omahaNuttiness = omahaNuttiness.clamped01
        self.machiavelliSearchDepth = machiavelliSearchDepth.clamped01
        self.machiavelliPatience = machiavelliPatience.clamped01
        self.machiavelliMalusAversion = machiavelliMalusAversion.clamped01
        self.studBoardReading = studBoardReading.clamped01
    }

    // MARK: - Pressure heuristic (pure, shared by both bots — D-048)

    /// The bet-to-pot ratio above which a bet reads as a strong "I have it"
    /// signal (60% of the pot). Below it, no extra equity is demanded.
    public static let pressureSignalRatio = 0.6

    /// The MULTIPLIER applied to the base call-equity threshold when facing a bet
    /// of `betFraction` × the pot (D-048). Returns 1.0 (no change) for small bets;
    /// for big bets it grows, inversely to `pressureResistance`, so a
    /// pressure-shy bot needs much more equity to call while a stubborn one barely
    /// budges. Capped so the threshold at most roughly doubles.
    ///
    /// Calibration (bet = 70% of the pot): pressureResistance 0.3 → ≈ +44% equity
    /// demanded; 0.9 → ≈ +6%.
    public static func callThresholdMultiplier(betFraction: Double, pressureResistance: Double) -> Double {
        guard betFraction > pressureSignalRatio else { return 1.0 }
        let growth = Swift.min(0.8, betFraction * (1.0 - pressureResistance) * 0.9)
        return 1.0 + growth
    }
}

public extension Personality {

    /// "Principiante emotivo": plays far too many hands, easily scared off big
    /// bets, improvised bluffs, very emotional. Mathematically simple.
    static let eagerNovice = Personality(
        name: "Eager Novice",
        tightness: 0.20,        // enters almost anything
        aggression: 0.45,
        bluffFrequency: 0.30,   // spur-of-the-moment bluffs
        riskTolerance: 0.25,    // folds when the pressure is real
        positionAwareness: 0.15,
        rationality: 0.30,      // fallible reads
        tiltReactivity: 0.80,   // rides its emotions
        pressureResistance: 0.35, // scared off by big bets
        trashFoldTendency: 0.30,  // undisciplined, but folds trash sometimes
        drawDiscipline: 0.25,   // chaotic exchange — keeps the wrong cards
        drawBluffiness: 0.15,   // draws honestly, doesn't scheme
        openingDiscipline: 0.50, // doesn't always realise it holds openers
        omahaCoordination: 0.25, // Omaha: plays any four cards
        omahaNuttiness: 0.30     // Omaha: overvalues weak made hands (pays off)
    )

    /// "Sasso conservativo": only strong hands, little aggression, predictable,
    /// disciplined, unshakeable. Mathematically solid but transparent.
    static let conservativeRock = Personality(
        name: "Conservative Rock",
        tightness: 0.90,        // waits for premium holdings
        aggression: 0.20,
        bluffFrequency: 0.03,   // essentially never bluffs
        riskTolerance: 0.30,
        positionAwareness: 0.70,
        rationality: 0.90,      // sticks to the maths
        tiltReactivity: 0.10,   // hard to rattle
        pressureResistance: 0.50, // respects strong signals, not easily bullied
        trashFoldTendency: 0.90,  // folds junk pre-flop almost always
        drawDiscipline: 0.90,   // textbook-correct exchange
        drawBluffiness: 0.05,   // never misrepresents the draw
        openingDiscipline: 0.95, // opens only with provable openers
        omahaCoordination: 0.85, // Omaha: only coherent, coordinated holdings
        omahaNuttiness: 0.85     // Omaha: nut-disciplined, folds dominated hands
    )

    /// "Aggressivo caldo": raises constantly, bluffs a lot, barely reads
    /// position, happy to gamble. Loud and dangerous, but exploitable.
    static let hotAggressor = Personality(
        name: "Hot Aggressor",
        tightness: 0.35,        // plays a wide range
        aggression: 0.90,       // raise-first instinct
        bluffFrequency: 0.50,
        riskTolerance: 0.80,    // loves the gamble
        positionAwareness: 0.20, // ignores position
        rationality: 0.55,
        tiltReactivity: 0.55,
        pressureResistance: 0.75, // calls big bets out of pride
        trashFoldTendency: 0.15,  // plays far too many hands
        drawDiscipline: 0.50,   // tactically sound, but bends it to deceive
        drawBluffiness: 0.80,   // stands pat / short-draws to fake strength
        openingDiscipline: 0.20, // gambles on opening light, risks exposure
        omahaCoordination: 0.35, // Omaha: plays a wide, loose range
        omahaNuttiness: 0.35     // Omaha: gambles with non-nut hands
    )

    /// The starting roster. More personalities arrive with game progression.
    static let starting: [Personality] = [.eagerNovice, .conservativeRock, .hotAggressor]

    // MARK: - Machiavelli archetypes (D-070)
    //
    // Three attitudes toward the table, placed at distinct corners of the two
    // independent axes (search depth × patience) — NOT three grades of one dial. The
    // poker dials are left at neutral defaults: no Machiavelli bot reads them, and no
    // poker bot reads the Machiavelli dials, so these presets change nothing elsewhere.

    /// The student — young, quick. Scans little and lays down what it sees. Shallow
    /// search, little patience: it plays fast and takes the placement in front of it.
    static let machiavelliStudent = Personality(
        name: "Machiavelli Student",
        tightness: 0.5, aggression: 0.5, bluffFrequency: 0, riskTolerance: 0.5,
        positionAwareness: 0.3, rationality: 0.5, tiltReactivity: 0.4,
        machiavelliSearchDepth: 0.20,   // glances at the table
        machiavelliPatience: 0.15,      // grabs the first placement it finds
        machiavelliMalusAversion: 0.30  // young: only loosely aware of the penalty
    )

    /// The adult — searches the table well but is patient, sometimes forgoing a
    /// placement it has already spotted to wait for a better draw. Deep search, high
    /// patience: the two axes pulling in different directions.
    static let machiavelliAdult = Personality(
        name: "Machiavelli Adult",
        tightness: 0.5, aggression: 0.5, bluffFrequency: 0, riskTolerance: 0.5,
        positionAwareness: 0.5, rationality: 0.7, tiltReactivity: 0.2,
        machiavelliSearchDepth: 0.70,   // reads the table thoroughly
        machiavelliPatience: 0.80,      // holds, waiting for something better…
        machiavelliMalusAversion: 0.85  // …but sheds heavies and won't be caught holding
    )

    /// The professor — old, a master who dismantles and rebuilds the table (yours
    /// included) with relish. Deepest search; moderate patience — it usually acts on
    /// what its deep search unearths. Takes its time, and that time is character.
    static let machiavelliProfessor = Personality(
        name: "Machiavelli Professor",
        tightness: 0.5, aggression: 0.6, bluffFrequency: 0, riskTolerance: 0.5,
        positionAwareness: 0.6, rationality: 0.9, tiltReactivity: 0.1,
        machiavelliSearchDepth: 1.00,   // exhausts the recomposition space
        machiavelliPatience: 0.50,      // reworks the table and plays it
        machiavelliMalusAversion: 0.90  // a master: keenly aware of the penalty
    )

    /// The three Machiavelli archetypes, in progression order.
    static let machiavelliRoster: [Personality] = [.machiavelliStudent, .machiavelliAdult, .machiavelliProfessor]
}

// MARK: - Small numeric helper

extension Double {
    /// Clamped into the closed unit interval.
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
