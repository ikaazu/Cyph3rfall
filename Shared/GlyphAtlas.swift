import AppKit

/// Pre-renders each (glyph, colorID) pair into a CGImage so the hot draw
/// path is a GPU-accelerated bitmap blit rather than a Core Text layout call.
///
/// Color IDs are assigned by Cyph3rfallView:
///   preset.rawValue * 2       → foreground colour for that preset
///   preset.rawValue * 2 + 1   → head colour for that preset
///   GlyphAtlas.whiteID        → pure white (flash)
///
/// Images are rendered with a y-flip applied to the CGBitmapContext so they
/// match the flipped NSView coordinate system and can be drawn directly with
/// ctx.draw(cgImage, in:) — no per-draw transform or AppKit compositing overhead.
///
/// All access is on the main thread (draw path), so no locking is needed.
final class GlyphAtlas {

    static let whiteID: Int = 18   // one slot beyond the 9-preset fg/head pairs

    // Spectrafall cycle slots — re-rendered each time the quantized cycle
    // colour advances. Kept separate from the preset IDs so invalidating
    // them never touches the warm preset cache.
    static let spectraFgID:   Int = 19
    static let spectraHeadID: Int = 20

    private struct Key: Hashable {
        let char:    Character
        let colorID: Int
    }

    private var cache:    [Key: CGImage] = [:]
    private var cellSize: CGFloat        = 0
    private var font:     NSFont         = .monospacedSystemFont(ofSize: 13, weight: .regular)

    /// Call from rebuild() whenever cell size or font may have changed.
    /// Clears the cache only when a relevant property actually changed.
    func configure(cellSize: CGFloat, font: NSFont) {
        guard cellSize != self.cellSize || font != self.font else { return }
        self.cellSize = cellSize
        self.font     = font
        cache.removeAll(keepingCapacity: true)
    }

    /// Discard all cached images. Call when colour settings change.
    func invalidate() {
        cache.removeAll(keepingCapacity: true)
    }

    /// Discard cached images for specific colour IDs only — used by the
    /// Spectrafall cycle so a colour step doesn't dump the whole atlas.
    func invalidate(colorIDs: Set<Int>) {
        for key in cache.keys where colorIDs.contains(key.colorID) {
            cache.removeValue(forKey: key)
        }
    }

    /// Pre-renders every unique glyph in a single colour. Used by the
    /// Spectrafall cycle to warm its two slots after a colour step so the
    /// next draw frame never falls back to lazy rendering.
    func prewarm(colorID: Int, color: NSColor, glyphs: [Character]) {
        var seen = Set<Character>()
        for char in glyphs {
            guard seen.insert(char).inserted else { continue }
            _ = image(for: char, colorID: colorID, color: color)
        }
    }

    /// Pre-renders all (char, colorID) pairs for the given presets upfront.
    /// Call from rebuild() so the atlas is fully warm before the first draw
    /// frame — eliminates the cold-start jank from lazy population in draw().
    func prewarm(presets: [Cyph3rfallSettings.ColorPreset], glyphs: [Character]) {
        var seen = Set<Character>()
        for char in glyphs {
            guard seen.insert(char).inserted else { continue }
            _ = image(for: char, colorID: Self.whiteID, color: .white)
            for preset in presets {
                _ = image(for: char, colorID: preset.rawValue * 2,     color: preset.foregroundColor)
                _ = image(for: char, colorID: preset.rawValue * 2 + 1, color: preset.headColor)
            }
        }
    }

    /// Returns the cached CGImage for this glyph + colorID, rendering it on
    /// first call. Returns nil only if CGContext allocation fails (out of memory).
    func image(for char: Character, colorID: Int, color: NSColor) -> CGImage? {
        let key = Key(char: char, colorID: colorID)
        if let hit = cache[key] { return hit }

        let size = Int(ceil(cellSize))
        guard size > 0,
              let ctx = CGContext(
                data: nil, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (String(char) as NSString).draw(
            in: CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)),
            withAttributes: [.font: font, .foregroundColor: color]
        )
        NSGraphicsContext.restoreGraphicsState()

        let image = ctx.makeImage()
        cache[key] = image
        return image
    }
}
