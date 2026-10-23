// Draws the winlego icon: a screen split into zones, each zone a brick with studs.
//   swift scripts/make-icon.swift Resources   → Resources/AppIcon.icns + docs-ready PNG
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024  // design on a 1024 grid

    // Squircle background, inset like Apple's template (824 of 1024).
    let bg = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                          xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.14, blue: 0.24, alpha: 1),
                        NSColor(srgbRed: 0.20, green: 0.28, blue: 0.46, alpha: 1)])!
        .draw(in: bg, angle: 90)

    // The screen: a dark panel with a thin light rim.
    let screen = NSRect(x: 196 * s, y: 268 * s, width: 632 * s, height: 488 * s)
    NSColor(white: 1, alpha: 0.14).setFill()
    NSBezierPath(roundedRect: screen.insetBy(dx: -14 * s, dy: -14 * s), xRadius: 54 * s, yRadius: 54 * s).fill()
    NSColor(srgbRed: 0.06, green: 0.08, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(roundedRect: screen, xRadius: 40 * s, yRadius: 40 * s).fill()

    // Three zones: one tall on the left, two stacked on the right. Each a brick with studs.
    let gap = 22 * s
    let inner = screen.insetBy(dx: gap, dy: gap)
    let leftW = (inner.width - gap) * 0.58
    let rightW = inner.width - gap - leftW
    let halfH = (inner.height - gap) / 2
    let bricks: [(NSRect, NSColor, NSColor)] = [
        (NSRect(x: inner.minX, y: inner.minY, width: leftW, height: inner.height),
         NSColor(srgbRed: 0.98, green: 0.58, blue: 0.18, alpha: 1), NSColor(srgbRed: 1.0, green: 0.76, blue: 0.40, alpha: 1)),
        (NSRect(x: inner.minX + leftW + gap, y: inner.minY + halfH + gap, width: rightW, height: halfH),
         NSColor(srgbRed: 0.26, green: 0.76, blue: 0.46, alpha: 1), NSColor(srgbRed: 0.52, green: 0.90, blue: 0.66, alpha: 1)),
        (NSRect(x: inner.minX + leftW + gap, y: inner.minY, width: rightW, height: halfH),
         NSColor(srgbRed: 0.33, green: 0.55, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.60, green: 0.75, blue: 1.0, alpha: 1)),
    ]
    for (rect, color, stud) in bricks {
        NSGradient(colors: [color.blended(withFraction: 0.18, of: .black)!, color])!
            .draw(in: NSBezierPath(roundedRect: rect, xRadius: 26 * s, yRadius: 26 * s), angle: 90)
        // Studs along the top edge.
        let studD = min(rect.width, rect.height) * 0.22
        let count = max(1, Int(rect.width / (studD * 2.2)))
        let span = CGFloat(count) * studD + CGFloat(count - 1) * studD * 0.9
        var x = rect.midX - span / 2
        for _ in 0..<count {
            let studRect = NSRect(x: x, y: rect.maxY - studD * 1.35, width: studD, height: studD * 0.78)
            stud.setFill()
            NSBezierPath(ovalIn: studRect).fill()
            x += studD * 1.9
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try draw(size: 512).representation(using: .png, properties: [:])!
    .write(to: outDir.appendingPathComponent("winlego-512.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print("wrote \(outDir.path)/AppIcon.icns")
