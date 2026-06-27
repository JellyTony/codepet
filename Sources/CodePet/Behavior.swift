import CoreGraphics
import Foundation

/// Which `PetAction` to play right now plus how the pet should translate —
/// shared by the spritesheet player and the vector renderer so both express
/// the same behaviors (walk, wave, jump, twitch, fail, sit-and-review).
///
/// This is where high-level `PetActivity` (what Claude is doing) is *choreographed*
/// into concrete `PetAction`s. Keeping it separate from the renderers means a new
/// pet — built-in, Codex, or from the Petdex gallery — needs no behavior code of
/// its own: it just supplies frames for each action.
struct PetMotion {
    var action: PetAction
    var dx: CGFloat   // horizontal offset in points (gait patrol)
    var dy: CGFloat   // vertical offset, negative = up (hops)
    var facingLeft: Bool
}

enum Behavior {
    /// The largest upward (negative-dy) travel any state produces — the jump hop.
    /// Renderers reserve this much headroom so the pet never clips at the top.
    static let maxUpwardTravel: CGFloat = 22

    /// `span` is the half-width the pet may patrol within its overlay.
    static func motion(for activity: PetActivity, t: Double, span: CGFloat) -> PetMotion {
        switch activity {
        case .idle:
            // Mostly still; greet with a wave every ~10s.
            let phase = t.truncatingRemainder(dividingBy: 10)
            if phase < 1.1 {
                return PetMotion(action: .wave, dx: 0, dy: 0, facingLeft: false)
            }
            return PetMotion(action: .idle, dx: 0, dy: 0, facingLeft: false)

        case .running:
            // A 12s loop: greet → patrol gait → a jump → patrol gait.
            let phase = t.truncatingRemainder(dividingBy: 12)
            let patrol = CGFloat(sin(t * 1.7)) * span
            let movingLeft = cos(t * 1.7) < 0
            if phase < 1.0 {
                return PetMotion(action: .wave, dx: patrol, dy: 0, facingLeft: movingLeft)
            } else if phase >= 6.0 && phase < 6.9 {
                let hop = -abs(sin((phase - 6.0) * .pi / 0.9)) * Behavior.maxUpwardTravel
                return PetMotion(action: .jump, dx: patrol, dy: hop, facingLeft: movingLeft)
            } else {
                let action: PetAction = movingLeft ? .walkLeft : .walkRight
                return PetMotion(action: action, dx: patrol, dy: 0, facingLeft: movingLeft)
            }

        case .waiting:
            // Stops and stares; an occasional impatient twitch.
            let twitch = (t.truncatingRemainder(dividingBy: 3) < 0.2)
                ? CGFloat(sin(t * 40)) * 2 : 0
            return PetMotion(action: .wait, dx: twitch, dy: 0, facingLeft: false)

        case .ready:
            // Sits, looks happy; bobs and waves now and then.
            let phase = t.truncatingRemainder(dividingBy: 8)
            if phase < 1.0 {
                return PetMotion(action: .wave, dx: 0, dy: 0, facingLeft: false)
            }
            let bob = CGFloat(sin(t * 3)) * 2
            return PetMotion(action: .review, dx: 0, dy: bob, facingLeft: false)

        case .failed:
            // Shakes in distress, then settles.
            let phase = t.truncatingRemainder(dividingBy: 4)
            let shake = phase < 1.6 ? CGFloat(sin(t * 34)) * 3 : 0
            return PetMotion(action: .fail, dx: shake, dy: 0, facingLeft: false)
        }
    }

    /// Frames-per-second for spritesheet playback (Codex pets read as ~8fps).
    static let fps: Double = 8
}
