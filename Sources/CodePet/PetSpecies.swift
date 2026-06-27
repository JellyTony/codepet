import SwiftUI

/// A drawable creature form. Codex ships several forms; CodePet draws them as
/// vectors so they animate crisply at any size.
enum PetSpecies: String, CaseIterable {
    case blob
    case cat
    case robot
    case ghost
    case duck     // rubber-duck debugging 🦆
    case dino     // the offline dino 🦖
    case coffee   // fuel ☕

    static let displayName: [PetSpecies: String] = [
        .blob: "Blob", .cat: "Stacky", .robot: "Byte", .ghost: "Glitch",
        .duck: "Ducky", .dino: "Rex", .coffee: "Java"
    ]

    var title: String { PetSpecies.displayName[self] ?? rawValue.capitalized }

    /// Constant identity colour for the built-in form.
    var identityColor: Color {
        switch self {
        case .blob:   return Color(red: 0.27, green: 0.74, blue: 0.78)
        case .cat:    return Color(red: 0.95, green: 0.62, blue: 0.30)
        case .robot:  return Color(red: 0.55, green: 0.60, blue: 0.72)
        case .ghost:  return Color(red: 0.64, green: 0.52, blue: 0.92)
        case .duck:   return Color(red: 0.97, green: 0.80, blue: 0.27)
        case .dino:   return Color(red: 0.42, green: 0.74, blue: 0.46)
        case .coffee: return Color(red: 0.55, green: 0.40, blue: 0.31)
        }
    }

    static func from(_ key: String) -> PetSpecies {
        // Accept "blob" or "built-in:blob".
        let raw = key.contains(":") ? String(key.split(separator: ":").last!) : key
        return PetSpecies(rawValue: raw) ?? .blob
    }

