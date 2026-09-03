import SwiftUI
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
}

struct BreathState {
    let phase: BreathPhase
    let fullness: Double
    let phaseProgress: Double
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
    let progress = inhaling ? pos / inhaleDuration
                            : (pos - inhaleDuration) / exhaleDuration
    let remaining = inhaling ? inhaleDuration - pos : cycleDuration - pos
    return BreathState(
        phase: inhaling ? .inhale : .exhale,
        fullness: breathFullness(at: t),
        phaseProgress: progress,
        cycleCount: Int(t / cycleDuration),
        secondsRemaining: max(1, Int(ceil(remaining)))
    )
}

// MARK: - Monument Valley Palette
// Flat, confident pastels. Each solid carries a light and a dark face; that
// tonal step is what sells the fold, so there is no blur or glow anywhere.

enum MV {
    static let skyTop      = Color(red: 0.639, green: 0.624, blue: 0.804)
    static let skyTopFull  = Color(red: 0.706, green: 0.686, blue: 0.859)
    static let skyBottom   = Color(red: 0.972, green: 0.816, blue: 0.702)
    static let skyBotFull  = Color(red: 0.984, green: 0.871, blue: 0.769)

    static let sun         = Color(red: 0.992, green: 0.937, blue: 0.867)

    static let coralLight  = Color(red: 0.965, green: 0.616, blue: 0.553)
    static let coralDark   = Color(red: 0.847, green: 0.451, blue: 0.404)

    static let roseLight   = Color(red: 0.882, green: 0.596, blue: 0.702)
    static let roseDark    = Color(red: 0.722, green: 0.435, blue: 0.553)

    static let violetLight = Color(red: 0.706, green: 0.612, blue: 0.808)
    static let violetDark  = Color(red: 0.545, green: 0.451, blue: 0.667)

    static let sageLight   = Color(red: 0.510, green: 0.776, blue: 0.702)
    static let sageDark    = Color(red: 0.361, green: 0.616, blue: 0.561)

    static let cream       = Color(red: 0.992, green: 0.949, blue: 0.906)
    static let plum        = Color(red: 0.318, green: 0.235, blue: 0.361)

    static let groundLight = Color(red: 0.914, green: 0.769, blue: 0.706)
    static let groundDark  = Color(red: 0.788, green: 0.635, blue: 0.596)

    static let stoneLight  = Color(red: 0.784, green: 0.694, blue: 0.788)
    static let stoneMid    = Color(red: 0.639, green: 0.545, blue: 0.678)
    static let stoneDark   = Color(red: 0.502, green: 0.412, blue: 0.549)
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
func ptAt(_ c: CGPoint, _ angle: Double, _ radius: Double) -> CGPoint {
    CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
}

/// One petal, creased down the middle. The outline is a pair of quadratic
/// curves rather than straight edges: a curved flank stays wide most of the way
/// out, so neighbouring petals overlap instead of leaving hard wedge-shaped
/// gaps between their tips as the flower opens.
func drawPetal(_ ctx: inout GraphicsContext, center c: CGPoint, angle: Double,
               r0: Double, r1: Double, widthRatio: Double,
               light: Color, dark: Color) {
    let dir  = CGPoint(x: cos(angle), y: sin(angle))
    let perp = CGPoint(x: -sin(angle), y: cos(angle))
    let rm = (r0 + r1) * 0.5
    let w  = rm * widthRatio

    func P(_ r: Double, _ off: Double) -> CGPoint {
        CGPoint(x: c.x + dir.x * r + perp.x * off,
                y: c.y + dir.y * r + perp.y * off)
    }

    let base = P(r0, 0)
    let apex = P(r1, 0)
    // A quadratic passes through half its control offset at the midpoint,
    // so doubling w puts the widest point exactly at ±w.
    let ctrlL = P(rm,  w * 2)
    let ctrlR = P(rm, -w * 2)

    var left = Path()
    left.move(to: base)
    left.addQuadCurve(to: apex, control: ctrlL)
    left.closeSubpath()                    // straight back down the crease
    ctx.fill(left, with: .color(light))

    var right = Path()
    right.move(to: base)
    right.addQuadCurve(to: apex, control: ctrlR)
    right.closeSubpath()
    ctx.fill(right, with: .color(dark))
}

/// A ring of petals. `lag` delays this ring's breath so the layers unfold in
/// sequence rather than all at once.
func drawPetalRing(_ ctx: inout GraphicsContext, center: CGPoint, elapsed: Double,
                   count: Int, scale: Double, R: Double, spin: Double, lag: Double,
                   offset: Double, light: Color, dark: Color) {
    let b = breathFullness(at: elapsed - lag)
    let r0 = R * scale * (0.10 + 0.05 * b)
    let r1 = R * scale * (0.62 + 0.34 * b)   // stays composed even when empty
    // Widen slightly as the flower opens, so the petals spread without parting.
    let wr = 0.47 + 0.05 * b
    let rot = elapsed * spin + offset

    for i in 0..<count {
        let a = rot + (Double(i) / Double(count)) * 2 * .pi
        drawPetal(&ctx, center: center, angle: a, r0: r0, r1: r1,
                  widthRatio: wr, light: light, dark: dark)
    }
}

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

