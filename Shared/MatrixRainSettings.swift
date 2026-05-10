import AppKit

/// Central configuration for the Matrix rain effect.
struct MatrixRainSettings {

    // --- Visual ---
    var glyphSize: CGFloat = 16
    var trailLength: Int = 22
    var backgroundColor: NSColor = .black
    var showGlow: Bool = true
    var colorPreset: ColorPreset = .matrixGreen

    // foregroundColor is always derived from the preset so colour and head
    // colour stay coordinated without any extra bookkeeping.
    var foregroundColor: NSColor { colorPreset.foregroundColor }
    var headColor:       NSColor { colorPreset.headColor }

    // --- Animation ---
    var speedMultiplier: Double = 1.0
    var density: Double = 0.9

    // --- Presets ---
    var classicDenseMode: Bool = false

    static let `default` = MatrixRainSettings()
}

// MARK: - Color presets

extension MatrixRainSettings {

    enum ColorPreset: Int, CaseIterable {
        case matrixGreen = 0
        case amber       = 1
        case cyan        = 2
        case monochrome  = 3
        case amethyst    = 4
        case blue        = 5
        case red         = 6
        case orange      = 7
        case pink        = 8

        var label: String {
            switch self {
            case .matrixGreen: return "Green"
            case .amber:       return "Amber"
            case .cyan:        return "Cyan"
            case .monochrome:  return "White"
            case .amethyst:    return "Purple"
            case .blue:        return "Blue"
            case .red:         return "Red"
            case .orange:      return "Orange"
            case .pink:        return "Pink"
            }
        }

        /// Base trail colour.
        var foregroundColor: NSColor {
            switch self {
            case .matrixGreen: return NSColor(calibratedRed: 0.00, green: 0.88, blue: 0.08, alpha: 1)
            case .amber:       return NSColor(calibratedRed: 1.00, green: 0.60, blue: 0.00, alpha: 1)
            case .cyan:        return NSColor(calibratedRed: 0.00, green: 0.85, blue: 0.95, alpha: 1)
            case .monochrome:  return NSColor(calibratedRed: 0.80, green: 0.80, blue: 0.80, alpha: 1)
            case .amethyst:    return NSColor(calibratedRed: 0.58, green: 0.18, blue: 0.88, alpha: 1)
            case .blue:        return NSColor(calibratedRed: 0.10, green: 0.40, blue: 1.00, alpha: 1)
            case .red:         return NSColor(calibratedRed: 0.92, green: 0.08, blue: 0.08, alpha: 1)
            case .orange:      return NSColor(calibratedRed: 1.00, green: 0.38, blue: 0.00, alpha: 1)
            case .pink:        return NSColor(calibratedRed: 1.00, green: 0.20, blue: 0.60, alpha: 1)
            }
        }

        /// Leading-glyph colour (bright, colour-tinted near-white).
        var headColor: NSColor {
            switch self {
            case .matrixGreen: return NSColor(calibratedRed: 0.85, green: 1.00, blue: 0.85, alpha: 1)
            case .amber:       return NSColor(calibratedRed: 1.00, green: 0.92, blue: 0.70, alpha: 1)
            case .cyan:        return NSColor(calibratedRed: 0.80, green: 1.00, blue: 1.00, alpha: 1)
            case .monochrome:  return NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)
            case .amethyst:    return NSColor(calibratedRed: 0.90, green: 0.78, blue: 1.00, alpha: 1)
            case .blue:        return NSColor(calibratedRed: 0.68, green: 0.85, blue: 1.00, alpha: 1)
            case .red:         return NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.72, alpha: 1)
            case .orange:      return NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.60, alpha: 1)
            case .pink:        return NSColor(calibratedRed: 1.00, green: 0.75, blue: 0.88, alpha: 1)
            }
        }
    }
}

// MARK: - Preset option tables

extension MatrixRainSettings {

    static let speedOptions: [(label: String, value: Double)] = [
        ("Slow", 0.5), ("Normal", 1.0), ("Fast", 2.0)
    ]

    /// Density is a continuous Double: 0.1 = very sparse, 1.0 = one stream per
    /// column slot, 2.0 = two overlapping streams per slot ("super dense").
    static let densityRange: ClosedRange<Double> = 0.1 ... 5.0

    static let glyphSizeOptions: [(label: String, value: CGFloat)] = [
        ("Small", 10), ("Normal", 16), ("Large", 22)
    ]

    static func nearest<T: FloatingPoint>(in options: [(label: String, value: T)], to current: T) -> Int {
        options.enumerated()
            .min(by: { abs($0.element.value - current) < abs($1.element.value - current) })?
            .offset ?? 0
    }
}
