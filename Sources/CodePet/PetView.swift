import SwiftUI

extension PetActivity {
    /// Bright tint for accents drawn *on the pet* and on dark surfaces.
    var tint: Color {
        switch self {
        case .idle:    return Color(red: 0.62, green: 0.66, blue: 0.74)
        case .running: return Color(red: 0.20, green: 0.78, blue: 0.85)
        case .waiting: return Color(red: 0.98, green: 0.80, blue: 0.27)
        case .ready:   return Color(red: 0.35, green: 0.82, blue: 0.48)
        case .failed:  return Color(red: 0.92, green: 0.36, blue: 0.36)
        }
    }

    /// Darker, readable-on-white variant — used by the white cards and the
    /// pet's status chip so they share one palette.
    var inkTint: Color {
        switch self {
        case .running: return Color(red: 0.09, green: 0.55, blue: 0.62)
        case .waiting: return Color(red: 0.82, green: 0.55, blue: 0.05)
        case .ready:   return Color(red: 0.16, green: 0.60, blue: 0.30)
        case .failed:  return Color(red: 0.82, green: 0.22, blue: 0.22)
        case .idle:    return Color(red: 0.45, green: 0.49, blue: 0.57)
        }
    }
}

/// Root view of the corner pet: a sprite/vector creature that reflects the
/// **aggregate** of all live sessions, reacts to the cursor (gaze + perk-up),
/// and surfaces an at-a-glance summary on hover.
struct PetView: View {
    @ObservedObject var store: StateStore
    @State private var pop: CGFloat = 1.0   // transient bounce on state change

    /// Base overlay size at scale 1.0 (the window grows by `scale`). The height
    /// includes transparent headroom above the pet so the jump never clips — the
    /// window is a borderless transparent overlay, so the extra room is invisible.
    static let baseW: CGFloat = 160
    static let baseH: CGFloat = 172
    /// The creature stage size (inside the overlay), tall enough to hold the
    /// sprite plus its full upward hop.
    static let stageW: CGFloat = 128
    static let stageH: CGFloat = 138

    var body: some View {
        let activity = store.displayActivity
        let entry = PetCatalog.resolve(store.config.pet, in: store.catalog)
        let scale = store.config.scale

        // Inset for the resize handle (bottom-right).
        let edgeInset = 8 * scale

        // Drop to a calm redraw cadence when idle and not being interacted with,
        // and stop entirely while the pet is hidden behind other windows.
        let lowPower = (activity == .idle && !store.hovering)
        let paused = !store.petVisible

        ZStack {
            VStack(spacing: 4 * scale) {
                // Status sits ABOVE the pet, and only while the card stack is
                // closed — when cards are open they already show each session's
                // status, so a second status line here would be redundant.
                if !store.panelOpen {
                    caption(activity: activity, scale: scale)
                        .transition(.opacity)
                }
                // Only the creature breathes on hover — scaling the whole stack
                // used to nudge the corner chip/handle out of frame and clip them.
                Group {
                    if let atlas = entry.atlas {
                        SpriteStage(atlas: atlas, activity: activity, scale: scale,
                                    gaze: store.gaze, lowPower: lowPower, paused: paused)
                    } else {
                        VectorStage(species: entry.species ?? .blob, baseColor: entry.baseColor,
                                    activity: activity, scale: scale, gaze: store.gaze,
                                    lowPower: lowPower, paused: paused)
                    }
                }
                .frame(width: PetView.stageW * scale, height: PetView.stageH * scale)
                .scaleEffect((store.hovering ? 1.06 : 1.0) * pop, anchor: .bottom)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: store.hovering)
                .onChange(of: activity) { _ in
                    pop = 1.16
                    withAnimation(.interpolatingSpring(stiffness: 260, damping: 12)) { pop = 1.0 }
                }
            }
            // Bottom-anchor so the pet keeps its resting position whether or not
            // the caption is present above it.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.easeOut(duration: 0.18), value: store.panelOpen)

            // Resize handle — bottom-right.
            if store.hovering {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 18 * scale, height: 18 * scale)
                    .background(Circle().fill(.black.opacity(0.42)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, edgeInset).padding(.bottom, edgeInset)
                    .transition(.opacity)
                    .help("Drag to resize")
            }
        }
        .frame(width: PetView.baseW * scale, height: PetView.baseH * scale)
        .animation(.easeOut(duration: 0.15), value: store.hovering)
    }

    /// The state caption: a dark translucent pill so text stays legible on any
    /// wallpaper (label + the winning detail, or an aggregate summary on hover).
    /// Sits above the pet and only when the card stack is closed.
    private func caption(activity: PetActivity, scale: Double) -> some View {
        let count = store.liveSessions.count
        let attention = store.attentionCount
        return VStack(spacing: 2.5 * scale) {
            // Status label, with the live-session count folded in as a small
            // badge (so the count no longer crowds in a separate corner chip).
            HStack(spacing: 5 * scale) {
                Text(activity.label)
                    .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(activity.tint)
                if count > 1 {
                    HStack(spacing: 2 * scale) {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 7 * scale, weight: .bold))
                        Text("\(count)")
                            .font(.system(size: 9 * scale, weight: .heavy, design: .rounded))
                        if attention > 0 {
                            Circle()
                                .fill(Color(red: 0.98, green: 0.80, blue: 0.27))
                                .frame(width: 4 * scale, height: 4 * scale)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 4 * scale).padding(.vertical, 1 * scale)
                    .background(Capsule().fill(.white.opacity(0.16)))
                }
            }
            Group {
                if store.hovering {
                    Text(store.summaryLine)
                } else if let detail = store.displayDetail, !detail.isEmpty {
                    Text(detail)
                }
            }
            .font(.system(size: 9 * scale, weight: .regular, design: .rounded))
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 150 * scale)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 4 * scale)
        .background(
            Capsule().fill(.black.opacity(0.46))
                .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.5))
                // Soft lift so the pill floats like the cards do, not flat on the wall.
                .shadow(color: .black.opacity(0.28), radius: 5 * scale, x: 0, y: 2.5 * scale)
        )
    }
}

