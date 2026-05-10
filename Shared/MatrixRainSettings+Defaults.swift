import Foundation

extension MatrixRainSettings {

    private enum Key {
        static let speedIndex       = "speedIndex"
        static let density          = "density"        // raw Double (0.1 … 2.0)
        static let sizeIndex        = "glyphSizeIndex"
        static let showGlow         = "showGlow"
        static let colorPresetIndex = "colorPresetIndex"
        static let classicDenseMode = "classicDenseMode"
    }

    // MARK: - Load / Save

    static func load() -> MatrixRainSettings {
        loadFromFile(appSupportURL) ?? .default
    }

    func save() {
        saveToFile(MatrixRainSettings.appSupportURL)
    }

    // MARK: - Internals

    private static var appSupportURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MatrixRainSaver")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.plist")
    }

    private static func loadFromFile(_ url: URL) -> MatrixRainSettings? {
        guard
            let data = try? Data(contentsOf: url),
            let raw  = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = raw as? [String: Any]
        else { return nil }

        func int(_ k: String)    -> Int    { dict[k] as? Int    ?? 0 }
        func double(_ k: String) -> Double { dict[k] as? Double ?? -1 }
        func bool(_ k: String)   -> Bool   { dict[k] as? Bool   ?? false }

        var s = MatrixRainSettings.default
        s.speedMultiplier  = speedOptions[int(Key.speedIndex).clamped(to: speedOptions.indices)].value
        s.glyphSize        = glyphSizeOptions[int(Key.sizeIndex).clamped(to: glyphSizeOptions.indices)].value
        s.showGlow         = bool(Key.showGlow)
        s.colorPreset      = ColorPreset(rawValue: int(Key.colorPresetIndex)
                                .clamped(to: 0 ..< ColorPreset.allCases.count)) ?? .matrixGreen
        s.classicDenseMode = bool(Key.classicDenseMode)

        // Density stored as raw Double since the slider replaced the old index.
        let rawDensity = double(Key.density)
        if rawDensity > 0 {
            s.density = min(max(rawDensity, MatrixRainSettings.densityRange.lowerBound),
                            MatrixRainSettings.densityRange.upperBound)
        }
        return s
    }

    private func saveToFile(_ url: URL) {
        let dict: [String: Any] = [
            Key.speedIndex:       MatrixRainSettings.nearest(in: MatrixRainSettings.speedOptions,     to: speedMultiplier),
            Key.density:          density,
            Key.sizeIndex:        MatrixRainSettings.nearest(in: MatrixRainSettings.glyphSizeOptions, to: glyphSize),
            Key.showGlow:         showGlow,
            Key.colorPresetIndex: colorPreset.rawValue,
            Key.classicDenseMode: classicDenseMode,
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
