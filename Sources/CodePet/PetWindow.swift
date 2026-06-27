import AppKit
import SwiftUI

/// The borderless, transparent, always-on-top panel the corner pet lives in.
/// Hosts an `PetContainerView` that owns all mouse interaction (hover, gaze,
/// click-to-open-panel, drag-to-reposition) so the pet feels alive.
final class PetWindow: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PetView.baseW, height: PetView.baseH),
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
        isMovableByWindowBackground = false   // we drive dragging ourselves
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Restore a hand-dragged position if present, else park in the corner.
    func restorePosition(_ config: Config) {
        if let origin = config.customOrigin, onScreen(origin) {
            setFrameOrigin(origin)
        } else {
            snapToCorner(config.corner)
        }
    }

    private func onScreen(_ origin: CGPoint) -> Bool {
        let r = NSRect(origin: origin, size: frame.size)
        return NSScreen.screens.contains { $0.frame.intersects(r) }
    }

    /// Park the panel in the chosen screen corner with a small margin. Uses the
    /// screen the pet is currently on (falling back to the main screen) so corner
    /// snapping does the right thing on multi-monitor setups.
    func snapToCorner(_ corner: String) {
        guard let screen = self.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let margin: CGFloat = 24
        let w = frame.width, h = frame.height
        var origin = CGPoint(x: vf.maxX - w - margin, y: vf.minY + margin)
        switch corner {
        case "bottomLeft": origin = CGPoint(x: vf.minX + margin, y: vf.minY + margin)
        case "topRight":   origin = CGPoint(x: vf.maxX - w - margin, y: vf.maxY - h - margin)
        case "topLeft":    origin = CGPoint(x: vf.minX + margin, y: vf.maxY - h - margin)
        default:           break // bottomRight
        }
        setFrameOrigin(origin)
    }
}

/// NSView that wraps the SwiftUI pet and intercepts every mouse interaction.
/// Returning `self` from hitTest means the SwiftUI hosting view never sees the
/// mouse — the pet is purely visual and this container owns the behavior.
final class PetContainerView: NSView {
    var onHover: ((Bool) -> Void)?
    var onGaze: ((CGSize) -> Void)?
    var onClick: (() -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    var onResizeBegan: (() -> Void)?
    var onResize: ((CGFloat) -> Void)?            // horizontal screen delta
    var onResizeEnded: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var dragging = false
    private var totalDrag: CGFloat = 0
    private var lastMouse: NSPoint = .zero          // screen coords
    private var resizing = false
    private var resizeStartX: CGFloat = 0
    private var hosting: NSView?

    /// Bottom-right hot zone for the resize handle (view is not flipped, so the
    /// visual bottom-right corner is at maxX / minY). Scales with the pet so the
    /// clickable area keeps covering the handle at every size.
    private var resizeHotZone: NSRect {
        let s = max(30, bounds.width * 0.22)
        return NSRect(x: bounds.maxX - s, y: bounds.minY, width: s, height: s)
    }

    init(hosting: NSView) {
        super.init(frame: NSRect(x: 0, y: 0, width: PetView.baseW, height: PetView.baseH))
        self.hosting = hosting
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }
    required init?(coder: NSCoder) { fatalError() }

    // Swallow mouse so the SwiftUI canvas never intercepts it.
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
        publishGaze(event)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
        onGaze?(.zero)
    }

    override func mouseMoved(with event: NSEvent) { publishGaze(event) }

    private func publishGaze(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let nx = max(-1, min(1, (p.x - bounds.midX) / (bounds.width / 2)))
        let ny = max(-1, min(1, (p.y - bounds.midY) / (bounds.height / 2)))
        // SwiftUI y grows downward; flip so positive = look up.
        onGaze?(CGSize(width: nx, height: -ny))
    }

    // MARK: - Click vs drag

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if resizeHotZone.contains(pt) {
            resizing = true
            resizeStartX = NSEvent.mouseLocation.x
            onResizeBegan?()
            return
        }
        dragging = false
        totalDrag = 0
        lastMouse = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        if resizing {
            onResize?(NSEvent.mouseLocation.x - resizeStartX)
            return
        }
        guard let window = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - lastMouse.x
        let dy = now.y - lastMouse.y
        totalDrag += abs(dx) + abs(dy)
        if totalDrag > 4 { dragging = true }
        var origin = window.frame.origin
        origin.x += dx
        origin.y += dy
        window.setFrameOrigin(origin)
        onDragMove?(origin)
        lastMouse = now
    }

    override func mouseUp(with event: NSEvent) {
        if resizing {
            resizing = false
            onResizeEnded?()
            return
        }
        if dragging, let window = window {
            onDragEnded?(window.frame.origin)
        } else {
            onClick?()
        }
        dragging = false
    }
}
