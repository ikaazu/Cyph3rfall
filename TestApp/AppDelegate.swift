import AppKit
import ServiceManagement
import LocalAuthentication
import Carbon
import CryptoKit

private struct UpdateAsset {
    let url: URL
    let expectedBytes: Int64
    let sha256: String?
    let allowedContentTypes: Set<String>
}

private struct ReleaseMetadata {
    let version: String
    let asset: UpdateAsset?
}

private struct HTTPPayload {
    let data: Data
    let response: HTTPURLResponse
}

private struct ProcessResult {
    let status: Int32
    let output: String
}

private enum UpdateError: LocalizedError {
    case unexpectedResponse
    case responseTooLarge
    case invalidMetadata
    case invalidDownload
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:
            return "The update server redirected to an unapproved location."
        case .responseTooLarge:
            return "The update response exceeded the allowed size."
        case .invalidMetadata:
            return "The update server returned invalid release metadata."
        case .invalidDownload:
            return "The downloaded update did not match its release metadata."
        case .validationFailed(let message):
            return message
        }
    }
}

// MARK: - Bounded update transport

/// Loads a small response while enforcing status, redirect, origin, and byte
/// limits before untrusted data reaches JSON parsing.
private final class BoundedDataRequest: NSObject, URLSessionDataDelegate,
                                        URLSessionTaskDelegate {
    private let maximumBytes: Int
    private let allowedURL: (URL) -> Bool
    private let completion: (Result<HTTPPayload, Error>) -> Void

    private var session: URLSession?
    private var receivedData = Data()
    private var response: HTTPURLResponse?
    private var terminalError: Error?
    private var hasCompleted = false

    init(maximumBytes: Int,
         allowedURL: @escaping (URL) -> Bool,
         completion: @escaping (Result<HTTPPayload, Error>) -> Void) {
        self.maximumBytes = maximumBytes
        self.allowedURL = allowedURL
        self.completion = completion
    }

    func start(with request: URLRequest) {
        guard let url = request.url, allowedURL(url) else {
            finish(.failure(UpdateError.unexpectedResponse))
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        self.session = session
        session.dataTask(with: request).resume()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, allowedURL(url) else {
            terminalError = UpdateError.unexpectedResponse
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard
            let http = response as? HTTPURLResponse,
            http.statusCode == 200,
            let finalURL = http.url,
            allowedURL(finalURL)
        else {
            terminalError = UpdateError.unexpectedResponse
            completionHandler(.cancel)
            return
        }

        if http.expectedContentLength > Int64(maximumBytes) {
            terminalError = UpdateError.responseTooLarge
            completionHandler(.cancel)
            return
        }

        self.response = http
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard receivedData.count + data.count <= maximumBytes else {
            terminalError = UpdateError.responseTooLarge
            dataTask.cancel()
            return
        }
        receivedData.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let terminalError {
            finish(.failure(terminalError))
        } else if let error {
            finish(.failure(error))
        } else if let response {
            finish(.success(HTTPPayload(data: receivedData, response: response)))
        } else {
            finish(.failure(UpdateError.unexpectedResponse))
        }
    }

    private func finish(_ result: Result<HTTPPayload, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        session?.finishTasksAndInvalidate()
        DispatchQueue.main.async { self.completion(result) }
    }
}

/// Downloads a release asset to a caller-created private destination. Redirects,
/// status, MIME type, declared size, streamed size, and final file size are all
/// checked before the file is returned to the updater.
private final class BoundedDownload: NSObject, URLSessionDownloadDelegate,
                                     URLSessionTaskDelegate {
    private let destination: URL
    private let maximumBytes: Int64
    private let expectedBytes: Int64
    private let allowedContentTypes: Set<String>
    private let allowedURL: (URL) -> Bool
    private let completion: (Result<URL, Error>) -> Void

    private var session: URLSession?
    private var downloadedURL: URL?
    private var terminalError: Error?
    private var hasCompleted = false

    init(destination: URL,
         maximumBytes: Int64,
         expectedBytes: Int64,
         allowedContentTypes: Set<String>,
         allowedURL: @escaping (URL) -> Bool,
         completion: @escaping (Result<URL, Error>) -> Void) {
        self.destination = destination
        self.maximumBytes = maximumBytes
        self.expectedBytes = expectedBytes
        self.allowedContentTypes = allowedContentTypes
        self.allowedURL = allowedURL
        self.completion = completion
    }

    func start(with url: URL) {
        guard allowedURL(url) else {
            finish(.failure(UpdateError.unexpectedResponse))
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        self.session = session
        session.downloadTask(with: url).resume()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, allowedURL(url) else {
            terminalError = UpdateError.unexpectedResponse
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > maximumBytes
            || totalBytesExpectedToWrite > maximumBytes {
            terminalError = UpdateError.responseTooLarge
            downloadTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            guard
                let response = downloadTask.response as? HTTPURLResponse,
                response.statusCode == 200,
                let finalURL = response.url,
                allowedURL(finalURL),
                allowedContentTypes.contains((response.mimeType ?? "").lowercased())
            else {
                throw UpdateError.unexpectedResponse
            }

            let values = try location.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            let size = Int64(values.fileSize ?? -1)
            guard values.isRegularFile == true,
                  size == expectedBytes,
                  size <= maximumBytes
            else {
                throw UpdateError.invalidDownload
            }

            try FileManager.default.moveItem(at: location, to: destination)
            downloadedURL = destination
        } catch {
            terminalError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let terminalError {
            finish(.failure(terminalError))
        } else if let error {
            finish(.failure(error))
        } else if let downloadedURL {
            finish(.success(downloadedURL))
        } else {
            finish(.failure(UpdateError.invalidDownload))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        session?.finishTasksAndInvalidate()
        DispatchQueue.main.async { self.completion(result) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    private var statusItem: NSStatusItem!
    private var idleWatcher: IdleWatcher!
    private var fullScreen: FullScreenWindow?
    private var prefsController: PreferencesWindowController?
    private var settings = Cyph3rfallSettings.load()
    private var updateAvailableVersion: String? = nil
    private var updateAsset:            UpdateAsset?
    private var isDownloadingUpdate             = false
    private var automaticUpdateRequest: BoundedDataRequest?
    private var manualUpdateRequest:    BoundedDataRequest?
    private var activeUpdateDownload:   BoundedDownload?
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
    /// Identity-bound timeout for the currently active authentication attempt.
    private var authTimeoutWorkItem: DispatchWorkItem?
    /// Fires every 5 s during a manually-started session to check whether the
    /// user's idle threshold has now been met, at which point lock arms itself.
    private var lockEligibilityTimer: Timer?

    // MARK: - Constants

    private static let idleTimeoutKey  = "idleTimeoutSeconds"
    private static let releasesPageURL = URL(string: "https://github.com/ikaazu/Cyph3rfall/releases/latest")!
    private static let githubReleaseAPIURL =
        URL(string: "https://api.github.com/repos/ikaazu/Cyph3rfall/releases/latest")!
    private static let expectedBundleIdentifier = "com.cyph3rfall.Cyph3rfall"
    private static let expectedTeamIdentifier   = "GHXKLLWQPM"
    private static let maximumReleaseResponseBytes = 1 * 1024 * 1024
    private static let maximumDMGBytes: Int64 = 512 * 1024 * 1024

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

        // ── Version ────────────────────────────────────────────────────
        let appVersion   = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let versionItem  = NSMenuItem(title: "Version \(appVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

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

        let checkItem = NSMenuItem(title: "Check for Updates…",
                                   action: #selector(checkForUpdatesManually),
                                   keyEquivalent: "")
        checkItem.target = self
        checkItem.image  = NSImage(systemSymbolName: "arrow.trianglehead.2.clockwise.rotate.90",
                                   accessibilityDescription: nil)
        menu.addItem(checkItem)

        menu.addItem(.separator())

        // ── Quit ───────────────────────────────────────────────────────
        let quitItem = NSMenuItem(title: "Quit Cyph3rfall",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    /// Manual update check triggered from the About tab in Settings.
    /// Shows feedback in both the update-found and up-to-date cases.
    @objc private func checkForUpdatesManually() {
        guard manualUpdateRequest == nil else { return }

        let request = makeReleaseRequest { [weak self] result in
            guard let self else { return }
            self.manualUpdateRequest = nil

            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let alert   = NSAlert()

            switch result {
            case .success(let release):
                if self.isNewerVersion(release.version, than: current) {
                    self.updateAvailableVersion = release.version
                    self.updateAsset            = release.asset
                    self.rebuildMenu()
                    alert.messageText     = "Update Available"
                    alert.informativeText = "Cyph3rfall \(release.version) is available."
                    alert.addButton(withTitle: release.asset != nil ? "Download & Install" : "View Release")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn {
                        release.asset != nil ? self.installUpdate() : self.openReleasePage()
                    }
                } else {
                    alert.messageText     = "You're Up to Date"
                    alert.informativeText = "Cyph3rfall \(current) is the latest version."
                    alert.runModal()
                }

            case .failure:
                alert.messageText     = "Update Check Failed"
                alert.informativeText = "The update server returned an invalid or unavailable response. Try again later."
                alert.alertStyle      = .warning
                alert.runModal()
            }
        }
        manualUpdateRequest = request
        request.start(with: Self.makeGitHubReleaseRequest())
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
            prefsController?.onCheckForUpdates = { [weak self] in
                self?.checkForUpdatesManually()
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
                self.authTimeoutWorkItem?.cancel()
                self.authTimeoutWorkItem = nil
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
        authTimeoutWorkItem?.cancel()
        isAuthenticating = true

        let context = LAContext()
        authContext = context

        // Safety valve: if evaluatePolicy's completion block never fires for any
        // reason (sleep interruption, system hiccup, etc.) reset after 90 s so
        // the user can try again rather than being permanently locked out.
        // Bind the timeout to this exact context so an older timeout cannot
        // invalidate a newer authentication attempt.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, context === self.authContext else { return }
            context.invalidate()
            self.authContext = nil
            self.isAuthenticating = false
            self.authTimeoutWorkItem = nil
        }
        authTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: timeout)
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authTimeoutWorkItem?.cancel()
            authTimeoutWorkItem = nil
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
                self.authTimeoutWorkItem?.cancel()
                self.authTimeoutWorkItem = nil
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
        let armForSleep = {
            if self.fullScreen == nil {
                self.showScreensaver(manual: false)
                return
            }

            // An already-visible manually started overlay may not have reached
            // its idle threshold yet. Sleep is itself a lock-triggering event,
            // so arm it immediately instead of letting showScreensaver's
            // existing-window guard preserve the unlocked state.
            self.lockEligibilityTimer?.invalidate()
            self.lockEligibilityTimer = nil
            self.lockActive = self.settings.requirePassword
            self.authTimeoutWorkItem?.cancel()
            self.authTimeoutWorkItem = nil
            self.authContext?.invalidate()
            self.authContext = nil
            self.isAuthenticating = false
        }

        if Thread.isMainThread {
            armForSleep()
        } else {
            DispatchQueue.main.sync(execute: armForSleep)
        }
    }

    @objc private func systemDidWake(_ notification: Notification) {
        DispatchQueue.main.async {
            // Any LAContext created before sleep is now invalid — its completion
            // block will never fire. Invalidate and reset unconditionally so the
            // user is never permanently blocked from dismissing the screensaver.
            self.authTimeoutWorkItem?.cancel()
            self.authTimeoutWorkItem = nil
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
        var req = URLRequest(url: githubReleaseAPIURL,
                             cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28",                  forHTTPHeaderField: "X-GitHub-Api-Version")
        return req
    }

    /// Strips the leading "v" from a GitHub tag name (e.g. "v1.1" → "1.1").
    private static func stripVersionTag(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private func checkForUpdates() {
        guard automaticUpdateRequest == nil else { return }

        let request = makeReleaseRequest { [weak self] result in
            guard let self else { return }
            self.automaticUpdateRequest = nil
            guard case .success(let release) = result else { return }

            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            guard self.isNewerVersion(release.version, than: current) else { return }

            self.updateAvailableVersion = release.version
            self.updateAsset            = release.asset
            self.rebuildMenu()
        }
        automaticUpdateRequest = request
        request.start(with: Self.makeGitHubReleaseRequest())
    }

    private func makeReleaseRequest(
        completion: @escaping (Result<ReleaseMetadata, Error>) -> Void
    ) -> BoundedDataRequest {
        BoundedDataRequest(
            maximumBytes: Self.maximumReleaseResponseBytes,
            allowedURL: Self.isAllowedUpdateNetworkURL
        ) { result in
            completion(result.flatMap { payload in
                Result { try Self.parseReleaseMetadata(payload) }
            })
        }
    }

    private static func parseReleaseMetadata(_ payload: HTTPPayload) throws -> ReleaseMetadata {
        guard payload.response.url == githubReleaseAPIURL else {
            throw UpdateError.unexpectedResponse
        }
        guard
            let raw = try? JSONSerialization.jsonObject(with: payload.data),
            let json = raw as? [String: Any],
            let tagName = json["tag_name"] as? String
        else {
            throw UpdateError.invalidMetadata
        }

        let version = stripVersionTag(tagName)
        guard version.range(
            of: #"^\d+(?:\.\d+){1,3}$"#,
            options: .regularExpression
        ) != nil else {
            throw UpdateError.invalidMetadata
        }

        let expectedName = "Cyph3rfall-v\(version).dmg"
        let allowedContentTypes = [
            "application/octet-stream",
            "application/x-apple-diskimage",
        ]
        let assets = json["assets"] as? [[String: Any]] ?? []

        let asset = assets.compactMap { item -> UpdateAsset? in
            guard
                item["name"] as? String == expectedName,
                let urlString = item["browser_download_url"] as? String,
                let url = URL(string: urlString),
                isExpectedGitHubAssetURL(url),
                let sizeNumber = item["size"] as? NSNumber
            else { return nil }

            let size = sizeNumber.int64Value
            guard size > 0, size <= maximumDMGBytes else { return nil }

            let contentType = (item["content_type"] as? String ?? "").lowercased()
            guard allowedContentTypes.contains(contentType) else { return nil }

            let digest: String?
            if let rawDigest = item["digest"] as? String {
                guard let normalized = normalizedSHA256Digest(rawDigest) else { return nil }
                digest = normalized
            } else {
                digest = nil
            }

            return UpdateAsset(
                url: url,
                expectedBytes: size,
                sha256: digest,
                allowedContentTypes: Set(allowedContentTypes)
            )
        }.first

        return ReleaseMetadata(version: version, asset: asset)
    }

    private static func normalizedSHA256Digest(_ value: String) -> String? {
        let lower = value.lowercased()
        guard lower.hasPrefix("sha256:") else { return nil }
        let digest = String(lower.dropFirst("sha256:".count))
        guard digest.count == 64,
              digest.allSatisfy({ $0.isHexDigit })
        else { return nil }
        return digest
    }

    private static func isExpectedGitHubAssetURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.port == nil
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/ikaazu/Cyph3rfall/releases/download/")
    }

    private static func isAllowedUpdateNetworkURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.port == nil,
              let host = url.host?.lowercased()
        else { return false }

        switch host {
        case "api.github.com":
            return url.path == githubReleaseAPIURL.path
        case "github.com":
            return url.path.hasPrefix("/ikaazu/Cyph3rfall/releases/download/")
        case "release-assets.githubusercontent.com",
             "objects.githubusercontent.com",
             "github-releases.githubusercontent.com":
            return true
        default:
            return false
        }
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
        guard let asset = updateAsset,
              let version = updateAvailableVersion,
              !isDownloadingUpdate,
              activeUpdateDownload == nil
        else {
            if updateAsset == nil { openReleasePage() }
            return
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cyph3rfall-update-\(UUID().uuidString)", isDirectory: true)
        let tempDMG = root.appendingPathComponent("update.dmg")
        do {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            showUpdateError("Could not create a private update staging directory.")
            return
        }

        isDownloadingUpdate = true
        rebuildMenu()

        let download = BoundedDownload(
            destination: tempDMG,
            maximumBytes: Self.maximumDMGBytes,
            expectedBytes: asset.expectedBytes,
            allowedContentTypes: asset.allowedContentTypes,
            allowedURL: Self.isAllowedUpdateNetworkURL
        ) { [weak self] result in
            guard let self else { return }
            self.activeUpdateDownload = nil
            self.isDownloadingUpdate = false
            self.rebuildMenu()

            switch result {
            case .failure:
                try? FileManager.default.removeItem(at: root)
                self.showUpdateError("The update download failed validation or exceeded the allowed size.")

            case .success(let downloadedURL):
                self.verifyDownloadedUpdate(
                    downloadedURL,
                    root: root,
                    version: version,
                    asset: asset
                )
            }
        }
        activeUpdateDownload = download
        download.start(with: asset.url)
    }

    private func verifyDownloadedUpdate(
        _ url: URL,
        root: URL,
        version: String,
        asset: UpdateAsset
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true,
                      Int64(values.fileSize ?? -1) == asset.expectedBytes
                else { throw UpdateError.invalidDownload }

                if let expectedDigest = asset.sha256 {
                    let actualDigest = try Self.sha256Digest(of: url)
                    guard actualDigest == expectedDigest else {
                        throw UpdateError.invalidDownload
                    }
                }

                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText     = "Update Ready"
                    alert.informativeText = "Cyph3rfall \(version) has been downloaded and its release metadata validated. Click Install & Restart to verify its signature and install it."
                    alert.addButton(withTitle: "Install & Restart")
                    alert.addButton(withTitle: "Later")
                    guard alert.runModal() == .alertFirstButtonReturn else {
                        try? FileManager.default.removeItem(at: root)
                        return
                    }

                    DispatchQueue.global(qos: .userInitiated).async {
                        self.installDownloadedUpdate(
                            dmgURL: url,
                            root: root,
                            expectedVersion: version
                        )
                    }
                }
            } catch {
                try? FileManager.default.removeItem(at: root)
                DispatchQueue.main.async {
                    self.showUpdateError("The downloaded update did not match its release metadata.")
                }
            }
        }
    }

    private func installDownloadedUpdate(
        dmgURL: URL,
        root: URL,
        expectedVersion: String
    ) {
        let mount = root.appendingPathComponent("mount", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: mount,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            try? FileManager.default.removeItem(at: root)
            DispatchQueue.main.async {
                self.showUpdateError("Could not create a private mount point for the update.")
            }
            return
        }

        let attach = runProcess(
            "/usr/bin/hdiutil",
            ["attach", dmgURL.path,
             "-mountpoint", mount.path,
             "-readonly", "-nobrowse", "-quiet"]
        )
        guard attach.status == 0 else {
            try? FileManager.default.removeItem(at: root)
            DispatchQueue.main.async {
                self.showUpdateError("Could not mount the update disk image.")
            }
            return
        }

        defer {
            _ = runProcess("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
            try? FileManager.default.removeItem(at: root)
        }

        do {
            let candidate = try validatedMountedApplication(
                in: mount,
                expectedVersion: expectedVersion
            )
            try replaceInstalledApplication(
                with: candidate,
                expectedVersion: expectedVersion
            )
            DispatchQueue.main.async { self.relaunchApp() }
        } catch {
            DispatchQueue.main.async {
                self.showUpdateError(error.localizedDescription)
            }
        }
    }

    private func validatedMountedApplication(
        in mount: URL,
        expectedVersion: String
    ) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: mount,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let apps = contents.filter { $0.pathExtension.lowercased() == "app" }
        guard apps.count == 1, apps[0].lastPathComponent == "Cyph3rfall.app" else {
            throw UpdateError.validationFailed("The disk image does not contain exactly one expected application.")
        }

        let candidate = apps[0].standardizedFileURL
        let values = try candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw UpdateError.validationFailed("The application in the disk image is not a regular app bundle.")
        }

        let resolvedMount = mount.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedCandidate.path.hasPrefix(resolvedMount.path + "/") else {
            throw UpdateError.validationFailed("The application path escapes the mounted disk image.")
        }

        try validateApplication(candidate, expectedVersion: expectedVersion)
        return candidate
    }

    private func validateApplication(_ appURL: URL, expectedVersion: String) throws {
        guard
            let bundle = Bundle(url: appURL),
            bundle.bundleIdentifier == Self.expectedBundleIdentifier,
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion
        else {
            throw UpdateError.validationFailed("The update has an unexpected bundle identifier or version.")
        }

        let signature = runProcess(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", "--verbose=2", appURL.path]
        )
        guard signature.status == 0 else {
            throw UpdateError.validationFailed("The update's code signature is invalid.")
        }

        let details = runProcess(
            "/usr/bin/codesign",
            ["-d", "--verbose=4", appURL.path]
        )
        let expectedTeamLine = "TeamIdentifier=\(Self.expectedTeamIdentifier)"
        guard details.status == 0,
              details.output.split(whereSeparator: { $0.isNewline })
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .contains(expectedTeamLine),
              details.output.contains("(runtime)")
        else {
            throw UpdateError.validationFailed("The update is not signed by the expected team with hardened runtime.")
        }

        let gatekeeper = runProcess(
            "/usr/sbin/spctl",
            ["--assess", "--type", "execute", "--verbose=2", appURL.path]
        )
        guard gatekeeper.status == 0 else {
            throw UpdateError.validationFailed("Gatekeeper did not accept the update as notarized software.")
        }
    }

    private func replaceInstalledApplication(
        with candidate: URL,
        expectedVersion: String
    ) throws {
        let fileManager = FileManager.default
        let destination = URL(fileURLWithPath: Bundle.main.bundlePath).standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        let token = UUID().uuidString
        let staged = parent.appendingPathComponent(".Cyph3rfall-update-\(token).app")
        let backupName = ".Cyph3rfall-backup-\(token).app"
        let backup = parent.appendingPathComponent(backupName)

        guard runProcess("/usr/bin/ditto", [candidate.path, staged.path]).status == 0 else {
            try? fileManager.removeItem(at: staged)
            throw UpdateError.validationFailed("Could not stage the update beside the installed application.")
        }

        do {
            try validateApplication(staged, expectedVersion: expectedVersion)
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: staged,
                backupItemName: backupName,
                options: []
            )
            try? fileManager.removeItem(at: backup)
        } catch {
            if !fileManager.fileExists(atPath: destination.path),
               fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            try? fileManager.removeItem(at: staged)
            throw UpdateError.validationFailed(
                "Could not replace the installed application safely. The existing installation was preserved when possible."
            )
        }
    }

    private static func sha256Digest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func relaunchApp() {
        let appURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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

    private func runProcess(_ path: String, _ args: [String]) -> ProcessResult {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments     = args
        task.standardOutput = output
        task.standardError  = output
        do {
            try task.run()
        } catch {
            return ProcessResult(status: -1, output: error.localizedDescription)
        }
        task.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            status: task.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
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
