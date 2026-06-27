import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = StateStore()
    var window: PetWindow!
    var panel: SessionsPanel!
    var statusItem: NSStatusItem!
    private var cornerObserver: Any?
    private var occlusionObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var petdexFeatured: [PetdexPet] = []   // gallery pets, for the in-menu installer
    private var installingCount = 0                // >0 while a Petdex install is in flight
    private var resizeAnchorBR: CGPoint?
    private var resizeBaseScale: Double = 1.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Docs mode: render the README promo images and quit (no UI).
        if ProcessInfo.processInfo.environment["CODEPET_DOCSHOT"] != nil {
            DocShot.renderAll()
            exit(0)
        }
        // Agent app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        // The corner pet — wrapped in an interactive container that owns hover,
        // gaze tracking, click-to-open-panel, drag-to-reposition, drag-to-resize.
        let hosting = NSHostingView(rootView: PetView(store: store))
        let container = PetContainerView(hosting: hosting)
        container.onHover = { [weak self] in self?.store.hovering = $0 }
        container.onGaze = { [weak self] in self?.store.gaze = $0 }
        container.onClick = { [weak self] in self?.togglePanel() }
        container.onDragMove = { [weak self] _ in self?.followPanel() }
        container.onDragEnded = { [weak self] origin in
            self?.store.setCustomPosition(origin)
            self?.followPanel()
        }
        container.onResizeBegan = { [weak self] in
            guard let self = self else { return }
            self.resizeBaseScale = self.store.config.scale
            self.resizeAnchorBR = CGPoint(x: self.window.frame.maxX, y: self.window.frame.minY)
        }
        container.onResize = { [weak self] dx in
            guard let self = self, let br = self.resizeAnchorBR else { return }
            let s = min(1.8, max(0.6, self.resizeBaseScale + Double(dx) / 180.0))
            self.store.setScaleLive(s)
            self.applyScale(keepingBottomRight: br)
        }
        container.onResizeEnded = { [weak self] in
            self?.resizeAnchorBR = nil
            self?.store.commitScale()
        }

        window = PetWindow(content: container)
        window.orderFrontRegardless()
        applyScale(keepingBottomRight: nil)   // size the window to the saved scale

        // The session-card stack that floats above the pet.
        panel = SessionsPanel(store: store, onCollapse: { [weak self] in self?.hidePanel() })

        setupMenuBar()
        loadPetdexFeatured()   // populate the in-menu Petdex installer
        ensureHooksWired()     // self-install Claude Code hooks on first launch (.pkg flow)

        // Keep the badge + card stack in sync as sessions change.
        store.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateBadge()
                self?.followPanel()
            }
            .store(in: &cancellables)
        updateBadge()

        // Show the card stack by default (the primary view), per the Codex layout.
        if store.config.wantsCards {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showPanel()
            }
        }

        // Pause the pet's animation when its window is fully occluded (covered by
        // other windows / off a sleeping display) — saves the redraw cost entirely.
        store.petVisible = window.occlusionState.contains(.visible)
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.store.petVisible = self.window.occlusionState.contains(.visible)
        }

        // Re-place if the screen layout changes.
        cornerObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.window.restorePosition(self.store.config)
            self.followPanel()
        }
    }

    // MARK: - Sessions panel

    @objc private func togglePanel() {
        if panel?.isVisible == true { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let panel = panel else { return }
        panel.reposition(above: window.frame)
        panel.orderFront(nil)
        store.panelOpen = true
        if store.config.showCards != true { store.config.showCards = true; store.config.save() }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        store.panelOpen = false
        if store.config.showCards != false { store.config.showCards = false; store.config.save() }
    }

    /// Keep the card stack glued above the pet (drag-follow + content resize).
    private func followPanel() {
        guard let panel = panel, panel.isVisible else { return }
        panel.reposition(above: window.frame)
    }

    /// Resize the pet window to the current scale. During a resize drag we keep
    /// the bottom-right corner pinned so the pet stays put under the handle.
    private func applyScale(keepingBottomRight br: CGPoint?) {
        let scale = CGFloat(store.config.scale)
        let size = NSSize(width: PetView.baseW * scale, height: PetView.baseH * scale)
        if let br = br {
            let origin = CGPoint(x: br.x - size.width, y: br.y)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        } else {
            window.setContentSize(size)
            window.restorePosition(store.config)
        }
        followPanel()
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐾"
        let menu = NSMenu()
        menu.delegate = self   // menuNeedsUpdate → rediscover pets on open
        statusItem.menu = menu
        rebuildMenu()
    }

    /// Rediscover pets right before the menu opens, so a pet installed while
    /// CodePet is running (e.g. `npx petdex install <slug>`) appears with no
    /// manual refresh — "install and it's there".
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        store.refreshCatalog()
        if petdexFeatured.isEmpty { loadPetdexFeatured() }
        rebuildMenu()
    }

    /// Fetch the Petdex gallery's featured pets in the background, then refresh
    /// the menu so they appear under "Install from Petdex".
    private func loadPetdexFeatured() {
        PetdexGallery.fetchFeatured { [weak self] pets in
            guard let self = self, !pets.isEmpty else { return }
            self.petdexFeatured = pets
            self.rebuildMenu()
        }
    }

    private func updateBadge() {
        // While installing a Petdex pet, show a busy indicator instead of the
        // attention badge so the click gets immediate, visible feedback.
        if installingCount > 0 {
            statusItem.button?.title = "🐾⌛"
            statusItem.button?.toolTip = L.t(.petdexInstalling)
            return
        }
        statusItem.button?.toolTip = nil
        let n = store.attentionCount
        statusItem.button?.title = n > 0 ? "🐾\(n)" : "🐾"
    }

    /// The hook set this build expects to be wired. Must match HOOKS_VERSION in
    /// install-hooks.js — bump both together when the event list changes so an
    /// older install re-runs the installer and picks up the new hooks.
    private static let expectedHooksVersion = 2

    /// Version of the hooks currently wired, recorded by install-hooks.js in
    /// ~/.codepet/hook.json. 0 when absent (pre-versioning install).
    private func installedHooksVersion() -> Int {
        let cfg = Paths.home.appendingPathComponent(".codepet/hook.json")
        guard let data = try? Data(contentsOf: cfg),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return 0 }
        return (obj["version"] as? Int) ?? 0
    }

    /// When CodePet ships as a prebuilt app (installed by the .pkg), nothing has
    /// wired its Claude Code hooks yet. On first launch — or after an upgrade
    /// that adds new hook events — run the bundled installer (via a login shell
    /// so Node is on PATH) so it "just works".
    private func ensureHooksWired() {
        guard let resURL = Bundle.main.resourceURL else { return }
        let installer = resURL.appendingPathComponent("tools/install-hooks.js")
        guard FileManager.default.fileExists(atPath: installer.path) else { return }

        let settings = Paths.home.appendingPathComponent(".claude/settings.json")
        if let s = try? String(contentsOf: settings, encoding: .utf8),
           s.contains("/codepet/hook") || s.contains("codepet-hook.js"),
           installedHooksVersion() >= Self.expectedHooksVersion {
            return   // already wired at the current version (this app, or install.sh)
        }
        // Wired by an older CodePet (or not at all) → run the idempotent installer
        // so newly-added events like SessionEnd get registered.

        let res = resURL.path
        DispatchQueue.global(qos: .utility).async {
            let script = """
            node "\(res)/tools/install-hooks.js" install "\(res)"
            mkdir -p "$HOME/.claude/skills"
            ln -sfn "\(res)/skills/hatch-pet" "$HOME/.claude/skills/codepet-hatch"
            ln -sfn "\(res)/skills/petdex" "$HOME/.claude/skills/codepet-petdex"
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", script]
            try? p.run()
            p.waitUntilExit()
            NSLog("CodePet: first-launch hook setup finished (status \(p.terminationStatus))")
        }
    }

    private func beginInstalling() { installingCount += 1; updateBadge() }
    private func endInstalling() { installingCount = max(0, installingCount - 1); updateBadge() }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        let brand = header("CodePet")
        if let icon = NSApp.applicationIconImage?.copy() as? NSImage {
            icon.size = NSSize(width: 16, height: 16)
            brand.image = icon
        }
        menu.addItem(brand)

        let show = NSMenuItem(title: L.t(.showSessions), action: #selector(togglePanel), keyEquivalent: "s")
        show.target = self
        show.image = sym("rectangle.stack")
        menu.addItem(show)
        menu.addItem(.separator())

        let petMenu = NSMenu()
        var lastSource = ""
        for entry in store.catalog {
            if entry.source != lastSource {
                let header = NSMenuItem(title: sourceLabel(entry.source), action: nil, keyEquivalent: "")
                header.isEnabled = false
                petMenu.addItem(header)
                lastSource = entry.source
            }
            let item = NSMenuItem(title: "  " + entry.title, action: #selector(selectPet(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.key
            item.state = (store.config.pet == entry.key) ? .on : .off
            petMenu.addItem(item)
        }
        // ── Install a pet straight from the Petdex gallery, no terminal ──
        petMenu.addItem(.separator())
        let petdexParent = NSMenuItem(title: L.t(.installFromPetdex), action: nil, keyEquivalent: "")
        petdexParent.image = sym("square.and.arrow.down")
        let petdexSub = NSMenu()
        if petdexFeatured.isEmpty {
            let loading = NSMenuItem(title: L.t(.petdexLoading), action: nil, keyEquivalent: "")
            loading.isEnabled = false
            petdexSub.addItem(loading)
        } else {
            for pet in petdexFeatured {
                let item = NSMenuItem(title: pet.displayName,
                                      action: #selector(installPetdexPet(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pet.slug
                // Tick pets that are already installed.
                item.state = store.catalog.contains { $0.key == "petdex:\(pet.slug)" } ? .on : .off
                petdexSub.addItem(item)
            }
        }
        petdexSub.addItem(.separator())
        // Install ANY pet by typing its name — not just the featured ones.
        let byName = NSMenuItem(title: L.t(.petdexInstallByName),
                                action: #selector(installPetdexByName), keyEquivalent: "")
        byName.target = self
        byName.image = sym("keyboard")
        petdexSub.addItem(byName)
        let browse = NSMenuItem(title: L.t(.petdexBrowseWeb), action: #selector(browsePetdex), keyEquivalent: "")
        browse.target = self
        browse.image = sym("safari")
        petdexSub.addItem(browse)
        petMenu.setSubmenu(petdexSub, for: petdexParent)
        petMenu.addItem(petdexParent)

        petMenu.addItem(.separator())
        let refresh = NSMenuItem(title: L.t(.refreshPets), action: #selector(refreshPets), keyEquivalent: "r")
        refresh.target = self
        refresh.image = sym("arrow.clockwise")
        petMenu.addItem(refresh)
        let petParent = NSMenuItem(title: L.t(.pet), action: nil, keyEquivalent: "")
        petParent.image = sym("pawprint")
        menu.setSubmenu(petMenu, for: petParent)
        menu.addItem(petParent)

        let cornerMenu = NSMenu()
        let corners: [(String, L.Key)] = [("bottomRight", .cornerBR), ("bottomLeft", .cornerBL),
                                          ("topRight", .cornerTR), ("topLeft", .cornerTL)]
        for (key, nameKey) in corners {
            let item = NSMenuItem(title: L.t(nameKey), action: #selector(selectCorner(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = (store.config.corner == key && store.config.customOrigin == nil) ? .on : .off
            cornerMenu.addItem(item)
        }
        cornerMenu.addItem(.separator())
        let snap = NSMenuItem(title: L.t(.snapToCorner), action: #selector(snapToCorner), keyEquivalent: "")
        snap.target = self
        snap.image = sym("arrow.down.right.and.arrow.up.left")
        cornerMenu.addItem(snap)
        let cornerParent = NSMenuItem(title: L.t(.position), action: nil, keyEquivalent: "")
        cornerParent.image = sym("macwindow")
        menu.setSubmenu(cornerMenu, for: cornerParent)
        menu.addItem(cornerParent)

        // Language picker.
        let langMenu = NSMenu()
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(title: lang.menuTitle, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            item.state = (store.config.appLanguage == lang) ? .on : .off
            langMenu.addItem(item)
        }
        let langParent = NSMenuItem(title: L.t(.language), action: nil, keyEquivalent: "")
        langParent.image = sym("globe")
        menu.setSubmenu(langMenu, for: langParent)
        menu.addItem(langParent)

        menu.addItem(.separator())
        // Quick state preview for testing without a Claude session.
        let previewMenu = NSMenu()
        for act in ["idle", "running", "waiting", "ready", "failed"] {
            let title = PetActivity(rawValue: act)?.label ?? act.capitalized
            let item = NSMenuItem(title: title, action: #selector(previewState(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = act
            previewMenu.addItem(item)
        }
        previewMenu.addItem(.separator())
        let clearPreview = NSMenuItem(title: L.t(.clearPreview), action: #selector(clearPreview), keyEquivalent: "")
        clearPreview.target = self
        clearPreview.image = sym("xmark.circle")
        previewMenu.addItem(clearPreview)
        let previewParent = NSMenuItem(title: L.t(.previewState), action: nil, keyEquivalent: "")
        previewParent.image = sym("eye")
        menu.setSubmenu(previewMenu, for: previewParent)
        menu.addItem(previewParent)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L.t(.quit), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.image = sym("power")
        menu.addItem(quit)
    }

    /// A small template SF Symbol for menu-item styling.
    private func sym(_ name: String) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        return img
    }

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "codepet": return L.t(.installedPets)
        case "petdex":  return L.t(.petdexPets)
        case "codex":   return L.t(.codexPets)
        default:        return L.t(.builtinForms)
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = AppLanguage(rawValue: raw) else { return }
        store.setLanguage(lang)
        rebuildMenu()
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        store.setPet(key)
        rebuildMenu()
    }

    @objc private func refreshPets() {
        store.refreshCatalog()
        rebuildMenu()
    }

    /// Install the clicked featured Petdex pet natively (download → ~/.petdex/pets),
    /// then select it. Everything happens in-app: no terminal, no npx.
    @objc private func installPetdexPet(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String,
              let pet = petdexFeatured.first(where: { $0.slug == slug }) else { return }
        beginInstalling()
        installResolved(pet)
    }

    /// Install any pet by name — prompts for a slug, resolves it via its gallery
    /// page, then installs. Covers pets not in the featured list.
    @objc private func installPetdexByName() {
        let alert = NSAlert()
        alert.messageText = L.t(.installFromPetdex)
        alert.informativeText = L.t(.petdexEnterName)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "boba"
        alert.accessoryView = field
        alert.addButton(withTitle: L.t(.install))
        alert.addButton(withTitle: L.t(.cancel))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let slug = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return }
        beginInstalling()
        PetdexGallery.resolve(slug: slug) { [weak self] pet in
            guard let self = self else { return }
            if let pet = pet {
                self.installResolved(pet)   // ends the indicator on completion
            } else {
                self.endInstalling()
                self.notify(title: L.t(.petdexInstallFailedTitle), message: slug)
            }
        }
    }

    /// Download + write a resolved pet, then select it and report the result.
    private func installResolved(_ pet: PetdexPet) {
        PetdexGallery.install(pet) { [weak self] result in
            guard let self = self else { return }
            self.endInstalling()
            switch result {
            case .success(let key):
                self.store.refreshCatalog()
                self.store.setPet(key)      // switch to the freshly installed pet
                self.rebuildMenu()
                self.notify(title: L.t(.petdexInstalledTitle), message: pet.displayName)
            case .failure(let err):
                self.notify(title: L.t(.petdexInstallFailedTitle), message: err.localizedDescription)
            }
        }
    }

    @objc private func browsePetdex() {
        NSWorkspace.shared.open(PetdexGallery.pageURL)
    }

    private func notify(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L.t(.ok))
        alert.runModal()
    }

    @objc private func selectCorner(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        store.setCorner(key)
        window.restorePosition(store.config)
        followPanel()
        rebuildMenu()
    }

    @objc private func snapToCorner() {
        store.clearCustomPosition()
        window.snapToCorner(store.config.corner)
        followPanel()
        rebuildMenu()
    }

    @objc private func previewState(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let act = PetActivity(rawValue: key) else { return }
        // Write both the legacy state and a preview session so both the corner
        // pet and the dashboard demonstrate the state.
        let now = Date().timeIntervalSince1970
        let st = PetState(state: act, detail: "preview", sessionId: "preview", updatedAt: now)
        Paths.ensureDir()
        if let data = try? JSONEncoder().encode(st) { try? data.write(to: Paths.stateFile) }

        Paths.ensureSessionsDir()
        let session = Session(sessionId: "preview", state: act, detail: act.label,
                              cwd: FileManager.default.currentDirectoryPath,
                              prompt: "Preview of the \"\(act.label)\" state.",
                              lastTool: "Preview", recentTools: ["Read", "Edit", "Bash"],
                              toolCount: 7, startedAt: now - 180, updatedAt: now,
                              transcriptPath: nil, termProgram: nil, termSession: nil)
        let file = Paths.sessionsDir.appendingPathComponent("preview.json")
        if let data = try? JSONEncoder().encode(session) { try? data.write(to: file) }
    }

    @objc private func clearPreview() {
        let file = Paths.sessionsDir.appendingPathComponent("preview.json")
        try? FileManager.default.removeItem(at: file)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
