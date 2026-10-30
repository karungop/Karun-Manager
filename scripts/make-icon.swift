// Renders Resources/AppIcon.icns: an Obsidian-purple squircle with a check and three queue bars.
// Usage: swift scripts/make-icon.swift <output-dir>   (bundle.sh runs this when the icon is missing)
import AppKit

let outputDir = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = size * 0.1
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    // Shadow + gradient body.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor(srgbRed: 0.16, green: 0.15, blue: 0.19, alpha: 1).setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(
        starting: NSColor(srgbRed: 0.62, green: 0.45, blue: 0.98, alpha: 1),
        ending: NSColor(srgbRed: 0.42, green: 0.27, blue: 0.86, alpha: 1)
    )?.draw(in: squircle, angle: -90)

    // Three queue bars (Urgent / Standard / Someday colours), left-aligned like list rows.
    let barColors = [
        NSColor(srgbRed: 0.98, green: 0.27, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 0.91, green: 0.59, blue: 0.25, alpha: 1),
        NSColor(srgbRed: 0.33, green: 0.65, blue: 1.0, alpha: 1),
    ]
    let barHeight = tile.height * 0.085
    for (i, color) in barColors.enumerated() {
        let y = tile.minY + tile.height * (0.48 - 0.15 * CGFloat(i))  // Urgent on top
        let dot = NSRect(x: tile.minX + tile.width * 0.16, y: y, width: barHeight, height: barHeight)
        color.setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSColor.white.withAlphaComponent(0.55 - 0.12 * CGFloat(i)).setFill()
        let bar = NSRect(x: dot.maxX + tile.width * 0.05, y: y, width: tile.width * (0.42 - 0.08 * CGFloat(i)), height: barHeight)
        NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    }

    // Check mark, top right.
    let check = NSBezierPath()
    check.move(to: NSPoint(x: tile.minX + tile.width * 0.44, y: tile.minY + tile.height * 0.75))
    check.line(to: NSPoint(x: tile.minX + tile.width * 0.55, y: tile.minY + tile.height * 0.65))
    check.line(to: NSPoint(x: tile.minX + tile.width * 0.80, y: tile.minY + tile.height * 0.87))
    check.lineWidth = tile.width * 0.075
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor.white.setStroke()
    check.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
let process = Process()
process.executableURL = URL(filePath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", outputDir.appending(path: "AppIcon.icns").path]
try process.run()
process.waitUntilExit()
print("Wrote \(outputDir.appending(path: "AppIcon.icns").path)")
