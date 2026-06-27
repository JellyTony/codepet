import CoreGraphics

/// A named animation **action** a pet can perform.
///
/// This is the abstraction layer that lets CodePet support the Petdex pet
/// gallery (https://petdex.crafter.run) and real Codex pets out of the box:
/// instead of hard-coding spritesheet geometry throughout the app, every
/// renderer (the spritesheet player and the built-in vector engine) speaks in
/// these actions, and the `SpriteContract` below maps each action onto a row of
/// the standard sheet. Any pet that follows the contract animates correctly
/// with **zero per-pet configuration** — drop it in and it plays.
///
/// The case order *is* the contract: a raw value equals the sheet row index, so
/// the order here must match the Petdex / Codex spritesheet layout exactly.
enum PetAction: Int, CaseIterable {
    case idle = 0          // row 0 — resting / breathing
    case walkRight = 1     // row 1 — walking, facing right
    case walkLeft = 2      // row 2 — walking, facing left
    case wave = 3          // row 3 — greeting wave
    case jump = 4          // row 4 — hop / jump
    case fail = 5          // row 5 — distress / error
    case wait = 6          // row 6 — waiting for input
    case walk = 7          // row 7 — neutral walk-in-place
    case review = 8        // row 8 — sit & present (ready for review)
}

/// The Petdex / Codex spritesheet contract.
///
/// A pet sheet is a grid of `columns × PetAction.allCases.count` cells where
/// each row holds the frames of one `PetAction`, left to right. The recommended
/// sheet is 1536×1872 (8 columns × 9 rows, 192×208 per cell), but the cell size
/// is always derived from the actual image, so any sheet that divides evenly
/// into the grid works — `.png` or `.webp`.
///
/// Both Petdex (`petdex install <slug>` → `~/.petdex/pets`, `~/.codex/pets`) and
/// Codex publish sheets in this exact layout, which is why CodePet can load them
/// verbatim.
enum SpriteContract {
    /// Number of frame columns per row.
    static let columns = 8

    /// Number of rows — one per action. Derived from `PetAction` so the contract
    /// can never drift out of sync with the action set.
    static var rows: Int { PetAction.allCases.count }

    /// The sheet size Petdex recommends for new pets.
    static let recommendedSize = CGSize(width: 1536, height: 1872)

    /// Which sheet row plays a given action.
    static func row(for action: PetAction) -> Int { action.rawValue }
}
