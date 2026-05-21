import Foundation

extension Cyph3rfallSettings {

    private enum Key {
        static let speedIndex         = "speedIndex"
        static let density            = "density"        // raw Double (0.1 … 5.0)
        static let sizeIndex          = "glyphSizeIndex"
        static let trailLengthIndex   = "trailLengthIndex"
        static let showGlow           = "showGlow"
        static let colorPresetIndex   = "colorPresetIndex"
        static let classicDenseMode   = "classicDenseMode"
        static let colorZonesEnabled  = "colorZonesEnabled"
        static let requirePassword    = "requirePassword"
        static let columnSpacingIndex = "columnSpacingIndex"
        static let showClock              = "showClock"
        static let showDate               = "showDate"
        static let clockColorTiedToPreset = "clockColorTiedToPreset"
        static let clockFontName          = "clockFontName"
        static let clockFontSize          = "clockFontSize"
        static let messageEnabled     = "messageEnabled"
        static let customMessage      = "customMessage"
        static let hotkeyCode         = "hotkeyCode"
        static let hotkeyModifiers    = "hotkeyModifiers"
        static let hotkeyCharacter    = "hotkeyCharacter"
    }

    // MARK: - Load / Save

    static func load() -> Cyph3rfallSettings {
        loadFromFile(appSupportURL) ?? .default
    }

    func save() {
        saveToFile(Cyph3rfallSettings.appSupportURL)
    }

    // MARK: - Internals

    private static var appSupportURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MatrixRainSaver")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.plist")
    }

    private static func loadFromFile(_ url: URL) -> Cyph3rfallSettings? {
        guard
            let data = try? Data(contentsOf: url),
            let raw  = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = raw as? [String: Any]
        else { return nil }

        func int(_ k: String)    -> Int    { dict[k] as? Int    ?? 0 }
        func double(_ k: String) -> Double { dict[k] as? Double ?? -1 }
        func bool(_ k: String)   -> Bool   { dict[k] as? Bool   ?? false }

        var s = Cyph3rfallSettings.default
        s.speedMultiplier  = speedOptions[int(Key.speedIndex).clamped(to: speedOptions.indices)].value
        s.glyphSize        = glyphSizeOptions[int(Key.sizeIndex).clamped(to: glyphSizeOptions.indices)].value
        s.trailLength      = trailLengthOptions[int(Key.trailLengthIndex).clamped(to: trailLengthOptions.indices)].value
        s.showGlow         = bool(Key.showGlow)
        s.colorPreset      = ColorPreset(rawValue: int(Key.colorPresetIndex)
                                .clamped(to: 0 ..< ColorPreset.allCases.count)) ?? .matrixGreen
        s.classicDenseMode  = bool(Key.classicDenseMode)
        s.colorZonesEnabled = bool(Key.colorZonesEnabled)
        s.requirePassword      = bool(Key.requirePassword)
        s.columnSpacingIndex   = int(Key.columnSpacingIndex).clamped(to: 0 ..< columnSpacingOptions.count)
        s.showClock              = bool(Key.showClock)
        s.showDate               = bool(Key.showDate)
        s.clockColorTiedToPreset = bool(Key.clockColorTiedToPreset)
        if let name = dict[Key.clockFontName] as? String, !name.isEmpty {
            s.clockFontName = name
        }
        let rawSize = double(Key.clockFontSize)
        if rawSize > 0 {
            s.clockFontSize = CGFloat(min(max(rawSize,
                Double(Cyph3rfallSettings.clockFontSizeRange.lowerBound)),
                Double(Cyph3rfallSettings.clockFontSizeRange.upperBound)))
        }

        // Density stored as raw Double since the slider replaced the old index.
        let rawDensity = double(Key.density)
        if rawDensity > 0 {
            s.density = min(max(rawDensity, Cyph3rfallSettings.densityRange.lowerBound),
                            Cyph3rfallSettings.densityRange.upperBound)
        }

        s.messageEnabled = bool(Key.messageEnabled)
        if let msg = dict[Key.customMessage] as? String {
            s.customMessage = msg
        }
        // hotkeyCode stored as Int; absence or -1 means no hotkey.
        if let code = dict[Key.hotkeyCode] as? Int, code >= 0 {
            s.hotkeyCode      = code
            s.hotkeyModifiers = dict[Key.hotkeyModifiers] as? Int ?? 0
            s.hotkeyCharacter = dict[Key.hotkeyCharacter] as? String ?? ""
        }
        return s
    }

    private func saveToFile(_ url: URL) {
        let trailIdx = Cyph3rfallSettings.trailLengthOptions
            .enumerated()
            .min(by: { abs($0.element.value - trailLength) < abs($1.element.value - trailLength) })?
            .offset ?? 1

        let dict: [String: Any] = [
            Key.speedIndex:         Cyph3rfallSettings.nearest(in: Cyph3rfallSettings.speedOptions,     to: speedMultiplier),
            Key.density:            density,
            Key.sizeIndex:          Cyph3rfallSettings.nearest(in: Cyph3rfallSettings.glyphSizeOptions, to: glyphSize),
            Key.trailLengthIndex:   trailIdx,
            Key.showGlow:           showGlow,
            Key.colorPresetIndex:   colorPreset.rawValue,
            Key.classicDenseMode:   classicDenseMode,
            Key.colorZonesEnabled:  colorZonesEnabled,
            Key.requirePassword:    requirePassword,
            Key.columnSpacingIndex: columnSpacingIndex,
            Key.showClock:              showClock,
            Key.showDate:               showDate,
            Key.clockColorTiedToPreset: clockColorTiedToPreset,
            Key.clockFontName:          clockFontName,
            Key.clockFontSize:      Double(clockFontSize),
            Key.messageEnabled:     messageEnabled,
            Key.customMessage:      customMessage,
            Key.hotkeyCode:         hotkeyCode,
            Key.hotkeyModifiers:    hotkeyModifiers,
            Key.hotkeyCharacter:    hotkeyCharacter,
        ]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private extension Int {
    func clamped(to range: Range<Int>) -> Int {
        guard !range.isEmpty else { return self }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound - 1)
    }
}