    let steps = max(8, Int((f1 - f0) * 240))
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

/// Isometric cube: diamond top face plus two extruded sides.
/// Returns the centre of the top face, so things can stand on it.
@discardableResult
func drawCube(_ ctx: inout GraphicsContext, center c: CGPoint, a: Double, h: Double,
              top: Color, left: Color, right: Color) -> CGPoint {
    let tp = CGPoint(x: c.x,     y: c.y - a * 0.5)
    let rt = CGPoint(x: c.x + a, y: c.y)
    let bt = CGPoint(x: c.x,     y: c.y + a * 0.5)
    let lf = CGPoint(x: c.x - a, y: c.y)

    ctx.fill(poly([lf, bt, CGPoint(x: bt.x, y: bt.y + h),
                   CGPoint(x: lf.x, y: lf.y + h)]), with: .color(left))
    ctx.fill(poly([bt, rt, CGPoint(x: rt.x, y: rt.y + h),
                   CGPoint(x: bt.x, y: bt.y + h)]), with: .color(right))
    ctx.fill(poly([tp, rt, bt, lf]), with: .color(top))
    return c
}

/// A small Ida-like figure. The silhouette only reads at this size if the hat
/// is clearly broader than the head and the gown flares into a bell — otherwise
/// the three shapes merge into an arrow.
func drawFigure(_ ctx: inout GraphicsContext, feet: CGPoint, height h: Double) {
    let gownH   = h * 0.46
    let gownBot = h * 0.50
    let gownTop = h * 0.20
    let headR   = h * 0.13
    let hatW    = h * 0.31   // half-width
    let hatH    = h * 0.24

    // Gown — a wide bell.
    ctx.fill(poly([
        CGPoint(x: feet.x - gownBot / 2, y: feet.y),
        CGPoint(x: feet.x + gownBot / 2, y: feet.y),
        CGPoint(x: feet.x + gownTop / 2, y: feet.y - gownH),
        CGPoint(x: feet.x - gownTop / 2, y: feet.y - gownH)
    ]), with: .color(MV.cream))

    // Head.
    let headC = CGPoint(x: feet.x, y: feet.y - gownH - headR * 0.85)
    ctx.fill(Path(ellipseIn: CGRect(x: headC.x - headR, y: headC.y - headR,
                                    width: headR * 2, height: headR * 2)),
             with: .color(MV.cream))

    // Hat — broad brim, shallow cone.
    let hatBase = headC.y - headR * 0.35
    ctx.fill(poly([
        CGPoint(x: feet.x - hatW, y: hatBase),
        CGPoint(x: feet.x + hatW, y: hatBase),
        CGPoint(x: feet.x, y: hatBase - hatH)
    ]), with: .color(MV.cream))
}

// MARK: - Scene

struct MonumentScene: View {
    let elapsed: Double
    let state: BreathState

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let b = state.fullness
            let w = size.width, h = size.height
            let R = min(w, h) * 0.285
            let center = CGPoint(x: w / 2, y: h * 0.305)

