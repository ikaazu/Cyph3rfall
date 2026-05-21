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

    var settings = Cyph3rfallSettings.default {
        didSet { rebuild() }
    }

    private var columns:      [GlyphColumn] = []
    private var columnStep:   CGFloat       = 0   // horizontal distance between columns (< glyphSize)
    private var lastTickTime: CFTimeInterval = 0

    // Per-stream colours — one entry per element in `columns`, refreshed each
    // time a stream resets off the bottom of the screen.
    private struct StreamColor {
        let fg:     NSColor
        let head:   NSColor
        let fgCG:   CGColor   // pre-computed — avoids .cgColor per glyph
        let headCG: CGColor
        let glowCG: CGColor   // fg at 0.8 alpha, ready for setShadow

        init(fg: NSColor, head: NSColor) {
            self.fg   = fg
            self.head = head
            fgCG      = fg.cgColor
            headCG    = head.cgColor
            glowCG    = fg.withAlphaComponent(0.8).cgColor
        }
    }
    private var columnColors: [StreamColor] = []

    // Shared draw attributes — .font is set once in rebuild(), .foregroundColor
    // is updated inline per-glyph.  Avoids allocating a new NSAttributedString
    // for every glyph (~5 000+/frame at typical densities).
    private var sharedAttrs: [NSAttributedString.Key: Any] = [:]

    // NSString cache for the finite glyph-pool set.  Populated once in rebuild()
    // so String(char) → NSString bridging is not done thousands of times per frame.
    private var glyphStringCache: [Character: NSString] = [:]

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

    // Clock overlay — slow positional drift to prevent screen burn.
    // Two out-of-phase sine waves with different periods trace a path that
    // never exactly repeats, covering ±30 pt (X) and ±20 pt (Y).
    private var clockDriftElapsed: Double = 0   // accumulates real seconds
    private var clockDriftX: CGFloat = 0
    private var clockDriftY: CGFloat = 0

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

        // Advance clock drift — only costs two trig calls per frame.
        if settings.showClock {
            clockDriftElapsed += dt
            // X: 210 s half-period (~3.5 min full cycle), ±30 pt
            // Y: 157 s half-period (~2.6 min full cycle), ±20 pt
            // Different periods → path never repeats; coprime-ish values help.
            clockDriftX = CGFloat(sin(clockDriftElapsed / 210 * .pi) * 30)
            clockDriftY = CGFloat(sin(clockDriftElapsed / 157 * .pi) * 20)
        }

        needsDisplay = true
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
        sharedAttrs[.font] = glyphFont

        // Build NSString cache on first call (or when the pool changes — it doesn't).
        if glyphStringCache.isEmpty {
            var seen = Set<Character>()
            for char in matrixGlyphPool {
                if seen.insert(char).inserted {
                    glyphStringCache[char] = String(char) as NSString
                }
            }
        }

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

        rebuildMessageChars()

        columns = (0 ..< totalSlots).flatMap { i -> [GlyphColumn] in
            let x = CGFloat(i) * colStep
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
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(settings.backgroundColor.cgColor)
        ctx.fill(bounds)

        let cell = settings.glyphSize

        // Compute the default StreamColor once per frame (not inside the loop)
        // so the CGColor bridging only happens once when Chromafall is off.
        let defaultStream = StreamColor(fg: settings.foregroundColor,
                                        head: settings.headColor)
        for (i, col) in columns.enumerated() {
            let stream = (columnColors.isEmpty || i >= columnColors.count)
                ? defaultStream
                : columnColors[i]
            drawColumn(col, ctx: ctx, cell: cell, colStep: columnStep, stream: stream)
        }

        if !messageChars.isEmpty { drawMessage(ctx) }
        if settings.showClock    { drawClock(ctx) }
    }

    private func drawColumn(_ col: GlyphColumn,
                            ctx: CGContext,
                            cell: CGFloat,
                            colStep: CGFloat,
                            stream: StreamColor) {

        let viewH = bounds.height
        let count = col.glyphs.count

        // Track the context's global alpha so we only call setAlpha when it
        // changes — redundant state-sets are cheap but still worth avoiding.
        var currentAlpha: CGFloat = 1.0

        for i in 0 ..< count {
            let glyphTop = col.headY - CGFloat(i) * cell
            guard glyphTop + cell > 0 && glyphTop < viewH else { continue }

            let rect = CGRect(x: col.x, y: glyphTop, width: colStep, height: cell)

            if i == 0 {
                // ── Head glyph ── always full alpha.
                if currentAlpha != 1.0 { ctx.setAlpha(1.0); currentAlpha = 1.0 }

                if col.flashTimer > 0 {
                    // White-hot flash — glowCG pre-computed as white @ 0.8.
                    if settings.showGlow {
                        ctx.saveGState()
                        ctx.setShadow(offset: .zero, blur: 10,
                                      color: CGColor(gray: 1.0, alpha: 0.8))
                        drawGlyph(col.glyphs[0], in: rect, color: .white)
                        ctx.restoreGState()
                    } else {
                        drawGlyph(col.glyphs[0], in: rect, color: .white)
                    }
                } else if settings.showGlow {
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: 10, color: stream.glowCG)
                    drawGlyph(col.glyphs[0], in: rect, color: stream.head)
                    ctx.restoreGState()
                } else {
                    drawGlyph(col.glyphs[0], in: rect, color: stream.head)
                }
            } else {
                // ── Trail glyph ── use ctx.setAlpha() to avoid allocating a new
                // NSColor via withAlphaComponent() for every glyph (~5 000+/frame).
                let baseAlpha = max(0, pow(1.0 - CGFloat(i) / CGFloat(count), 2))
                let jitter    = i < col.brightnessJitter.count ? col.brightnessJitter[i] : 1.0
                let alpha     = min(1.0, baseAlpha * jitter * col.columnBrightness)

                if alpha != currentAlpha { ctx.setAlpha(alpha); currentAlpha = alpha }
                drawGlyph(col.glyphs[i], in: rect, color: stream.fg)
            }
        }

        // Restore the context's global alpha so subsequent draws are unaffected.
        if currentAlpha != 1.0 { ctx.setAlpha(1.0) }
    }

    private func drawGlyph(_ char: Character, in rect: CGRect, color: NSColor) {
        // Mutate the shared dict rather than allocating a new NSAttributedString.
        sharedAttrs[.foregroundColor] = color
        let s = glyphStringCache[char] ?? (String(char) as NSString)
        s.draw(in: rect, withAttributes: sharedAttrs)
    }

    // MARK: - Per-stream colours

    /// Assigns a random colour to every stream. Called from rebuild() and
    /// whenever a stream resets off the bottom of the screen.
    private func rebuildColumnColors() {
        guard settings.colorZonesEnabled else { columnColors = []; return }
        columnColors = columns.map { _ in Self.randomStreamColor() }
    }

    private static func randomStreamColor() -> StreamColor {
        let preset = Cyph3rfallSettings.ColorPreset.allCases.randomElement()!
        return StreamColor(fg: preset.foregroundColor, head: preset.headColor)
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

        // Ideal centred left edge, then snap to the nearest column boundary so
        // every message character lands exactly on an existing rain column.
        let idealStartX = (bounds.width - CGFloat(chars.count) * colStep) / 2.0
        let startCol    = Int((idealStartX / colStep).rounded())

        // Vertical anchor: centre of the character cell sits at 2/3 height.
        let targetY = bounds.height * (2.0 / 3.0)

        // Preserve existing alphas so an in-progress fade isn't reset mid-animation.
        let oldChars = messageChars
        messageChars = chars.enumerated().map { i, char in
            let colIdx = startCol + i
            let cx     = CGFloat(colIdx) * colStep + colStep / 2.0
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
        let cell   = settings.glyphSize
        // Cache solid colour references and CGColors once per draw call —
        // no withAlphaComponent allocations inside the loop.
        let headCol = settings.headColor        // solid NSColor, alpha=1
        let fgCol   = settings.foregroundColor  // solid NSColor, alpha=1
        let fgCG    = fgCol.cgColor             // bridged once; used for glow

        for mc in messageChars {
            guard mc.alpha > 0.01 else { continue }

            // At full alpha use the bright head colour; as it fades shift toward
            // the trail colour so the character blends back into the rain.
            // Alpha is applied via ctx.setAlpha() — no NSColor allocation needed.
            let drawColor: NSColor
            let drawAlpha: CGFloat
            if mc.alpha > 0.5 {
                drawColor = headCol
                drawAlpha = mc.alpha
            } else {
                drawColor = fgCol
                drawAlpha = min(1.0, mc.alpha * 1.4)
            }

            let rect = CGRect(x: mc.x - cell / 2.0,
                              y: mc.y - cell / 2.0,
                              width: cell, height: cell)

            ctx.saveGState()
            ctx.setAlpha(drawAlpha)
            if settings.showGlow && mc.alpha > 0.4 {
                // CGColor.copy(alpha:) is cheaper than constructing an NSColor.
                ctx.setShadow(offset: .zero, blur: 12,
                              color: fgCG.copy(alpha: mc.alpha * 0.7))
            }
            drawGlyph(mc.char, in: rect, color: drawColor)
            ctx.restoreGState()
        }
    }

    // MARK: - Clock overlay

    private func drawClock(_ ctx: CGContext) {
        // Refresh cached strings at most once per second.
        let now       = Date()
        let second    = Calendar.current.component(.second, from: now)
        let minute    = Calendar.current.component(.minute, from: now)
        let uniqueSec = minute * 60 + second
        if uniqueSec != lastClockSecond {
            lastClockSecond  = uniqueSec
            cachedTimeString = clockTimeFmt.string(from: now)
            cachedDateString = clockDateFmt.string(from: now)
        }

        let font = NSFont(name: settings.clockFontName,
                          size: settings.clockFontSize)
                ?? NSFont.systemFont(ofSize: settings.clockFontSize, weight: .thin)

        // Colour: either preset-matched or neutral white, depending on user setting.
        let textColor: NSColor
        let glowColor: CGColor
        if settings.clockColorTiedToPreset {
            textColor = settings.headColor.withAlphaComponent(0.82)
            glowColor = settings.foregroundColor.withAlphaComponent(0.45).cgColor
        } else {
            textColor = NSColor(calibratedWhite: 0.93, alpha: 0.62)
            glowColor = NSColor(calibratedWhite: 1.00, alpha: 0.28).cgColor
        }

        let timeStr = NSAttributedString(string: cachedTimeString, attributes: [
            .font:            font,
            .foregroundColor: textColor,
        ])
        let timeSize = timeStr.size()

        // Anchor: horizontal centre, vertical centre at 1/3 from top.
        // isFlipped = true → y increases downward, so 1/3 from top = bounds.height / 3.
        // clockDriftX/Y apply the slow burn-in-prevention offset.
        let clockCentreY = bounds.height / 3.0
        let timeX = (bounds.width  - timeSize.width)  / 2 + clockDriftX
        let timeY = clockCentreY - timeSize.height / 2    + clockDriftY

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 24, color: glowColor)
        timeStr.draw(at: NSPoint(x: timeX, y: timeY))
        ctx.restoreGState()

        guard settings.showDate else { return }

        // Date line — 32 % of clock size, slightly dimmer, 6 pt below the time.
        let dateFontSize = settings.clockFontSize * 0.32
        let dateFont     = NSFont(name: settings.clockFontName, size: dateFontSize)
                        ?? NSFont.systemFont(ofSize: dateFontSize, weight: .thin)
        let dateColor: NSColor = settings.clockColorTiedToPreset
            ? settings.foregroundColor.withAlphaComponent(0.65)
            : NSColor(calibratedWhite: 0.80, alpha: 0.52)
        let dateStr  = NSAttributedString(string: cachedDateString, attributes: [
            .font:            dateFont,
            .foregroundColor: dateColor,
        ])
        let dateSize = dateStr.size()

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 14, color: glowColor)
        dateStr.draw(at: NSPoint(x: (bounds.width - dateSize.width) / 2 + clockDriftX,
                                 y: timeY + timeSize.height + 6))
        ctx.restoreGState()
    }
}
