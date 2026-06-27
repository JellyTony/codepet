import AppKit

/// Sends a quick reply straight into the Claude Code session a card represents —
/// no need to switch to the terminal. For iTerm2 we target the exact pane by its
/// `ITERM_SESSION_ID` and use `write text`, which delivers the line to the
/// session's input as if typed (and submits it). Other terminals fall back to
/// focusing the window and pasting + Return.
enum TerminalInput {
    /// Whether a reply can be delivered to this session (needs a terminal).
    static func canSend(to session: Session) -> Bool { session.termProgram != nil }

    /// Best-effort send of `text` (a single line) to the session's prompt.
    @discardableResult
    static func send(_ text: String, to session: Session) -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return false }

        switch session.termProgram {
        case "iTerm.app":
            guard let raw = session.termSession, !raw.isEmpty else { return focusAndPaste(line, session) }
            // ITERM_SESSION_ID is "wNtNpN:UUID" — the UUID is the session id.
            // iTerm2 has no `session id <uuid>` specifier, so find the pane by
            // matching `id of s` (same as TerminalFocus) and write to it.
            let uuid = raw.contains(":") ? String(raw.split(separator: ":").last!) : raw
            let script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (id of s) is "\(esc(uuid))" then
                                tell s to write text "\(esc(line))"
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
            runAsync(script)
            return true
        default:
            return focusAndPaste(line, session)
        }
    }

    /// Generic fallback: bring the terminal forward, paste the line, press Return.
    private static func focusAndPaste(_ line: String, _ session: Session) -> Bool {
        guard TerminalFocus.focus(session) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(line, forType: .string)
        let script = """
        tell application "System Events"
            keystroke "v" using command down
            delay 0.05
            key code 36
        end tell
        """
        runAsync(script)
        return true
    }

    /// Escape a string for embedding inside an AppleScript "…" literal.
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAsync(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let script = NSAppleScript(source: source) else { return }
            var err: NSDictionary?
            script.executeAndReturnError(&err)
            guard let err = err else { return }
            let code = (err[NSAppleScript.errorNumber] as? Int) ?? 0
            NSLog("CodePet: reply send failed (\(code)) — \(err[NSAppleScript.errorMessage] ?? "")")
            // -1743 = not authorized to send Apple events (Automation denied).
            if code == -1743 {
                DispatchQueue.main.async { showPermissionHelp() }
            }
        }
    }

    /// Guide the user to grant Automation permission when it's been denied.
    private static func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = L.t(.replyPermTitle)
        alert.informativeText = L.t(.replyPermBody)
        alert.addButton(withTitle: L.t(.openSettings))
        alert.addButton(withTitle: L.t(.cancel))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
