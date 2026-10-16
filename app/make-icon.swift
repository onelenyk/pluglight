// Малює іконку програми: темний квадрат зі штекером MagSafe і помаранчевим та зеленим вогником.
// swift app/make-icon.swift <тека.iconset>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(white: 0.22, alpha: 1), ending: NSColor(white: 0.08, alpha: 1))!.draw(in: bg, angle: -90)

    // штекер
    let plug = NSRect(x: s * 0.3, y: s * 0.42, width: s * 0.4, height: s * 0.16)
    NSColor(white: 0.85, alpha: 1).setFill()
    NSBezierPath(roundedRect: plug, xRadius: s * 0.08, yRadius: s * 0.08).fill()
    NSColor(white: 0.6, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: s * 0.44, y: s * 0.24, width: s * 0.12, height: s * 0.18)).fill()

    // вогники з ореолом
    for (x, color) in [(0.42, NSColor.systemOrange), (0.58, NSColor.systemGreen)] {
        let c = NSPoint(x: s * x, y: s * 0.5)
        for (r, a) in [(0.09, 0.25), (0.055, 0.5), (0.03, 1.0)] {
            color.withAlphaComponent(a).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - s * r, y: c.y - s * r, width: 2 * s * r, height: 2 * s * r)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! draw(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
    try! draw(size * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}
