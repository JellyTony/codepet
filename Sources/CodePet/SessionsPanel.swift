import AppKit
import SwiftUI

/// The session stack — a vertical column of clean white "task cards" that float
/// directly above the pet (the Codex-pets layout). Each card is one Claude Code
/// session: the task title, a calm one-line status, and a status indicator.
/// Deliberately minimal to match the Codex reference; extra actions live in the
/// right-click menu, not in visible chrome.
struct SessionsView: View {
    @ObservedObject var store: StateStore
    var onCollapse: () -> Void

    static let cardWidth: CGFloat = 268

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date.timeIntervalSince1970
            let visible = store.displaySessions
            VStack(spacing: 9) {
                if visible.isEmpty {
                    emptyCard.transition(.opacity)
                } else {
                    ForEach(visible) { session in
                        SessionCard(session: session, now: now)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity),
                                removal: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity)))
                    }
                }
                // Right-aligned so the chevron sits over the pet (which the
                // stack now hangs to the upper-left of), matching the reference.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    collapseButton
                }
                .padding(.trailing, 16)
            }
            .frame(width: SessionsView.cardWidth)
            // Breathing room so the soft card shadows aren't clipped.
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .animation(.spring(response: 0.42, dampingFraction: 0.82),
                       value: visible.map(\.id))
        }
    }

    private var emptyCard: some View {
        HStack(spacing: 10) {
            MiniPet(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t(.noSessions))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CardInk.title)
                Text(L.t(.noSessionsHint))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(CardInk.subtle)
            }
            Spacer()
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(CardBackground())
    }

    private var collapseButton: some View {
        Button(action: onCollapse) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.42))
                .frame(width: 26, height: 26)
                // A little glossy pebble — same top-lit material as the cards.
                .background(
                    Circle()
                        .fill(LinearGradient(colors: [Color.white, Color(white: 0.95)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.9), Color.black.opacity(0.09)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)))
                .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 2)
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .help(L.t(.collapseCards))
    }
}

// MARK: - Card

struct SessionCard: View {
    let session: Session
    let now: Double

    @State private var hovering = false
    @State private var replyOpen = false
    @State private var replyText = ""
    @FocusState private var replyFocused: Bool

