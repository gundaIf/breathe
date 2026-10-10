import SwiftUI
import AppKit

// Offscreen renderer: draws the scene at several points in the breath cycle
// into one contact sheet, so the visuals can be reviewed without running the app.
//
// Usage: preview <out.png> [t1 t2 ...]   — times in seconds of breath time.

MainActor.assumeIsolated {
    let W: CGFloat = 380, H: CGFloat = 540
    let args = CommandLine.arguments
    let custom = args.dropFirst(2).compactMap(Double.init)
    let times: [Double] = custom.isEmpty ? [0, 1.5, 3.0, 4.5, 6.0, 9.0] : Array(custom)
    let cols = 3
    let rows = (times.count + cols - 1) / cols

    let sheet = NSImage(size: NSSize(width: W * CGFloat(cols), height: H * CGFloat(rows)))
    sheet.lockFocus()

    for (i, t) in times.enumerated() {
        let view = MonumentScene(elapsed: t).frame(width: W, height: H)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage else { continue }

        let col = i % cols
        let row = i / cols
        let x = CGFloat(col) * W
        let y = sheet.size.height - CGFloat(row + 1) * H
        img.draw(in: NSRect(x: x, y: y, width: W, height: H))

        // label the frame time
        let label = "t=\(t)s" as NSString
        label.draw(at: NSPoint(x: x + 8, y: y + 8), withAttributes: [
            .foregroundColor: NSColor.black.withAlphaComponent(0.55),
            .font: NSFont.systemFont(ofSize: 11)
        ])
    }

    sheet.unlockFocus()

    guard let tiff = sheet.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("encode failed")
    }
    let out = args.count > 1 ? args[1] : "frames.png"
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
