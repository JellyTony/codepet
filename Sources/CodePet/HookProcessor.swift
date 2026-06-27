import Foundation

/// Ports the `codepet-hook.js` logic into the app. Given a Claude Code hook
/// event payload (POSTed by an HTTP hook), it infers the pet state, accumulates
/// a per-session record, and writes the same JSON files the app watches —
/// `~/.codepet/state.json` + `~/.codepet/sessions/<id>.json`.
///
/// The heavy work (transcript parsing, file I/O) now runs here in the app,
/// OFF Claude Code's critical path. Terminal identity (term_program /
/// term_session) is captured once by the SessionStart command hook and merged
/// in via the previous record, so "click a card → focus the terminal" still
/// works.
enum HookProcessor {
    static let recentToolsMax = 8
    static let promptMax = 500

    /// Process one hook event payload. Returns true if a record was written.
    @discardableResult
    static func process(_ payload: [String: Any]) -> Bool {
        let event = payload["hook_event_name"] as? String ?? ""
        guard let state = inferState(event, payload) else { return false }

        let now = Date().timeIntervalSince1970
        let detail = detailFor(event, payload)
        let sessionId = payload["session_id"] as? String

        Paths.ensureDir()

        // --- Back-compat: single latest-event state file. ---
        var stateObj: [String: Any] = ["state": state, "updated_at": now]
        if let detail = detail { stateObj["detail"] = detail }
        if let sid = sessionId { stateObj["session_id"] = sid }
        atomicWrite(Paths.stateFile, stateObj)

        guard let sessionId = sessionId else { return true }

        // --- Per-session record (the multi-session model). ---
        Paths.ensureSessionsDir()
        let file = Paths.sessionsDir.appendingPathComponent(safeName(sessionId) + ".json")
        let prev = readSession(file) ?? [:]

        var rec: [String: Any] = [:]
        rec["session_id"] = sessionId
        rec["state"] = state
        set(&rec, "detail", merged(detail, prev["detail"]))
        set(&rec, "cwd", merged(payload["cwd"], prev["cwd"]))
        set(&rec, "prompt", prev["prompt"])
        set(&rec, "title", prev["title"])
        set(&rec, "summary", prev["summary"])
        set(&rec, "last_tool", prev["last_tool"])
        rec["recent_tools"] = (prev["recent_tools"] as? [String]) ?? []
        rec["tool_count"] = (prev["tool_count"] as? Int) ?? 0
        rec["started_at"] = prev["started_at"] ?? now
        rec["updated_at"] = now
        set(&rec, "transcript_path", merged(payload["transcript_path"], prev["transcript_path"]))
        // Terminal identity — written by the SessionStart command hook; preserved
        // here so the app can bring the right terminal forward on click.
        set(&rec, "term_program", prev["term_program"])
        set(&rec, "term_session", prev["term_session"])

        // The title is the current task = the message just submitted. Take it
        // straight from the payload: it's authoritative and instant, whereas the
        // transcript often hasn't flushed the new message yet when this fires —
        // which is exactly why the card looked stuck on the previous task.
        if event == "UserPromptSubmit", let p = payload["prompt"] as? String {
            let raw = p.trimmingCharacters(in: .whitespacesAndNewlines)
            rec["prompt"] = String(raw.prefix(promptMax))
            let t = extractCommand(raw) ?? raw     // slash command → readable title
            if !t.isEmpty { rec["title"] = clean(t, 100) }
        }

        // Summary (latest assistant narration) refreshes from the transcript on
        // every event — that's the live "what's it doing now".
        if let tpath = (payload["transcript_path"] as? String) ?? (prev["transcript_path"] as? String) {
            if let s = transcriptSummary(tpath) { rec["summary"] = s }
        }

        // Track tool usage as progress.
        if event == "PreToolUse", let tool = payload["tool_name"] as? String {
            rec["tool_count"] = ((rec["tool_count"] as? Int) ?? 0) + 1
            rec["last_tool"] = tool
            var rt = (rec["recent_tools"] as? [String]) ?? []
            rt.append(tool)
            if rt.count > recentToolsMax { rt = Array(rt.suffix(recentToolsMax)) }
            rec["recent_tools"] = rt
        }

        atomicWrite(file, rec)
        return true
    }

    // MARK: - State inference

    static func inferState(_ event: String, _ payload: [String: Any]) -> String? {
        switch event {
        case "UserPromptSubmit", "PreToolUse", "SubagentStop":
            return "running"
        case "PostToolUse":
            return looksLikeError(payload) ? "failed" : "running"
        case "Notification":
            return looksLikeError(payload) ? "failed" : "waiting"
        case "Stop":
            return "ready"
        case "SessionStart":
            return "idle"
        default:
            return nil
        }
    }

    static func looksLikeError(_ payload: [String: Any]) -> Bool {
        let response = payload["tool_response"] ?? payload["tool_result"]
        if let r = response as? [String: Any] {
            if let isErr = r["is_error"] as? Bool, isErr { return true }
            if let err = r["error"], !(err is NSNull) { return true }
            if let stderr = r["stderr"] as? String,
               matches(stderr, "error|fail|exception") { return true }
        }
        let nt = ((payload["notification_type"] as? String) ?? "") + " "
               + ((payload["message"] as? String) ?? "")
        return matches(nt, "error|fail|denied|exception") && !matches(nt, "permission")
    }