    /// The outline of the body for the given bounding rect.
    func bodyPath(in rect: CGRect) -> Path {
        switch self {
        case .blob:
            return Path(roundedRect: rect, cornerRadius: rect.height * 0.42)
        case .cat:
            return Path(roundedRect: rect, cornerRadius: rect.height * 0.34)
        case .robot:
            return Path(roundedRect: rect, cornerRadius: rect.height * 0.18)
        case .duck:
            return Path(roundedRect: rect, cornerRadius: rect.height * 0.46)
        case .dino:
            return Path(roundedRect: rect, cornerRadius: rect.height * 0.32)
        case .coffee:
            return Path(roundedRect: rect, cornerRadius: rect.width * 0.14)
        case .ghost:
            // Rounded top, wavy bottom.
            var p = Path()
            let topR = rect.width * 0.5
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topR))
            p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + topR),
                     radius: topR, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            // Three bottom scallops.
            let waves = 3
            let step = rect.width / CGFloat(waves)
            for i in 0..<waves {
                let x0 = rect.maxX - CGFloat(i) * step
                let x1 = x0 - step
                p.addQuadCurve(to: CGPoint(x: x1, y: rect.maxY),
                               control: CGPoint(x: (x0 + x1) / 2, y: rect.maxY - rect.height * 0.16))
            }
            p.closeSubpath()
            return p
        }
    }

    /// Ears, antenna, whiskers, etc.
    func drawFeatures(ctx: inout GraphicsContext, body: CGRect, t: Double, tint: Color) {
        switch self {
        case .blob, .ghost:
            break
        case .cat:
            // Two triangular ears with a soft pink inner ear.
            for sx in [-1.0, 1.0] {
                let ex = body.midX + CGFloat(sx) * body.width * 0.30
                let topY = body.minY - body.height * 0.02
                var ear = Path()
                ear.move(to: CGPoint(x: ex - body.width * 0.12, y: topY))
                ear.addLine(to: CGPoint(x: ex + CGFloat(sx) * body.width * 0.02, y: topY - body.height * 0.26))
                ear.addLine(to: CGPoint(x: ex + body.width * 0.12, y: topY))
                ear.closeSubpath()
                ctx.fill(ear, with: .color(tint))
                var inner = Path()
                inner.move(to: CGPoint(x: ex - body.width * 0.06, y: topY - body.height * 0.01))
                inner.addLine(to: CGPoint(x: ex + CGFloat(sx) * body.width * 0.015, y: topY - body.height * 0.175))
                inner.addLine(to: CGPoint(x: ex + body.width * 0.06, y: topY - body.height * 0.01))
                inner.closeSubpath()
                ctx.fill(inner, with: .color(Color(red: 0.97, green: 0.62, blue: 0.68).opacity(0.9)))
                ctx.stroke(ear, with: .color(.black.opacity(0.20)), lineWidth: 1.6)
            }
            // Whiskers.
            for sx in [-1.0, 1.0] {
                for k in 0..<2 {
                    var wk = Path()
                    let y = body.midY + body.height * (0.14 + Double(k) * 0.08)
                    let x0 = body.midX + CGFloat(sx) * body.width * 0.18
                    wk.move(to: CGPoint(x: x0, y: y))
                    wk.addLine(to: CGPoint(x: x0 + CGFloat(sx) * body.width * 0.28, y: y - CGFloat(k) * 3 + 2))
                    ctx.stroke(wk, with: .color(.white.opacity(0.75)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
        case .robot:
            // Antenna with a blinking bulb.
            var stem = Path()
            stem.move(to: CGPoint(x: body.midX, y: body.minY))
            stem.addLine(to: CGPoint(x: body.midX, y: body.minY - body.height * 0.22))
            ctx.stroke(stem, with: .color(.black.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            let pulse = (sin(t * 4) + 1) / 2
            let br = body.width * 0.078
            let bc = CGPoint(x: body.midX, y: body.minY - body.height * 0.22)
            // Glowing, glossy bulb.
            ctx.fill(Circle().path(in: CGRect(x: bc.x - br * 1.9, y: bc.y - br * 1.9,
                                              width: br * 3.8, height: br * 3.8)),
                     with: .color(Color(red: 1, green: 0.3, blue: 0.3).opacity(0.10 + 0.20 * pulse)))
            ctx.fill(Circle().path(in: CGRect(x: bc.x - br, y: bc.y - br, width: br * 2, height: br * 2)),
                     with: .color(Color(red: 1, green: 0.33, blue: 0.33).opacity(0.62 + 0.38 * pulse)))
            ctx.fill(Circle().path(in: CGRect(x: bc.x - br * 0.32, y: bc.y - br * 0.55,
                                              width: br * 0.5, height: br * 0.5)),
                     with: .color(.white.opacity(0.85)))
            // Riveted side bolts with a highlight.
            for sx in [-1.0, 1.0] {
                let r = body.width * 0.055
                let bx = body.midX + CGFloat(sx) * body.width * 0.5
                ctx.fill(Circle().path(in: CGRect(x: bx - r, y: body.midY - r, width: r * 2, height: r * 2)),
                         with: .color(.black.opacity(0.22)))
                ctx.fill(Circle().path(in: CGRect(x: bx - r * 0.5, y: body.midY - r * 0.55,
                                                  width: r, height: r)),
                         with: .color(.white.opacity(0.45)))
            }

        case .duck:
            // A jaunty head tuft + a folded wing. (Beak is drawn as the mouth.)
            var tuft = Path()
            let tx = body.midX + body.width * 0.02, ty = body.minY + body.height * 0.02
            tuft.move(to: CGPoint(x: tx, y: ty))
            tuft.addQuadCurve(to: CGPoint(x: tx - body.width * 0.05, y: ty - body.height * 0.20),
                              control: CGPoint(x: tx + body.width * 0.13, y: ty - body.height * 0.10))
            ctx.stroke(tuft, with: .color(tint), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            var wing = Path()
            wing.addArc(center: CGPoint(x: body.midX + body.width * 0.20, y: body.midY + body.height * 0.12),
                        radius: body.width * 0.18, startAngle: .degrees(-50), endAngle: .degrees(55), clockwise: false)
            ctx.stroke(wing, with: .color(.black.opacity(0.10)), lineWidth: 2)

        case .dino:
            // Stegosaurus-style back plates across the top.
            for k in 0..<3 {
                let fx = body.midX + CGFloat(Double(k) - 1) * body.width * 0.20
                let baseY = body.minY + body.height * 0.05
                let sz = body.width * 0.075
                var sp = Path()
                sp.move(to: CGPoint(x: fx - sz, y: baseY))
                sp.addLine(to: CGPoint(x: fx, y: baseY - body.height * 0.17))
                sp.addLine(to: CGPoint(x: fx + sz, y: baseY))
                sp.closeSubpath()
                ctx.fill(sp, with: .color(tint))
                ctx.stroke(sp, with: .color(.black.opacity(0.12)), lineWidth: 1.2)
            }

        case .coffee:
            // Mug handle on the right + two wisps of rising steam.
            var handle = Path()
            handle.addArc(center: CGPoint(x: body.maxX + body.width * 0.02, y: body.midY + body.height * 0.06),
                          radius: body.width * 0.17, startAngle: .degrees(-72), endAngle: .degrees(72), clockwise: false)
            ctx.stroke(handle, with: .color(tint), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            for sx in [-1.0, 1.0] {
                let x0 = body.midX + CGFloat(sx) * body.width * 0.13 + CGFloat(sin(t * 2 + sx)) * body.width * 0.02
                let y0 = body.minY - body.height * 0.03
                var steam = Path()
                steam.move(to: CGPoint(x: x0, y: y0))
                steam.addCurve(to: CGPoint(x: x0, y: y0 - body.height * 0.24),
                               control1: CGPoint(x: x0 + body.width * 0.09, y: y0 - body.height * 0.07),
                               control2: CGPoint(x: x0 - body.width * 0.09, y: y0 - body.height * 0.16))
                ctx.stroke(steam, with: .color(.white.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }
}