            // — Sky: warms and lifts a touch on the inhale.
            let top = MV.skyTop.mix(MV.skyTopFull, b)
            let bot = MV.skyBottom.mix(MV.skyBotFull, b)
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [top, bot]),
                                           startPoint: .zero,
                                           endPoint: CGPoint(x: 0, y: h)))

            // — Distant floating blocks, drifting slowly. Architectural depth.
            let d1 = sin(elapsed * 0.20) * h * 0.010
            let d2 = sin(elapsed * 0.16 + 1.7) * h * 0.010
            drawCube(&ctx, center: CGPoint(x: w * 0.135, y: h * 0.565 + d1),
                     a: min(w, h) * 0.043, h: min(w, h) * 0.030,
                     top: MV.stoneLight.opacity(0.72),
                     left: MV.stoneDark.opacity(0.60),
                     right: MV.stoneMid.opacity(0.62))
            drawCube(&ctx, center: CGPoint(x: w * 0.868, y: h * 0.505 + d2),
                     a: min(w, h) * 0.033, h: min(w, h) * 0.024,
                     top: MV.stoneLight.opacity(0.62),
                     left: MV.stoneDark.opacity(0.50),
                     right: MV.stoneMid.opacity(0.52))

            // — Pale sun disc. Held at a fixed size so the breathing lotus has a
            //   stable frame to open inside, like a moon or a portal.
            let sunR = R * 1.20
            let sunRect = CGRect(x: center.x - sunR, y: center.y - sunR,
                                 width: sunR * 2, height: sunR * 2)
            ctx.fill(Path(ellipseIn: sunRect), with: .color(MV.sun.opacity(0.62)))

            // — Hand-drawn progress line. The seed changes only at the start of a
            //   cycle, where the line is empty, so its waver never visibly jumps.
            let ringR = R * 1.06
            let seed = Double(state.cycleCount % 11) * 1.37
            // Track and line share a radius function, so the line traces the
            // track exactly rather than drifting beside it.
            let wob = R * 0.018

            ctx.fill(handDrawnArc(center: center, radius: ringR, from: 0, to: 1,
                                  thickness: R * 0.013, wobble: wob, seed: seed,
                                  tapered: false),
                     with: .color(MV.plum.opacity(0.11)))

            // Inhale draws the line on; exhale erases it from behind. Both turns
            // land on a full or empty circle, so the transition is seamless.
            let span: (Double, Double) = state.phase == .inhale
                ? (0, state.phaseProgress)
                : (state.phaseProgress, 1)
            ctx.fill(handDrawnArc(center: center, radius: ringR,
                                  from: span.0, to: span.1,
                                  thickness: R * 0.028, wobble: wob, seed: seed),
                     with: .color(MV.plum.opacity(0.48)))

            // — The lotus: outer ring leads, inner rings follow on a lag.
            //   Counts and widths are set so neighbours overlap at every point
            //   in the breath, leaving no gaps as the flower opens.
            drawPetalRing(&ctx, center: center, elapsed: elapsed, count: 10,
                          scale: 1.0, R: R, spin: 0.050, lag: 0.0, offset: 0,
                          light: MV.coralLight, dark: MV.coralDark)
            drawPetalRing(&ctx, center: center, elapsed: elapsed, count: 10,
                          scale: 0.72, R: R, spin: -0.078, lag: 0.50,
                          offset: .pi / 10,
                          light: MV.roseLight, dark: MV.roseDark)
            drawPetalRing(&ctx, center: center, elapsed: elapsed, count: 8,
                          scale: 0.46, R: R, spin: 0.115, lag: 0.95, offset: 0,
                          light: MV.violetLight, dark: MV.violetDark)

            // — Core: a small sage diamond that opens with the breath.
            let cR = R * (0.055 + 0.045 * b)
            ctx.fill(poly([
                CGPoint(x: center.x, y: center.y - cR),
                CGPoint(x: center.x + cR, y: center.y),
                CGPoint(x: center.x, y: center.y + cR),
                CGPoint(x: center.x - cR, y: center.y)
            ]), with: .color(MV.sageLight))
            ctx.fill(poly([
                CGPoint(x: center.x, y: center.y - cR),
                CGPoint(x: center.x + cR, y: center.y),
                CGPoint(x: center.x, y: center.y + cR)
            ]), with: .color(MV.sageDark))

            // — Ground plane.
            let groundY = h * 0.885
            ctx.fill(Path(CGRect(x: 0, y: groundY, width: w, height: h - groundY)),
                     with: .color(MV.groundLight))
            ctx.fill(Path(CGRect(x: 0, y: groundY, width: w, height: 2.5)),
                     with: .color(MV.groundDark.opacity(0.55)))

            // — Plinth in stone, so the cream figure reads against it.
            let a = min(w, h) * 0.080
            let plinthC = CGPoint(x: w / 2, y: groundY - h * 0.004)
            drawCube(&ctx, center: plinthC, a: a, h: h * 0.042,
                     top: MV.stoneLight, left: MV.stoneDark, right: MV.stoneMid)

            drawFigure(&ctx, feet: CGPoint(x: plinthC.x, y: plinthC.y + a * 0.05),
                       height: min(w, h) * 0.105)
        }
        .drawingGroup() // render the whole scene on the GPU
    }
}

