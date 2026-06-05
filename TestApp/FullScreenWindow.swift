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
    private(set) var primaryRainView: Cyph3rfallView?

    // All rain views across every screen — used to stop animation reliably.
    private var rainViews: [Cyph3rfallView] = []

    private var windows: [NSWindow] = []
    private var localMonitor:  Any?
    private var globalMonitor: Any?
    /// Called when user input is detected — AppDelegate decides whether to
    /// authenticate or dismiss immediately.
    private let onDismissRequested: () -> Void
    /// Called after the windows are actually torn down.
    private let onDismiss: () -> Void
    private var settleWorkItem: DispatchWorkItem?

    init(onDismissRequested: @escaping () -> Void,
         onDismiss: @escaping () -> Void) {
        self.onDismissRequested = onDismissRequested
        self.onDismiss          = onDismiss
    }

    // MARK: - Public

    func show(settings: Cyph3rfallSettings) {
        guard windows.isEmpty else { return }

        for (index, screen) in NSScreen.screens.enumerated() {
            let win = makeWindow(for: screen, settings: settings, isPrimary: index == 0)
            win.alphaValue = 0          // start invisible; fade-in reveals the rain
            windows.append(win)
        }

        NSCursor.hide()
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)

        // Fade in over 1.5 s — the desktop shows through the transparent window
        // and the rain materialises from it.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration        = 1.5
            ctx.timingFunction  = CAMediaTimingFunction(name: .easeInEaseOut)
            for win in windows { win.animator().alphaValue = 1.0 }
        }

        // Arm dismiss monitors after a short settle so the activation event
        // doesn't trigger an instant dismissal.
        let item = DispatchWorkItem { [weak self] in self?.armMonitors() }
        settleWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func dismiss() {
        settleWorkItem?.cancel()
        settleWorkItem = nil

        // Remove monitors immediately — no more dismiss requests during the fade.
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        localMonitor  = nil
        globalMonitor = nil

        // Stop all CVDisplayLinks immediately — don't wait for the fade completion
        // handler, which can be skipped if self is released before it fires.
        // The rain freezing during the 0.8 s fade is invisible since the window
        // is fading to transparent.
        rainViews.forEach { $0.stopAnimation() }
        rainViews.removeAll()
        primaryRainView = nil

        // Fade out, then tear down windows in the completion handler.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration       = 0.8
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for win in windows { win.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            guard let self else { return }
            for win in self.windows { win.orderOut(nil) }
            self.windows.removeAll()
            NSCursor.unhide()
            self.onDismiss()
        })
    }

    // MARK: - Private

    private func makeWindow(for screen: NSScreen,
                            settings: Cyph3rfallSettings,
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

        guard let contentView = win.contentView else { return win }
        let rainView = Cyph3rfallView(frame: contentView.bounds)
        rainView.autoresizingMask = [.width, .height]
        rainView.settings = settings
        contentView.addSubview(rainView)
        rainView.startAnimation()

        if isPrimary {
            primaryRainView = rainView
            rainView.isPrimaryDisplay = true
        }
        rainViews.append(rainView)

        win.makeKeyAndOrderFront(nil)
        return win
    }

    private func armMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .mouseMoved, .scrollWheel
        ]

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.onDismissRequested()
            return nil   // swallow the event so it doesn't leak to the desktop
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.onDismissRequested()
        }
    }
}
