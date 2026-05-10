import ScreenSaver

/// ScreenSaverView subclass that wraps MatrixRainView.
///
/// macOS screensaver lifecycle notes:
/// ─────────────────────────────────
/// • The framework instantiates one MatrixRainSaverView per screen.
/// • startAnimation() / stopAnimation() must be idempotent.
/// • animateOneFrame() is our heartbeat; we tick MatrixRainView from here
///   rather than running a second timer inside the view.
///
/// macOS 26 note — configureSheet:
/// ─────────────────────────────────
/// In macOS 26, legacy screensaver bundles run inside legacyScreenSaver.appex,
/// a separate process from the Wallpaper/System Settings process that owns the
/// "Screen Saver Options…" button. The XPC bridge that should relay configureSheet
/// across that process boundary is not functional for third-party bundles.
/// Settings are therefore written by MatrixRainTestApp into the installed .saver
/// bundle's Resources folder (settings.plist), which this extension always has
/// unconditional read access to via Bundle(for: MatrixRainSaverView.self).
final class MatrixRainSaverView: ScreenSaverView {

    private var rainView: MatrixRainView!

    // MARK: - Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup(preview: isPreview)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(preview: false)
    }

    private func setup(preview: Bool) {
        animationTimeInterval = 1.0 / 60.0

        rainView = MatrixRainView(frame: bounds)
        rainView.autoresizingMask = [.width, .height]

        let bundle = Bundle(for: MatrixRainSaverView.self)
        var settings = MatrixRainSettings.load(from: bundle)

        if preview {
            settings.glyphSize   = 9
            settings.trailLength = 10
        }

        rainView.settings = settings
        addSubview(rainView)
    }

    // MARK: - ScreenSaverView lifecycle

    override func startAnimation() {
        super.startAnimation()
        // Reload settings each time the screensaver activates so changes
        // made in the test app take effect without restarting.
        let bundle = Bundle(for: MatrixRainSaverView.self)
        rainView.settings = MatrixRainSettings.load(from: bundle)
        rainView.startExternalAnimation()
    }

    override func stopAnimation() {
        super.stopAnimation()
        rainView.stopExternalAnimation()
    }

    override func animateOneFrame() {
        rainView.externalTick()
    }

    override func draw(_ rect: NSRect) { }

    // configureSheet does not work on macOS 26; see comment above.
    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
