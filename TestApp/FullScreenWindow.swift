import AppKit

// Borderless NSWindow returns NO from canBecomeKeyWindow by default,
// which produces a console warning when makeKeyAndOrderFront is called.
// This subclass opts in explicitly so event monitors work correctly.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Covers every attached screen with a borderless Matrix Rain window.
/// Dismisses on the first mouse move, click, or key press after a short
/// settle delay (to avoid the activation event triggering instant dismissal).
final class FullScreenWindow {

    // Expose the primary rain view so AppDelegate can push settings updates.
    private(set) var primaryRainView: MatrixRainView?

    private var windows: [NSWindow] = []
    private var localMonitor:  Any?
    private var globalMonitor: Any?
    private let onDismiss: () -> Void
    private var settleWorkItem: DispatchWorkItem?

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    // MARK: - Public

    func show(settings: MatrixRainSettings) {
        guard windows.isEmpty else { return }

        for (index, screen) in NSScreen.screens.enumerated() {
            let win = makeWindow(for: screen, settings: settings, isPrimary: index == 0)
            windows.append(win)
        }

        NSCursor.hide()
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)

        // Wait briefly before arming dismiss monitors so the
        // mouse-moved event from activation doesn't fire immediately.
        let item = DispatchWorkItem { [weak self] in self?.armMonitors() }
        settleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func dismiss() {
        settleWorkItem?.cancel()
        settleWorkItem = nil

        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        localMonitor  = nil
        globalMonitor = nil

        for win in windows {
            (win.contentView?.subviews.first as? MatrixRainView)?.stopAnimation()
            win.orderOut(nil)
        }
        windows.removeAll()
        primaryRainView = nil

        NSCursor.unhide()
        onDismiss()
    }

    // MARK: - Private

    private func makeWindow(for screen: NSScreen,
                            settings: MatrixRainSettings,
                            isPrimary: Bool) -> NSWindow {
        let win = KeyableWindow(
            contentRect: screen.frame,
            styleMask:   .borderless,
            backing:     .buffered,
            defer:       false
        )
        win.level                = .screenSaver
        win.backgroundColor      = .black
        win.isOpaque             = true
        win.ignoresMouseEvents   = false
        win.collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.setFrame(screen.frame, display: false)

        let rainView = MatrixRainView(frame: win.contentView!.bounds)
        rainView.autoresizingMask = [.width, .height]
        rainView.settings = settings
        win.contentView?.addSubview(rainView)
        rainView.startAnimation()

        if isPrimary { primaryRainView = rainView }

        win.makeKeyAndOrderFront(nil)
        return win
    }

    private func armMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .mouseMoved, .scrollWheel
        ]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.dismiss()
            return nil   // swallow the event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.dismiss()
        }
    }
}
