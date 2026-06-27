import Foundation

/// The high-level developer-facing states a pet reflects — mirrors Codex pets:
/// running, waiting for input, ready for review, plus failed and idle.
enum PetActivity: String, Codable {
    case idle
    case running
    case waiting
    case ready      // "ready for review"
    case failed

    /// Short human label shown under the pet (localized).
    var label: String {
        switch self {
        case .idle:    return L.t(.idle)
        case .running: return L.t(.working)
        case .waiting: return L.t(.needsYou)
        case .ready:   return L.t(.ready)
        case .failed:  return L.t(.failed)
        }
    }
}

/// Decoded contents of ~/.codepet/state.json, written by Claude Code hooks.
struct PetState: Codable, Equatable {
    var state: PetActivity
    var detail: String?
    var sessionId: String?
    var updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case state
        case detail
        case sessionId = "session_id"
        case updatedAt = "updated_at"
    }

    static let initial = PetState(state: .idle, detail: nil, sessionId: nil, updatedAt: nil)
}