    private var title: String { session.displayTitle }
    private var canReply: Bool { TerminalInput.canSend(to: session) }
    /// The reply field is shown when the user opens it, or whenever the session
    /// is actually waiting on input (where a reply is the obvious next move).
    private var showReply: Bool { canReply && (replyOpen || session.state == .waiting) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Tapping the body focuses the terminal; press gives a gentle dip.
            Button(action: focusTerminal) { contentRow }
                .buttonStyle(CardPressStyle())
            footer
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(CardBackground(highlighted: hovering || replyFocused,
                                   accent: session.state.needsAttention ? statusColor : nil))
        .opacity(session.isLive(now: now) ? 1.0 : 0.66)
        .scaleEffect(hovering && !replyFocused ? 1.012 : 1.0, anchor: .center)
        .offset(y: hovering && !replyFocused ? -2 : 0)   // gentle lift on hover
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: showReply)
        .help(helpText)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .contextMenu { contextItems }
    }

    /// Below the content: the reply field when open/waiting, otherwise a quiet
    /// "reply" affordance that only appears on hover — so the layout stays calm
    /// until you actually reach for it.
    @ViewBuilder private var footer: some View {
        if showReply {
            replyRow.transition(.move(edge: .bottom).combined(with: .opacity))
        } else if hovering && canReply {
            replyHint.transition(.opacity)
        }
    }

    private var replyHint: some View {
        Button(action: openReply) {
            HStack(spacing: 5) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text(L.t(.replyPlaceholder))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(CardInk.subtle)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(
                Capsule().fill(Color.black.opacity(0.035))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.055), lineWidth: 0.75)))
            .contentShape(Capsule())
        }
        .buttonStyle(CardPressStyle())
    }

    private var contentRow: some View {
        HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                // Project chip + title row.
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 4.5, height: 4.5)
                        Text(session.project)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.3)
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(statusColor.opacity(0.11)))
                    Spacer(minLength: 0)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CardInk.title)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                // Summary — what Claude is doing right now.
                Text(summaryText)
                    .font(.system(size: 11, weight: session.state.needsAttention ? .semibold : .regular,
                                  design: .rounded))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                // Metrics line.
                let progress = session.progressLine(now: now)
                if !progress.isEmpty {
                    Text(progress)
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .foregroundStyle(CardInk.faint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            StatusIndicator(state: session.state, color: indicatorColor)
                .frame(width: 16, height: 16)
        }
    }

    /// Inline quick-reply: type a line and press return (or the send button) to
    /// deliver it straight to this session's prompt. Auto-focuses when opened,
    /// grows up to a few lines, and the trailing button flips between send (when
    /// there's text) and dismiss (when empty). Esc also closes it.
    private var replyRow: some View {
        let hasText = !replyText.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(alignment: .bottom, spacing: 7) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(statusColor.opacity(0.85))
                .padding(.bottom, 2)
            TextField(L.t(.replyPlaceholder), text: $replyText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CardInk.title)
                .focused($replyFocused)
                .onSubmit(sendReply)
            Button(action: hasText ? sendReply : closeReply) {
                Image(systemName: hasText ? "arrow.up.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(hasText ? statusColor : CardInk.faint)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(statusColor.opacity(replyFocused ? 0.08 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(replyFocused ? statusColor.opacity(0.5) : Color.black.opacity(0.06),
                                      lineWidth: replyFocused ? 1.2 : 0.75)))
        .animation(.easeOut(duration: 0.14), value: replyFocused)
        .onExitCommand(perform: closeReply)   // Esc dismisses
    }

    private func openReply() {
        replyOpen = true
        replyFocused = true
    }

    private func closeReply() {
        replyText = ""
        replyOpen = false
        replyFocused = false
    }

    private func sendReply() {
        let t = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        TerminalInput.send(t, to: session)
        replyText = ""
        replyOpen = false
        replyFocused = false
    }

    // MARK: Content

    /// What's happening now. Attention states surface the notification/detail;
    /// otherwise the latest assistant narration, falling back to the status.
    private var summaryText: String {
        switch session.state {
        case .running, .waiting, .failed:
            // Real-time: the current tool action / notification straight from the
            // hooks (localized at render so it follows the language live). The
            // transcript narration isn't written live, so it can't be the source
            // of a real-time "what's it doing now" line.
            if let d = session.detail, !d.isEmpty { return L.localizeDetail(d) }
            return session.summary ?? session.state.label
        default: // ready, idle — show the model's latest narration / result
            if let s = session.summary, !s.isEmpty { return s }
            return session.detail.map(L.localizeDetail) ?? session.state.label
        }
    }

    private var subtitleColor: Color {
        session.state.needsAttention ? statusColor : CardInk.subtle
    }

    /// Running uses a calm grey spinner (like the reference); attention states
    /// keep their colour so they stand out.
    private var indicatorColor: Color {
        session.state == .running ? Color.black.opacity(0.30) : statusColor
    }

    // Darker, readable-on-white variant of the state tint (shared with the pet
    // status chip so cards + caption use one palette).
    private var statusColor: Color { session.state.inkTint }

    private var helpText: String {
        var s = title
        if let c = session.cwd, !c.isEmpty { s += "\n" + c }
        return s
    }

    @ViewBuilder private var contextItems: some View {
        Text(title)
        if let s = session.summary, !s.isEmpty { Text(s) }
        Divider()
        if session.termProgram != nil {
            Button { focusTerminal() } label: { Label(L.t(.focusTerminal), systemImage: "terminal") }
        }
        Button { reveal() } label: { Label(L.t(.revealInFinder), systemImage: "folder") }
        Button { copyId() } label: { Label(L.t(.copyId), systemImage: "doc.on.doc") }
        Divider()
        Text(session.project)
        if let c = session.toolCount, c > 0 {
            Text("\(L.actions(c)) · \(Session.elapsed(since: session.startedAt, now: now))")
        }
        if let tools = session.recentTools, !tools.isEmpty {
            Text(L.t(.recent) + " " + tools.suffix(6).joined(separator: ", "))
        }
    }

    // MARK: Actions

    private func focusTerminal() {
        if !TerminalFocus.focus(session) { reveal() }  // fall back to Finder if unknown
    }
    private func reveal() {
        guard let cwd = session.cwd else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }
    private func copyId() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.sessionId, forType: .string)
    }
}

