import SwiftUI
import Combine
import AppKit

// MARK: - Breathing Model

private let inhaleDuration: Double = 6
private let exhaleDuration: Double = 6
private let cycleDuration: Double = inhaleDuration + exhaleDuration

enum BreathPhase {
    case inhale, exhale
    var label: String {
        switch self {
        case .inhale: return "Breathe In"
        case .exhale: return "Breathe Out"
        }
    }
    var hint: String {
        switch self {
        case .inhale: return "Slowly, through your nose"
        case .exhale: return "Gently, through your nose"
        }
    }
    var other: BreathPhase { self == .inhale ? .exhale : .inhale }
}

struct BreathState {
    let phase: BreathPhase
    let fullness: Double
    let phaseProgress: Double
    let timeIntoPhase: Double
    let cycleCount: Int
    let secondsRemaining: Int
}

/// Raised-cosine easing: velocity reaches zero at the turning points, so the
/// breath settles rather than snapping. Pure function of time — every element
/// samples this, so nothing can drift out of sync.
func breathFullness(at elapsed: Double) -> Double {
    let t = max(0, elapsed)
    let pos = t.truncatingRemainder(dividingBy: cycleDuration)
    return (1 - cos(2 * .pi * pos / cycleDuration)) / 2
}

func breathState(at elapsed: Double) -> BreathState {
    let t = max(0, elapsed)
    let pos = t.truncatingRemainder(dividingBy: cycleDuration)
    let inhaling = pos < inhaleDuration
    let into = inhaling ? pos : pos - inhaleDuration
    let progress = into / (inhaling ? inhaleDuration : exhaleDuration)
    let remaining = inhaling ? inhaleDuration - pos : cycleDuration - pos
    return BreathState(
        phase: inhaling ? .inhale : .exhale,
        fullness: breathFullness(at: t),
        phaseProgress: progress,
        timeIntoPhase: into,
        cycleCount: Int(t / cycleDuration),
        secondsRemaining: max(1, Int(ceil(remaining)))
    )
}

// MARK: - Palette

/// An sRGB colour that can be mixed cheaply. The scene blends colours with the
/// breath every frame, and doing that through NSColor conversions at display
/// rate is wasted work.
struct RGB {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        let k = max(0, min(1, t))
        return RGB(r + (o.r - r) * k, g + (o.g - g) * k, b + (o.b - b) * k)
    }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

// Monument Valley: flat, confident pastels. Each solid carries a light and a
// dark face; that tonal step is what sells the fold, so there is no blur or
// glow anywhere.
enum MV {
    static let skyTop      = RGB(0.639, 0.624, 0.804)
    static let skyTopFull  = RGB(0.706, 0.686, 0.859)
    static let skyMid      = RGB(0.827, 0.718, 0.792)
    static let skyMidFull  = RGB(0.871, 0.765, 0.820)
    static let skyBottom   = RGB(0.972, 0.816, 0.702)
    static let skyBotFull  = RGB(0.984, 0.871, 0.769)

    static let sun         = RGB(0.992, 0.937, 0.867)

    static let coralLight  = RGB(0.965, 0.616, 0.553)
    static let coralDark   = RGB(0.847, 0.451, 0.404)
    static let roseLight   = RGB(0.882, 0.596, 0.702)
    static let roseDark    = RGB(0.722, 0.435, 0.553)
    static let violetLight = RGB(0.706, 0.612, 0.808)
    static let violetDark  = RGB(0.545, 0.451, 0.667)
    static let sageLight   = RGB(0.510, 0.776, 0.702)
    static let sageDark    = RGB(0.361, 0.616, 0.561)

    static let cream       = RGB(0.992, 0.949, 0.906)
    static let plum        = RGB(0.318, 0.235, 0.361)

    static let groundLight = RGB(0.914, 0.769, 0.706)
    static let groundDark  = RGB(0.788, 0.635, 0.596)

    static let stoneLight  = RGB(0.784, 0.694, 0.788)
    static let stoneMid    = RGB(0.639, 0.545, 0.678)
    static let stoneDark   = RGB(0.502, 0.412, 0.549)
}

