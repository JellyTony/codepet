import Foundation
import Combine
import CoreGraphics

/// Observes ~/.codepet — both the legacy single state.json and the per-session
/// records under sessions/ — and republishes everything the UI needs:
///  • `sessions`     the full multi-session list (sorted by attention)
///  • `state`        the legacy/global last-event state (fallback)
///  • aggregate      the highest-priority live session → drives the corner pet
///  • interaction    hover / gaze / panel-open, for the live mouse feel
final class StateStore: ObservableObject {
    @Published private(set) var state: PetState = .initial
    @Published private(set) var sessions: [Session] = []
    @Published var config: Config = Config.load()
    @Published private(set) var catalog: [PetEntry] = PetCatalog.discover()

    // Interaction state (mouse), published so the renderer reacts live.
    @Published var hovering: Bool = false
    @Published var gaze: CGSize = .zero          // cursor offset, normalized -1…1
    @Published var panelOpen: Bool = false
    @Published var petVisible: Bool = true        // false when the pet is fully occluded

    private var stateSource: DispatchSource?
    private var stateFD: Int32 = -1
    private var sessionsSource: DispatchSource?
    private var sessionsFD: Int32 = -1
    private var pollTimer: Timer?
    private var hookServer: HookServer?
    private var lastSessionsSignature: String?
    /// Serial queue for hook processing, kept off the server's network queue.
    private let processQueue = DispatchQueue(label: "codepet.hookprocess", qos: .utility)

