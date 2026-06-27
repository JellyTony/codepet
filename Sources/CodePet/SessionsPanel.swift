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
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, session in
                        SessionCard(session: session, now: now)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.86, anchor: .bottom).combined(with: .opacity),
                                removal: .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity)))
                            // Stagger each card in for a lively cascade.
                            .animation(.spring(response: 0.42, dampingFraction: 0.78)
                                        .delay(Double(idx) * 0.05),
                                       value: visible.count)
                    }
                }
                collapseButton
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
                .foregroundStyle(Color.black.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white))
                .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 2)
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
    @State private var replyText = ""

    private var title: String { session.displayTitle }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            contentRow
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onTapGesture { focusTerminal() }   // click body → focus terminal
            // Quick reply — type straight into this session without switching.
            if TerminalInput.canSend(to: session) && (hovering || session.state == .waiting) {
                replyRow.transition(.opacity)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(CardBackground(highlighted: hovering,
                                   accent: session.state.needsAttention ? statusColor : nil))
        .opacity(session.isLive(now: now) ? 1.0 : 0.66)
        .offset(y: hovering ? -1.5 : 0)   // gentle lift on hover (with the shadow)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: session.state)
        .help(helpText)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .contextMenu { contextItems }
    }

    private var contentRow: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                // Project chip + title row.
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(statusColor.opacity(0.12)))
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
                .padding(.top, 1)
                .id(session.state)   // cross-fade when the state changes
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }

    /// Inline quick-reply: type a line and press return (or the send button) to
    /// deliver it straight to this session's prompt.
    private var replyRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 9))
                .foregroundStyle(CardInk.faint)
            TextField(L.t(.replyPlaceholder), text: $replyText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(CardInk.title)
                .onSubmit(sendReply)
            if !replyText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: sendReply) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(statusColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.05)))
    }

    private func sendReply() {
        let t = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        TerminalInput.send(t, to: session)
        replyText = ""
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

    // Darker, readable-on-white variants of the state tints.
    private var statusColor: Color {
        switch session.state {
        case .running: return Color(red: 0.09, green: 0.55, blue: 0.62)
        case .waiting: return Color(red: 0.82, green: 0.55, blue: 0.05)
        case .ready:   return Color(red: 0.16, green: 0.60, blue: 0.30)
        case .failed:  return Color(red: 0.82, green: 0.22, blue: 0.22)
        case .idle:    return Color(red: 0.45, green: 0.49, blue: 0.57)
        }
    }

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

/// Crisp white, very rounded, softly shadowed card — matches the Codex pet
/// stack. Borderless and pure white normally; needs-attention cards get a warm
/// colour tint, a thin accent edge, and a colour-tinted glow.
struct CardBackground: View {
    var highlighted: Bool = false
    var accent: Color? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        shape
            .fill(Color.white)
            .overlay(shape.fill(accent?.opacity(0.07) ?? .clear))      // warm tint on accent
            .overlay(accent.map { shape.stroke($0.opacity(0.40), lineWidth: 1.1) })
            .shadow(color: (accent ?? .black).opacity(accent != nil ? 0.26 : 0.15),
                    radius: highlighted ? 13 : 10, x: 0, y: highlighted ? 6 : 4)
            .shadow(color: .black.opacity(0.05), radius: 1.5, x: 0, y: 1)
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
    private var hosting: NSHostingView<SessionsView>!

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
        hosting = NSHostingView(rootView: root)
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }   // so card taps + menu work
    override var canBecomeMain: Bool { false }

    /// Size to fit content and anchor the bottom just above the pet, centered.
    func reposition(above petFrame: NSRect) {
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 10 { size.width = SessionsView.cardWidth + 36 }
        if size.height < 10 { size.height = 80 }

        guard let screen = NSScreen.main else { setContentSize(size); return }
        let vf = screen.visibleFrame
        let gap: CGFloat = 0
        var x = petFrame.midX - size.width / 2
        var y = petFrame.maxY + gap            // bottom edge above the pet's top
        x = max(vf.minX + 6, min(x, vf.maxX - size.width - 6))
        if y + size.height > vf.maxY { y = max(vf.minY + 6, vf.maxY - size.height - 6) }
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
