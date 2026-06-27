import Foundation

/// One Claude Code session, decoded from ~/.codepet/sessions/<id>.json.
/// The hook accumulates progress across events so every field reflects the
/// live state of that session — not just the most recent global write.
struct Session: Codable, Equatable, Identifiable {
    var sessionId: String
    var state: PetActivity
    var detail: String?
    var cwd: String?
    var prompt: String?            // most-recent user prompt
    var title: String?             // the task — first user message (from transcript)
    var summary: String?           // what Claude is doing now — latest assistant text
    var lastTool: String?
    var recentTools: [String]?
    var toolCount: Int?
    var startedAt: Double?
    var updatedAt: Double?
    var transcriptPath: String?
    var termProgram: String?       // "iTerm.app", "Apple_Terminal", "vscode", …
    var termSession: String?       // ITERM_SESSION_ID / TERM_SESSION_ID

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case state, detail, cwd, prompt, title, summary
        case lastTool = "last_tool"
        case recentTools = "recent_tools"
        case toolCount = "tool_count"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case transcriptPath = "transcript_path"
        case termProgram = "term_program"
        case termSession = "term_session"
    }

    var id: String { sessionId }

    /// Project name — the git repo root folder when available, else a sensible
    /// fallback (see `ProjectResolver`). Cached, so this is cheap to call.
    var project: String { ProjectResolver.name(forCwd: cwd) }

    var shortId: String { String(sessionId.prefix(6)) }

    /// Identity of the terminal this session runs in, if known. A terminal tab
    /// runs only one Claude Code session at a time, so this is what lets us tell
    /// a *superseded* session (an old one in a tab that's since started a new
    /// session) from a genuinely separate one. nil when there's no terminal
    /// identity (e.g. GUI-spawned sessions) — those can't be de-duped this way.
    var terminalKey: String? {
        guard let ts = termSession, !ts.isEmpty else { return nil }
        return "\(termProgram ?? ""):\(ts)"
    }

    /// Best available task title: the first user message, else latest prompt,
    /// else the project name.
    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        if let p = prompt, !p.isEmpty { return p }
        return project
    }

    /// Seconds since last update.
    func age(now: Double) -> Double { now - (updatedAt ?? 0) }

    /// Considered "live" (drives the corner pet / attention badge) if it was
    /// touched recently. Older sessions still appear in the panel, dimmed.
    func isLive(now: Double) -> Bool { age(now: now) < Session.liveWindow }

    static let liveWindow: Double = 20 * 60      // 20 min
    static let pruneWindow: Double = 6 * 3600    // drop files older than 6h

    /// Compact one-line progress, e.g. "Edit · 42 actions · 3m" (localized).
    func progressLine(now: Double) -> String {
        var parts: [String] = []
        if let d = detail, !d.isEmpty { parts.append(d) }   // tool names stay as-is
        if let c = toolCount, c > 0 { parts.append(L.actions(c)) }
        let e = Session.elapsed(since: startedAt, now: now)
        if !e.isEmpty { parts.append(e) }
        return parts.joined(separator: " · ")
    }

    /// Localized compact duration since `since`.
    static func elapsed(since: Double?, now: Double) -> String {
        guard let since = since, since > 0 else { return "" }
        return L.elapsed(now - since)
    }

    /// Localized "x ago" string.
    static func ago(_ updatedAt: Double?, now: Double) -> String {
        guard let u = updatedAt, u > 0 else { return "" }
        return L.ago(now - u)
    }

    /// Collapse sessions that share a terminal down to the most-recently-updated
    /// one — the only live session that tab can actually be running. This drops
    /// the stale/ghost cards left behind when a terminal starts a new session
    /// (or `/clear`s) without the previous one ever leaving the `running` state.
    /// Sessions without a `terminalKey` pass through untouched. Input order is
    /// preserved (callers sort by attention/recency first).
    static func dedupedByTerminal(_ sessions: [Session]) -> [Session] {
        var winnerId: [String: String] = [:]   // terminalKey → winning sessionId
        var winnerTime: [String: Double] = [:]
        for s in sessions {
            guard let key = s.terminalKey else { continue }
            let t = s.updatedAt ?? 0
            if t >= (winnerTime[key] ?? -.greatestFiniteMagnitude) {
                winnerTime[key] = t
                winnerId[key] = s.sessionId
            }
        }
        return sessions.filter { s in
            guard let key = s.terminalKey else { return true }   // keep GUI/no-terminal sessions
            return winnerId[key] == s.sessionId
        }
    }
}

extension PetActivity {
    /// Attention priority — higher wins for the aggregated corner pet and sorts
    /// the session list. A session that needs input outranks everything.
    var priority: Int {
        switch self {
        case .waiting: return 5   // needs you NOW
        case .failed:  return 4   // something broke
        case .ready:   return 3   // ready for review (come look)
        case .running: return 2   // busy, fine
        case .idle:    return 1
        }
    }

    /// Does this state want the human's attention?
    var needsAttention: Bool {
        switch self {
        case .waiting, .failed, .ready: return true
        case .running, .idle: return false
        }
    }
}
