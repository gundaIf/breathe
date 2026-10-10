# Breathe

A calm, native macOS breathing app. Six seconds in, six seconds out, through the nose.

Built with SwiftUI and drawn entirely in code — no image assets, no audio files, no
dependencies. The whole app is about 1 MB.

## The breath

One cycle is 12 seconds: a 6-second inhale and a 6-second exhale.

Fullness follows a raised cosine:

```
fullness(t) = (1 - cos(2π · t / 12)) / 2
```

Velocity reaches zero at the turning points, so the breath *settles* at the top and
bottom instead of snapping around. It's a pure function of elapsed time, and every
element on screen samples it — the petals, the sky, the progress line, the countdown —
so nothing can drift out of sync with anything else.

A single `TimelineView` drives the whole scene at the display's own refresh rate —
120Hz on a ProMotion screen. The scene, words included, is one `Canvas`, so each frame
is a single display list rather than a tree of views to rebuild and diff.

### Pausing

Tap and the breath doesn't freeze — it glides to rest, and eases back in on resume.
The clock runs at a rate that follows a critically damped glide (two identical one-pole
lags in series), so a pause has no jolt as it begins and no overshoot as it lands. The
app opens the same way, easing into motion from stillness.

The sound runs the same glide sample by sample. Because each step uses the glide's exact
solution rather than an approximation, the picture (once per frame) and the sound (once
per sample) trace the same curve: through a pause and resume their breath clocks stay
within 0.00003s of each other. Once a pause has settled, the picture stops redrawing and
the audio engine suspends.

## The look

A flat pastel geometry, no glow and no blur anywhere. Depth comes only
from pairing a light and a dark face across a crease, the way folded paper reads.

- **An origami lotus** of three petal rings that open and close with the breath. Each
  ring lags the one outside it and twists a little against its neighbour as it opens,
  so the flower unfurls rather than simply scaling. Open petals catch the light: both
  faces lift a touch on the inhale. Petal flanks are quadratic curves, which keeps
  neighbours overlapping at every point in the breath instead of parting into gaps.
  Every dark half is drawn before every light half, so the pinwheel's layering is the
  same all the way round — drawn petal by petal, the first one ends up tucked under both
  its neighbours.
- **A heart** of two-tone sage that turns a quarter as the breath fills, around a cream
  seed.
- **A hand-drawn progress line** that draws itself on during the inhale and erases from
  behind during the exhale. It's a filled ribbon rather than a stroked path, so its
  weight can vary; layered sines keyed to the angle give it a pen's waver, and both ends
  taper like a nib touching down and lifting. The pen eases into and out of each turn,
  settling with the breath rather than arriving at full speed. The waver reseeds each
  cycle, but only at the cycle start where the line is empty, so it never visibly jumps.
- **Ripples** that slip out from behind the disc at each turn, in time with the singing
  bowl.
- **A fixed cream disc** behind the lotus, giving the breathing a stable frame to happen
  inside.
- **A world behind it**: faint towers and domes on the horizon, tiny motes rising very
  slowly through the sky, drifting stone blocks that lift with the inhale, and a small
  figure on an isometric plinth who breathes with you.
- **Words that hand over** on the breath's own timeline. The outgoing line lifts away and
  clears before the incoming one settles into place, and each countdown digit rolls up
  as the last leaves. The letter spacing of the phase words opens with the breath; each
  letter is shaped once and placed by hand, so that spacing can move continuously
  without re-shaping text every frame.

## The sound

A generated zen soundscape locked to the same 12-second cycle — synthesised sample by
sample, which is why there are no audio files in the repo.

- A low **drone** on G2, slowly drifting, lifting a little with the breath
- A **pad** on G4/D5/A4 that swells on the inhale and recedes on the exhale
- A **singing bowl** struck at each turn — inharmonic partials with independent decay
  rates. The inhale opens on the fifth, the exhale settles onto the root
- A whisper of filtered **air** breathing underneath

Everything runs through `tanh` soft-clipping with a 2.5-second fade-in. Across a cycle,
RMS swings roughly 0.046 → 0.101 → 0.050, peaking exactly at full lungs.

Pitch follows real time while the breath follows the glide, so on pause the swell
settles and the sound fades with it, without any note bending. Mute is the speaker
button, top right: a ~120 ms gain ramp inside the render loop, so it's click-free. The
setting persists across launches.

## Controls

| Action | What it does |
| --- | --- |
| Tap anywhere | Pause / resume |
| Speaker button | Mute / unmute |
| Drag anywhere | Move the window (it has no title bar) |

## Requirements

macOS 14 Sonoma or later. The app is a universal binary, so it runs natively on both
Apple silicon and Intel Macs.

## Building

Requires the Xcode Command Line Tools — full Xcode is not needed.

```bash
./build.sh
```

That compiles the app for both architectures, renders the icon, assembles
`Breathe.app`, and packages `Breathe.dmg`, all into `build/`.

The window's state lives in `ObservableObject`s rather than `@State`. On the macOS 27
SDK, `@State` is a macro whose plugin ships only with full Xcode, so using it would
break the Command Line Tools build.

The build is ad-hoc signed rather than notarised, so on first launch macOS Gatekeeper
will warn. Right-click the app → **Open** → **Open**, once.

## Layout

| File | |
| --- | --- |
| `App.swift` | The `@main` entry point and window setup |
| `Core.swift` | Breath model, palette, geometry, the whole scene, and its words |
| `Clock.swift` | The glide and the breath clock that pausing and launch ease through |
| `Sound.swift` | The synthesised soundscape and its audio engine |
| `makeicon.swift` | Draws the app icon into an sRGB bitmap |
| `main.swift` | Offscreen renderer — draws the scene at chosen points in the cycle into a contact sheet, for reviewing visual changes without running the app |
| `build.sh` | Compile, bundle, package |

`main.swift` is a development tool, not part of the app. To render particular moments
— say, either side of a turn:

```bash
swiftc -O -target arm64-apple-macos14.0 -o build/preview main.swift Core.swift Clock.swift Sound.swift && build/preview turn.png 5.8 6.2 6.6
```

## License

MIT
