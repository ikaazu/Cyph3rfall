import Foundation

// MARK: - JSON Export / Import

extension Cyph3rfallSettings {

    // Schema version — bump if the format ever changes incompatibly.
    private static let jsonSchemaVersion = 1

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
            "classicDense":         classicDenseMode,
            "columnSpacing":        columnSpacingIndex,
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
        guard
            let raw  = try? JSONSerialization.jsonObject(with: data),
            let dict = raw as? [String: Any]
        else { throw ImportError.invalidJSON }

        func int(_ k: String)    -> Int?    { dict[k] as? Int    ?? (dict[k] as? Double).map { Int($0) } }
        func double(_ k: String) -> Double? { dict[k] as? Double }
        func bool(_ k: String)   -> Bool?   { dict[k] as? Bool   }
        func string(_ k: String) -> String? { dict[k] as? String }

        var s = base   // start from base so unlisted fields keep their current values

        if let v = double("speed") {
            s.speedMultiplier = v.clamped(to: 0.1 ... 4.0)
        }
        if let v = double("density") {
            s.density = v.clamped(to: densityRange)
        }
        if let v = double("glyphSize") {
            s.glyphSize = CGFloat(v).clamped(to: 8 ... 32)
        }
        if let v = int("trailLength") {
            s.trailLength = v.clamped(to: 4 ... 60)
        }
        if let v = bool("showGlow")       { s.showGlow         = v }
        if let v = int("colorPreset"),
           let preset = ColorPreset(rawValue: v) { s.colorPreset = preset }
        if let v = bool("chromafall")     { s.colorZonesEnabled  = v }
        if let v = bool("classicDense")   { s.classicDenseMode   = v }
        if let v = int("columnSpacing")   { s.columnSpacingIndex = v.clamped(to: 0 ..< columnSpacingOptions.count) }
        if let v = bool("messageEnabled") { s.messageEnabled     = v }
        if let v = string("message")      { s.customMessage      = String(v.prefix(30)) }
        if let v = bool("showClock")      { s.showClock          = v }
        if let v = bool("showDate")       { s.showDate           = v }
        if let v = bool("clockColorTiedToPreset") { s.clockColorTiedToPreset = v }
        if let v = string("clockFont")    { s.clockFontName      = v }
        if let v = double("clockSize") {
            s.clockFontSize = CGFloat(v).clamped(to: clockFontSizeRange)
        }

        return s
    }

    enum ImportError: LocalizedError {
        case invalidJSON
        var errorDescription: String? { "The file could not be read as a valid Cyph3rfall settings file." }
    }
}

// MARK: - Clamp helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
    func clamped(to range: Range<Int>) -> Int {
        guard !range.isEmpty else { return self }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound - 1)
    }
}
