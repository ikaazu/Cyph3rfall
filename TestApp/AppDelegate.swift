import AppKit
import ServiceManagement
import LocalAuthentication
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private var statusItem: NSStatusItem!
    private var idleWatcher: IdleWatcher!
    private var fullScreen: FullScreenWindow?
    private var prefsController: PreferencesWindowController?
    private var aboutPanel: NSPanel?
    private var settings = Cyph3rfallSettings.load()
    private var updateAvailableVersion: String? = nil
    private var updateDownloadURL:      URL?    = nil
    private var isDownloadingUpdate             = false
    private let hotkeyManager = HotkeyManager()

    // MARK: - Lock state
    /// True while a LocalAuthentication prompt is on screen — prevents stacking dialogs.
    private var isAuthenticating = false
    /// True when dismissal requires a successful auth challenge.
    private var lockActive = false
    /// The in-flight LocalAuthentication context. Tracked so the safety valve
    /// and wake handler can invalidate a stale prompt instead of letting its
    /// completion fire later and dismiss a re-locked screensaver.
    private var authContext: LAContext?
    /// Fires every 5 s during a manually-started session to check whether the
    /// user's idle threshold has now been met, at which point lock arms itself.
    private var lockEligibilityTimer: Timer?

    // MARK: - Constants

    private static let idleTimeoutKey  = "idleTimeoutSeconds"
    private static let websiteURL      = URL(string: "https://cyph3rfall.app")!
    private static let emailURL        = URL(string: "mailto:dev@cyph3rfall.app")!
    private static let releasesPageURL = URL(string: "https://github.com/ikaazu/Cyph3rfall/releases/latest")!

    // Persisted idle timeout in seconds; 0 = disabled.
    private var idleTimeout: TimeInterval {
        get { UserDefaults.standard.double(forKey: Self.idleTimeoutKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.idleTimeoutKey) }
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Terminate any previously running instance (e.g. stale Login Item copy).
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != .current && !$0.isTerminated }
            .forEach { $0.terminate() }

        // First-run default: 5 minutes
        if UserDefaults.standard.object(forKey: Self.idleTimeoutKey) == nil {
            idleTimeout = 300
        }

        setupStatusItem()

        // Register the global hotkey (if one was saved).
        hotkeyManager.onTriggered = { [weak self] in self?.showScreensaver(manual: true) }
        applyHotkey(from: settings)

        idleWatcher = IdleWatcher { [weak self] in
            DispatchQueue.main.async { self?.showScreensaver(manual: false) }
        }
        applyIdleTimeout()

        // Activate screensaver when the system sleeps or the lid closes.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification, object: nil)

        // Reset any stale auth state when the system wakes. If the Mac slept
        // while an LAContext evaluation was in flight, the completion block
        // never fires and isAuthenticating stays true forever — locking the
        // user out with no way to dismiss the screensaver.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil)

        // Check GitHub for a newer release. Runs in the background; menu is
        // updated on the main thread only if a newer version is found.
        checkForUpdates()
    }

    // MARK: - Status-item / menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = Self.makeMenuBarIcon()
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // ── Update available banner (shown only when a newer version is found) ──
        if isDownloadingUpdate {
            let item = NSMenuItem(title: "Downloading Update…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        } else if let v = updateAvailableVersion {
            let updateItem = NSMenuItem(title: "⬆ Update Available (v\(v))",
                                        action: #selector(installUpdate),
                                        keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(.separator())
        }

        // ── Start Now ──────────────────────────────────────────────────
        let hotkeyChar = settings.hotkeyCode >= 0 ? settings.hotkeyCharacter.lowercased() : ""
        let startItem = NSMenuItem(title: "Start Now",
                                   action: #selector(startNow),
                                   keyEquivalent: hotkeyChar)
        if settings.hotkeyCode >= 0 {
            startItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(
                rawValue: UInt(settings.hotkeyModifiers))
        }
        startItem.target = self
        menu.addItem(startItem)

        menu.addItem(.separator())

        // ── Idle-timeout submenu ───────────────────────────────────────
        let timeoutParent = NSMenuItem(title: "Start After Idle",
                                       action: nil, keyEquivalent: "")
        let timeoutMenu = NSMenu()
        let options: [(String, TimeInterval)] = [
            ("Never",      0),
            ("1 Minute",   60),
            ("2 Minutes",  120),
            ("5 Minutes",  300),
            ("10 Minutes", 600),
            ("15 Minutes", 900),
            ("30 Minutes", 1800),
        ]
        for (title, secs) in options {
            let item = NSMenuItem(title: title,
                                  action: #selector(setIdleTimeout(_:)),
                                  keyEquivalent: "")
            item.representedObject = secs as NSNumber
            item.state  = (secs == idleTimeout) ? .on : .off
            item.target = self
            timeoutMenu.addItem(item)
        }
        timeoutParent.submenu = timeoutMenu
        menu.addItem(timeoutParent)

        menu.addItem(.separator())

        // ── Launch at Login ────────────────────────────────────────────
        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin(_:)),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.state  = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        // ── Settings ───────────────────────────────────────────────────
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings),
                                      keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // ── About ──────────────────────────────────────────────────────
        let aboutItem = NSMenuItem(title: "About Cyph3rfall…",
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        // ── Quit ───────────────────────────────────────────────────────
        let quitItem = NSMenuItem(title: "Quit Cyph3rfall",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func showAbout() {
        // Re-use the panel if it already exists.
        if let existing = aboutPanel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask:   [.titled, .closable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        panel.title = "About Cyph3rfall"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titlebarAppearsTransparent = true

        let vfx = NSVisualEffectView(frame: .zero)
        vfx.material     = .hudWindow
        vfx.blendingMode = .behindWindow
        vfx.state        = .active
        vfx.alphaValue   = 0.82

        // Second pass: re-blurs the already-blurred content for stronger perceived blur
        let vfx2 = NSVisualEffectView(frame: .zero)
        vfx2.material                                  = .hudWindow
        vfx2.blendingMode                              = .withinWindow
        vfx2.state                                     = .active
        vfx2.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(vfx2)
        NSLayoutConstraint.activate([
            vfx2.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            vfx2.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            vfx2.topAnchor.constraint(equalTo: vfx.topAnchor),
            vfx2.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
        ])

        panel.contentView = vfx
        let content = vfx

        // ── Icon ──────────────────────────────────────────────────────────
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true

        // ── App name ──────────────────────────────────────────────────────
        let nameLabel = NSTextField(labelWithString: "Cyph3rfall")
        nameLabel.font      = .systemFont(ofSize: 22, weight: .bold)
        nameLabel.alignment = .center

        // ── Version ───────────────────────────────────────────────────────
        let appVersion  = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let versionLabel = NSTextField(labelWithString: "Version \(appVersion)")
        versionLabel.font      = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        // ── Check for Updates link ────────────────────────────────────────
        let updateBtn = NSButton(title: "Check for Updates…",
                                 target: self,
                                 action: #selector(checkForUpdatesManually))
        updateBtn.isBordered = false
        updateBtn.attributedTitle = NSAttributedString(
            string: "Check for Updates…",
            attributes: [.foregroundColor: NSColor.linkColor,
                         .font: NSFont.systemFont(ofSize: 13)])

        // ── Tagline ───────────────────────────────────────────────────────
        let taglineLabel = NSTextField(labelWithString: "Ambient digital rain for macOS")
        taglineLabel.font      = .systemFont(ofSize: 12)
        taglineLabel.textColor = .secondaryLabelColor
        taglineLabel.alignment = .center

        // ── Website + email links ─────────────────────────────────────────
        let siteRow  = makeAboutLinkView(icon: "link",     title: "cyph3rfall.app",     action: #selector(openWebsite))
        let emailRow = makeAboutLinkView(icon: "envelope", title: "dev@cyph3rfall.app", action: #selector(openContactEmail))
        let linksRow = NSStackView(views: [siteRow, emailRow])
        linksRow.orientation = .horizontal
        linksRow.spacing     = 22
        linksRow.alignment   = .centerY

        // ── Credits ───────────────────────────────────────────────────────
        let creditsLabel = NSTextField(wrappingLabelWithString:
            "Built with Swift & AppKit\n\n" +
            "Inspired by The Matrix (1999) and MatrixMania for Windows by StrongGames.\n\n" +
            "I used MatrixMania for decades, once gave feedback that improved it, " +
            "missed that feeling on modern macOS, and built my own spiritual successor.\n\n" +
            "No screensaver frameworks were harmed.")
        creditsLabel.font                    = .systemFont(ofSize: 12)
        creditsLabel.textColor               = .secondaryLabelColor
        creditsLabel.alignment               = .center
        creditsLabel.maximumNumberOfLines    = 0
        creditsLabel.preferredMaxLayoutWidth = 380

        // ── Copyright ─────────────────────────────────────────────────────
        let copyrightLabel = NSTextField(labelWithString: "© 2026 Greg Stock")
        copyrightLabel.font      = .systemFont(ofSize: 11)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center

        // ── Layout ────────────────────────────────────────────────────────
        let stack = NSStackView(views: [
            iconView, nameLabel, versionLabel, updateBtn,
            taglineLabel, linksRow, creditsLabel, copyrightLabel,
        ])
        stack.orientation = .vertical
        stack.alignment   = .centerX
        stack.spacing     = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        stack.setCustomSpacing(14, after: iconView)
        stack.setCustomSpacing(2,  after: nameLabel)
        stack.setCustomSpacing(6,  after: versionLabel)
        stack.setCustomSpacing(16, after: updateBtn)
        stack.setCustomSpacing(14, after: taglineLabel)
        stack.setCustomSpacing(18, after: linksRow)
        stack.setCustomSpacing(16, after: creditsLabel)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -28),
            stack.widthAnchor.constraint(equalToConstant: 392),
        ])

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        aboutPanel = panel
    }

    /// Builds a small icon + blue-text link suitable for the About panel.
    private func makeAboutLinkView(icon: String, title: String, action: Selector) -> NSView {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let img    = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                         .withSymbolConfiguration(config)
        let imgView = NSImageView(image: img ?? NSImage())
        imgView.contentTintColor = .linkColor

        let btn = NSButton(title: title, target: self, action: action)
        btn.isBordered = false
        btn.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.linkColor,
                         .font: NSFont.systemFont(ofSize: 13)])

        let h = NSStackView(views: [imgView, btn])
        h.orientation = .horizontal
        h.spacing     = 4
        h.alignment   = .centerY
        return h
    }

    @objc private func openWebsite() {
        NSWorkspace.shared.open(Self.websiteURL)
    }

    @objc private func openContactEmail() {
        NSWorkspace.shared.open(Self.emailURL)
    }

    /// Manual update check triggered from the About panel.
    /// Shows feedback in both the update-found and up-to-date cases.
    @objc private func checkForUpdatesManually() {
        URLSession.shared.dataTask(with: Self.makeGitHubReleaseRequest()) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                let alert   = NSAlert()

                if let data, error == nil,
                   let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String {

                    let latest  = Self.stripVersionTag(tagName)
                    let assets  = json["assets"] as? [[String: Any]] ?? []
                    let dmgURL  = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                        .flatMap { $0["browser_download_url"] as? String }
                        .flatMap(URL.init(string:))

                    if self.isNewerVersion(latest, than: current) {
                        self.updateAvailableVersion = latest
                        self.updateDownloadURL      = dmgURL
                        self.rebuildMenu()
                        alert.messageText     = "Update Available"
                        alert.informativeText = "Cyph3rfall \(latest) is available."
                        alert.addButton(withTitle: dmgURL != nil ? "Download & Install" : "View Release")
                        alert.addButton(withTitle: "Later")
                        if alert.runModal() == .alertFirstButtonReturn {
                            dmgURL != nil ? self.installUpdate() : self.openReleasePage()
                        }
                    } else {
                        alert.messageText     = "You're Up to Date"
                        alert.informativeText = "Cyph3rfall \(current) is the latest version."
                        alert.runModal()
                    }
                } else {
                    alert.messageText     = "Update Check Failed"
                    alert.informativeText = "Could not reach the update server. Check your internet connection and try again."
                    alert.alertStyle      = .warning
                    alert.runModal()
                }
            }
        }.resume()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                sender.state = .off
            } else {
                try service.register()
                sender.state = .on
            }
        } catch {
            // App must be in /Applications for this to work.
            let alert = NSAlert()
            alert.messageText     = "Couldn't update Login Items"
            alert.informativeText = "Move Cyph3rfall.app to your Applications folder first, then try again.\n\n(\(error.localizedDescription))"
            alert.alertStyle      = .warning
            alert.runModal()
        }
    }

    @objc private func startNow() {
        showScreensaver(manual: true)
    }

    @objc private func setIdleTimeout(_ sender: NSMenuItem) {
        guard let secs = (sender.representedObject as? NSNumber)?.doubleValue else { return }
        idleTimeout = secs
        // Update checkmarks in the submenu
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        applyIdleTimeout()
    }

    @objc func openSettings() {
        if prefsController == nil {
            prefsController = PreferencesWindowController(settings: settings)
            prefsController?.onApply = { [weak self] newSettings in
                guard let self else { return }
                let previousSettings = self.settings
                if self.hotkeyChanged(from: previousSettings, to: newSettings) {
                    guard self.applyHotkey(from: newSettings) else {
                        self.applyHotkey(from: previousSettings)
                        self.prefsController?.refresh(from: previousSettings)
                        return
                    }
                }
                self.settings = newSettings
                newSettings.save()
                self.rebuildMenu()
                // Push live into any active full-screen window.
                self.fullScreen?.primaryRainView?.settings = newSettings
            }
            prefsController?.onStartNow = { [weak self] in
                self?.showScreensaver(manual: true)
            }
        }
        prefsController?.refresh(from: settings)
        prefsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        prefsController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Screensaver

    private func showScreensaver(manual: Bool) {
        guard fullScreen == nil else { return }
        idleWatcher.stop()

        // Determine initial lock state.
        if manual {
            // Manual start with a timed idle threshold arms the lock only after
            // that same threshold elapses. If idle activation is disabled,
            // requiring a password means the manual session locks immediately.
            if settings.requirePassword {
                if idleTimeout > 0 {
                    lockActive = false
                    startLockEligibilityTimer()
                } else {
                    lockActive = true
                }
            } else {
                lockActive = false
            }
        } else {
            // Idle-triggered: threshold already met — arm lock immediately.
            lockActive = settings.requirePassword
        }

        let fs = FullScreenWindow(
            onDismissRequested: { [weak self] in
                self?.handleDismissRequest()
            },
            onDismiss: { [weak self] in
                guard let self else { return }
                self.lockEligibilityTimer?.invalidate()
                self.lockEligibilityTimer = nil
                self.lockActive = false
                self.authContext?.invalidate()
                self.authContext = nil
                self.isAuthenticating = false
                self.fullScreen = nil
                self.idleWatcher.resetIdleState()
                self.applyIdleTimeout()
                // If the settings window was open when the screensaver launched,
                // bring it back to the front and restart its preview.
                self.prefsController?.resumePreview()
            }
        )
        fullScreen = fs
        fs.show(settings: settings)
    }

    /// Called whenever the user moves the mouse, presses a key, etc.
    /// Routes through LocalAuthentication when the lock is armed.
    private func handleDismissRequest() {
        guard !isAuthenticating else { return }   // auth dialog already on screen

        if settings.requirePassword && lockActive {
            authenticate()
        } else {
            fullScreen?.dismiss()
        }
    }

    private func authenticate() {
        isAuthenticating = true

        // Safety valve: if evaluatePolicy's completion block never fires for any
        // reason (sleep interruption, system hiccup, etc.) reset after 90 s so
        // the user can try again rather than being permanently locked out.
        // Invalidate the stale context so its completion can never fire later
        // and dismiss a screensaver that has since re-armed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            guard let self, self.isAuthenticating else { return }
            self.authContext?.invalidate()
            self.authContext = nil
            self.isAuthenticating = false
        }

        let context = LAContext()
        authContext = context
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isAuthenticating = false
            authContext = nil
            if let laError = error as? LAError, laError.code == .passcodeNotSet {
                // No password or biometrics exist on this Mac — the lock cannot
                // verify anything, so dismiss rather than trap the user.
                fullScreen?.dismiss()
            }
            // Any other (likely transient) failure: fail closed. The rain stays
            // up and the next input event retries authentication.
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock Cyph3rfall"
        ) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // Ignore results from a context the safety valve or wake
                // handler has already invalidated and replaced.
                guard context === self.authContext else { return }
                self.authContext = nil
                self.isAuthenticating = false
                if success {
                    self.fullScreen?.dismiss()
                }
                // On failure or cancel: do nothing — rain stays visible.
            }
        }
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        DispatchQueue.main.async { self.showScreensaver(manual: false) }
    }

    @objc private func systemDidWake(_ notification: Notification) {
        DispatchQueue.main.async {
            // Any LAContext created before sleep is now invalid — its completion
            // block will never fire. Invalidate and reset unconditionally so the
            // user is never permanently blocked from dismissing the screensaver.
            self.authContext?.invalidate()
            self.authContext = nil
            self.isAuthenticating = false

            // If the screensaver is still showing and the lock is armed, present
            // a fresh authentication prompt now that the system has woken.
            if self.fullScreen != nil && self.lockActive {
                self.authenticate()
            }
        }
    }

    /// Polls system idle time every 5 s during a manually-started session.
    /// Once the user's chosen idle threshold is met, the lock arms itself.
    private func startLockEligibilityTimer() {
        lockEligibilityTimer?.invalidate()
        lockEligibilityTimer = Timer.scheduledTimer(
            withTimeInterval: 5, repeats: true
        ) { [weak self] _ in
            guard let self, self.fullScreen != nil else {
                self?.lockEligibilityTimer?.invalidate()
                return
            }
            if IdleWatcher.currentIdleTime() >= self.idleTimeout {
                self.lockActive = true
                self.lockEligibilityTimer?.invalidate()
                self.lockEligibilityTimer = nil
            }
        }
        // Ensure the timer fires even when the run loop is in event-tracking mode.
        RunLoop.main.add(lockEligibilityTimer!, forMode: .common)
    }

    // MARK: - Menu bar icon

    /// Filled rounded square with the ﾐ katakana glyph cut through as a
    /// transparent hole. Using isTemplate = true so macOS inverts it
    /// automatically for light / dark menu bars.
    private static func makeMenuBarIcon() -> NSImage {
        let dim: CGFloat = 17
        let char = "Ξ"

        let image = NSImage(size: NSSize(width: dim, height: dim))
        image.lockFocusFlipped(false)

        // — Filled rounded square background —
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5,
                                         width: dim - 1, height: dim - 1),
                     xRadius: 3.5, yRadius: 3.5).fill()

        // — Punch the character through using destinationOut —
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setBlendMode(.destinationOut)
            let font = NSFont.monospacedSystemFont(ofSize: dim * 0.72, weight: .regular)
            let str  = NSAttributedString(string: char, attributes: [
                .font: font,
                .foregroundColor: NSColor.black
            ])
            let sz = str.size()
            str.draw(at: NSPoint(x: (dim - sz.width)  / 2,
                                 y: (dim - sz.height) / 2))
            ctx.setBlendMode(.normal)
        }

        image.unlockFocus()
        image.isTemplate = true   // system handles light/dark inversion
        return image
    }

    // MARK: - Update check

    /// Builds the GitHub releases API request with correct caching and versioning headers.
    private static func makeGitHubReleaseRequest() -> URLRequest {
        let url = URL(string: "https://api.github.com/repos/ikaazu/Cyph3rfall/releases/latest")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28",                  forHTTPHeaderField: "X-GitHub-Api-Version")
        return req
    }

    /// Strips the leading "v" from a GitHub tag name (e.g. "v1.1" → "1.1").
    private static func stripVersionTag(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private func checkForUpdates() {
        URLSession.shared.dataTask(with: Self.makeGitHubReleaseRequest()) { [weak self] data, _, error in
            guard let self, let data, error == nil,
                  let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String
            else { return }

            let latest  = Self.stripVersionTag(tagName)
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            guard self.isNewerVersion(latest, than: current) else { return }

            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmgURL = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))

            DispatchQueue.main.async {
                self.updateAvailableVersion = latest
                self.updateDownloadURL      = dmgURL
                self.rebuildMenu()
            }
        }.resume()
    }

    /// Returns true if `candidate` is a higher version number than `current`.
    ///
    /// Compares each dot-separated component as a decimal number, so "1.1"
    /// correctly sorts above "1.02" (second component: 1 > 0, not 1 vs 2).
    /// Components with leading zeros (e.g. "02") are treated as "0.2" —
    /// i.e. split into their individual digits — matching the versioning scheme
    /// used by this app (1.0 → 1.01 → 1.02 → 1.1).
    private func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        func components(_ v: String) -> [Int] {
            v.split(separator: ".").flatMap { part -> [Int] in
                guard let n = Int(part) else { return [] }
                // "02" → treat as minor=0, patch=2 so 1.02 sorts below 1.1
                if part.count > 1 && part.hasPrefix("0") {
                    return part.map { Int(String($0))! }
                }
                return [n]
            }
        }
        let lhs = components(candidate)
        let rhs = components(current)
        let len = max(lhs.count, rhs.count)
        for i in 0 ..< len {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    @objc private func installUpdate() {
        guard let downloadURL = updateDownloadURL, !isDownloadingUpdate else {
            if updateDownloadURL == nil { openReleasePage() }
            return
        }
        isDownloadingUpdate = true
        rebuildMenu()

        let tempDMG = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Cyph3rfall-update.dmg")

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, _, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    self.isDownloadingUpdate = false
                    self.rebuildMenu()
                    let a = NSAlert()
                    a.messageText     = "Download Failed"
                    a.informativeText = error.localizedDescription
                    a.alertStyle      = .warning
                    a.runModal()
                }
                return
            }
            guard let tempURL else { return }
            try? FileManager.default.removeItem(at: tempDMG)
            try? FileManager.default.moveItem(at: tempURL, to: tempDMG)

            DispatchQueue.main.async {
                self.isDownloadingUpdate = false
                self.rebuildMenu()

                let a = NSAlert()
                a.messageText     = "Update Ready"
                a.informativeText = "Cyph3rfall \(self.updateAvailableVersion ?? "") has been downloaded. Click Install & Restart to apply it now."
                a.addButton(withTitle: "Install & Restart")
                a.addButton(withTitle: "Later")
                guard a.runModal() == .alertFirstButtonReturn else {
                    try? FileManager.default.removeItem(at: tempDMG)
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    let mount = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent("cyph3rfall-update-mount")
                    guard self.run("/usr/bin/hdiutil",
                                   ["attach", tempDMG.path,
                                    "-mountpoint", mount.path,
                                    "-nobrowse", "-quiet"]) == 0
                    else {
                        try? FileManager.default.removeItem(at: tempDMG)
                        DispatchQueue.main.async {
                            self.showUpdateError("Could not mount the update disk image.")
                        }
                        return
                    }

                    let src  = mount.appendingPathComponent("Cyph3rfall.app")
                    let dest = URL(fileURLWithPath: Bundle.main.bundlePath)
                    let ok   = self.run("/usr/bin/ditto", [src.path, dest.path]) == 0
                    _ = self.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
                    try? FileManager.default.removeItem(at: tempDMG)

                    DispatchQueue.main.async {
                        if ok {
                            self.relaunchApp()
                        } else {
                            self.showUpdateError("Could not install the update. Make sure Cyph3rfall is in your Applications folder.")
                        }
                    }
                }
            }
        }.resume()
    }

    private func relaunchApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments     = [Bundle.main.bundlePath]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    private func showUpdateError(_ message: String) {
        let a = NSAlert()
        a.messageText     = "Update Failed"
        a.informativeText = message
        a.alertStyle      = .warning
        a.runModal()
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments     = args
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    @objc private func openReleasePage() {
        NSWorkspace.shared.open(Self.releasesPageURL)
    }

    // MARK: - Helpers

    private func hotkeyChanged(from old: Cyph3rfallSettings,
                               to new: Cyph3rfallSettings) -> Bool {
        old.hotkeyCode      != new.hotkeyCode ||
        old.hotkeyModifiers != new.hotkeyModifiers ||
        old.hotkeyCharacter != new.hotkeyCharacter
    }

    @discardableResult
    private func applyHotkey(from settings: Cyph3rfallSettings) -> Bool {
        guard settings.hotkeyCode >= 0 else {
            hotkeyManager.unregister()
            return true
        }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifiers))
        do {
            try hotkeyManager.update(keyCode: settings.hotkeyCode,
                                     carbonModifiers: carbonModifiers(from: mods))
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Shortcut Not Available"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    private func applyIdleTimeout() {
        if idleTimeout > 0 {
            idleWatcher.start(threshold: idleTimeout)
        } else {
            idleWatcher.stop()
        }
    }
}