    init() {
        Paths.ensureDir()
        Paths.ensureSessionsDir()
        L.language = config.appLanguage
        reload()
        reloadSessions()
        startWatchingState()
        startWatchingSessions()
        startHookServer()
        // Polling fallback for missed FS events. Re-decoding every session file
        // each second is wasteful when nothing changed (and produces no UI change
        // anyway, since the published list would be identical), so the poll only
        // re-reads when the directory's file set / mtimes actually moved.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.reload()
            self?.reloadSessionsIfChanged()
            self?.refreshLiveSummaries()
        }
    }

    deinit {
        stateSource?.cancel()
        sessionsSource?.cancel()
        pollTimer?.invalidate()
        hookServer?.stop()
    }

    // MARK: - HTTP hook server

    /// Receive Claude Code hook events over a loopback HTTP server instead of
    /// spawning a node process per event. High-frequency events (every tool
    /// call) arrive here; SessionStart still uses a command hook to capture
    /// terminal identity. Falls back gracefully to file watching if the port
    /// can't be bound (events written by the command hook still flow in).
    private func startHookServer() {
        let cfg = HookConfig.load()
        let server = HookServer(port: cfg.port, token: cfg.token) { [weak self] payload in
            // Hand off to a dedicated queue so transcript parsing / file writes
            // never block the server's network queue — otherwise a slow parse on
            // a big transcript would back up incoming events and stall updates.
            self?.processQueue.async {
                HookProcessor.process(payload)
                DispatchQueue.main.async {
                    self?.reload()
                    self?.reloadSessions()
                }
            }
        }
        server.start()
        hookServer = server
    }

    // MARK: - Derived / aggregate

    private func now() -> Double { Date().timeIntervalSince1970 }

    /// Live sessions only (recently active) — these drive the corner pet.
    /// De-duped by terminal so a tab that started a new session doesn't keep
    /// showing the previous (now superseded) one as a ghost/duplicate card.
    var liveSessions: [Session] {
        let t = now()
        let live = sessions.filter { $0.isLive(now: t) }
        return Session.dedupedByTerminal(live)
    }

    /// Sessions shown as cards: live AND actually doing something or wanting
    /// attention (running / needs-you / ready / failed). Idle and stale sessions
    /// are hidden so the stack stays focused on what's happening now.
    /// Already sorted by attention then recency (see `reloadSessions`).
    var displaySessions: [Session] {
        liveSessions.filter { $0.state != .idle }
    }

    /// The state the corner pet shows: the most attention-worthy live session,
    /// falling back to the legacy global state when no sessions are tracked.
    var displayActivity: PetActivity {
        if let top = liveSessions.max(by: { $0.state.priority < $1.state.priority }) {
            return top.state
        }
        return sessions.isEmpty ? state.state : .idle
    }

    /// The short detail line under the corner pet.
    var displayDetail: String? {
        let live = liveSessions
        if live.isEmpty { return sessions.isEmpty ? state.detail : nil }
        // Show the winning session's project + action.
        if let top = live.max(by: { $0.state.priority < $1.state.priority }) {
            let d = top.detail.map { " · \($0)" } ?? ""
            return "\(top.project)\(d)"
        }
        return nil
    }

    /// How many live sessions want my attention (needs-you / failed / ready).
    var attentionCount: Int {
        liveSessions.filter { $0.state.needsAttention }.count
    }

    /// A one-line aggregate summary for the hover bubble, e.g.
    /// "2 working · 1 needs you".
    var summaryLine: String {
        let live = liveSessions
        if live.isEmpty { return L.t(.noActiveSessions) }
        var buckets: [(PetActivity, Int)] = []
        for act in [PetActivity.waiting, .failed, .ready, .running, .idle] {
            let n = live.filter { $0.state == act }.count
            if n > 0 { buckets.append((act, n)) }
        }
        return buckets.map { "\($0.1) \($0.0.label)" }.joined(separator: " · ")
    }

    // MARK: - Loading

    private func reload() {
        guard let data = try? Data(contentsOf: Paths.stateFile),
              let decoded = try? JSONDecoder().decode(PetState.self, from: data) else {
            return
        }
        if decoded != state {
            DispatchQueue.main.async { self.state = decoded }
        }
    }

    /// Poll-side reload that skips the work when the sessions directory is
    /// unchanged since the last read (event-driven reloads keep the signature
    /// current, so this only fires on FS events the watcher missed).
    private func reloadSessionsIfChanged() {
        if sessionsSignature() != lastSessionsSignature { reloadSessions() }
    }

    /// Cheap fingerprint of the sessions directory — file names + mtimes — used
    /// to skip redundant per-second re-decodes.
    private func sessionsSignature() -> String {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: Paths.sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return "" }
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { f in
                let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate)?.timeIntervalSince1970 ?? 0
                return "\(f.lastPathComponent):\(Int(m))"
            }
            .joined(separator: "|")
    }

    /// Re-read each live session's summary straight from its transcript, so the
    /// "what's it doing now" line stays current even during long stretches with
    /// no hook events — e.g. while the model is writing a reply and not calling
    /// tools (the only signal then is the transcript growing). Reads run off the
    /// main thread; only changed summaries are published.
    private func refreshLiveSummaries() {
        let t = now()
        let targets = sessions.filter {
            $0.isLive(now: t) && $0.state != .idle && ($0.transcriptPath?.isEmpty == false)
        }
        guard !targets.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var fresh: [String: String] = [:]
            for s in targets {
                guard let tp = s.transcriptPath,
                      let sum = HookProcessor.transcriptSummary(tp), sum != s.summary else { continue }
                fresh[s.sessionId] = sum
            }
            guard !fresh.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                var updated = self.sessions
                var didChange = false
                for i in updated.indices {
                    if let sum = fresh[updated[i].sessionId], updated[i].summary != sum {
                        updated[i].summary = sum
                        didChange = true
                    }
                }
                if didChange { self.sessions = updated }
            }
        }
    }

    private func reloadSessions() {
        lastSessionsSignature = sessionsSignature()
        let t = now()
        var loaded: [Session] = []
        if let files = try? FileManager.default.contentsOfDirectory(
            at: Paths.sessionsDir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "json" {
                guard let data = try? Data(contentsOf: f),
                      let s = try? JSONDecoder().decode(Session.self, from: data) else { continue }
                if s.age(now: t) > Session.pruneWindow {
                    try? FileManager.default.removeItem(at: f)  // drop ancient sessions
                    continue
                }
                loaded.append(s)
            }
        }
        // Sort: attention first, then most-recently active.
        loaded.sort { a, b in
            if a.state.priority != b.state.priority { return a.state.priority > b.state.priority }
            return (a.updatedAt ?? 0) > (b.updatedAt ?? 0)
        }
        // Resolve project names (git root lookup) off the render path so the
        // first card render never blocks on a git subprocess.
        let cwds = Set(loaded.compactMap { $0.cwd })
        if !cwds.isEmpty {
            DispatchQueue.global(qos: .utility).async { cwds.forEach { _ = ProjectResolver.name(forCwd: $0) } }
        }
        if loaded != sessions {
            DispatchQueue.main.async { self.sessions = loaded }
        }
    }

    // MARK: - File watching

    private func startWatchingState() {
        let path = Paths.stateFile.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: Data())
        }
        stateFD = open(path, O_EVTONLY)
        guard stateFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: stateFD,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        ) as? DispatchSource
        stateSource = src
        src?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.reload()
            self.stateSource?.cancel()
            self.stateSource = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.startWatchingState() }
        }
        src?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.stateFD >= 0 { close(self.stateFD); self.stateFD = -1 }
        }
        src?.resume()
    }

    private func startWatchingSessions() {
        Paths.ensureSessionsDir()
        let path = Paths.sessionsDir.path
        sessionsFD = open(path, O_EVTONLY)
        guard sessionsFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: sessionsFD,
            eventMask: [.write, .delete, .rename, .extend, .link],
            queue: .main
        ) as? DispatchSource
        sessionsSource = src
        src?.setEventHandler { [weak self] in
            self?.reloadSessions()
        }
        src?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.sessionsFD >= 0 { close(self.sessionsFD); self.sessionsFD = -1 }
        }
        src?.resume()
    }

    // MARK: - Mutations

    func refreshCatalog() {
        // Only republish when the pet directories actually changed — keeps the
        // menu's per-open rescan from churning the UI on every click.
        if let fresh = PetCatalog.discoverIfChanged() {
            catalog = fresh
        }
    }

    func setPet(_ key: String) {
        config.pet = key
        config.save()
        objectWillChange.send()
    }

    func setCorner(_ corner: String) {
        config.corner = corner
        config.customX = nil   // corner choice overrides a dragged position
        config.customY = nil
        config.save()
        objectWillChange.send()
    }

    func setCustomPosition(_ origin: CGPoint) {
        config.customX = Double(origin.x)
        config.customY = Double(origin.y)
        config.save()
    }

    func clearCustomPosition() {
        config.customX = nil
        config.customY = nil
        config.save()
        objectWillChange.send()
    }

    /// Live scale update during a resize drag (not persisted until committed).
    func setScaleLive(_ s: Double) {
        config.scale = s
        objectWillChange.send()
    }

    func commitScale() {
        config.scale = min(1.8, max(0.6, config.scale))
        config.save()
        objectWillChange.send()
    }

    func setLanguage(_ lang: AppLanguage) {
        config.language = lang == .system ? nil : lang.rawValue
        config.save()
        L.language = lang
        objectWillChange.send()
    }
}
