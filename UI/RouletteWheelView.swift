// RouletteWheelView.swift
// =====================================================================
// The VISUAL wheel and ball (D-105): the sighted player's reveal.
//
// Until now the spin's outcome lived only in the spoken line and in the number
// that appears on the felt — channels built for the ear. A sighted player at a
// real table watches the ball settle; this view gives that back: the wheel
// (drawn from the engine's `RouletteLayout.wheelOrder`, so it can never disagree
// with the resolver) spins and decelerates so the WINNING pocket ends under the
// top marker, while the ball counter-orbits and drops into it, timed to the same
// wait the audio already governs (the wheel mp3's duration, D-104). The ball
// settles right before the outcome line — the sighted reveal and the audible
// reveal land together, and neither anticipates the other (D-085).
//
// The whole thing is DECORATIVE for VoiceOver (`accessibilityHidden`): the blind
// player's channel is the outcome line and the stable felt anchor element, which
// keep working exactly as before. "Nessuno perde niente", in both directions
// (D-097): the wheel adds the eye's channel without touching the ear's.
//
// Reduce Motion is honoured: no orbiting — the wheel presents the result by
// snapping when the spin resolves.

import SwiftUI
import GameEngine
import GameWorld

/// Pure angles of the physical wheel, testable without SwiftUI (D-017).
public enum RouletteWheelGeometry {
    /// The angular width of one pocket sector.
    public static let sectorDegrees: Double = 360.0 / 37.0

    /// The centre of `pocket`'s sector in the wheel's own space, in degrees
    /// clockwise from the top (pocket 0 sits at the top of the unrotated wheel).
    public static func angle(of pocket: Int) -> Double {
        let index = RouletteLayout.wheelOrder.firstIndex(of: pocket) ?? 0
        return Double(index) * sectorDegrees
    }

    /// The wheel rotation that brings `pocket` under the top marker, normalised
    /// to 0..<360 — the spin's destination angle before full turns are added.
    public static func restingRotation(for pocket: Int) -> Double {
        normalized(-angle(of: pocket))
    }

    /// A value congruent mod 360, in 0..<360.
    public static func normalized(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}

/// The spinning wheel with its ball. Purely visual — the parent's stable
/// accessibility anchor carries the spoken state.
struct RouletteWheelView: View {
    let spinTarget: Int?
    let spinDuration: Double
    /// The last settled pocket, so the ball rests where it landed while betting.
    let restingPocket: Int?
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var wheelRotation: Double = 0
    @State private var ballAngle: Double = 0
    @State private var ballSettled = true
    @State private var ballVisible = false

    var body: some View {
        ZStack {
            wheelFace
                .rotationEffect(.degrees(wheelRotation))
            marker
            if ballVisible { ball }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
        .onAppear { if let pocket = restingPocket { rest(on: pocket) } }
        .onChange(of: spinTarget) { target in
            // Without motion (or with a near-zero test wait) nothing moves at spin
            // start: the result is presented when the spin RESOLVES, below — the
            // visual reveal must not anticipate the audible one (D-085).
            guard let target, !reduceMotion, spinDuration >= 0.3 else { return }
            spin(to: target)
        }
        .onChange(of: restingPocket) { pocket in
            guard let pocket, reduceMotion || spinDuration < 0.3 else { return }
            rest(on: pocket)
        }
    }

    // MARK: - The spin

    /// Plans the whole spin at once: the wheel takes two clockwise turns and stops
    /// with the winning pocket under the marker; the ball takes three counter turns
    /// and ends at the marker too, dropping from the rim into the pocket ring over
    /// the final beat — so ball, pocket and marker meet exactly when the audio wait
    /// ends, right before the outcome line.
    private func spin(to target: Int) {
        let wheelEndBase = RouletteWheelGeometry.restingRotation(for: target)
        let wheelEnd = wheelRotation + 720
            + RouletteWheelGeometry.normalized(wheelEndBase - wheelRotation)
        let ballEnd = ballAngle - 1080 - RouletteWheelGeometry.normalized(ballAngle)

        ballVisible = true
        ballSettled = false
        withAnimation(.timingCurve(0.16, 0.6, 0.22, 1.0, duration: spinDuration)) {
            wheelRotation = wheelEnd
            ballAngle = ballEnd
        }
        withAnimation(.easeOut(duration: 0.5).delay(max(0, spinDuration - 0.6))) {
            ballSettled = true
        }
    }

    /// The settled pose, without motion: `pocket` under the marker, ball resting in it.
    /// Used on appear, and as the reveal when Reduce Motion (or a test-speed wait)
    /// skips the orbit — it runs at RESOLVE, so it reveals no earlier than the line.
    private func rest(on pocket: Int) {
        wheelRotation = RouletteWheelGeometry.restingRotation(for: pocket)
        ballAngle = 0
        ballSettled = true
        ballVisible = true
    }

    // MARK: - Drawing

    private var wheelFace: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let sector = RouletteWheelGeometry.sectorDegrees

            for (index, pocket) in RouletteLayout.wheelOrder.enumerated() {
                let mid = Double(index) * sector - 90
                let start = Angle.degrees(mid - sector / 2)
                let end = Angle.degrees(mid + sector / 2)
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius * 0.97,
                            startAngle: start, endAngle: end, clockwise: false)
                path.closeSubpath()
                context.fill(path, with: .color(sectorColor(pocket)))
                context.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 0.5)

                let radians = mid * .pi / 180
                let position = CGPoint(x: center.x + cos(radians) * radius * 0.84,
                                       y: center.y + sin(radians) * radius * 0.84)
                let label = context.resolve(
                    Text(verbatim: "\(pocket)")
                        .font(.system(size: max(7, radius * 0.10), weight: .bold, design: .rounded))
                        .foregroundColor(.white))
                context.drawLayer { layer in
                    layer.translateBy(x: position.x, y: position.y)
                    layer.rotate(by: .degrees(mid + 90))
                    layer.draw(label, at: .zero, anchor: .center)
                }
            }

            // The pocket ring separator and the hub.
            let ringRect = CGRect(x: center.x - radius * 0.72, y: center.y - radius * 0.72,
                                  width: radius * 1.44, height: radius * 1.44)
            context.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.25)), lineWidth: 1)
            let hubRect = CGRect(x: center.x - radius * 0.5, y: center.y - radius * 0.5,
                                 width: radius, height: radius)
            context.fill(Path(ellipseIn: hubRect), with: .color(.black.opacity(0.55)))
            context.stroke(Path(ellipseIn: hubRect), with: .color(TablePalette.accent.opacity(0.6)), lineWidth: 1)
        }
        .overlay(Circle().strokeBorder(TablePalette.accent.opacity(0.8), lineWidth: 2))
    }

    /// The stationary marker the winning pocket stops under.
    private var marker: some View {
        Triangle()
            .fill(TablePalette.accent)
            .frame(width: 12, height: 9)
            .offset(y: -diameter / 2 - 1)
    }

    private var ball: some View {
        Circle()
            .fill(Color.white)
            .frame(width: max(7, diameter * 0.045), height: max(7, diameter * 0.045))
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
            .offset(y: -diameter / 2 * (ballSettled ? 0.60 : 0.90))
            .rotationEffect(.degrees(ballAngle))
    }

    private func sectorColor(_ pocket: Int) -> Color {
        switch RouletteLayout.color(of: pocket) {
        case .red: return Color(red: 0.62, green: 0.13, blue: 0.13)
        case .black: return Color(white: 0.10)
        case .green: return Color(red: 0.10, green: 0.42, blue: 0.24)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
