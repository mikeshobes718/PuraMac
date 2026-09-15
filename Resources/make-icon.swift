import AppKit
import CoreImage

// A luminous scan ring around a sparkle: the ring reads as "the system is
// being examined", the sparkle as "and it comes out clean". Built with real
// depth — layered radial blooms, gaussian glow, gradient-filled glyphs and a
// rim light — because a flat silhouette on a flat gradient looks cheap at
// any size.

let canvas: CGFloat = 1024
let margin = canvas * 0.085
let tileSide = canvas - margin * 2
let tileRect = NSRect(x: margin, y: margin, width: tileSide, height: tileSide)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

/// Apple-style squircle (superellipse) rather than a rounded rect — the
/// corner curvature is continuous, which is what makes a tile read as native.
func squircle(_ rect: NSRect, n: CGFloat = 5) -> NSBezierPath {
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let path = NSBezierPath()
    let steps = 1440
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * pow(abs(ct), 2/n) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2/n) * (st < 0 ? -1 : 1)
        if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
    }
    path.close()
    return path
}

/// Four-point sparkle with concave pinched sides.
func sparkle(center: NSPoint, longArm: CGFloat, shortArm: CGFloat, pinch: CGFloat = 0.3) -> NSBezierPath {
    let top = NSPoint(x: center.x, y: center.y + longArm)
    let right = NSPoint(x: center.x + shortArm, y: center.y)
    let bottom = NSPoint(x: center.x, y: center.y - longArm)
    let left = NSPoint(x: center.x - shortArm, y: center.y)
    let cT = NSPoint(x: center.x, y: center.y + longArm * pinch)
    let cR = NSPoint(x: center.x + shortArm * pinch, y: center.y)
    let cB = NSPoint(x: center.x, y: center.y - longArm * pinch)
    let cL = NSPoint(x: center.x - shortArm * pinch, y: center.y)
    let p = NSBezierPath()
    p.move(to: top)
    p.curve(to: right, controlPoint1: cT, controlPoint2: cR)
    p.curve(to: bottom, controlPoint1: cR, controlPoint2: cB)
    p.curve(to: left, controlPoint1: cB, controlPoint2: cL)
    p.curve(to: top, controlPoint1: cL, controlPoint2: cT)
    p.close()
    return p
}

