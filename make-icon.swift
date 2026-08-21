import AppKit

let canvas: CGFloat = 1024
let margin = canvas * 0.098
let tileSide = canvas - margin * 2
let tileRect = NSRect(x: margin, y: margin, width: tileSide, height: tileSide)
let white = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)
let softWhite = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.85)
let deepInk = NSColor(srgbRed: 0.05, green: 0.25, blue: 0.35, alpha: 0.35)

func sparklePath(center: NSPoint, longArm: CGFloat, shortArm: CGFloat, thickness: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let half = thickness / 2
    let points: [(NSPoint, NSPoint, NSPoint, NSPoint)] = [
        (NSPoint(x: center.x - half, y: center.y), NSPoint(x: center.x - half, y: center.y + shortArm * 0.35),
         NSPoint(x: center.x - half, y: center.y + longArm - shortArm), NSPoint(x: center.x, y: center.y + longArm)),
        (NSPoint(x: center.x, y: center.y + longArm), NSPoint(x: center.x + half, y: center.y + longArm - shortArm),
         NSPoint(x: center.x + half, y: center.y + shortArm * 0.35), NSPoint(x: center.x + half, y: center.y)),
        (NSPoint(x: center.x + half, y: center.y), NSPoint(x: center.x + half, y: center.y - shortArm * 0.35),
         NSPoint(x: center.x + half, y: center.y - longArm + shortArm), NSPoint(x: center.x, y: center.y - longArm)),
        (NSPoint(x: center.x, y: center.y - longArm), NSPoint(x: center.x - half, y: center.y - longArm + shortArm),
         NSPoint(x: center.x - half, y: center.y - shortArm * 0.35), NSPoint(x: center.x - half, y: center.y))
    ]
    for (start, c1, c2, end) in points {
        path.move(to: start)
        path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
    }
    path.close()
    return path
}

func rotatedSparkle(center: NSPoint, longArm: CGFloat, shortArm: CGFloat, thickness: CGFloat, angleDegrees: CGFloat) -> NSBezierPath {
    let path = sparklePath(center: center, longArm: longArm, shortArm: shortArm, thickness: thickness)
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: angleDegrees)
    transform.translateX(by: -center.x, yBy: -center.y)
    path.transform(using: transform as AffineTransform)
    return path
}

func renderIcon(scaleTo size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!
    ctx.cgContext.setAllowsAntialiasing(true)
    ctx.cgContext.setShouldAntialias(true)
    ctx.cgContext.scaleBy(x: size / canvas, y: size / canvas)

    let u = canvas / 1024

    let tile = NSBezierPath(roundedRect: tileRect, xRadius: tileSide * 0.225, yRadius: tileSide * 0.225)
    NSGradient(colors: [
        NSColor(srgbRed: 0.13, green: 0.62, blue: 0.60, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.42, blue: 0.78, alpha: 1)
    ])!.draw(in: tile, angle: -70)

    let sheen = NSBezierPath(roundedRect: tileRect, xRadius: tileSide * 0.225, yRadius: tileSide * 0.225)
    sheen.lineWidth = 10 * u
    white.withAlphaComponent(0.18).setStroke()
    sheen.stroke()

    let main = sparklePath(center: NSPoint(x: 470 * u, y: 540 * u), longArm: 300 * u, shortArm: 96 * u, thickness: 74 * u)
    white.setFill()
    main.fill()

    let small = rotatedSparkle(center: NSPoint(x: 716 * u, y: 316 * u), longArm: 120 * u, shortArm: 42 * u, thickness: 34 * u, angleDegrees: 0)
    softWhite.setFill()
    small.fill()

    let tiny = rotatedSparkle(center: NSPoint(x: 300 * u, y: 292 * u), longArm: 74 * u, shortArm: 28 * u, thickness: 24 * u, angleDegrees: 45)
    white.withAlphaComponent(0.7).setFill()
    tiny.fill()

    let dot = NSBezierPath(ovalIn: NSRect(x: 668 * u, y: 640 * u, width: 44 * u, height: 44 * u))
    white.withAlphaComponent(0.8).setFill()
    dot.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, size) in specs {
    let rep = renderIcon(scaleTo: size)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("iconset written to \(outDir)")
