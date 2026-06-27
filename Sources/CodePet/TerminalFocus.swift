import AppKit

/// Brings the terminal a session is running in to the front. The terminal is
/// auto-detected from `TERM_PROGRAM` (captured by the hook), so this "just
/// works" for whatever the user runs Claude Code in. For iTerm2 we go further
/// and select the exact tab via `ITERM_SESSION_ID`.
enum TerminalFocus {
    /// Returns false if we couldn't identify/activate a terminal (caller can
    /// then fall back to revealing the working directory).
    @discardableResult
    static func focus(_ session: Session) -> Bool {
        switch session.termProgram {
        case "iTerm.app":
            return focusITerm(session)
        case "Apple_Terminal":
            return focusAppleTerminal(session)
        case "vscode":
            return activate(bundleIds: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
                                        "com.visualstudio.code.oss"])
        case "WarpTerminal":
            return activate(bundleIds: ["dev.warp.Warp-Stable", "dev.warp.Warp"])
        case "Hyper":
            return activate(bundleIds: ["co.zeit.hyper"])
        case "WezTerm":
            return activate(bundleIds: ["com.github.wez.wezterm"])
        case "ghostty", "Ghostty":
            return activate(bundleIds: ["com.mitchellh.ghostty"])
        case "Tabby":
            return activate(bundleIds: ["org.tabby"])
        case "kitty":
            return activate(bundleIds: ["net.kovidgoyal.kitty"])
        case "Alacritty":
            return activate(bundleIds: ["org.alacritty"])
        default:
            return false
        }
    }

    // MARK: - Generic activation

    private static func activate(bundleIds: [String]) -> Bool {
        for bid in bundleIds {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            if let app = apps.first {
                app.activate(options: [.activateAllWindows])
                return true
            }
        }
        return false
    }

    // MARK: - Apple Terminal

    private static func focusAppleTerminal(_ session: Session) -> Bool {
        // Terminal.app can't be addressed by TERM_SESSION_ID via AppleScript,
        // so bring the app forward (and its frontmost window with it).
        let script = """
        tell application "Terminal"
            activate
            if (count of windows) > 0 then set index of front window to 1
        end tell
        """
        return runAppleScript(script) || activate(bundleIds: ["com.apple.Terminal"])
    }

    // MARK: - iTerm2 (precise tab selection)

    private static func focusITerm(_ session: Session) -> Bool {
        guard let raw = session.termSession else {
            return activate(bundleIds: ["com.googlecode.iterm2"])
        }
        // ITERM_SESSION_ID looks like "w0t1p0:UUID" — the UUID is the session id.
        let uuid = raw.contains(":") ? String(raw.split(separator: ":").last!) : raw
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if (id of s) is "\(uuid)" then
                            select w
                            select t
                            tell s to select
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        return runAppleScript(script) || activate(bundleIds: ["com.googlecode.iterm2"])
    }

    // MARK: - AppleScript

    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        return err == nil
    }
}
