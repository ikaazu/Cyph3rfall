import AppKit

/// NSView that renders the Matrix rain animation.
///
/// Supports two driver modes:
///   - **Internal** (test app): owns a CVDisplayLink.
///   - **External** (screensaver): caller invokes externalTick() each frame.
///
/// isFlipped = true so that y=0 is the top and y increases downward,
/// matching the natural direction of the falling rain.
final class Cyph3rfallView: NSView {

    /// Set to true on the primary display's view so overlays (clock, message)
    /// are suppressed on secondary displays when primaryDisplayOnly is enabled.
    var isPrimaryDisplay: Bool = false

    var settings = Cyph3rfallSettings.default {
        didSet {
            // Fresh enable of Spectrafall: seed the cycle phase from the
            // currently selected preset so the drift starts from the colour
            // already on screen instead of jumping to red.
            if settings.spectrafallEnabled && !oldValue.spectrafallEnabled {
                let path = Cyph3rfallSettings.spectraCyclePath
                let idx  = path.firstIndex(of: settings.colorPreset)
                       ?? path.firstIndex(of: .matrixGreen) ?? 0
                spectraPhase     = Double(idx)
                lastSpectraQuant = -1   // force a colour refresh in rebuild()
            }
            lastBuiltSize = .zero   // ensure layout()'s size guard doesn't skip the rebuild
            rebuild()
        }
    }

    /// Multiplier on Spectrafall cycle advancement. The settings preview sets
    /// this above 1 so the colour drift is visible while configuring; the
    /// full-screen views leave it at 1.
    var spectraTimeScale: Double = 1.0

    // ── Spectrafall cycle state ──────────────────────────────────────────────
    // spectraPhase ∈ [0, pathCount): fractional position along spectraCyclePath.
    // The phase is quantized into discrete steps; atlas re-rendering happens
    // only when the quantized step advances, keeping the per-frame draw path
    // identical to the static-preset case.
    private var spectraPhase:     Double = 0
    private var lastSpectraQuant: Int    = -1
    private var spectraStream:    StreamColor?
    private static let spectraStepsPerSegment = 32

    private var columns:      [GlyphColumn] = []
    private var columnStep:   CGFloat       = 0   // horizontal distance between columns (< glyphSize)
    private var columnOffset: CGFloat       = 0   // left margin so column grid is centred on screen
    private var lastTickTime: CFTimeInterval = 0

    // Frame rate cap — physics ticks every display link callback, but the view
    // only redraws at this rate. 60 fps divides evenly into 60 Hz and 120 Hz
    // displays; 30 fps caused uneven frame pacing on high-refresh monitors.
    private var lastRenderTime:      CFTimeInterval = 0
    private let targetFrameInterval: CFTimeInterval = 1.0 / 60.0

    // Per-stream colours — one entry per element in `columns`, refreshed each
    // time a stream resets off the bottom of the screen.
    private struct StreamColor {
        let fg:          NSColor
        let head:        NSColor
        let fgCG:        CGColor   // pre-computed — avoids .cgColor per glyph
        let headCG:      CGColor
        let glowCG:      CGColor   // fg at 0.8 alpha, ready for setShadow
        let fgColorID:   Int       // atlas key: preset.rawValue * 2
        let headColorID: Int       // atlas key: preset.rawValue * 2 + 1

        init(preset: Cyph3rfallSettings.ColorPreset) {
            fg          = preset.foregroundColor
            head        = preset.headColor
            fgCG        = fg.cgColor
            headCG      = head.cgColor
            glowCG      = fg.withAlphaComponent(0.8).cgColor
            fgColorID   = preset.rawValue * 2
            headColorID = preset.rawValue * 2 + 1
        }

