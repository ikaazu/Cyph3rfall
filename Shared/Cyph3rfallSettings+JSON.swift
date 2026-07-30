import Foundation
import CoreFoundation

// MARK: - JSON Export / Import

extension Cyph3rfallSettings {

    // Schema version — bump if the format ever changes incompatibly.
    private static let jsonSchemaVersion = 1
    static let jsonMaximumByteCount = 1 * 1024 * 1024

    // ── Export ──────────────────────────────────────────────────────────────

    /// Serialise the current settings to a pretty-printed JSON Data blob.
    /// Security-sensitive fields (password lock, hotkey) are intentionally omitted.
    func jsonData() throws -> Data {
        let dict: [String: Any] = [
            "schemaVersion":        Self.jsonSchemaVersion,
            "speed":                speedMultiplier,
            "density":              density,
            "glyphSize":            Double(glyphSize),
            "trailLength":          trailLength,
            "showGlow":             showGlow,
            "colorPreset":          colorPreset.rawValue,
            "chromafall":           colorZonesEnabled,
            "spectrafall":          spectrafallEnabled,
            "spectrafallSpeed":     spectrafallSpeedIndex,
            "classicDense":         classicDenseMode,
            "columnSpacing":        columnSpacingIndex,
            "primaryDisplayOnly":   primaryDisplayOnly,
            "messageEnabled":       messageEnabled,
            "message":              customMessage,
            "showClock":            showClock,
            "showDate":             showDate,
            "clockColorTiedToPreset": clockColorTiedToPreset,
            "clockFont":            clockFontName,
            "clockSize":            Double(clockFontSize),
        ]
        return try JSONSerialization.data(withJSONObject: dict,
                                         options: [.prettyPrinted, .sortedKeys])
    }

    // ── Import ──────────────────────────────────────────────────────────────

    /// Parse a JSON blob and return a new CyPh3rfallSettings, preserving any
    /// fields not present in the JSON (hotkey, password lock) from `base`.
    static func from(jsonData data: Data, base: Cyph3rfallSettings) throws -> Cyph3rfallSettings {
        guard data.count <= jsonMaximumByteCount else {
            throw ImportError.fileTooLarge
        }
        guard
            let raw  = try? JSONSerialization.jsonObject(with: data),
            let dict = raw as? [String: Any]
        else { throw ImportError.invalidJSON }

        func number(_ key: String) throws -> Double? {
            guard let rawValue = dict[key] else { return nil }
            guard let value = rawValue as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID()
            else { throw ImportError.invalidField(key) }
            let result = value.doubleValue
            guard result.isFinite else { throw ImportError.invalidField(key) }
            return result
        }

        func int(_ key: String) throws -> Int? {
            guard let value = try number(key) else { return nil }
            guard value.rounded(.towardZero) == value,
                  value >= Double(Int.min),
                  value < Double(Int.max)
            else { throw ImportError.invalidField(key) }
            return Int(value)
        }

        func double(_ key: String) throws -> Double? {
            try number(key)
        }

        func bool(_ key: String) throws -> Bool? {
            guard let rawValue = dict[key] else { return nil }
            guard let value = rawValue as? NSNumber,
                  CFGetTypeID(value) == CFBooleanGetTypeID()
            else { throw ImportError.invalidField(key) }
            return value.boolValue
        }

        func string(_ key: String) throws -> String? {
            guard let rawValue = dict[key] else { return nil }
            guard let value = rawValue as? String else {
                throw ImportError.invalidField(key)
            }
            return value
        }

        guard try int("schemaVersion") == jsonSchemaVersion else {
            throw ImportError.unsupportedSchema
        }

        var s = base   // start from base so unlisted fields keep their current values

        if let v = try double("speed") {
            s.speedMultiplier = v.clamped(to: 0.1 ... 4.0)
        }
        if let v = try double("density") {
            s.density = v.clamped(to: densityRange)
        }
        if let v = try double("glyphSize") {
            s.glyphSize = CGFloat(v).clamped(to: 8 ... 32)
        }
        if let v = try int("trailLength") {
            s.trailLength = v.clamped(to: 4 ... 60)
        }
        if let v = try bool("showGlow")       { s.showGlow         = v }
        if let v = try int("colorPreset"),
           let preset = ColorPreset(rawValue: v) { s.colorPreset = preset }
        if let v = try bool("chromafall")     { s.colorZonesEnabled  = v }
        if let v = try bool("spectrafall")    { s.spectrafallEnabled = v }
        if let v = try int("spectrafallSpeed") {
            s.spectrafallSpeedIndex = v.clamped(to: 0 ..< spectrafallSpeedOptions.count)
        }
        if let v = try bool("classicDense")   { s.classicDenseMode   = v }
        if let v = try int("columnSpacing")      { s.columnSpacingIndex  = v.clamped(to: 0 ..< columnSpacingOptions.count) }
        if let v = try bool("primaryDisplayOnly") { s.primaryDisplayOnly = v }
        if let v = try bool("messageEnabled") { s.messageEnabled     = v }
        if let v = try string("message")      { s.customMessage      = String(v.prefix(30)) }
        if let v = try bool("showClock")      { s.showClock          = v }
        if let v = try bool("showDate")       { s.showDate           = v }
        if let v = try bool("clockColorTiedToPreset") { s.clockColorTiedToPreset = v }
        if let v = try string("clockFont"), !v.isEmpty {
            s.clockFontName = String(v.prefix(128))
        }
        if let v = try double("clockSize") {
            s.clockFontSize = CGFloat(v).clamped(to: clockFontSizeRange)
        }

        // A hand-edited file can set both chromafall and spectrafall true —
        // apply the same canonical precedence rule used everywhere else.
        s.resolveExclusiveModes()

        return s
    }

    enum ImportError: LocalizedError {
        case invalidJSON
        case fileTooLarge
        case unsupportedSchema
        case invalidField(String)

        var errorDescription: String? {
            switch self {
            case .invalidJSON:
                return "The file is not valid JSON."
            case .fileTooLarge:
                return "The settings file is larger than 1 MB."
            case .unsupportedSchema:
                return "The settings file uses an unsupported schema version."
            case .invalidField(let field):
                return "The settings field “\(field)” has an unsupported value type."
            }
        }
    }
}

// MARK: - Clamp helpers
// Internal (not private) so Cyph3rfallSettings+Defaults can use the same extensions.

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
    func clamped(to range: Range<Int>) -> Int {
        guard !range.isEmpty else { return self }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound - 1)
    }
}
