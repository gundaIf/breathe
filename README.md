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

A single `TimelineView` drives the whole scene at 60fps.

## The look

A flat pastel geometry, no glow and no blur anywhere. Depth comes only
from pairing a light and a dark face across a crease, the way folded paper reads.

- **An origami lotus** of three petal rings that open and close with the breath. Each
  ring lags the one outside it, so the flower unfolds in sequence rather than pulsing as
  one shape. Petal flanks are quadratic curves, which keeps neighbours overlapping at
  every point in the breath instead of parting into gaps as it opens.
- **A hand-drawn progress line** that draws itself on during the inhale and erases from
  behind during the exhale. It's a filled ribbon rather than a stroked path, so its
  weight can vary; layered sines keyed to the angle give it a pen's waver, and both ends
  taper like a nib touching down and lifting. The waver reseeds each cycle, but only at
  the cycle start where the line is empty, so it never visibly jumps.
- **A fixed cream disc** behind the lotus, giving the breathing a stable frame to happen
  inside.
- A small figure on an isometric plinth, and slow-drifting stone blocks for depth.

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

Mute is the speaker button, top right. It rides the mixer's own volume, so it's
click-free, and the setting persists across launches.

## Controls

| Action | What it does |
| --- | --- |
| Tap anywhere | Pause / resume |
| Speaker button | Mute / unmute |
| Drag anywhere | Move the window (it has no title bar) |

## Building

Requires the Xcode Command Line Tools — full Xcode is not needed.

```bash
./build.sh
```

That compiles the app, renders the icon, assembles `Breathe.app`, and packages
`Breathe.dmg`, all into `build/`.

The build is ad-hoc signed rather than notarised, so on first launch macOS Gatekeeper
will warn. Right-click the app → **Open** → **Open**, once.

## Layout

| File | |
| --- | --- |
| `App.swift` | The `@main` entry point and window setup |
| `Core.swift` | Breath model, palette, geometry, and the whole scene |
| `Sound.swift` | The synthesised soundscape and its audio engine |
| `makeicon.swift` | Draws the app icon into an sRGB bitmap |
| `main.swift` | Offscreen renderer — draws the scene at points across the cycle into a contact sheet, for reviewing visual changes without running the app |
| `build.sh` | Compile, bundle, package |

`main.swift` is a development tool, not part of the app. `build.sh` compiles only
`App.swift`, `Core.swift`, and `Sound.swift`.

## License

MIT
