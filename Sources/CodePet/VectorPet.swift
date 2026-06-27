import SwiftUI

/// Procedurally-drawn, fully animated built-in pet. Expresses every `PetAction`
/// (idle, walk, wave, jump, fail, wait, review) so the built-in forms behave
/// like real Petdex/Codex spritesheet pets without any assets.
enum VectorPet {
    static func draw(ctx: inout GraphicsContext, size: CGSize, t: Double,
                     activity: PetActivity, species: PetSpecies, baseColor: Color,
                     gaze: CGSize = .zero) {
        let span = size.width * 0.16
        let motion = Behavior.motion(for: activity, t: t, span: span)

        let cx = size.width / 2 + motion.dx
        let baseY = size.height * 0.60 + motion.dy
        let bodyW = size.width * 0.46
        let bodyH = size.height * 0.42
        // Identity colour stays constant across states (like Codex); the state
        // is conveyed by pose, the accent badge, and the label.
        let tint = baseColor

        // Breathing + per-action squash.
        let breathe = sin(t * 2.0) * 0.04
        var squash = 1.0 + breathe
        switch motion.action {
        case .walk, .walkRight, .walkLeft:
            squash = 1.0 + sin(t * 12.0) * 0.05
        case .jump:
            squash = 1.12
        case .fail:
            squash = 0.96
        default: break
        }

        // Contact shadow (shrinks as the pet hops).
        let lift = max(0, -motion.dy)
        let shadowW = bodyW * (1.0 - lift / 120.0)
        let shadowRect = CGRect(x: cx - shadowW / 2,
                                y: size.height * 0.60 + bodyH * 0.52,
                                width: shadowW, height: bodyH * 0.16)
        ctx.fill(Ellipse().path(in: shadowRect), with: .color(.black.opacity(0.22)))

        let w = bodyW / squash
        let h = bodyH * squash
        let body = CGRect(x: cx - w / 2, y: baseY - h / 2, width: w, height: h)

        // Little alternating feet while walking.
        if motion.action == .walk || motion.action == .walkRight || motion.action == .walkLeft {
            drawFeet(ctx: &ctx, body: body, t: t, tint: tint)
        }

        // Body.
        let bodyPath = species.bodyPath(in: body)
        let grad = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [tint.opacity(0.98), tint.opacity(0.72)]),
            startPoint: CGPoint(x: body.midX, y: body.minY),
            endPoint: CGPoint(x: body.midX, y: body.maxY))
        ctx.fill(bodyPath, with: grad)
        ctx.stroke(bodyPath, with: .color(.black.opacity(0.28)), lineWidth: 2)

        species.drawFeatures(ctx: &ctx, body: body, t: t, tint: tint)

        // Waving arm.
        if motion.action == .wave {
            drawWavingArm(ctx: &ctx, body: body, t: t, tint: tint)
        }
        // Review: holds a little "code package".
        if motion.action == .review {
            drawPackage(ctx: &ctx, body: body)
        }

        let blinking = t.truncatingRemainder(dividingBy: 3.4) > 3.2
        drawEyes(ctx: &ctx, body: body, action: motion.action, blinking: blinking, t: t, gaze: gaze)
        drawMouth(ctx: &ctx, body: body, action: motion.action)

        if motion.action == .review || motion.action == .wave {
            drawCheeks(ctx: &ctx, body: body)
        }
        if motion.action == .fail {
            drawSweat(ctx: &ctx, body: body, t: t)
        }

        drawAccents(ctx: &ctx, size: size, body: body, t: t, activity: activity)
    }

    // MARK: - Parts

    private static func drawFeet(ctx: inout GraphicsContext, body: CGRect, t: Double, tint: Color) {
        let phase = sin(t * 12.0)
        for (i, sx) in [-1.0, 1.0].enumerated() {
            let swing = (i == 0 ? phase : -phase) * body.height * 0.08
            let fx = body.midX + CGFloat(sx) * body.width * 0.22
            let fy = body.maxY + body.height * 0.02 + swing
            let r = body.width * 0.09
            ctx.fill(Ellipse().path(in: CGRect(x: fx - r, y: fy - r * 0.6,
                                               width: r * 2, height: r * 1.2)),
                     with: .color(tint.opacity(0.85)))
        }
    }

    private static func drawWavingArm(ctx: inout GraphicsContext, body: CGRect, t: Double, tint: Color) {
        let wave = sin(t * 10) * 0.5
        let shoulder = CGPoint(x: body.maxX - body.width * 0.05, y: body.midY)
        let hand = CGPoint(x: body.maxX + body.width * 0.22,
                           y: body.minY - body.height * 0.08 + CGFloat(wave) * 14)
        var arm = Path()
        arm.move(to: shoulder)
        arm.addQuadCurve(to: hand, control: CGPoint(x: body.maxX + body.width * 0.18, y: body.midY))
        ctx.stroke(arm, with: .color(tint), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        let r = body.width * 0.07
        ctx.fill(Ellipse().path(in: CGRect(x: hand.x - r, y: hand.y - r, width: r * 2, height: r * 2)),
                 with: .color(tint))
    }

    private static func drawPackage(ctx: inout GraphicsContext, body: CGRect) {
        let s = body.width * 0.34
        let rect = CGRect(x: body.midX - s / 2, y: body.maxY - s * 0.35, width: s, height: s * 0.8)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color(white: 0.95)))
        ctx.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(.black.opacity(0.35)), lineWidth: 1.5)
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: rect.midX, y: rect.minY))
        ribbon.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        ribbon.move(to: CGPoint(x: rect.minX, y: rect.midY))
        ribbon.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        ctx.stroke(ribbon, with: .color(Color(red: 0.35, green: 0.82, blue: 0.48)), lineWidth: 2)
    }

    private static func drawEyes(ctx: inout GraphicsContext, body: CGRect, action: PetAction,
                                 blinking: Bool, t: Double, gaze: CGSize = .zero) {
        let eyeY = body.midY - body.height * 0.08
        let dx = body.width * 0.20
        let eyeR = body.width * 0.085
        // When the cursor is near, the pupils track it; otherwise idle drift.
        let tracking = abs(gaze.width) > 0.001 || abs(gaze.height) > 0.001
        let look: CGFloat
        let lookY: CGFloat
        if tracking {
            look = gaze.width * eyeR * 0.9
            lookY = -gaze.height * eyeR * 0.8   // gaze.height>0 = up; screen y down
        } else {
            switch action {
            case .walk, .walkRight, .walkLeft: look = CGFloat(sin(t * 3.0)) * eyeR * 0.5
            case .wait: look = CGFloat(sin(t * 1.5)) * eyeR * 0.5
            default: look = CGFloat(sin(t * 0.8)) * eyeR * 0.3
            }
            lookY = 0
        }
        // Failed/waiting expressions.
        let sad = (action == .fail)
        for sx in [-1.0, 1.0] {
            let ex = body.midX + CGFloat(sx) * dx
            if blinking || sad {
                var line = Path()
                let yy = sad ? eyeY - eyeR * 0.3 : eyeY
                line.move(to: CGPoint(x: ex - eyeR, y: sad ? yy + eyeR * 0.6 : yy))
                line.addLine(to: CGPoint(x: ex + eyeR, y: yy))
                ctx.stroke(line, with: .color(.black.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                continue
            }
            let white = CGRect(x: ex - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2)
            ctx.fill(Ellipse().path(in: white), with: .color(.white))
            let pr = eyeR * (action == .wait ? 0.62 : 0.55)
            let pupil = CGRect(x: ex - pr + look, y: eyeY - pr + lookY, width: pr * 2, height: pr * 2)
            ctx.fill(Ellipse().path(in: pupil), with: .color(.black.opacity(0.88)))
            let gr = pr * 0.35
            ctx.fill(Ellipse().path(in: CGRect(x: ex - pr + look + gr * 0.4, y: eyeY - pr * 0.4 + lookY,
                                               width: gr, height: gr)),
                     with: .color(.white.opacity(0.9)))
        }
    }

    private static func drawMouth(ctx: inout GraphicsContext, body: CGRect, action: PetAction) {
        let mY = body.midY + body.height * 0.18
        let mW = body.width * 0.22
        var p = Path()
        switch action {
        case .review, .wave, .jump:
            p.move(to: CGPoint(x: body.midX - mW, y: mY - 2))
            p.addQuadCurve(to: CGPoint(x: body.midX + mW, y: mY - 2),
                           control: CGPoint(x: body.midX, y: mY + mW * 0.9))
        case .wait:
            p.addEllipse(in: CGRect(x: body.midX - mW * 0.35, y: mY - mW * 0.35,
                                    width: mW * 0.7, height: mW * 0.7))
        case .fail:
            p.move(to: CGPoint(x: body.midX - mW, y: mY + 3))
            p.addQuadCurve(to: CGPoint(x: body.midX + mW, y: mY + 3),
                           control: CGPoint(x: body.midX, y: mY - mW * 0.6))
        case .walk, .walkRight, .walkLeft:
            p.move(to: CGPoint(x: body.midX - mW * 0.7, y: mY))
            p.addLine(to: CGPoint(x: body.midX + mW * 0.7, y: mY))
        case .idle:
            p.move(to: CGPoint(x: body.midX - mW * 0.6, y: mY))
            p.addQuadCurve(to: CGPoint(x: body.midX + mW * 0.6, y: mY),
                           control: CGPoint(x: body.midX, y: mY + mW * 0.4))
        }
        ctx.stroke(p, with: .color(.black.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    private static func drawCheeks(ctx: inout GraphicsContext, body: CGRect) {
        let r = body.height * 0.07
        for sx in [-1.0, 1.0] {
            let c = CGRect(x: body.midX + CGFloat(sx) * body.width * 0.28 - r,
                           y: body.midY + body.height * 0.06 - r, width: r * 2, height: r * 2)
            ctx.fill(Ellipse().path(in: c), with: .color(Color.pink.opacity(0.45)))
        }
    }

    private static func drawSweat(ctx: inout GraphicsContext, body: CGRect, t: Double) {
        let drop = (sin(t * 3) + 1) / 2
        let x = body.maxX - body.width * 0.05
        let y = body.minY + body.height * 0.1 + CGFloat(drop) * body.height * 0.2
        var p = Path()
        p.move(to: CGPoint(x: x, y: y - 6))
        p.addQuadCurve(to: CGPoint(x: x + 4, y: y), control: CGPoint(x: x + 4, y: y - 3))
        p.addQuadCurve(to: CGPoint(x: x - 4, y: y), control: CGPoint(x: x - 4, y: y + 3))
        p.addQuadCurve(to: CGPoint(x: x, y: y - 6), control: CGPoint(x: x - 4, y: y - 3))
        ctx.fill(p, with: .color(Color(red: 0.5, green: 0.8, blue: 1.0).opacity(0.85)))
    }

    private static func drawAccents(ctx: inout GraphicsContext, size: CGSize, body: CGRect,
                                    t: Double, activity: PetActivity) {
        switch activity {
        case .running:
            drawGear(ctx: &ctx, center: CGPoint(x: body.maxX, y: body.minY - 4),
                     radius: body.width * 0.13, angle: t * 3.0, color: activity.tint)
        case .waiting:
            let bob = CGFloat(sin(t * 3.0)) * 3
            drawBubble(ctx: &ctx, center: CGPoint(x: body.maxX + 4, y: body.minY - 6 + bob),
                       text: "?", color: activity.tint)
        case .ready:
            for i in 0..<3 {
                let phase = t * 2.0 + Double(i) * 2.094
                let life = (sin(phase) + 1) / 2
                let ang = Double(i) * 2.094 - t
                let rad = body.width * (0.4 + 0.3 * life)
                let px = body.midX + CGFloat(cos(ang)) * rad
                let py = body.minY + CGFloat(sin(ang)) * rad * 0.6 - 4
                drawSparkle(ctx: &ctx, center: CGPoint(x: px, y: py),
                            size: body.width * 0.06 * (0.5 + life),
                            color: activity.tint.opacity(0.4 + 0.6 * life))
            }
        case .failed:
            drawBubble(ctx: &ctx, center: CGPoint(x: body.maxX + 4, y: body.minY - 6),
                       text: "!", color: activity.tint)
        case .idle:
            for i in 0..<3 {
                let phase = (t * 0.6 + Double(i) * 0.6).truncatingRemainder(dividingBy: 2.4)
                let life = 1 - phase / 2.4
                guard life > 0 else { continue }
                let zx = body.maxX - 4 + CGFloat(phase) * 10
                let zy = body.minY - CGFloat(phase) * 14
                ctx.draw(Text("z").font(.system(size: 9 + CGFloat(i) * 2, weight: .bold, design: .rounded))
                    .foregroundColor(activity.tint.opacity(life)), at: CGPoint(x: zx, y: zy))
            }
        }
    }

    private static func drawGear(ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                                 angle: Double, color: Color) {
        var path = Path()
        let teeth = 8
        let inner = radius * 0.62
        for i in 0..<(teeth * 2) {
            let a = angle + Double(i) * .pi / Double(teeth)
            let r = (i % 2 == 0) ? radius : inner
            let pt = CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
        ctx.stroke(path, with: .color(.black.opacity(0.3)), lineWidth: 1)
        let holeR = inner * 0.45
        ctx.fill(Ellipse().path(in: CGRect(x: center.x - holeR, y: center.y - holeR,
                                           width: holeR * 2, height: holeR * 2)),
                 with: .color(.black.opacity(0.55)))
    }

    private static func drawBubble(ctx: inout GraphicsContext, center: CGPoint, text: String, color: Color) {
        let r: CGFloat = 11
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.fill(Circle().path(in: rect), with: .color(.white))
        ctx.stroke(Circle().path(in: rect), with: .color(color), lineWidth: 2)
        ctx.draw(Text(text).font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundColor(color), at: center)
    }

    private static func drawSparkle(ctx: inout GraphicsContext, center: CGPoint, size: CGFloat, color: Color) {
        var p = Path()
        for i in 0..<4 {
            let a = Double(i) * .pi / 2
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + CGFloat(cos(a)) * size, y: center.y + CGFloat(sin(a)) * size))
        }
        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}