// MARK: - Geometry helpers

@inline(__always)
func poly(_ pts: [CGPoint]) -> Path {
    var p = Path()
    guard let first = pts.first else { return p }
    p.move(to: first)
    for pt in pts.dropFirst() { p.addLine(to: pt) }
    p.closeSubpath()
    return p
}

@inline(__always)
func circle(_ c: CGPoint, _ r: Double) -> Path {
    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

@inline(__always)
func diamond(_ c: CGPoint, _ s: Double) -> Path {
    poly([CGPoint(x: c.x, y: c.y - s), CGPoint(x: c.x + s, y: c.y),
          CGPoint(x: c.x, y: c.y + s), CGPoint(x: c.x - s, y: c.y)])
}

// MARK: - Lotus

/// One half of a petal, on one side of its crease. The flank is a quadratic
/// curve rather than a straight edge, so it stays wide most of the way out and
/// neighbouring petals overlap instead of leaving wedge-shaped gaps.
func petalHalf(center c: CGPoint, angle: Double, r0: Double, r1: Double,
               widthRatio: Double, side: Double) -> Path {
    let dir  = CGPoint(x: cos(angle), y: sin(angle))
    let perp = CGPoint(x: -sin(angle), y: cos(angle))
    let rm = (r0 + r1) * 0.5
    let w  = rm * widthRatio

    func P(_ r: Double, _ off: Double) -> CGPoint {
        CGPoint(x: c.x + dir.x * r + perp.x * off,
                y: c.y + dir.y * r + perp.y * off)
    }

    var p = Path()
    p.move(to: P(r0, 0))
    // A quadratic passes through half its control offset at the midpoint,
    // so doubling w puts the widest point exactly at ±w.
    p.addQuadCurve(to: P(r1, 0), control: P(rm, side * w * 2))
    p.closeSubpath()                       // straight back down the crease
    return p
}

/// A ring of petals. `lag` delays this ring's breath so the layers unfold in
/// sequence; `twist` turns the ring a little as it opens, the way a real bloom
/// unfurls rather than simply scaling.
func drawPetalRing(_ ctx: inout GraphicsContext, center: CGPoint, elapsed: Double,
                   count: Int, scale: Double, R: Double, spin: Double, twist: Double,
                   lag: Double, offset: Double, light: RGB, dark: RGB) {
    let b = breathFullness(at: elapsed - lag)
    let r0 = R * scale * (0.10 + 0.05 * b)
    let r1 = R * scale * (0.62 + 0.34 * b)    // stays composed even when empty
    let wr = 0.47 + 0.05 * b                  // widen as it opens, so petals never part
    let rot = elapsed * spin + offset + twist * (b - 0.5)

    // Open petals catch the light: both faces lift a touch on the inhale.
    let lightC = light.mix(MV.cream, 0.16 * b).color
    let darkC  = dark.mix(light, 0.12 * b).color

    // Each petal's light half overlaps its neighbour's dark half. Drawing every
    // dark half first and every light half second keeps that layering identical
    // all the way round — drawing petal by petal leaves the first one tucked
    // under both neighbours, a visible seam in the pinwheel.
    for (side, fill) in [(-1.0, darkC), (1.0, lightC)] {
        for i in 0..<count {
            let a = rot + (Double(i) / Double(count)) * 2 * .pi
            ctx.fill(petalHalf(center: center, angle: a, r0: r0, r1: r1,
                               widthRatio: wr, side: side),
                     with: .color(fill))
        }
    }
}

/// The heart of the lotus: a two-tone diamond that turns a quarter as the
/// breath fills, around a small cream seed.
func drawCore(_ ctx: inout GraphicsContext, center c: CGPoint, R: Double, b: Double) {
    let r = R * (0.058 + 0.042 * b)
    let turn = b * .pi / 4
    let pts = (0..<4).map { k -> CGPoint in
        let a = -Double.pi / 2 + turn + Double(k) * .pi / 2
        return CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
    }
    ctx.fill(poly(pts), with: .color(MV.sageLight.color))
    ctx.fill(poly([pts[0], pts[1], pts[2]]), with: .color(MV.sageDark.color))
    ctx.fill(circle(c, R * (0.016 + 0.006 * b)), with: .color(MV.cream.color))
}

// MARK: - Progress line

/// A stroke that looks drawn by hand rather than plotted: the radius wavers,
/// the weight varies along its length, and both ends taper the way a pen does
/// as it touches down and lifts.
///
/// Built as a filled ribbon (an outer edge and an inner edge) rather than a
/// stroked path, because that is what allows the thickness to vary.
/// The wobble is layered sines keyed to the angle — deterministic, so the line
/// holds still within a breath instead of jittering frame to frame.
func handDrawnArc(center c: CGPoint, radius: Double, from f0: Double, to f1: Double,
                  thickness: Double, wobble: Double, seed: Double,
                  tapered: Bool = true) -> Path {
    var path = Path()
    guard f1 - f0 > 0.0015 else { return path }

    let steps = max(8, Int((f1 - f0) * 260))
    var outer = [CGPoint](); outer.reserveCapacity(steps + 1)
    var inner = [CGPoint](); inner.reserveCapacity(steps + 1)

    for i in 0...steps {
        let u = Double(i) / Double(steps)          // position across the visible span
        let f = f0 + (f1 - f0) * u
        let a = -Double.pi / 2 + f * 2 * .pi

        let waver = sin(a * 3.1 + seed) * 0.55
                  + sin(a * 6.7 + seed * 1.7) * 0.28
                  + sin(a * 11.3 + seed * 0.6) * 0.14
        let r = radius + waver * wobble

        // The track runs untapered, so a full circle has no thin spot where its
        // ends meet; the drawn line tapers like a pen touching down and lifting.
        let taper = tapered ? pow(sin(.pi * u), 0.30) : 1
        let vary = 1 + 0.26 * sin(a * 5.3 + seed * 2.3)
        let half = thickness * 0.5 * taper * vary

        outer.append(CGPoint(x: c.x + cos(a) * (r + half), y: c.y + sin(a) * (r + half)))
        inner.append(CGPoint(x: c.x + cos(a) * (r - half), y: c.y + sin(a) * (r - half)))
    }

    path.move(to: outer[0])
    for p in outer.dropFirst() { path.addLine(to: p) }
    for p in inner.reversed() { path.addLine(to: p) }
    path.closeSubpath()
    return path
}

// MARK: - World

/// Isometric cube: diamond top face plus two extruded sides.
func drawCube(_ ctx: inout GraphicsContext, center c: CGPoint, a: Double, h: Double,
              top: Color, left: Color, right: Color) {
    let tp = CGPoint(x: c.x,     y: c.y - a * 0.5)
    let rt = CGPoint(x: c.x + a, y: c.y)
    let bt = CGPoint(x: c.x,     y: c.y + a * 0.5)
    let lf = CGPoint(x: c.x - a, y: c.y)

    ctx.fill(poly([lf, bt, CGPoint(x: bt.x, y: bt.y + h),
                   CGPoint(x: lf.x, y: lf.y + h)]), with: .color(left))
    ctx.fill(poly([bt, rt, CGPoint(x: rt.x, y: rt.y + h),
                   CGPoint(x: bt.x, y: bt.y + h)]), with: .color(right))
    ctx.fill(poly([tp, rt, bt, lf]), with: .color(top))
}

/// A small Ida-like figure. The silhouette only reads at this size if the hat
/// is clearly broader than the head and the gown flares into a bell — otherwise
/// the three shapes merge into an arrow. `rise` lets her breathe with you.
func drawFigure(_ ctx: inout GraphicsContext, feet: CGPoint, height h: Double,
                rise: Double) {
    let gownH   = h * (0.46 + 0.025 * rise)
    let gownBot = h * 0.50
    let gownTop = h * 0.20
    let headR   = h * 0.13
    let hatW    = h * 0.31   // half-width
    let hatH    = h * 0.24
    let ink = MV.cream.color

    ctx.fill(poly([
        CGPoint(x: feet.x - gownBot / 2, y: feet.y),
        CGPoint(x: feet.x + gownBot / 2, y: feet.y),
        CGPoint(x: feet.x + gownTop / 2, y: feet.y - gownH),
        CGPoint(x: feet.x - gownTop / 2, y: feet.y - gownH)
    ]), with: .color(ink))

    let headC = CGPoint(x: feet.x, y: feet.y - gownH - headR * 0.85)
    ctx.fill(circle(headC, headR), with: .color(ink))

    let hatBase = headC.y - headR * 0.35
    ctx.fill(poly([
        CGPoint(x: feet.x - hatW, y: hatBase),
        CGPoint(x: feet.x + hatW, y: hatBase),
        CGPoint(x: feet.x, y: hatBase - hatH)
    ]), with: .color(ink))
}

/// Faint towers and domes on the horizon, in a tone barely off the sky. They
/// give the scene a world behind it without competing with the lotus.
func drawSkyline(_ ctx: inout GraphicsContext, w: Double, h: Double, groundY: Double) {
    enum Roof { case flat, dome, spire }
    let far = MV.skyBottom.mix(MV.stoneMid, 0.20).color
    let near = MV.skyBottom.mix(MV.stoneMid, 0.30).color

    // (x, width, height, roof, near?) — x and width as fractions of the width,
    // height as a fraction of the height. Kept clear of the centre, where the
    // plinth and the text live.
    let towers: [(Double, Double, Double, Roof, Bool)] = [
        (0.025, 0.060, 0.080, .dome,  false),
        (0.100, 0.085, 0.042, .flat,  false),
        (0.195, 0.032, 0.125, .spire, false),
        (0.745, 0.070, 0.048, .flat,  false),
        (0.830, 0.036, 0.108, .dome,  false),
        (0.905, 0.055, 0.068, .spire, false),
        (0.000, 0.120, 0.026, .flat,  true),
        (0.270, 0.070, 0.020, .flat,  true),
        (0.660, 0.080, 0.028, .flat,  true),
        (0.900, 0.100, 0.034, .flat,  true),
    ]
    for (x, bw, bh, roof, isNear) in towers {
        let fill = isNear ? near : far
        let rx = x * w, rw = bw * w, top = groundY - bh * h
        ctx.fill(Path(CGRect(x: rx, y: top, width: rw, height: groundY - top)),
                 with: .color(fill))
        switch roof {
        case .flat: break
        case .dome:
            ctx.fill(circle(CGPoint(x: rx + rw / 2, y: top), rw / 2), with: .color(fill))
        case .spire:
            ctx.fill(poly([CGPoint(x: rx, y: top), CGPoint(x: rx + rw, y: top),
                           CGPoint(x: rx + rw / 2, y: top - rw * 1.25)]),
                     with: .color(fill))
        }
    }
}

/// Tiny diamond motes rising very slowly through the sky. Each fades in at the
/// bottom of its travel and out at the top, so the wrap back down is invisible.
func drawMotes(_ ctx: inout GraphicsContext, w: Double, groundY: Double,
               elapsed: Double, b: Double) {
    let travel = groundY * 0.82
    for i in 0..<16 {
        let fi = Double(i)
        let h1 = frac(sin(fi * 12.9898) * 43758.5453)
        let h2 = frac(sin(fi * 78.233)  * 12543.1234)
        let h3 = frac(sin(fi * 39.425)  * 24634.6345)

        let p = frac(h3 + elapsed * (0.010 + 0.012 * h2))
        let y = groundY - 12 - p * travel
        let x = w * (0.04 + 0.92 * h1) + sin(elapsed * (0.22 + 0.2 * h2) + fi) * w * 0.012
        let alpha = 0.55 * sin(.pi * p) * (0.6 + 0.4 * b)
        ctx.fill(diamond(CGPoint(x: x, y: y), 1.1 + 1.7 * h2),
                 with: .color(MV.cream.color.opacity(alpha)))
    }
}

/// Rings that slip out from behind the disc at each turn of the breath, in time
/// with the singing bowl. A second, fainter ring trails the first.
func drawRipples(_ ctx: inout GraphicsContext, center: CGPoint, radius: Double,
                 elapsed: Double) {
    let age0 = elapsed.truncatingRemainder(dividingBy: inhaleDuration)
    guard elapsed - age0 > 0.5 else { return }   // no ripple for the launch itself
    let life = 3.6
    for (delay, strength) in [(0.0, 1.0), (0.45, 0.55)] {
        let age = age0 - delay
        guard age > 0, age < life else { continue }
        let k = age / life
        let grow = 1 - pow(1 - k, 3)
        let r = radius * (1.0 + 0.30 * grow)
        let alpha = 0.60 * strength * pow(1 - k, 2) * smoothstep(0, 0.20, age)
        ctx.stroke(circle(center, r), with: .color(MV.cream.color.opacity(alpha)),
                   lineWidth: 1.7 * (1 - 0.55 * k))
    }
}

// MARK: - Scene

struct MonumentScene: View {
    let elapsed: Double
    var intro: Double = 1
    var rate: Double = 1
    var everPaused = false

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let s = breathState(at: elapsed)
            let b = s.fullness
            let w = size.width, h = size.height
            let m = min(w, h)
            let R = m * 0.285
            let center = CGPoint(x: w / 2, y: h * 0.305)
            let groundY = h * 0.885

            // — Sky: three stops, warming and lifting a touch on the inhale.
            let sky = Gradient(stops: [
                .init(color: MV.skyTop.mix(MV.skyTopFull, b).color, location: 0),
                .init(color: MV.skyMid.mix(MV.skyMidFull, b).color, location: 0.55),
                .init(color: MV.skyBottom.mix(MV.skyBotFull, b).color, location: 1),
            ])
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(sky, startPoint: .zero,
                                           endPoint: CGPoint(x: 0, y: h)))

            drawMotes(&ctx, w: w, groundY: groundY, elapsed: elapsed, b: b)
            drawSkyline(&ctx, w: w, h: h, groundY: groundY)

            // — Floating blocks, drifting slowly and lifting with the inhale.
            let d1 = sin(elapsed * 0.20) * h * 0.010 - b * h * 0.006
            let d2 = sin(elapsed * 0.16 + 1.7) * h * 0.010 - b * h * 0.008
            drawCube(&ctx, center: CGPoint(x: w * 0.135, y: h * 0.565 + d1),
                     a: m * 0.043, h: m * 0.030,
                     top: MV.stoneLight.color.opacity(0.72),
                     left: MV.stoneDark.color.opacity(0.60),
                     right: MV.stoneMid.color.opacity(0.62))
            drawCube(&ctx, center: CGPoint(x: w * 0.868, y: h * 0.505 + d2),
                     a: m * 0.033, h: m * 0.024,
                     top: MV.stoneLight.color.opacity(0.62),
                     left: MV.stoneDark.color.opacity(0.50),
                     right: MV.stoneMid.color.opacity(0.52))

            // — Ripples first, so they slip out from behind the disc.
            let sunR = R * 1.20
            drawRipples(&ctx, center: center, radius: sunR, elapsed: elapsed)

            // — Pale sun disc: a fixed frame for the breathing to happen inside.
            ctx.fill(circle(center, sunR), with: .color(MV.sun.color.opacity(0.62)))

            // Everything that guides the breath fades in on launch.
            var guide = ctx
            guide.opacity = intro

            // — Hand-drawn progress line. The seed changes only at the start of a
            //   cycle, where the line is empty, so its waver never visibly jumps.
            let ringR = R * 1.06
            let seed = Double(s.cycleCount % 11) * 1.37
            let wob = R * 0.018    // shared, so the line traces the track exactly

            guide.fill(handDrawnArc(center: center, radius: ringR, from: 0, to: 1,
                                    thickness: R * 0.013, wobble: wob, seed: seed,
                                    tapered: false),
                       with: .color(MV.plum.color.opacity(0.11)))

            // The pen eases into and out of each turn, settling with the breath
            // instead of arriving at full speed. Inhale draws the line on; exhale
            // erases it from behind; both turns land on a full or empty circle.
            let p = s.phaseProgress
            let eased = 0.35 * p + 0.65 * (p * p * (3 - 2 * p))
            let span = s.phase == .inhale ? (0.0, eased) : (eased, 1.0)
            guide.fill(handDrawnArc(center: center, radius: ringR,
                                    from: span.0, to: span.1,
                                    thickness: R * 0.028, wobble: wob, seed: seed),
                       with: .color(MV.plum.color.opacity(0.48)))

            // — The lotus: outer ring leads, inner rings follow on a lag, each
            //   twisting a little against its neighbour as it opens.
            drawPetalRing(&guide, center: center, elapsed: elapsed, count: 10,
                          scale: 1.0, R: R, spin: 0.050, twist: 0.12, lag: 0.0,
                          offset: 0, light: MV.coralLight, dark: MV.coralDark)
            drawPetalRing(&guide, center: center, elapsed: elapsed, count: 10,
                          scale: 0.72, R: R, spin: -0.078, twist: -0.16, lag: 0.50,
                          offset: .pi / 10, light: MV.roseLight, dark: MV.roseDark)
            drawPetalRing(&guide, center: center, elapsed: elapsed, count: 8,
                          scale: 0.46, R: R, spin: 0.115, twist: 0.22, lag: 0.95,
                          offset: 0, light: MV.violetLight, dark: MV.violetDark)
            drawCore(&guide, center: center, R: R, b: breathFullness(at: elapsed - 1.2))

            // — Ground plane.
            ctx.fill(Path(CGRect(x: 0, y: groundY, width: w, height: h - groundY)),
                     with: .color(MV.groundLight.color))
            ctx.fill(Path(CGRect(x: 0, y: groundY, width: w, height: 2.5)),
                     with: .color(MV.groundDark.color.opacity(0.55)))

            // — Plinth in stone, so the cream figure reads against it.
            let a = m * 0.080
            let plinthC = CGPoint(x: w / 2, y: groundY - h * 0.004)
            drawCube(&ctx, center: plinthC, a: a, h: h * 0.042,
                     top: MV.stoneLight.color, left: MV.stoneDark.color,
                     right: MV.stoneMid.color)
            drawFigure(&ctx, feet: CGPoint(x: plinthC.x, y: plinthC.y + a * 0.05),
                       height: m * 0.105, rise: b)

            drawGuidance(&ctx, size: size, elapsed: elapsed, rate: rate,
                         everPaused: everPaused, intro: intro)
        }
    }
}