/// Renders a drawing into its own layer, gaussian-blurs it, and composites —
/// this is what gives the glyph a real glow instead of a flat sticker look.
func drawBlurred(radius: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    let side = Int(canvas)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = NSSize(width: canvas, height: canvas)
    let saved = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body()
    NSGraphicsContext.current = saved

    guard let cg = rep.cgImage else { return }
    let ci = CIImage(cgImage: cg)
    guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
    filter.setValue(ci, forKey: kCIInputImageKey)
    filter.setValue(radius, forKey: kCIInputRadiusKey)
    guard let out = filter.outputImage else { return }
    let ctx = CIContext()
    guard let blurred = ctx.createCGImage(out, from: ci.extent) else { return }
    NSGraphicsContext.current?.cgContext.saveGState()
    NSGraphicsContext.current?.cgContext.setAlpha(alpha)
    NSGraphicsContext.current?.cgContext.draw(blurred, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    NSGraphicsContext.current?.cgContext.restoreGState()
}

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: size / canvas, y: size / canvas)

    let tile = squircle(tileRect)

    ctx.saveGState()
    tile.addClip()

    // Base: indigo -> blue -> cyan, the cool end of the spectrum reads "clean".
    NSGradient(colorsAndLocations:
        (rgb(104, 88, 246), 0.0),
        (rgb(58, 104, 238), 0.45),
        (rgb(20, 170, 232), 1.0)
    )!.draw(in: tileRect, angle: -78)

    // True radial blooms. Drawing these into a rect hard-clips them into a
    // visible box, so they go through the from/to-radius API instead.
    func bloom(_ color: NSColor, at p: NSPoint, radius: CGFloat) {
        NSGradient(colors: [color, color.withAlphaComponent(0)])!
            .draw(fromCenter: p, radius: 0, toCenter: p, radius: radius, options: [])
    }
    bloom(rgb(186, 120, 255, 0.60), at: NSPoint(x: tileRect.minX + 60, y: tileRect.minY + 90), radius: tileSide * 0.78)
    bloom(rgb(130, 250, 255, 0.42), at: NSPoint(x: tileRect.maxX - 110, y: tileRect.maxY - 130), radius: tileSide * 0.62)
    bloom(rgb(255, 255, 255, 0.22), at: NSPoint(x: tileRect.midX - 40, y: tileRect.maxY - 40), radius: tileSide * 0.55)

    let glyphCenter = NSPoint(x: tileRect.midX, y: tileRect.midY)

    // Scan ring: a faint full orbit plus a bright glowing sweep, which reads
    // as "the system is being examined" rather than just decoration.
    let ringRadius: CGFloat = 238
    let ringWidth: CGFloat = 14

    let fullRing = NSBezierPath()
    fullRing.appendArc(withCenter: glyphCenter, radius: ringRadius, startAngle: 0, endAngle: 360)
    fullRing.lineWidth = ringWidth
    rgb(255, 255, 255, 0.17).setStroke()
    fullRing.stroke()

    let sweep = NSBezierPath()
    sweep.appendArc(withCenter: glyphCenter, radius: ringRadius,
                    startAngle: 128, endAngle: 384, clockwise: false)
    sweep.lineWidth = ringWidth
    sweep.lineCapStyle = .round

    drawBlurred(radius: 30, alpha: 0.95) {
        rgb(150, 240, 255, 1).setStroke()
        sweep.stroke()
    }
    // Clipping to the stroked path keeps the gradient inside the arc; filling
    // its bounding box directly would paint a rectangle.
    ctx.saveGState()
    ctx.addPath(sweep.cgPathCompat)
    ctx.setLineWidth(ringWidth)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    NSGradient(colorsAndLocations:
        (rgb(255, 255, 255), 0.0),
        (rgb(186, 246, 255), 0.5),
        (rgb(167, 190, 255), 1.0)
    )!.draw(in: sweep.bounds, angle: -55)
    ctx.restoreGState()

    // Main sparkle at the centre of the orbit.
    let main = sparkle(center: glyphCenter, longArm: 178, shortArm: 88)
    drawBlurred(radius: 46, alpha: 1.0) {
        rgb(170, 243, 255, 1).setFill()
        main.fill()
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                  color: rgb(10, 28, 86, 0.45).cgColor)
    NSColor.white.setFill()
    main.fill()
    ctx.restoreGState()

    ctx.saveGState()
    main.addClip()
    NSGradient(colorsAndLocations:
        (rgb(255, 255, 255), 0.0),
        (rgb(236, 251, 255), 0.42),
        (rgb(168, 220, 255), 0.78),
        (rgb(196, 181, 253), 1.0)
    )!.draw(in: main.bounds, angle: -82)
    ctx.restoreGState()

    // Accent sparkles sitting outside the orbit.
    let s2 = sparkle(center: NSPoint(x: glyphCenter.x + 262, y: glyphCenter.y + 248), longArm: 92, shortArm: 36)
    drawBlurred(radius: 22, alpha: 0.85) { rgb(195, 247, 255, 1).setFill(); s2.fill() }
    rgb(255, 255, 255, 0.98).setFill(); s2.fill()

    let s3 = sparkle(center: NSPoint(x: glyphCenter.x - 256, y: glyphCenter.y - 240), longArm: 58, shortArm: 24)
    drawBlurred(radius: 16, alpha: 0.75) { rgb(195, 247, 255, 1).setFill(); s3.fill() }
    rgb(255, 255, 255, 0.9).setFill(); s3.fill()

    // Top sheen as a plain top-down fade — an ellipse clip cuts the gradient
    // before it reaches zero and leaves a visible waterline.
    NSGradient(colors: [rgb(255, 255, 255, 0.20), rgb(255, 255, 255, 0)])!
        .draw(in: NSRect(x: tileRect.minX, y: tileRect.midY,
                         width: tileSide, height: tileSide / 2), angle: -90)

    // Bottom inner shadow grounds the tile.
    NSGradient(colors: [rgb(8, 22, 78, 0.28), rgb(8, 22, 78, 0)])!
        .draw(in: NSRect(x: tileRect.minX, y: tileRect.minY,
                         width: tileSide, height: tileSide * 0.42), angle: 90)

    ctx.restoreGState()

    // Rim light: bright along the top edge, fading out by the equator.
    ctx.saveGState()
    let rim = squircle(tileRect.insetBy(dx: 2.5, dy: 2.5))
    rim.lineWidth = 5
    ctx.addPath(rim.cgPathCompat)
    ctx.setLineWidth(5)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    NSGradient(colors: [rgb(255, 255, 255, 0.80), rgb(255, 255, 255, 0.04)])!
        .draw(in: tileRect, angle: -90)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

extension NSBezierPath {
    var cgPathCompat: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
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
    let rep = renderIcon(size: size)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("iconset written to \(outDir)")
