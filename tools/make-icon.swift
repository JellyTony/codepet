// Generates CodePet's app icon: the blob mascot on a soft rounded tile.
// Renders every iconset size and builds Resources/AppIcon.icns via iconutil.
//
//   xcrun swift tools/make-icon.swift
//
import AppKit

func draw(size s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)

    // ── Rounded "app tile" with a soft teal gradient ──
    let pad = s * 0.085
    let tile = CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)
    let radius = tile.width * 0.235
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.43, green: 0.84, blue: 0.86, alpha: 1),   // top
        CGColor(red: 0.16, green: 0.62, blue: 0.69, alpha: 1),   // bottom
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: tile.midX, y: tile.maxY),
                           end: CGPoint(x: tile.midX, y: tile.minY), options: [])
    ctx.restoreGState()

    func ellipse(_ r: CGRect, _ c: CGColor) { ctx.setFillColor(c); ctx.fillEllipse(in: r) }

    // ── Mascot: a soft white blob body ──
    let bw = s * 0.46, bh = s * 0.44
    let body = CGRect(x: (s - bw) / 2, y: s * 0.30, width: bw, height: bh)
    // contact shadow
    ellipse(CGRect(x: body.midX - bw * 0.42, y: body.minY - s * 0.01,
                   width: bw * 0.84, height: bh * 0.16),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.16))
    let bodyPath = CGPath(roundedRect: body, cornerWidth: bw * 0.46, cornerHeight: bh * 0.46, transform: nil)
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let bodyGrad = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        CGColor(red: 0.90, green: 0.97, blue: 0.98, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bodyGrad, start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.minY), options: [])
    ctx.restoreGState()

    // eyes
    let eyeR = bw * 0.115, dx = bw * 0.21
    let eyeY = body.midY + bh * 0.06
    let teal = CGColor(red: 0.13, green: 0.45, blue: 0.52, alpha: 1)
    for sx in [-1.0, 1.0] {
        let ex = body.midX + CGFloat(sx) * dx
        ellipse(CGRect(x: ex - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2), teal)
        // sparkle
        let g = eyeR * 0.42
        ellipse(CGRect(x: ex - eyeR * 0.1, y: eyeY + eyeR * 0.2, width: g, height: g),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    }
    // cheeks
    for sx in [-1.0, 1.0] {
        let cr = bw * 0.075
        ellipse(CGRect(x: body.midX + CGFloat(sx) * dx * 1.35 - cr, y: eyeY - eyeR * 1.7,
                       width: cr * 2, height: cr * 1.5),
                CGColor(red: 0.98, green: 0.55, blue: 0.55, alpha: 0.45))
    }
    // smile
    ctx.setStrokeColor(teal); ctx.setLineWidth(s * 0.018); ctx.setLineCap(.round)
    let my = eyeY - eyeR * 1.5, mw = bw * 0.18
    ctx.move(to: CGPoint(x: body.midX - mw, y: my))
    ctx.addQuadCurve(to: CGPoint(x: body.midX + mw, y: my),
                     control: CGPoint(x: body.midX, y: my - mw * 0.95))
    ctx.strokePath()

    img.unlockFocus()
    return img
}

func png(_ size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(size: size).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let iconset = (root as NSString).appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (base, scale) in specs {
    let px = base * scale
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try! png(CGFloat(px)).write(to: URL(fileURLWithPath: (iconset as NSString).appendingPathComponent(name)))
}
// also a standalone 1024 preview
try! png(1024).write(to: URL(fileURLWithPath: (root as NSString).appendingPathComponent("build/icon-preview.png")))
print("wrote iconset to \(iconset)")
