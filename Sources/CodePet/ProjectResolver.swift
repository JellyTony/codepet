import Foundation

/// Resolves a session's working directory into a meaningful **project name**.
///
/// `basename(cwd)` is often wrong: a session in `~/code/stock/backend` reads as
/// "backend" (and a sibling in `stock/macos` as "macos") when both belong to the
/// *stock* project, and a session started in `$HOME` reads as the username. So we
/// prefer the **git repository root** folder name when the directory is inside a
/// repo, special-case the home directory, and fall back to the basename.
///
/// Results are cached per cwd (git is only consulted once per directory), with a
/// lock so the render path and the session-loading path can share it safely.
enum ProjectResolver {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func name(forCwd cwd: String?) -> String {
        guard let cwd = cwd, !cwd.isEmpty else { return "session" }
        lock.lock()
        let cached = cache[cwd]
        lock.unlock()
        if let cached = cached { return cached }

        let resolved = compute(cwd)   // may spawn git — done outside the lock
        lock.lock()
        cache[cwd] = resolved
        lock.unlock()
        return resolved
    }

    private static func compute(_ cwd: String) -> String {
        if cwd == Paths.home.path { return "home" }
        if let root = gitRoot(cwd) {
            let name = URL(fileURLWithPath: root).lastPathComponent
            if !name.isEmpty { return name }
        }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "session" : name
    }

    /// `git -C <cwd> rev-parse --show-toplevel`, or nil if not a repo / no git.
    private static func gitRoot(_ cwd: String) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", cwd, "rev-parse", "--show-toplevel"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let root = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : root
    }
}