        /// Explicit-colour init for the Spectrafall cycle, where the colours
        /// are blended between presets rather than taken from one.
        init(fg: NSColor, head: NSColor, fgColorID: Int, headColorID: Int) {
            self.fg          = fg
            self.head        = head
            self.fgCG        = fg.cgColor
            self.headCG      = head.cgColor
            self.glowCG      = fg.withAlphaComponent(0.8).cgColor
            self.fgColorID   = fgColorID
            self.headColorID = headColorID
        }
    }
    private var columnColors: [StreamColor] = []

    // Glyph atlas — pre-rendered (char, colorID) → NSImage bitmaps.
    // Turns Core Text layout calls into bitmap blits in the draw loop.
    private let glyphAtlas = GlyphAtlas()

    // Custom message overlay — each character has its own fade state.
    private struct MessageChar {
        let char:        Character
        let x:           CGFloat   // centre X of the character cell
        let y:           CGFloat   // centre Y (target row, 2/3 down)
        let columnIndex: Int       // which column slot lights this char (pre-computed)
        var alpha:       CGFloat   // current opacity, 0–1
    }
    private var messageChars:      [MessageChar] = []
    // Maps column-slot index → index into messageChars. Built once in
    // rebuildMessageChars(); lets updateMessageChars() do a single O(1)
    // dict lookup per column instead of scanning all chars per column.
    private var charByColumnIndex: [Int: Int]    = [:]
    // Reused every frame to avoid a Set<Int> heap allocation.
    private var litFlags:          [Bool]        = []

    // Message display cycle:
    //   building  → characters light up as rain columns pass through them.
    //               Each char stays at alpha = 1 once triggered (no per-char decay).
    //   fadingOut → all chars were shown; the whole message fades as a group.
    //   cooldown  → message is gone; wait before starting the next cycle.
    private enum MessagePhase { case building, fadingOut, cooldown }
    private var messagePhase:    MessagePhase = .building
    private var messageCooldown: Double       = 0   // seconds remaining in cooldown
    private var charHasBeenLit:  [Bool]       = []  // set permanently once a char hits alpha=1

    private static let messageFadeOutRate:      CGFloat = 0.35  // ~3 s to fully fade
    private static let messageCooldownDuration: Double  = 8     // seconds before restart

    // Clock overlay — font size nudges ±1 pt once per minute to prevent burn-in
    // without moving the clock off-centre relative to the message.
    private var clockFontSizeOffset: CGFloat = 0
    private var lastClockMinute: Int = -1