/// A soft, top-lit "pebble" card that speaks the same visual language as the
/// pet: a gentle vertical gradient body, a bevelled rim (bright on top, soft
/// shade below) and a blurred contact shadow — so a card reads as a smooth,
/// illuminated object, not a flat web sheet. Attention cards warm to the state
/// colour with a tinted rim and glow.
struct CardBackground: View {
    var highlighted: Bool = false
    var accent: Color? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        let glow = accent ?? .black
        shape
            // Top-lit body gradient — the pet's "lit from above" sheen language.
            .fill(LinearGradient(colors: [Color.white, Color(white: 0.955)],
                                 startPoint: .top, endPoint: .bottom))
            // Warm wash on attention cards.
            .overlay(accent.map { shape.fill($0.opacity(0.07)) })
            // Bevelled rim: a bright highlight along the top easing to a soft
            // shade below — mirrors the pet's sheen-on-top, shade-underneath.
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: accent.map { [$0.opacity(0.46), $0.opacity(0.20)] }
                            ?? [Color.white.opacity(0.9), Color.black.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
            // Soft, blurred drop shadow echoing the pet's contact shadow.
            .shadow(color: glow.opacity(accent != nil ? 0.22 : 0.12),
                    radius: highlighted ? 16 : 12, x: 0, y: highlighted ? 7 : 5)
            .shadow(color: .black.opacity(0.06), radius: 2.5, x: 0, y: 1)
    }
}

/// Press feedback for tappable card surfaces — a gentle dip + dim, so a click
/// feels physical (matching the soft, springy pet) instead of dead-flat.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A tiny idle pet — used to give the empty state some brand charm.
struct MiniPet: View {
    var size: CGFloat = 42
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                VectorPet.draw(ctx: &ctx, size: sz, t: t, activity: .idle,
                               species: .blob, baseColor: PetSpecies.blob.identityColor, gaze: .zero)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Card text palette (fixed dark-on-white, like the reference).
enum CardInk {
    static let title = Color.black.opacity(0.88)
    static let subtle = Color.black.opacity(0.48)
    static let faint = Color.black.opacity(0.33)
}

// MARK: - Status indicator

struct StatusIndicator: View {
    let state: PetActivity
    let color: Color

    var body: some View {
        switch state {
        case .running:
            SpinnerArc(color: color)
        case .waiting:
            PulseDot(color: color)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(color)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(color)
        case .idle:
            Circle().stroke(color.opacity(0.5), lineWidth: 2)
                .frame(width: 12, height: 12)
        }
    }
}

/// A thin indeterminate spinner — the reference's "正在思考" indicator.
struct SpinnerArc: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().stroke(color.opacity(0.16), lineWidth: 2)
                // Comet-tail arc — the colour fades into the track for a smoother spin.
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(AngularGradient(gradient: Gradient(colors: [color.opacity(0), color]),
                                            center: .center),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 0.85) / 0.85 * 360))
            }
            .frame(width: 15, height: 15)
        }
    }
}

