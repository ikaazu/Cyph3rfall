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
    private var settings = MatrixRainSettings.load()
    private let hotkeyManager = HotkeyManager()

    // MARK: - Lock state
    /// True while a LocalAuthentication prompt is on screen — prevents stacking dialogs.
    private var isAuthenticating = false
    /// True when dismissal requires a successful auth challenge.
    private var lockActive = false
    /// Fires every 5 s during a manually-started session to check whether the
    /// user's idle threshold has now been met, at which point lock arms itself.
    private var lockEligibilityTimer: Timer?

    // Persisted idle timeout in seconds; 0 = disabled.
    private var idleTimeout: TimeInterval {
        get { UserDefaults.standard.double(forKey: "idleTimeoutSeconds") }
        set { UserDefaults.standard.set(newValue, forKey: "idleTimeoutSeconds") }
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Terminate any previously running instance (e.g. stale Login Item copy).
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != .current && !$0.isTerminated }
            .forEach { $0.terminate() }

        // First-run default: 5 minutes
        if UserDefaults.standard.object(forKey: "idleTimeoutSeconds") == nil {
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

        // ── Start Now ──────────────────────────────────────────────────
        let startItem = NSMenuItem(title: "Start Now",
                                   action: #selector(startNow),
                                   keyEquivalent: "")
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
                                      keyEquivalent: ",")
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
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 460),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        panel.title = "About Cyph3rfall"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true

        guard let content = panel.contentView else { return }

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
        let versionLabel = NSTextField(labelWithString: "Version 1.01")
        versionLabel.font      = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        // ── Credits ───────────────────────────────────────────────────────
        let creditsLabel = NSTextField(wrappingLabelWithString: """
            Ambient digital rain for macOS

            Built with Swift & AppKit

            Inspired by The Matrix (1999)
            & MatrixMania for Windows by StrongGames

            I used MatrixMania for decades, once gave feedback \
            that improved it, missed that feeling on modern macOS, \
            and built my own spiritual successor.

            No screensaver frameworks were harmed.
            """)
        creditsLabel.font                   = .systemFont(ofSize: 12)
        creditsLabel.textColor              = .secondaryLabelColor
        creditsLabel.alignment              = .center
        creditsLabel.maximumNumberOfLines   = 0
        creditsLabel.preferredMaxLayoutWidth = 380

        // ── Copyright ─────────────────────────────────────────────────────
        let copyrightLabel = NSTextField(labelWithString: "© 2026 Greg Stock")
        copyrightLabel.font      = .systemFont(ofSize: 11)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center

        // ── Layout ────────────────────────────────────────────────────────
        let stack = NSStackView(views: [
            iconView, nameLabel, versionLabel, creditsLabel, copyrightLabel
        ])
        stack.orientation  = .vertical
        stack.alignment    = .centerX
        stack.spacing      = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        stack.setCustomSpacing(14, after: iconView)
        stack.setCustomSpacing(4,  after: nameLabel)
        stack.setCustomSpacing(20, after: versionLabel)
        stack.setCustomSpacing(20, after: creditsLabel)

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
                self.settings = newSettings
                newSettings.save()
                // Push live into any active full-screen window.
                self.fullScreen?.primaryRainView?.settings = newSettings
                // Re-register the global hotkey with any updated combo.
                self.applyHotkey(from: newSettings)
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
            // Manual start: lock is not active yet.
            // It will arm once the user's idle threshold has been sitting idle
            // for at least idleTimeout seconds (same rule as auto-activation).
            lockActive = false
            if settings.requirePassword && idleTimeout > 0 {
                startLockEligibilityTimer()
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
        let context = LAContext()
        var error: NSError?

        // Prefer Apple Watch unlock if the Watch app is paired and reachable;
        // fall back to Touch ID / Face ID + password.
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithWatch, error: &error)
            ? .deviceOwnerAuthenticationWithWatch
            : .deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &error) else {
            // No auth mechanism available — just dismiss.
            isAuthenticating = false
            fullScreen?.dismiss()
            return
        }

        context.evaluatePolicy(
            policy,
            localizedReason: "Unlock Cyph3rfall"
        ) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAuthenticating = false
                if success { self.fullScreen?.dismiss() }
                // On failure or cancel: do nothing — rain stays visible.
            }
        }
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        DispatchQueue.main.async { self.showScreensaver(manual: false) }
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
            let idle = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: CGEventType(rawValue: ~UInt32(0))!
            )
            if idle >= self.idleTimeout {
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

    // MARK: - Helpers

    private func applyHotkey(from settings: MatrixRainSettings) {
        guard settings.hotkeyCode >= 0 else { hotkeyManager.unregister(); return }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(settings.hotkeyModifiers))
        hotkeyManager.update(keyCode: settings.hotkeyCode,
                             carbonModifiers: carbonModifiers(from: mods))
    }

    private func applyIdleTimeout() {
        if idleTimeout > 0 {
            idleWatcher.start(threshold: idleTimeout)
        } else {
            idleWatcher.stop()
        }
    }
}
