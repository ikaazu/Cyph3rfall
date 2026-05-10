import AppKit

/// NSView that renders the Matrix rain animation.
///
/// Supports two driver modes:
///   - **Internal** (test app): owns a CVDisplayLink.
///   - **External** (screensaver): caller invokes externalTick() each frame.
///
/// isFlipped = true so that y=0 is the top and y increases downward,
/// matching the natural direction of the falling rain.
final class MatrixRainView: NSView {

    var settings = MatrixRainSettings.default {
        didSet { rebuild() }
    }

    private var columns: [GlyphColumn] = []
    private var lastTickTime: CFTimeInterval = 0
    private var displayLink: CVDisplayLink?
    private(set) var isAnimating = false

    private var glyphFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    // MARK: - NSView

    override var isFlipped: Bool { true }
    override var isOpaque: Bool  { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds   = true   // prevent glyphs drawing outside the view bounds
    }

    override func layout() {
        super.layout()
        rebuild()
    }

    // MARK: - Public API (test app)

    func startAnimation() {
        guard !isAnimating else { return }
        isAnimating  = true
        lastTickTime = 0
        rebuild()
        startDisplayLink()
    }

    func stopAnimation() {
        guard isAnimating else { return }
        isAnimating = false
        stopDisplayLink()
    }

    // MARK: - Public API (screensaver)

    func startExternalAnimation() {
        guard !isAnimating else { return }
        isAnimating  = true
        lastTickTime = 0
        rebuild()
    }

    func externalTick() {
        guard isAnimating else { return }
        tick(at: CACurrentMediaTime())
    }

    func stopExternalAnimation() {
        isAnimating = false
    }

    // MARK: - Display link

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        displayLink = link

        CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, _, _, _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isAnimating else { return }
                self.tick(at: CACurrentMediaTime())
            }
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        if let link = displayLink { CVDisplayLinkStop(link) }
        displayLink = nil
    }

    // MARK: - Animation core

    private func tick(at time: CFTimeInterval) {
        let dt: Double = lastTickTime == 0 ? 1.0 / 60.0 : min(time - lastTickTime, 0.1)
        lastTickTime = time

        for col in columns {
            col.update(dt: dt)
            if col.isOffScreen { col.reset(settings: settings) }
        }
        needsDisplay = true
    }

    // MARK: - Column management

    private func rebuild() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let cell = settings.glyphSize
        glyphFont = .monospacedSystemFont(ofSize: cell * 0.85, weight: .regular)

        // Classic dense mode overrides density and trail length.
        let effectiveDensity     = settings.classicDenseMode ? 1.0 : max(0.01, min(1.0, settings.density))
        let effectiveTrailLength = settings.classicDenseMode ? min(settings.trailLength, 12) : settings.trailLength

        var effectiveSettings = settings
        effectiveSettings.density     = effectiveDensity
        effectiveSettings.trailLength = effectiveTrailLength
        if settings.classicDenseMode {
            effectiveSettings.speedMultiplier = max(settings.speedMultiplier, 1.5)
        }

        // Density 0…1 = probability that a slot gets ONE stream.
        // Density >1  = every slot gets floor(density) streams, with the
        //               fractional remainder as the probability of one extra.
        //               e.g. 1.6 → always 1 stream + 60 % chance of a 2nd.
        let totalSlots = max(1, Int(size.width / cell))
        let guaranteed = Int(effectiveDensity)              // streams always added
        let extraProb  = effectiveDensity - Double(guaranteed) // chance of +1 more

        columns = (0 ..< totalSlots).flatMap { i -> [GlyphColumn] in
            let x = CGFloat(i) * cell
            var streams: [GlyphColumn] = []
            for _ in 0 ..< guaranteed {
                streams.append(GlyphColumn(columnIndex: i, x: x,
                                           viewHeight: size.height, cellSize: cell,
                                           settings: effectiveSettings))
            }
            if Double.random(in: 0 ... 1) < extraProb {
                streams.append(GlyphColumn(columnIndex: i, x: x,
                                           viewHeight: size.height, cellSize: cell,
                                           settings: effectiveSettings))
            }
            return streams
        }
        lastTickTime = 0
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(settings.backgroundColor.cgColor)
        ctx.fill(bounds)

        let cell = settings.glyphSize
        let base = settings.foregroundColor
        let head = settings.headColor

        for col in columns {
            drawColumn(col, ctx: ctx, cell: cell, base: base, headColor: head)
        }
    }

    private func drawColumn(_ col: GlyphColumn,
                            ctx: CGContext,
                            cell: CGFloat,
                            base: NSColor,
                            headColor: NSColor) {

        let viewH = bounds.height
        let count = col.glyphs.count

        for i in 0 ..< count {
            let glyphTop = col.headY - CGFloat(i) * cell
            guard glyphTop + cell > 0 && glyphTop < viewH else { continue }

            let isHead = (i == 0)

            // Base alpha: quadratic fade from head toward tail.
            let baseAlpha: CGFloat = isHead ? 1.0 : max(0, pow(1.0 - CGFloat(i) / CGFloat(count), 2))

            // Apply per-slot brightness jitter (clamp so alpha stays in 0…1).
            let jitter = i < col.brightnessJitter.count ? col.brightnessJitter[i] : 1.0
            let alpha   = min(1.0, baseAlpha * jitter)

            let color: NSColor
            if isHead && col.flashTimer > 0 {
                // White-hot flash — pure white regardless of colour preset.
                color = .white
            } else if isHead {
                color = headColor
            } else {
                color = base.withAlphaComponent(alpha)
            }

            let rect = CGRect(x: col.x, y: glyphTop, width: cell, height: cell)

            if settings.showGlow && isHead {
                ctx.saveGState()
                let glowColor = (col.flashTimer > 0 ? NSColor.white : base).withAlphaComponent(0.8).cgColor
                ctx.setShadow(offset: .zero, blur: 10, color: glowColor)
                drawGlyph(col.glyphs[i], in: rect, color: color)
                ctx.restoreGState()
            } else {
                drawGlyph(col.glyphs[i], in: rect, color: color)
            }
        }
    }

    private func drawGlyph(_ char: Character, in rect: CGRect, color: NSColor) {
        NSAttributedString(string: String(char), attributes: [
            .font: glyphFont,
            .foregroundColor: color
        ]).draw(in: rect)
    }
}