struct PulseDot: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.4 + 0.6 * (sin(t * 3.4) + 1) / 2
            ZStack {
                Circle().fill(color.opacity(0.25 * pulse)).frame(width: 16, height: 16)
                Circle().fill(color).frame(width: 8, height: 8).opacity(pulse)
            }
        }
    }
}

// MARK: - Panel window

/// Transparent, draggable panel that hosts the card stack directly above the
/// pet. Auto-sizes to its content and bottom-anchors so cards grow upward.
final class SessionsPanel: NSPanel {
    private var hosting: ContentSizingHostingView<SessionsView>!
    private var lastPetFrame: NSRect = .zero
    private var refitting = false

    init(store: StateStore, onCollapse: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: SessionsView.cardWidth + 36, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let root = SessionsView(store: store, onCollapse: onCollapse)
        hosting = ContentSizingHostingView(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        // Re-fit whenever a card grows/shrinks (e.g. a reply field opening) so
        // the panel tracks its content instead of clipping it.
        hosting.onContentResize = { [weak self] in self?.refit() }
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }   // so card taps + menu work
    override var canBecomeMain: Bool { false }

    /// Horizontal padding baked into the SwiftUI stack (so soft shadows aren't
    /// clipped). The *visible* card right edge sits this far inside the window.
    private static let shadowInset: CGFloat = 18
    /// How far below the pet window's top edge the card stack's bottom tucks,
    /// as a fraction of the pet's height — so the gap scales with the pet.
    /// Kept small so the chevron clears the pet's head (which reaches fairly
    /// high in the window) instead of being occluded by it.
    private static let headGap: CGFloat = 0.06

    /// Size to fit content and anchor the bottom just above the pet.
    func reposition(above petFrame: NSRect) {
        lastPetFrame = petFrame
        refit()
    }

    /// Re-measure the SwiftUI content and re-anchor above the pet. Guarded
    /// against re-entrancy (layout can itself invalidate the intrinsic size).
    private func refit() {
        guard !refitting, lastPetFrame != .zero else { return }
        refitting = true
        defer { refitting = false }

        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 10 { size.width = SessionsView.cardWidth + 36 }
        if size.height < 10 { size.height = 80 }

        guard let screen = NSScreen.main else { setContentSize(size); return }
        let vf = screen.visibleFrame

        // Right-align the stack to the pet so cards fan out to its upper-left.
        // The visible card's right edge lands at the pet's right-of-centre, and
        // because the stack only ever grows leftward it stays fully on-screen
        // when the pet is dragged to the right edge.
        let anchorRight = lastPetFrame.midX + lastPetFrame.width * 0.18
        var x = anchorRight - size.width + SessionsPanel.shadowInset
        // The pet rests in the lower part of its window, with transparent
        // headroom on top (for the jump). Tuck the stack's bottom down to just
        // above the pet's head — as a fraction of the pet's height, so the gap
        // tracks the pet's size instead of being a fixed distance.
        var y = lastPetFrame.maxY - lastPetFrame.height * SessionsPanel.headGap
        // Clamp to the screen: pin to the left edge if the pet is hard left,
        // and never let the visible card spill past the right edge.
        x = max(vf.minX + 6, min(x, vf.maxX - size.width + SessionsPanel.shadowInset - 6))
        if y + size.height > vf.maxY { y = max(vf.minY + 6, vf.maxY - size.height - 6) }
        let newFrame = NSRect(x: x, y: y, width: size.width, height: size.height)
        if newFrame != frame { setFrame(newFrame, display: true, animate: false) }
    }
}

/// An `NSHostingView` that reports SwiftUI content-size changes so the hosting
/// window can re-fit. Coalesced to one callback per run-loop turn.
final class ContentSizingHostingView<V: View>: NSHostingView<V> {
    var onContentResize: (() -> Void)?
    private var scheduled = false

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.scheduled = false
            self.onContentResize?()
        }
    }
}
