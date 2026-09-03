import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Render into an explicit sRGB bitmap context at an exact size, so the icon's
// colours match the app's palette rather than being shifted by whatever
// colour space and backing scale an NSImage would have picked up.

let size = 1024
let S = CGFloat(size)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("context")
}
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

func C(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Squircle-ish rounded clip
let rect = CGRect(x: 0, y: 0, width: S, height: S)
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: S * 0.225,
                   cornerHeight: S * 0.225, transform: nil))
ctx.clip()

// Sky: periwinkle above, warm peach below.
if let g = CGGradient(colorsSpace: cs,
                      colors: [C(0.639, 0.624, 0.804), C(0.972, 0.816, 0.702)] as CFArray,
                      locations: [0, 1]) {
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
}

let center = CGPoint(x: S / 2, y: S / 2)

// Pale sun disc
ctx.setFillColor(C(0.992, 0.937, 0.867, 0.62))
let sunR = S * 0.355
ctx.fillEllipse(in: CGRect(x: center.x - sunR, y: center.y - sunR,
                           width: sunR * 2, height: sunR * 2))

func fillPoly(_ pts: [CGPoint], _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.beginPath()
    ctx.move(to: pts[0])
    for p in pts.dropFirst() { ctx.addLine(to: p) }
    ctx.closePath()
    ctx.fillPath()
}

/// Creased origami petal, blunted into a shallow chevron — matches the app.
func petal(angle: Double, r0: CGFloat, r1: CGFloat, wr: CGFloat,
           light: CGColor, dark: CGColor) {
    let dir  = CGPoint(x: cos(angle), y: sin(angle))
    let perp = CGPoint(x: -sin(angle), y: cos(angle))
    let rm = r0 + (r1 - r0) * 0.45
    let rt = r0 + (r1 - r0) * 0.86
    let w  = rm * wr
    let wt = w * 0.42

    func P(_ r: CGFloat, _ off: CGFloat) -> CGPoint {
        CGPoint(x: center.x + dir.x * r + perp.x * off,
                y: center.y + dir.y * r + perp.y * off)
    }
    let base = P(r0, 0), apex = P(r1, 0)
    fillPoly([base, P(rm,  w), P(rt,  wt), apex], light)
    fillPoly([base, apex, P(rt, -wt), P(rm, -w)], dark)
}

func ring(count: Int, r0: CGFloat, r1: CGFloat, offset: Double,
          light: CGColor, dark: CGColor) {
    for i in 0..<count {
        petal(angle: offset + (Double(i) / Double(count)) * 2 * .pi,
              r0: r0, r1: r1, wr: 0.44, light: light, dark: dark)
    }
}

// Outer coral, mid rose, inner violet — same palette as the app.
ring(count: 8, r0: S * 0.048, r1: S * 0.315, offset: 0,
     light: C(0.965, 0.616, 0.553), dark: C(0.847, 0.451, 0.404))
ring(count: 8, r0: S * 0.034, r1: S * 0.214, offset: .pi / 8,
     light: C(0.882, 0.596, 0.702), dark: C(0.722, 0.435, 0.553))
ring(count: 6, r0: S * 0.020, r1: S * 0.126, offset: 0,
     light: C(0.706, 0.612, 0.808), dark: C(0.545, 0.451, 0.667))

// Sage core diamond
let cR = S * 0.042
fillPoly([CGPoint(x: center.x, y: center.y + cR), CGPoint(x: center.x + cR, y: center.y),
          CGPoint(x: center.x, y: center.y - cR), CGPoint(x: center.x - cR, y: center.y)],
         C(0.510, 0.776, 0.702))
fillPoly([CGPoint(x: center.x, y: center.y + cR), CGPoint(x: center.x + cR, y: center.y),
          CGPoint(x: center.x, y: center.y - cR)],
         C(0.361, 0.616, 0.561))

guard let image = ctx.makeImage() else { fatalError("makeImage") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
guard let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("finalize") }
print("wrote \(out) (\(size)x\(size) sRGB)")
