import AppKit

/// Central configuration for the Matrix rain effect.
struct Cyph3rfallSettings {

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
    var density: Double = 1.5

    // --- Presets ---
    var classicDenseMode:   Bool = false
    var colorZonesEnabled:  Bool = false

    // --- Spectrafall (full-screen colour cycle) ---
    // Mutually exclusive with Chromafall; resolveExclusiveModes() enforces it.
    var spectrafallEnabled:    Bool = false
    var spectrafallSpeedIndex: Int  = 1   // index into spectrafallSpeedOptions

    // --- Message ---
    var messageEnabled: Bool   = false
    var customMessage:  String = ""

    // --- Global hotkey (-1 = not set) ---
    var hotkeyCode:      Int    = -1
    var hotkeyModifiers: Int    = 0     // NSEvent.ModifierFlags rawValue
    var hotkeyCharacter: String = ""    // single display character, e.g. "S"

    // --- Security ---
    var requirePassword: Bool = false

    // --- Column spacing ---
    var columnSpacingIndex: Int = 0   // 0 = Wide, 1 = Narrow

    // --- Display ---
    var primaryDisplayOnly: Bool = false   // restrict clock/message overlays to main display

    // --- Clock overlay ---
    var showClock:              Bool    = false
    var showDate:               Bool    = false
    var clockColorTiedToPreset: Bool    = false
    var clockFontName:          String  = "Gill Sans"
    var clockFontSize:          CGFloat = 80

    static let `default` = Cyph3rfallSettings()
}

// MARK: - Color presets

extension Cyph3rfallSettings {

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

extension Cyph3rfallSettings {

    static let speedOptions: [(label: String, value: Double)] = [
        ("Slow", 0.5), ("Normal", 1.0), ("Fast", 2.0)
    ]

    /// Density is a continuous Double: 0.1 = very sparse, 1.0 = one stream per
    /// column slot, 2.0 = two overlapping streams per slot ("super dense").
    static let densityRange: ClosedRange<Double> = 0.1 ... 5.0

    static let glyphSizeOptions: [(label: String, value: CGFloat)] = [
        ("Small", 10), ("Normal", 16), ("Large", 22)
    ]

    static let trailLengthOptions: [(label: String, value: Int)] = [
        ("Short", 12), ("Normal", 22), ("Long", 35)
    ]

    /// Column spacing multiplier — fraction of glyph cell used as horizontal step.
    static let columnSpacingOptions: [(label: String, multiplier: CGFloat)] = [
        ("Wide", 1.00), ("Narrow", 0.75)
    ]

    /// Spectrafall cycle speed — seconds spent drifting from one preset to the
    /// next. Full loop = secondsPerPreset × spectraCyclePath.count.
    static let spectrafallSpeedOptions: [(label: String, secondsPerPreset: Double)] = [
        ("Slow", 90), ("Normal", 45), ("Fast", 20)
    ]

    /// The Spectrafall traversal order — presets sorted by hue so adjacent
    /// blends stay saturated and natural (red → orange → amber → green →
    /// cyan → blue → purple → pink → wrap). White is excluded: a slow fade
    /// to grayscale mid-cycle reads as a malfunction, not a feature.
    static let spectraCyclePath: [ColorPreset] = [
        .red, .orange, .amber, .matrixGreen, .cyan, .blue, .amethyst, .pink
    ]

    /// Spectrafall and Chromafall are mutually exclusive. One canonical rule,
    /// applied everywhere settings enter the system (defaults load, JSON
    /// import, UI collect): Spectrafall wins.
    mutating func resolveExclusiveModes() {
        if spectrafallEnabled { colorZonesEnabled = false }
    }

    /// Fonts offered in the clock font picker.
    /// Every entry ships with macOS 14 Sonoma.
    static let clockFontOptions: [(label: String, name: String)] = [
        ("Helvetica Neue",        "Helvetica Neue"),
        ("Avenir",                "Avenir"),
        ("Futura",                "Futura"),
        ("Gill Sans",             "Gill Sans"),
        ("Optima",                "Optima"),
        ("Trebuchet MS",          "Trebuchet MS"),
        ("Baskerville",           "Baskerville"),
        ("Didot",                 "Didot"),
        ("Georgia",               "Georgia"),
        ("American Typewriter",   "American Typewriter"),
        ("Impact",                "Impact"),
        ("Menlo",                 "Menlo"),
        ("Courier New",           "Courier New"),
    ]

    static let clockFontSizeRange: ClosedRange<CGFloat> = 36 ... 144

    /// Pre-loaded messages for the message-overlay picker.
    /// The first entry is the default selection shown in the popup.
    static let messagePresets: [String] = [
        "CYPHΞRFALL",
        "WAKE UP NEO",
        "THE MATRIX HAS YOU",
        "FOLLOW THE WHITE RABBIT",
        "THERE IS NO SPOON",
        "FREE YOUR MIND",
        "KNOCK KNOCK",
    ]

    static func nearest<T: FloatingPoint>(in options: [(label: String, value: T)], to current: T) -> Int {
        options.enumerated()
            .min(by: { abs($0.element.value - current) < abs($1.element.value - current) })?
            .offset ?? 0
    }

    static func nearest(in options: [(label: String, value: Int)], to current: Int) -> Int {
        options.enumerated()
            .min(by: { abs($0.element.value - current) < abs($1.element.value - current) })?
            .offset ?? 0
    }
}
