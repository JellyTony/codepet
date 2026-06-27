import Foundation
import CoreGraphics

/// Filesystem locations shared between the app and the Claude Code hooks.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let dir = home.appendingPathComponent(".codepet", isDirectory: true)
    static let stateFile = dir.appendingPathComponent("state.json")
    static let configFile = dir.appendingPathComponent("config.json")
    static let hookFile = dir.appendingPathComponent("hook.json")  // {port, token} for the HTTP hook server
    static let sessionsDir = dir.appendingPathComponent("sessions", isDirectory: true)

    static func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func ensureSessionsDir() {
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    }
}

/// User preferences persisted to ~/.codepet/config.json.
struct Config: Codable {
    var pet: String          // species key, e.g. "blob", "cat", "robot", "ghost"
    var corner: String       // "bottomRight", "bottomLeft", "topRight", "topLeft"
    var scale: Double        // size multiplier
    var customX: Double?      // dragged position (window origin), overrides corner
    var customY: Double?
    var showCards: Bool?      // is the session-card stack expanded? (nil = yes)
    var language: String?     // AppLanguage rawValue (nil = system)

    static let `default` = Config(pet: "built-in:blob", corner: "bottomRight",
                                  scale: 1.0, customX: nil, customY: nil,
                                  showCards: true, language: nil)

    /// Whether the session cards should be shown (defaults to true).
    var wantsCards: Bool { showCards ?? true }

    /// Resolved UI language (defaults to following the system).
    var appLanguage: AppLanguage {
        language.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// A persisted dragged origin, if the user moved the pet by hand.
    var customOrigin: CGPoint? {
        guard let x = customX, let y = customY else { return nil }
        return CGPoint(x: x, y: y)
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: Paths.configFile),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            return .default
        }
        return cfg
    }

    func save() {
        Paths.ensureDir()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: Paths.configFile)
        }
    }
}