// MARK: - Guidance text

/// Shaped text, kept between frames. Re-shaping the words every frame measured
/// at about 7 of the app's 24% CPU; the strings here are few and repeat
/// constantly, so each is shaped once.
final class TextCache {
    static let shared = TextCache()
    struct Entry { let text: GraphicsContext.ResolvedText; let size: CGSize }
    private var store: [String: Entry] = [:]

    func get(_ key: String, in ctx: GraphicsContext, _ make: () -> Text) -> Entry {
        if let e = store[key] { return e }
        if store.count > 256 { store.removeAll() }     // cycle counts keep growing
        let r = ctx.resolve(make())
        let e = Entry(text: r, size: r.measure(in: CGSize(width: 2000, height: 200)))
        store[key] = e
        return e
    }
}

/// The words, drawn into the same canvas as the scene, on the same clock.
///
/// Changes hand over on the breath's own timeline: the outgoing line lifts away
/// and clears before the incoming one settles up into place. Two lines of text
/// overlapping, even briefly, reads as a glitch.
func drawGuidance(_ ctx: inout GraphicsContext, size: CGSize, elapsed: Double,
                  rate: Double, everPaused: Bool, intro: Double) {
    guard intro > 0.002 else { return }
    let s = breathState(at: elapsed)
    let into = s.timeIntoPhase
    let hasPrevious = elapsed >= inhaleDuration

    // Phase words.
    let leave = smoothstep(0, 0.32, into)
    let outA = hasPrevious ? 1 - leave : 0
    let inA  = hasPrevious ? smoothstep(0.32, 0.95, into) : 1

    // Countdown: each digit rolls up as the last lifts away. Both move on one
    // curve, so they stay well apart for the brief moment both show.
    let remaining = 6 - into
    let digit = min(6, max(1, Int(ceil(remaining - 1e-9))))
    let u = Double(digit) - remaining              // seconds this digit has shown
    let prevDigit = digit == 6 ? 1 : digit + 1
    let roll = smoothstep(0, 0.42, u)
    let digitIn  = smoothstep(0.10, 0.40, u)
    let digitOut = elapsed > 0.6 ? 1 - smoothstep(0, 0.24, u) : 0

    // Status follows the glide itself: "tap to pause" fades as the breath slows,
    // "paused" arrives as it comes to rest, and the reverse on resume.
    let runA    = smoothstep(0.45, 0.92, rate)
    let pausedA = everPaused ? 1 - smoothstep(0.08, 0.50, rate) : 0
    // The cycle number hands over with the phase words at the top of each cycle.
    let newCycle = s.phase == .inhale && hasPrevious
    let cycleOut = newCycle ? outA : 0
    let cycleIn  = newCycle ? inA : 1

    // Letter spacing opens with the breath.
    let tracking = 5 + 2.4 * s.fullness
    let plum = MV.plum.color
    let cx = size.width / 2
    let y0 = size.height * 0.660 + 8 * (1 - intro)
    let base = ctx
    let cache = TextCache.shared

    func put(_ key: String, dy: Double, _ alpha: Double, _ make: () -> Text) {
        let a = alpha * intro
        guard a > 0.003 else { return }
        var g = base
        g.opacity = a
        g.draw(cache.get(key, in: base, make).text,
               at: CGPoint(x: cx, y: y0 + dy), anchor: .center)
    }

    // The phase words are set letter by letter from glyphs shaped once, so the
    // spacing can breathe smoothly without re-shaping the word every frame. At
    // this much letter spacing kerning plays no part, and centring is exact.
    let labelFont = Font.system(size: 12, weight: .medium, design: .rounded)
    func glyph(_ ch: Character) -> TextCache.Entry {
        cache.get("L\(ch)", in: base) {
            Text(String(ch)).font(labelFont).foregroundStyle(plum.opacity(0.82))
        }
    }
    let spaceW = glyph("A").size.width * 0.55
    func spaced(_ word: String, dy: Double, _ alpha: Double) {
        let a = alpha * intro
        guard a > 0.003 else { return }
        let letters = Array(word)
        let widths = letters.map { $0 == " " ? spaceW : glyph($0).size.width }
        let total = widths.reduce(0, +) + tracking * Double(letters.count - 1)
        var g = base
        g.opacity = a
        var x = cx - total / 2
        for (ch, w) in zip(letters, widths) {
            if ch != " " {
                g.draw(glyph(ch).text, at: CGPoint(x: x, y: y0 + dy), anchor: .leading)
            }
            x += w + tracking
        }
    }

    spaced(s.phase.other.label.uppercased(), dy: -43 - 8 * leave, outA)
    spaced(s.phase.label.uppercased(),       dy: -43 + 8 * (1 - inA), inA)

    func number(_ n: Int) -> () -> Text {
        { Text("\(n)")
            .font(.system(size: 30, weight: .thin, design: .rounded).monospacedDigit())
            .foregroundStyle(plum.opacity(0.52)) }
    }
    put("N\(prevDigit)", dy: -10 - 12 * roll, digitOut, number(prevDigit))
    put("N\(digit)",     dy: -10 + 12 * (1 - roll), digitIn, number(digit))

    func hint(_ p: BreathPhase) -> () -> Text {
        { Text(p.hint)
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundStyle(plum.opacity(0.48)) }
    }
    put("H" + s.phase.other.hint, dy: 22, outA, hint(s.phase.other))
    put("H" + s.phase.hint,       dy: 22, inA, hint(s.phase))

    func status(_ str: String) -> () -> Text {
        { Text(str)
            .font(.system(size: 10, weight: .regular, design: .rounded))
            .tracking(1)
            .foregroundStyle(plum.opacity(0.34)) }
    }
    let was = "cycle \(s.cycleCount) · tap to pause"
    let now = "cycle \(s.cycleCount + 1) · tap to pause"
    let paused = "paused · tap to resume"
    put("S" + was,    dy: 45, runA * cycleOut, status(was))
    put("S" + now,    dy: 45, runA * cycleIn, status(now))
    put("S" + paused, dy: 45, pausedA, status(paused))
}