// MARK: - Spritesheet playback (real Codex pets)

struct SpriteStage: View {
    let atlas: SpriteAtlas
    let activity: PetActivity
    let scale: Double
    var gaze: CGSize = .zero
    /// Throttle redraws to ~10fps when there's nothing lively to show (idle and
    /// not hovered) — the subtle idle motion doesn't need the full display rate,
    /// and it keeps a always-on-top pet from burning CPU/battery in the corner.
    var lowPower: Bool = false
    /// Stop redrawing entirely when the pet window is fully occluded by other
    /// windows — no point animating pixels nobody can see.
    var paused: Bool = false

    /// Headroom kept above the resting sprite so the upward hop never clips.
    static let hopHeadroom: CGFloat = Behavior.maxUpwardTravel + 4

    /// Place the sprite cell in the stage: scaled to fit the width and the height
    /// *minus the hop headroom*, then bottom-anchored so it rests low and hops up
    /// into the reserved space. The returned rect is guaranteed to stay inside
    /// the stage for any dy the Behavior emits (proof: restY ≥ headroom ≥ |dy|).
    static func placedRect(in size: CGSize, cell: CGSize, dx: CGFloat, dy: CGFloat) -> CGRect {
        let availH = max(1, size.height - hopHeadroom)
        let fit = min(size.width / cell.width, availH / cell.height) * 0.96
        let w = cell.width * fit, h = cell.height * fit
        let restY = size.height - h - 3          // bottom-anchored, 3pt margin
        return CGRect(x: (size.width - w) / 2 + dx, y: restY + dy, width: w, height: h)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: lowPower ? 0.1 : nil, paused: paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let span = size.width * 0.16
                let m = Behavior.motion(for: activity, t: t, span: span)
                let frames = atlas.frames(m.action)
                guard !frames.isEmpty else { return }
                let idx = Int(t * Behavior.fps) % frames.count
                let cg = frames[idx]

                // Bitmap eyes can't move; lean the whole body toward the cursor.
                let lean = gaze.width * 4
                let base = SpriteStage.placedRect(in: size, cell: atlas.cellSize,
                                                  dx: m.dx + lean, dy: m.dy)

                var img = ctx
                if m.facingLeft {
                    img.translateBy(x: size.width, y: 0)
                    img.scaleBy(x: -1, y: 1)
                }
                let rect = m.facingLeft
                    ? CGRect(x: size.width - base.maxX, y: base.minY, width: base.width, height: base.height)
                    : base
                img.draw(Image(decorative: cg, scale: 1), in: rect)
            }
        }
    }
}

// MARK: - Vector pet (built-in forms, zero install)

struct VectorStage: View {
    let species: PetSpecies
    let baseColor: Color
    let activity: PetActivity
    let scale: Double
    var gaze: CGSize = .zero
    /// See `SpriteStage.lowPower`.
    var lowPower: Bool = false
    /// See `SpriteStage.paused`.
    var paused: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: lowPower ? 0.1 : nil, paused: paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                VectorPet.draw(ctx: &ctx, size: size, t: t, activity: activity,
                               species: species, baseColor: baseColor, gaze: gaze)
            }
        }
    }
}
