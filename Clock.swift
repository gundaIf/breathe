import Foundation

// MARK: - Easing helpers

@inline(__always)
func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = max(0, min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
}

@inline(__always)
func frac(_ x: Double) -> Double { x - floor(x) }

// MARK: - Glide

/// A critically damped glide: two identical one-pole lags in series.
///
/// A step in the target produces an S-shaped response — no jolt as it starts,
/// no overshoot as it lands — so pausing reads as the breath slowing to rest
/// rather than freezing mid-motion.
///
/// The visuals and the audio each run one of these toward the same target, and
/// because `step` is the exact solution rather than an approximation, both trace
/// the same curve whatever their step size: once per frame for the picture, once
/// per sample for the sound. That is what keeps them in sync through a pause.
struct Glide {
    static let tau = 0.32

    private(set) var m: Double   // first pole
    private(set) var r: Double   // second pole: the current rate

    init(_ value: Double) { m = value; r = value }

    /// Advances by `dt` toward `g` and returns the integral of the rate over the
    /// step — how far the breath clock moves. Exact, so a long gap (a hidden
    /// window, a minute of pause) lands correctly in a single step.
    mutating func step(_ dt: Double, toward g: Double) -> Double {
        let T = Glide.tau
        let e = exp(-dt / T)
        let x0 = m - g, y0 = r - g
        let moved = g * dt
                  + y0 * T * (1 - e)
                  + x0 * T * (1 - (1 + dt / T) * e)
        m = g + x0 * e
        r = g + (y0 + x0 * dt / T) * e
        return moved
    }
}

// MARK: - Breath clock

/// The clock the visuals breathe by. It runs at `rate`, which glides toward 1
/// while breathing and toward 0 while paused. It starts at rest, so on launch
/// the flower eases into motion instead of starting at full speed.
final class BreathClock {
    private var glide = Glide(0)
    private(set) var target: Double = 1
    private(set) var elapsed: Double = 0
    /// Whether a pause has ever happened — the "paused" line has nothing to
    /// fade out of on the first launch.
    private(set) var everPaused = false
    private var last: Date?
    private var born: Date?

    var rate: Double { glide.r }

    @discardableResult
    func advance(to now: Date) -> Double {
        if born == nil { born = now }
        guard let last else { self.last = now; return elapsed }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return elapsed }
        self.last = now
        elapsed += glide.step(dt, toward: target)
        return elapsed
    }

    /// Brings the clock up to `now` under the old target before switching, so
    /// the gap since the last frame is integrated at the rate that applied then.
    func setTarget(_ g: Double, at now: Date = Date()) {
        advance(to: now)
        target = g
        if g == 0 { everPaused = true }
    }

    func secondsSinceLaunch(_ now: Date) -> Double {
        born.map { now.timeIntervalSince($0) } ?? 0
    }
}