// MARK: - Session

/// The window's state. An ObservableObject rather than `@State`: on the macOS 27
/// SDK `@State` is a macro whose plugin ships only with full Xcode, and this
/// keeps the app buildable with the Command Line Tools alone.
final class BreathSession: ObservableObject {
    let clock = BreathClock()
    private(set) var isRunning = true
    /// True once a pause has fully glided to rest, so the timeline can stop
    /// redrawing a still picture. The only published value: everything else the
    /// picture needs is read from the clock each frame.
    @Published private(set) var settled = false
    private var pauseToken = 0

    func toggle() {
        let now = Date()
        pauseToken += 1
        isRunning.toggle()
        if isRunning {
            settled = false
            clock.setTarget(1, at: now)
            Soundscape.shared.setRunning(true)
        } else {
            clock.setTarget(0, at: now)
            Soundscape.shared.setRunning(false)
            let token = pauseToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                guard let self, token == self.pauseToken, !self.isRunning else { return }
                self.settled = true
                Soundscape.shared.suspend()
            }
        }
    }
}

// MARK: - Content

struct ContentView: View {
    @StateObject private var session = BreathSession()
    @AppStorage("muted") private var isMuted = false

    var body: some View {
        // Only the canvas lives inside the timeline, so each frame redraws one
        // display list; the gesture and the mute button are built once, outside.
        // No frame cap: on a ProMotion display this runs at 120Hz.
        TimelineView(.animation(paused: session.settled)) { timeline in
            let clock = session.clock
            let elapsed = clock.advance(to: timeline.date)
            MonumentScene(elapsed: elapsed,
                          intro: smoothstep(0.15, 1.9, clock.secondsSinceLaunch(timeline.date)),
                          rate: clock.rate,
                          everPaused: clock.everPaused)
        }
        .contentShape(Rectangle())
        .onTapGesture { session.toggle() }
        .overlay(alignment: .topTrailing) { MuteButton(isMuted: $isMuted) }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .onAppear {
            Soundscape.shared.setMuted(isMuted)
            Soundscape.shared.begin()
        }
        .onDisappear { Soundscape.shared.stop() }
    }
}

/// The button's own small state, so hovering redraws only the button.
final class ButtonState: ObservableObject {
    @Published var hovering = false
    @Published var shown = false
}

struct MuteButton: View {
    @Binding var isMuted: Bool
    @StateObject private var ui = ButtonState()

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.35)) { isMuted.toggle() }
            Soundscape.shared.setMuted(isMuted)
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(MV.plum.color.opacity(ui.hovering ? 0.75 : 0.50))
                .frame(width: 30, height: 30)
                .background(Circle().fill(MV.cream.color.opacity(ui.hovering ? 0.80 : 0.50)))
                .scaleEffect(ui.hovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.25)) { ui.hovering = h } }
        .help(isMuted ? "Unmute" : "Mute")
        .padding(18)
        // Arrives with the rest of the scene on launch.
        .opacity(ui.shown ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 1.4).delay(0.5)) { ui.shown = true } }
    }
}

// MARK: - Window styling

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(red: 0.972, green: 0.816, blue: 0.702, alpha: 1)
            window.center()
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