    static func detailFor(_ event: String, _ payload: [String: Any]) -> String? {
        switch event {
        case "PreToolUse", "PostToolUse":
            return actionLabel(payload["tool_name"] as? String, payload["tool_input"] as? [String: Any])
        case "Notification":
            return (payload["message"] as? String)
                ?? (payload["notification_type"] as? String)
                ?? "waiting for input"
        case "UserPromptSubmit":
            return "thinking…"
        case "Stop":
            return "done"
        case "SessionStart":
            return "session started"
        default:
            return nil
        }
    }

    /// A short, human-readable description of the current tool action, built from
    /// the live hook payload — this is the *real-time* "what's it doing now"
    /// (the transcript narration isn't written live, so it can't be).
    static func actionLabel(_ tool: String?, _ input: [String: Any]?) -> String? {
        guard let tool = tool, !tool.isEmpty else { return nil }
        func file(_ k: String) -> String? {
            (input?[k] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).lastPathComponent }
        }
        func str(_ k: String) -> String? {
            (input?[k] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        switch tool {
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return file("file_path").map { "\(tool) \($0)" } ?? tool
        case "Read":
            return file("file_path").map { "Read \($0)" } ?? "Read"
        case "Bash":
            return str("command").map { "Bash: " + String($0.prefix(48)) } ?? "Bash"
        case "Grep", "Glob":
            return str("pattern").map { "\(tool) \($0)" } ?? tool
        case "Task":
            return str("description").map { "Task: \($0)" } ?? "Task"
        case "WebFetch":
            return str("url").map { "Fetch \($0)" } ?? "WebFetch"
        case "WebSearch":
            return str("query").map { "Search \($0)" } ?? "WebSearch"
        default:
            // MCP tools arrive as "mcp__<server>__<tool>" — show "server: tool".
            if tool.hasPrefix("mcp__") {
                let parts = tool.dropFirst("mcp__".count).components(separatedBy: "__")
                if parts.count >= 2 { return "\(parts[0]): \(parts.dropFirst().joined(separator: " "))" }
            }
            return tool
        }
    }

    // MARK: - Transcript parsing

    /// Latest assistant narration — the live summary. Cheap: the most recent
    /// assistant message is almost always within the first tail window.
    static func transcriptSummary(_ path: String) -> String? {
        scanTail(path) { lastAssistantText($0) }.map { clean($0, 200) }
    }

    /// Read the transcript tail in widening windows (so a big tool result can't
    /// push the wanted line out of view) and return the first non-nil `extract`.
    private static func scanTail(_ path: String, _ extract: ([String]) -> String?) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let size = try? fh.seekToEnd(), size > 0 else { return nil }
        for window in [256 * 1024, 1024 * 1024, 4 * 1024 * 1024] as [UInt64] {
            let len = min(size, window)
            try? fh.seek(toOffset: size - len)
            let data = (try? fh.read(upToCount: Int(len))) ?? Data()
            if let v = extract(String(decoding: data, as: UTF8.self).components(separatedBy: "\n")) { return v }
            if len >= size { break }
        }
        return nil
    }

    private static func lastAssistantText(_ lines: [String]) -> String? {
        for line in lines.reversed() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let o = parseObject(line) else { continue }
            if entryRole(o) != "assistant" { continue }
            let t = blockText(entryContent(o)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    private static func entryRole(_ o: [String: Any]) -> String? {
        if let m = o["message"] as? [String: Any], let r = m["role"] as? String { return r }
        if let r = o["role"] as? String { return r }
        return o["type"] as? String
    }

    private static func entryContent(_ o: [String: Any]) -> Any? {
        if let m = o["message"] as? [String: Any] { return m["content"] }
        return o["content"]
    }

    private static func blockText(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            return arr
                .filter { ($0["type"] as? String) == "text" && $0["text"] is String }
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
        }
        return ""
    }

    private static func isToolResult(_ content: Any?) -> Bool {
        guard let arr = content as? [[String: Any]] else { return false }
        return arr.contains { ($0["type"] as? String) == "tool_result" }
    }

    // A slash-command turn embeds the command + args in tags — turn it into a
    // readable title like "codex-goal:pursue-agent <goal>".
    private static func extractCommand(_ t: String) -> String? {
        guard let name = firstCapture("<command-name>\\s*/?([^<]+?)\\s*</command-name>", in: t) else {
            return nil
        }
        let args = (firstCapture("<command-args>([\\s\\S]*?)</command-args>", in: t) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (n + (args.isEmpty ? "" : " " + args)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Small helpers

    static func clean(_ s: String, _ n: Int) -> String {
        let collapsed = s
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(n))
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func parseObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private static func merged(_ new: Any?, _ old: Any?) -> Any? {
        if let new = new, !(new is NSNull) { return new }
        if let old = old, !(old is NSNull) { return old }
        return nil
    }

    private static func set(_ rec: inout [String: Any], _ key: String, _ value: Any?) {
        if let value = value { rec[key] = value }
    }

    static func safeName(_ id: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return String(id.map { allowed.contains($0) ? $0 : "_" })
    }

    private static func readSession(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private static func atomicWrite(_ url: URL, _ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
