import Foundation
import CoreGraphics

/// The pool of characters drawn in the rain.
///
/// Composition (approximate draw probability):
///   ~80 % half-width katakana  (U+FF65–FF9F) — the dominant Matrix glyph set
///   ~12 % symbols              — add visual noise without Latin feel
///   ~5  % digits               — sparse numeric punctuation
///   ~3  % uppercase Latin      — occasional English letter for flavour
///
/// Achieved by adding katakana 4× and keeping the rest at 1×.
let matrixGlyphPool: [Character] = {
    var katakana: [Character] = []
    for cp in 0xFF65 ... 0xFF9F {
        if let scalar = Unicode.Scalar(cp) { katakana.append(Character(scalar)) }
    }

    let symbols: [Character] = Array("!@#$%&*+-=<>?|\\/:~^".map { $0 })
    let digits:  [Character] = Array("0123456789".map { $0 })
    let latin:   [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { $0 })

    // Weight: katakana ×4, symbols ×2, digits ×1, latin ×1
    return katakana + katakana + katakana + katakana
         + symbols  + symbols
         + digits
         + latin
}()

/// Model for one falling column of glyphs.
///
/// Coordinate convention: y=0 is the top of the view, y increases downward
/// (matches NSView with isFlipped = true). headY is the y of the leading glyph;
/// trail glyphs are at headY − i*cellSize for i in 1…trailLength−1 (above the head).
final class GlyphColumn {

    let columnIndex: Int
    let x: CGFloat

    var headY: CGFloat
    var speed: CGFloat
    var trailLength: Int
    var glyphs: [Character]          // glyphs[0] = head, glyphs[1…] = trail above

    // Per-slot brightness multiplier (0.78 … 1.22).
    // Gives the trail an organic, flickering quality.
    var brightnessJitter: [CGFloat]

    // Persistent per-column dimming (0.55 … 1.00).
    // Simulates rain at different depths — some columns bright, others receding.
    let columnBrightness: CGFloat

    // Flash countdown: while > 0 the head renders as pure white.
    var flashTimer: Int = 0

    private let cellSize: CGFloat
    private let viewHeight: CGFloat

    init(columnIndex: Int,
         x: CGFloat,
         viewHeight: CGFloat,
         cellSize: CGFloat,
         settings: MatrixRainSettings) {

        self.columnIndex = columnIndex
        self.x           = x
        self.viewHeight  = viewHeight
        self.cellSize    = cellSize

        trailLength      = max(4, settings.trailLength + Int.random(in: -6 ... 10))
        glyphs           = (0 ..< trailLength).map { _ in matrixGlyphPool.randomElement()! }
        brightnessJitter = (0 ..< trailLength).map { _ in CGFloat.random(in: 0.78 ... 1.22) }
        columnBrightness = CGFloat.random(in: 0.55 ... 1.00)
        speed            = CGFloat.random(in: 60 ... 220) * CGFloat(settings.speedMultiplier)
        headY            = -CGFloat.random(in: 0 ... viewHeight + cellSize * CGFloat(trailLength))
    }

    func update(dt: Double) {
        headY += speed * CGFloat(dt)

        // Swap one random glyph per tick — the "living characters" effect.
        glyphs[Int.random(in: 0 ..< glyphs.count)] = matrixGlyphPool.randomElement()!

        // Drift one brightness jitter value each tick.
        let ji = Int.random(in: 0 ..< brightnessJitter.count)
        brightnessJitter[ji] = CGFloat.random(in: 0.78 ... 1.22)

        // White-hot flash: tick down the timer, or randomly trigger a new flash.
        if flashTimer > 0 {
            flashTimer -= 1
        } else if Int.random(in: 0 ... 400) == 0 {
            flashTimer = Int.random(in: 2 ... 6)   // ~33–100 ms at 60 fps
        }
    }

    var isOffScreen: Bool {
        headY - CGFloat(trailLength - 1) * cellSize > viewHeight
    }

    func reset(settings: MatrixRainSettings) {
        trailLength      = max(4, settings.trailLength + Int.random(in: -6 ... 10))
        glyphs           = (0 ..< trailLength).map { _ in matrixGlyphPool.randomElement()! }
        brightnessJitter = (0 ..< trailLength).map { _ in CGFloat.random(in: 0.78 ... 1.22) }
        speed            = CGFloat.random(in: 60 ... 220) * CGFloat(settings.speedMultiplier)
        headY            = -cellSize * CGFloat.random(in: 1 ... 6)
        flashTimer       = 0
    }
}
