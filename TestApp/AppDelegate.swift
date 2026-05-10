import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private var statusItem: NSStatusItem!
    private var idleWatcher: IdleWatcher!
    private var fullScreen: FullScreenWindow?
    private var prefsController: PreferencesWindowController?
    private var settings = MatrixRainSettings.load()

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

        idleWatcher = IdleWatcher { [weak self] in
            DispatchQueue.main.async { self?.showScreensaver() }
        }
        applyIdleTimeout()
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
        let author    = "Greg Stock"
        let copyright = "© 2026 \(author)"

        let credits = """
            Ambient digital rain for macOS

            Built with Swift & AppKit

            Inspired by The Matrix (1999)
            dir. Lana & Lilly Wachowski
            & MatrixMania for Windows

            No screensaver frameworks were harmed.
            """

        let style = NSMutableParagraphStyle()
        style.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle:  style,
        ]

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName:    "Cyph3rfall",
            .applicationVersion: "1.0",
            .version:            "",
            .credits:            NSAttributedString(string: credits, attributes: attrs),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyright,
        ])
        NSApp.activate(ignoringOtherApps: true)
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
        showScreensaver()
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
            }
            prefsController?.onStartNow = { [weak self] in
                self?.showScreensaver()
            }
        }
        prefsController?.refresh(from: settings)
        prefsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        prefsController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Screensaver

    private func showScreensaver() {
        guard fullScreen == nil else { return }
        idleWatcher.stop()

        let fs = FullScreenWindow { [weak self] in
            guard let self else { return }
            self.fullScreen = nil
            self.idleWatcher.resetIdleState()
            self.applyIdleTimeout()
        }
        fullScreen = fs
        fs.show(settings: settings)
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

    private func applyIdleTimeout() {
        if idleTimeout > 0 {
            idleWatcher.start(threshold: idleTimeout)
        } else {
            idleWatcher.stop()
        }
    }
}
