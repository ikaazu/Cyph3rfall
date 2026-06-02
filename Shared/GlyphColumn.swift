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

    let symbols: [Character] = Array("!@#$%&*+-=<>?|\\/:~^")
    let digits:  [Character] = Array("0123456789")
    let latin:   [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

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

    // Throttle glyph mutation to every 2 physics ticks — halves random work
    // with no perceptible change to the "living characters" effect.
    private var mutationCounter: Int = 0

    private let cellSize: CGFloat
    private let viewHeight: CGFloat

    init(columnIndex: Int,
         x: CGFloat,
         viewHeight: CGFloat,
         cellSize: CGFloat,
         settings: Cyph3rfallSettings) {

        self.columnIndex = columnIndex
        self.x           = x
        self.viewHeight  = viewHeight
        self.cellSize    = cellSize

        columnBrightness = CGFloat.random(in: 0.55 ... 1.00)
        let tl           = max(4, settings.trailLength + Int.random(in: -6 ... 10))
        trailLength      = tl
        glyphs           = (0 ..< tl).map { _ in matrixGlyphPool.randomElement() ?? "｡" }
        brightnessJitter = (0 ..< tl).map { _ in CGFloat.random(in: 0.78 ... 1.22) }
        speed            = CGFloat.random(in: 60 ... 220) * CGFloat(settings.speedMultiplier)
        headY            = -CGFloat.random(in: 0 ... viewHeight + cellSize * CGFloat(tl))
    }

    func update(dt: Double) {
        headY += speed * CGFloat(dt)

        // Mutate glyphs every 2 ticks — halves random work while keeping the
        // "living characters" effect visually intact.
        mutationCounter += 1
        if mutationCounter >= 2 {
            mutationCounter = 0
            glyphs[Int.random(in: 0 ..< glyphs.count)] = matrixGlyphPool.randomElement() ?? "｡"
            let ji = Int.random(in: 0 ..< brightnessJitter.count)
            brightnessJitter[ji] = CGFloat.random(in: 0.78 ... 1.22)
        }

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

    func reset(settings: Cyph3rfallSettings) {
        let newLength = max(4, settings.trailLength + Int.random(in: -6 ... 10))
        speed           = CGFloat.random(in: 60 ... 220) * CGFloat(settings.speedMultiplier)
        headY           = -cellSize * CGFloat.random(in: 1 ... 6)
        flashTimer      = 0
        mutationCounter = 0

        // Refill arrays in-place when trail length is unchanged — avoids heap allocation
        // on the hot path (called every time a column wraps off the bottom of the screen).
        if newLength == trailLength {
            for i in glyphs.indices {
                glyphs[i]           = matrixGlyphPool.randomElement() ?? "｡"
                brightnessJitter[i] = CGFloat.random(in: 0.78 ... 1.22)
            }
        } else {
            trailLength      = newLength
            glyphs           = (0 ..< newLength).map { _ in matrixGlyphPool.randomElement() ?? "｡" }
            brightnessJitter = (0 ..< newLength).map { _ in CGFloat.random(in: 0.78 ... 1.22) }
        }
    }
}