    // Clock overlay — formatters are created once and reused every frame.
    private lazy var clockTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short    // respects the user's 12 / 24-hour system pref
        f.dateStyle = .none
        return f
    }()
    private lazy var clockDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full     // e.g. "Thursday, May 15, 2026"
        f.timeStyle = .none
        return f
    }()
    // Cache so we only re-format once per second rather than every frame.
    private var lastClockSecond: Int = -1
    private var cachedTimeString: String = ""
    private var cachedDateString: String = ""
    private var displayLink: CVDisplayLink?
    private(set) var isAnimating = false

    private var glyphFont: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    // ── Per-rebuild caches — avoids repeated allocations in the draw loop ────
    // Updated at the end of rebuild() whenever settings or geometry change.
    private var lastBuiltSize:           CGSize  = .zero
    private var cachedBackgroundCGColor: CGColor = NSColor.black.cgColor
    // Non-nil only when Chromafall is off; draw() falls back to creating one
    // on-the-fly only in the (rare) case where it's still nil.
    private var cachedDefaultStream:     StreamColor?
    // Pre-computed glow colour for the message overlay (settings.foregroundColor @ 70 %).
    private var cachedMessageGlowCG:     CGColor = NSColor.clear.cgColor

    // Clock caches — font lookup by name is expensive; cache the NSFont objects
    // and invalidate only when the relevant settings change.
    private var cachedClockFont:      NSFont  = .systemFont(ofSize: 80,   weight: .thin)
    private var cachedClockDateFont:  NSFont  = .systemFont(ofSize: 25.6, weight: .thin)
    private var cachedClockGlowCG:    CGColor = NSColor.clear.cgColor
    private var cachedClockTextColor: NSColor = .white
    private var cachedClockDateColor: NSColor = .gray
    // Per-second attributed-string cache — also invalidated by any settings change.
    private var cachedTimeAttr: NSAttributedString?
    private var cachedDateAttr: NSAttributedString?

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
        // Guard against redundant rebuilds during window-resize animations —
        // rebuild() tears down and recreates every column, so only do it when
        // the geometry has actually changed.
        let sz = bounds.size
        guard sz != lastBuiltSize else { return }
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

        for (i, col) in columns.enumerated() {
            col.update(dt: dt)
            if col.isOffScreen {
                col.reset(settings: settings)
                if !columnColors.isEmpty {
                    columnColors[i] = Self.randomStreamColor()
                }
            }
        }

        // Light up custom message characters as column heads pass through them.
        if !messageChars.isEmpty {
            updateMessageChars(dt: dt)
        }

        // Advance the Spectrafall colour cycle. Atlas work happens only when
        // the quantized step changes (~every 0.5–2 s depending on speed).
        if settings.spectrafallEnabled {
            advanceSpectraCycle(dt: dt)
        }


        // Only trigger a redraw when enough time has elapsed — caps render rate
        // at 30 fps regardless of the display link's native refresh rate.
        if time - lastRenderTime >= targetFrameInterval {
            lastRenderTime = time
            needsDisplay = true
        }
    }

    // MARK: - Column management

    private func rebuild() {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let cell = settings.glyphSize
        // Column step — Wide uses full cell width, Narrow uses 75 % for a
        // tighter look without the characters overlapping or being clipped.
        let spacingOptions    = Cyph3rfallSettings.columnSpacingOptions
        let spacingIdx        = max(0, min(settings.columnSpacingIndex, spacingOptions.count - 1))
        let spacingMultiplier = spacingOptions[spacingIdx].multiplier
        let colStep = ceil(cell * spacingMultiplier)
        columnStep = colStep
        glyphFont = .monospacedSystemFont(ofSize: cell * 0.85, weight: .regular)

        // Configure atlas for new cell size / font; invalidate on any other
        // settings change (colour preset, etc.) so stale images don't linger.
        // Then prewarm upfront so no lazy rendering happens during draw().
        glyphAtlas.configure(cellSize: cell, font: glyphFont)
        glyphAtlas.invalidate()
        let presetsToWarm: [Cyph3rfallSettings.ColorPreset] = settings.colorZonesEnabled
            ? Cyph3rfallSettings.ColorPreset.allCases
            : [settings.colorPreset]
        glyphAtlas.prewarm(presets: presetsToWarm, glyphs: matrixGlyphPool)

        // Classic dense mode overrides density and trail length.
        let effectiveDensity     = settings.classicDenseMode ? 1.0 : max(0.01, settings.density)
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
        let totalSlots = max(1, Int(size.width / colStep))
        let guaranteed = Int(effectiveDensity)              // streams always added
        let extraProb  = effectiveDensity - Double(guaranteed) // chance of +1 more

        columnOffset = (size.width - CGFloat(totalSlots) * colStep) / 2.0
        rebuildMessageChars()

        columns = (0 ..< totalSlots).flatMap { i -> [GlyphColumn] in
            let x = columnOffset + CGFloat(i) * colStep
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

        // Must be called after columns is built — sizes columnColors to match.
        rebuildColumnColors()
        lastTickTime = 0

        // ── Refresh per-frame caches ─────────────────────────────────────────
        // These values are read every frame in draw(); computing them once here
        // (on settings/geometry change) avoids repeated allocations in the hot path.

        cachedBackgroundCGColor = settings.backgroundColor.cgColor
        cachedDefaultStream     = settings.colorZonesEnabled
            ? nil
            : StreamColor(preset: settings.colorPreset)
        cachedMessageGlowCG     = settings.foregroundColor.withAlphaComponent(0.7).cgColor

        // Clock fonts — NSFont(name:size:) scans the system font registry; cache the result.
        cachedClockFont     = NSFont(name: settings.clockFontName, size: settings.clockFontSize)
                           ?? NSFont.systemFont(ofSize: settings.clockFontSize, weight: .thin)
        cachedClockDateFont = NSFont(name: settings.clockFontName, size: settings.clockFontSize * 0.32)
                           ?? NSFont.systemFont(ofSize: settings.clockFontSize * 0.32, weight: .thin)
        if settings.clockColorTiedToPreset {
            cachedClockTextColor = settings.headColor.withAlphaComponent(0.82)
            cachedClockDateColor = settings.foregroundColor.withAlphaComponent(0.65)
            cachedClockGlowCG    = settings.foregroundColor.withAlphaComponent(0.45).cgColor
        } else {
            cachedClockTextColor = NSColor(calibratedWhite: 0.93, alpha: 0.62)
            cachedClockDateColor = NSColor(calibratedWhite: 0.80, alpha: 0.52)
            cachedClockGlowCG    = NSColor(calibratedWhite: 1.00, alpha: 0.28).cgColor
        }
        // Invalidate per-second attributed strings so drawClock() rebuilds them
        // with the updated font, size, and colour.
        cachedTimeAttr = nil
        cachedDateAttr = nil

        // ── Spectrafall ──────────────────────────────────────────────────────
        // Runs after the cache refresh above so the cycling colour overrides
        // the static-preset message glow and clock colours when active.
        if settings.spectrafallEnabled {
            lastSpectraQuant = Int(spectraPhase * Double(Self.spectraStepsPerSegment))
            refreshSpectraColors(quant: lastSpectraQuant)
        } else {
            spectraStream    = nil
            lastSpectraQuant = -1
        }

        lastBuiltSize = size
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(cachedBackgroundCGColor)
        ctx.fill(bounds)

        let cell = settings.glyphSize

        // Use the cached default stream (pre-built in rebuild()); only fall back
        // to constructing one if somehow the cache is missing (e.g. first draw
        // before rebuild() has completed its cache pass).
        let defaultStream = cachedDefaultStream
                         ?? StreamColor(preset: settings.colorPreset)
        // When Spectrafall is active, every column draws in the current cycle
        // colour — exclusivity with Chromafall is enforced in the settings
        // model, and this guard also wins over any stale per-column colours.
        let spectra = settings.spectrafallEnabled ? spectraStream : nil
        for (i, col) in columns.enumerated() {
            let stream = spectra
                ?? ((columnColors.isEmpty || i >= columnColors.count)
                    ? defaultStream
                    : columnColors[i])
            drawColumn(col, ctx: ctx, cell: cell, colStep: columnStep, stream: stream)
        }

        let showOverlays = !settings.primaryDisplayOnly || isPrimaryDisplay
        if !messageChars.isEmpty && showOverlays { drawMessage(ctx) }
        if settings.showClock    && showOverlays { drawClock(ctx) }
    }

    private func drawColumn(_ col: GlyphColumn,
                            ctx: CGContext,
                            cell: CGFloat,
                            colStep: CGFloat,
                            stream: StreamColor) {

        let viewH = bounds.height
        let count = col.glyphs.count

        // Track ctx.setAlpha() state — only call when value changes.
        // ctx.setAlpha() works correctly with ctx.draw(CGImage, in:).
        var currentAlpha: CGFloat = 1.0

        for i in 0 ..< count {
            let glyphTop = col.headY - CGFloat(i) * cell
            guard glyphTop + cell > 0 && glyphTop < viewH else { continue }

            let rect = CGRect(x: col.x, y: glyphTop, width: colStep, height: cell)

            if i == 0 {
                // ── Head glyph ── always full alpha.
                if currentAlpha != 1.0 { ctx.setAlpha(1.0); currentAlpha = 1.0 }

                if col.flashTimer > 0 {
                    if settings.showGlow {
                        ctx.saveGState()
                        ctx.setShadow(offset: .zero, blur: 10,
                                      color: CGColor(gray: 1.0, alpha: 0.8))
                        drawGlyph(col.glyphs[0], in: rect,
                                  colorID: GlyphAtlas.whiteID, color: .white, ctx: ctx)
                        ctx.restoreGState()
                    } else {
                        drawGlyph(col.glyphs[0], in: rect,
                                  colorID: GlyphAtlas.whiteID, color: .white, ctx: ctx)
                    }
                } else if settings.showGlow {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 10, color: stream.glowCG)
                    drawGlyph(col.glyphs[0], in: rect,
                              colorID: stream.headColorID, color: stream.head, ctx: ctx)
                    ctx.restoreGState()
                } else {
                    drawGlyph(col.glyphs[0], in: rect,
                              colorID: stream.headColorID, color: stream.head, ctx: ctx)
                }
            } else {
                // ── Trail glyph ── ctx.setAlpha() works correctly with CGImage draws.
                let baseAlpha = max(0, pow(1.0 - CGFloat(i) / CGFloat(count), 2))
                let jitter    = i < col.brightnessJitter.count ? col.brightnessJitter[i] : 1.0
                let alpha     = min(1.0, baseAlpha * jitter * col.columnBrightness)
                if alpha != currentAlpha { ctx.setAlpha(alpha); currentAlpha = alpha }
                drawGlyph(col.glyphs[i], in: rect,
                          colorID: stream.fgColorID, color: stream.fg, ctx: ctx)
            }
        }

        // Restore context alpha so subsequent draws (message, clock) are unaffected.
        if currentAlpha != 1.0 { ctx.setAlpha(1.0) }
    }

    private func drawGlyph(_ char: Character, in rect: CGRect,
                            colorID: Int, color: NSColor, ctx: CGContext) {
        guard let image = glyphAtlas.image(for: char, colorID: colorID, color: color) else { return }
        // CGImage drawn with ctx.draw() appears upside-down in a flipped NSView.
        // Apply the standard CG flip compensation: translate to rect top-left,
        // flip y, draw at origin. Pure CGContext math — no AppKit compositing.
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    // MARK: - Per-stream colours

    /// Assigns a random colour to every stream. Called from rebuild() and
    /// whenever a stream resets off the bottom of the screen.
    private func rebuildColumnColors() {
        guard settings.colorZonesEnabled else { columnColors = []; return }
        columnColors = columns.map { _ in Self.randomStreamColor() }
    }

    private static func randomStreamColor() -> StreamColor {
        StreamColor(preset: Cyph3rfallSettings.ColorPreset.allCases.randomElement() ?? .matrixGreen)
    }

    // MARK: - Spectrafall colour cycle

    /// Advances the cycle phase and, when the quantized step changes, triggers
    /// a colour refresh. Called once per physics tick while Spectrafall is on.
    private func advanceSpectraCycle(dt: Double) {
        let options = Cyph3rfallSettings.spectrafallSpeedOptions
        let idx     = max(0, min(settings.spectrafallSpeedIndex, options.count - 1))
        let secondsPerPreset = options[idx].secondsPerPreset
        let pathCount = Double(Cyph3rfallSettings.spectraCyclePath.count)

        spectraPhase += (dt * spectraTimeScale) / secondsPerPreset
        if spectraPhase >= pathCount {
            spectraPhase -= pathCount * (spectraPhase / pathCount).rounded(.down)
        }

        let quant = Int(spectraPhase * Double(Self.spectraStepsPerSegment))
        if quant != lastSpectraQuant {
            lastSpectraQuant = quant
            refreshSpectraColors(quant: quant)
        }
    }

    /// Re-renders the two Spectrafall atlas slots in the blended colour for the
    /// given quantized step, and keeps the message glow and (when tied to the
    /// preset) clock colours in step with the cycle.
    ///
    /// Cost: ~230 small bitmap renders, only on step advance — never per frame.
    /// The interpolation parameter is derived from the quantized step rather
    /// than the raw phase so the rendered colour exactly matches the step.
    private func refreshSpectraColors(quant: Int) {
        let path  = Cyph3rfallSettings.spectraCyclePath
        let steps = Self.spectraStepsPerSegment
        guard !path.isEmpty, steps > 0 else { return }

        let segment = (quant / steps) % path.count
        let t       = CGFloat(quant % steps) / CGFloat(steps)

        let from = path[segment]
        let to   = path[(segment + 1) % path.count]

        // Head and trail blend with the same t so the head stays a coordinated
        // bright tint of the trail throughout every transition.
        let fg   = from.foregroundColor.blended(withFraction: t, of: to.foregroundColor)
                ?? from.foregroundColor
        let head = from.headColor.blended(withFraction: t, of: to.headColor)
                ?? from.headColor

        glyphAtlas.invalidate(colorIDs: [GlyphAtlas.spectraFgID, GlyphAtlas.spectraHeadID])
        glyphAtlas.prewarm(colorID: GlyphAtlas.spectraFgID,   color: fg,   glyphs: matrixGlyphPool)
        glyphAtlas.prewarm(colorID: GlyphAtlas.spectraHeadID, color: head, glyphs: matrixGlyphPool)

        spectraStream = StreamColor(fg: fg, head: head,
                                    fgColorID:   GlyphAtlas.spectraFgID,
                                    headColorID: GlyphAtlas.spectraHeadID)

        // Dependent overlays follow the cycle.
        cachedMessageGlowCG = fg.withAlphaComponent(0.7).cgColor
        if settings.clockColorTiedToPreset {
            cachedClockTextColor = head.withAlphaComponent(0.82)
            cachedClockDateColor = fg.withAlphaComponent(0.65)
            cachedClockGlowCG    = fg.withAlphaComponent(0.45).cgColor
            cachedTimeAttr = nil
            cachedDateAttr = nil
        }
    }

    // MARK: - Custom message overlay

    /// Recalculates message character positions whenever the view is rebuilt
    /// (size change, settings change). Characters are horizontally centred and
    /// vertically anchored at 2/3 of the view height — below the clock zone.
    private func rebuildMessageChars() {
        let msg = settings.customMessage.trimmingCharacters(in: .whitespaces)
        guard settings.messageEnabled, !msg.isEmpty, bounds.width > 0 else {
            messageChars = []; charByColumnIndex = [:]; litFlags = []
            charHasBeenLit = []; messagePhase = .building; messageCooldown = 0
            return
        }

        let cell    = settings.glyphSize
        let colStep = columnStep > 0 ? columnStep : ceil(cell * 0.75)
        let chars   = Array(msg)

        // Exact pixel centre for drawing. The column index is still snapped to
        // the nearest rain column so the reveal trigger works, but the draw
        // position is independent — no more snap-induced offset.
        let idealStartX = (bounds.width - CGFloat(chars.count) * colStep) / 2.0
        let startCol    = Int(((idealStartX - columnOffset) / colStep).rounded())

        // Vertical anchor: centre of the character cell sits at 2/3 height.
        let targetY = bounds.height * (2.0 / 3.0)

        // Preserve existing alphas so an in-progress fade isn't reset mid-animation.
        let oldChars = messageChars
        messageChars = chars.enumerated().map { i, char in
            let colIdx = startCol + i
            let cx     = columnOffset + (CGFloat(colIdx) + 0.5) * colStep
            let old    = oldChars.first(where: { $0.columnIndex == colIdx })
            return MessageChar(char: char, x: cx, y: targetY,
                               columnIndex: colIdx, alpha: old?.alpha ?? 0.0)
        }

        // Build the column-index lookup used by updateMessageChars().
        // This is a tiny dict (max 30 entries) computed once per rebuild, not per frame.
        charByColumnIndex = Dictionary(uniqueKeysWithValues:
            messageChars.enumerated().map { idx, mc in (mc.columnIndex, idx) })

        // Pre-allocate per-frame and per-cycle arrays.
        litFlags       = Array(repeating: false, count: messageChars.count)
        charHasBeenLit = Array(repeating: false, count: messageChars.count)

        // Start a fresh cycle. Preserve the phase only if we're mid-cooldown so
        // a settings change doesn't reset a nearly-complete countdown.
        if case .cooldown = messagePhase { /* keep */ } else {
            messagePhase = .building
            messageCooldown = 0
        }
    }

    /// Message display cycle, called every frame.
    ///
    /// • **building**   Rain columns light chars one by one. Each char stays
    ///                  at alpha = 1 once triggered — no individual decay.
    ///                  Transitions to fadingOut when every char has been lit.
    /// • **fadingOut**  No new lighting; every char fades together as a group.
    ///                  Transitions to cooldown when all alphas reach zero.
    /// • **cooldown**   Alphas are all zero; timer counts down, then the cycle
    ///                  resets and building begins again.
    ///
    /// Complexity: O(columns) — single pass with O(1) dict lookup per stream.
    private func updateMessageChars(dt: Double) {
        switch messagePhase {

        case .building:
            let halfH = settings.glyphSize * 1.2

            // Reset reusable flags — no allocation.
            for i in litFlags.indices { litFlags[i] = false }

            // Single O(N_columns) pass — X check eliminated (grid-aligned).
            for col in columns {
                guard let idx = charByColumnIndex[col.columnIndex] else { continue }
                if abs(col.headY - messageChars[idx].y) < halfH { litFlags[idx] = true }
            }

            // Light up triggered chars; others stay exactly where they are
            // (no per-char decay during building — they accumulate and hold).
            for i in messageChars.indices {
                if litFlags[i] {
                    messageChars[i].alpha = 1.0
                    charHasBeenLit[i]     = true
                }
            }

            // Once every character has been lit at least once, start the group fade.
            if charHasBeenLit.allSatisfy({ $0 }) {
                messagePhase = .fadingOut
            }

        case .fadingOut:
            // Unified group fade — no column lighting.
            let step     = CGFloat(dt) * Self.messageFadeOutRate
            var allGone  = true
            for i in messageChars.indices {
                messageChars[i].alpha = max(0, messageChars[i].alpha - step)
                if messageChars[i].alpha > 0 { allGone = false }
            }
            if allGone {
                messagePhase    = .cooldown
                messageCooldown = Self.messageCooldownDuration
            }

        case .cooldown:
            messageCooldown -= dt
            guard messageCooldown <= 0 else { return }

            // Cooldown elapsed — reset for the next cycle.
            for i in messageChars.indices {
                messageChars[i].alpha = 0
                charHasBeenLit[i]     = false
            }
            messagePhase = .building
        }
    }

    /// Renders the message characters on top of the rain with brightness
    /// proportional to each character's current alpha.
    private func drawMessage(_ ctx: CGContext) {
        let cell = settings.glyphSize
        // When Spectrafall is active the message follows the cycling colour;
        // otherwise it uses the static preset as before.
        let active      = settings.spectrafallEnabled ? spectraStream : nil
        let headCol     = active?.head ?? settings.headColor
        let fgCol       = active?.fg   ?? settings.foregroundColor
        let headColorID = active?.headColorID
                       ?? cachedDefaultStream?.headColorID
                       ?? (settings.colorPreset.rawValue * 2 + 1)
        let fgColorID   = active?.fgColorID
                       ?? cachedDefaultStream?.fgColorID
                       ?? (settings.colorPreset.rawValue * 2)

        for mc in messageChars {
            guard mc.alpha > 0.01 else { continue }

            // At full alpha use the bright head colour; as it fades shift toward
            // the trail colour so the character blends back into the rain.
            let drawColor: NSColor
            let colorID:   Int
            let drawAlpha: CGFloat
            if mc.alpha > 0.5 {
                drawColor = headCol
                colorID   = headColorID
                drawAlpha = mc.alpha
            } else {
                drawColor = fgCol
                colorID   = fgColorID
                drawAlpha = min(1.0, mc.alpha * 1.4)
            }

            let rect = CGRect(x: mc.x - cell / 2.0,
                              y: mc.y - cell / 2.0,
                              width: cell, height: cell)

            ctx.saveGState()
            ctx.setAlpha(drawAlpha)
            if settings.showGlow && mc.alpha > 0.4 {
                ctx.setShadow(offset: .zero, blur: 12, color: cachedMessageGlowCG)
            }
            drawGlyph(mc.char, in: rect, colorID: colorID, color: drawColor, ctx: ctx)
            ctx.restoreGState()
        }
    }

    // MARK: - Clock overlay

    private func drawClock(_ ctx: CGContext) {
        // Refresh formatter output at most once per second.
        let now    = Date()
        let comps  = Calendar.current.dateComponents([.minute, .second], from: now)
        let minute = comps.minute ?? 0
        if minute != lastClockMinute {
            lastClockMinute     = minute
            clockFontSizeOffset = CGFloat([-1, 0, 1].randomElement()!)
            let sz              = settings.clockFontSize + clockFontSizeOffset
            cachedClockFont     = NSFont(name: settings.clockFontName, size: sz)
                               ?? NSFont.systemFont(ofSize: sz, weight: .thin)
            cachedClockDateFont = NSFont(name: settings.clockFontName, size: sz * 0.32)
                               ?? NSFont.systemFont(ofSize: sz * 0.32, weight: .thin)
            cachedTimeAttr      = nil
            cachedDateAttr      = nil
        }
        let uniqueSec = minute * 60 + (comps.second ?? 0)
        if uniqueSec != lastClockSecond {
            lastClockSecond  = uniqueSec
            cachedTimeString = clockTimeFmt.string(from: now)
            cachedDateString = clockDateFmt.string(from: now)
            cachedTimeAttr   = nil
            cachedDateAttr   = nil
        }

        // Rebuild the attributed string if needed (new second, or settings changed).
        // Fonts, colours, and glow colour are all pre-built in rebuild().
        if cachedTimeAttr == nil {
            cachedTimeAttr = NSAttributedString(string: cachedTimeString, attributes: [
                .font: cachedClockFont, .foregroundColor: cachedClockTextColor,
            ])
        }
        let timeStr    = cachedTimeAttr!
        let timeSize   = timeStr.size()
        let timeLine   = CTLineCreateWithAttributedString(timeStr)
        let timeBounds = CTLineGetBoundsWithOptions(timeLine, .useGlyphPathBounds)

        // X: glyph-path bounds width minus left bearing → visual centre at screen centre.
        // Y: typographic size() height keeps vertical spacing stable across font variants.
        let clockCentreY = bounds.height / 3.0
        let timeX = (bounds.width - timeBounds.width) / 2.0 - timeBounds.origin.x
        let timeY = clockCentreY - timeSize.height / 2.0

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 24, color: cachedClockGlowCG)
        timeStr.draw(at: NSPoint(x: timeX, y: timeY))
        ctx.restoreGState()

        guard settings.showDate else { return }

        // Date line — 32 % of clock size, slightly dimmer, 6 pt below the time.
        if cachedDateAttr == nil {
            cachedDateAttr = NSAttributedString(string: cachedDateString, attributes: [
                .font: cachedClockDateFont, .foregroundColor: cachedClockDateColor,
            ])
        }
        let dateStr    = cachedDateAttr!
        let dateLine   = CTLineCreateWithAttributedString(dateStr)
        let dateBounds = CTLineGetBoundsWithOptions(dateLine, .useGlyphPathBounds)
        let dateX      = (bounds.width - dateBounds.width) / 2.0 - dateBounds.origin.x

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 14, color: cachedClockGlowCG)
        dateStr.draw(at: NSPoint(x: dateX, y: timeY + timeSize.height + 6))
        ctx.restoreGState()
    }
}