// Lets the sky interpolate between two flat tones.
extension Color {
    func mix(_ other: Color, _ t: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .white
        let k = max(0, min(1, t))
        return Color(red:   Double(a.redComponent   + (b.redComponent   - a.redComponent)   * k),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * k),
                     blue:  Double(a.blueComponent  + (b.blueComponent  - a.blueComponent)  * k))
    }
}

// MARK: - Content

struct ContentView: View {
    @State private var start = Date()
    @State private var isRunning = true
    @State private var pausedElapsed: Double = 0
    @AppStorage("muted") private var isMuted = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRunning)) { timeline in
            let elapsed = isRunning
                ? pausedElapsed + timeline.date.timeIntervalSince(start)
                : pausedElapsed
            let state = breathState(at: elapsed)

            ZStack {
                MonumentScene(elapsed: elapsed, state: state)
                Guidance(state: state, isRunning: isRunning)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { toggle() }
            .overlay(alignment: .topTrailing) { muteButton }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.light)
        .onAppear {
            Soundscape.shared.setMuted(isMuted)
            Soundscape.shared.start(atElapsed: 0)
        }
        .onDisappear { Soundscape.shared.pause() }
    }

    private var muteButton: some View {
        Button {
            isMuted.toggle()
            Soundscape.shared.setMuted(isMuted)
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MV.plum.opacity(0.50))
                .frame(width: 30, height: 30)
                .background(Circle().fill(MV.cream.opacity(0.50)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute" : "Mute")
        .padding(18)
    }

    private func toggle() {
        if isRunning {
            pausedElapsed += Date().timeIntervalSince(start)
            isRunning = false
            Soundscape.shared.pause()
        } else {
            start = Date()
            isRunning = true
            Soundscape.shared.start(atElapsed: pausedElapsed)
        }
    }
}

// MARK: - Guidance Text

struct Guidance: View {
    let state: BreathState
    let isRunning: Bool

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 5) {
                Text(state.phase.label.uppercased())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(MV.plum.opacity(0.82))

                Text("\(state.secondsRemaining)")
                    .font(.system(size: 30, weight: .thin, design: .rounded))
                    .foregroundStyle(MV.plum.opacity(0.52))
                    .contentTransition(.numericText())

                Text(state.phase.hint)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(MV.plum.opacity(0.48))
                    .animation(.easeInOut(duration: 0.7), value: state.phase.hint)

                Text(isRunning ? "cycle \(state.cycleCount + 1) · tap to pause"
                               : "paused · tap to resume")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(MV.plum.opacity(0.34))
                    .padding(.top, 3)
            }
            .frame(width: geo.size.width)
            .position(x: geo.size.width / 2, y: geo.size.height * 0.660)
        }
        .multilineTextAlignment(.center)
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
