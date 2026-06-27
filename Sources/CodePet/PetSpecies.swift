import SwiftUI

/// A drawable creature form. Codex ships several forms; CodePet draws them as
/// vectors so they animate crisply at any size.
enum PetSpecies: String, CaseIterable {
    case blob
    case cat
    case robot
    case ghost

    static let displayName: [PetSpecies: String] = [
        .blob: "Blob", .cat: "Stacky", .robot: "Byte", .ghost: "Glitch"
    ]

    var title: String { PetSpecies.displayName[self] ?? rawValue.capitalized }

    /// Constant identity colour for the built-in form.
    var identityColor: Color {
        switch self {
        case .blob:  return Color(red: 0.27, green: 0.74, blue: 0.78)
        case .cat:   return Color(red: 0.95, green: 0.62, blue: 0.30)
        case .robot: return Color(red: 0.55, green: 0.60, blue: 0.72)
        case .ghost: return Color(red: 0.64, green: 0.52, blue: 0.92)
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
            // Two triangular ears.
            for sx in [-1.0, 1.0] {
                var ear = Path()
                let ex = body.midX + CGFloat(sx) * body.width * 0.30
                let topY = body.minY - body.height * 0.02
                ear.move(to: CGPoint(x: ex - body.width * 0.12, y: topY))
                ear.addLine(to: CGPoint(x: ex + CGFloat(sx) * body.width * 0.02, y: topY - body.height * 0.26))
                ear.addLine(to: CGPoint(x: ex + body.width * 0.12, y: topY))
                ear.closeSubpath()
                ctx.fill(ear, with: .color(tint))
                ctx.stroke(ear, with: .color(.black.opacity(0.28)), lineWidth: 2)
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
            ctx.stroke(stem, with: .color(.black.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            let pulse = (sin(t * 4) + 1) / 2
            let br = body.width * 0.07
            let bulb = CGRect(x: body.midX - br, y: body.minY - body.height * 0.22 - br,
                              width: br * 2, height: br * 2)
            ctx.fill(Circle().path(in: bulb),
                     with: .color(.red.opacity(0.5 + 0.5 * pulse)))
            // Side bolts.
            for sx in [-1.0, 1.0] {
                let r = body.width * 0.05
                let c = CGRect(x: body.midX + CGFloat(sx) * body.width * 0.5 - r,
                               y: body.midY - r, width: r * 2, height: r * 2)
                ctx.fill(Circle().path(in: c), with: .color(.black.opacity(0.3)))
            }
        }
    }
}
