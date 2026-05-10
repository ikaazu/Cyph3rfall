import AppKit

/// Preferences panel for Cyph3rfall.
/// Left side: controls. Right side: live MatrixRainView preview.
final class PreferencesWindowController: NSWindowController {

    var onApply:    ((MatrixRainSettings) -> Void)?
    var onStartNow: (() -> Void)?

    private var speedControl:      NSSegmentedControl!
    private var densitySlider:     NSSlider!
    private var densityValueLabel: NSTextField!
    private var sizeControl:       NSSegmentedControl!
    private var colorControl:      NSPopUpButton!
    private var glowCheckbox:      NSButton!
    private var denseCheckbox:     NSButton!
    private var previewRainView:   MatrixRainView!

    private var originalSettings: MatrixRainSettings

    // MARK: - Init

    init(settings: MatrixRainSettings) {
        self.originalSettings = settings

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Cyph3rfall Settings"
        panel.isReleasedWhenClosed = false

        super.init(window: panel)
        buildUI()
        populate(from: settings)
    }

    required init?(coder: NSCoder) { fatalError("use init(settings:)") }

    func refresh(from settings: MatrixRainSettings) {
        originalSettings = settings
        populate(from: settings)
        if !previewRainView.isAnimating { previewRainView.startAnimation() }
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // ── Controls ──────────────────────────────────────────────────

        speedControl = segmented(from: MatrixRainSettings.speedOptions.map(\.label))
        speedControl.target = self
        speedControl.action = #selector(controlChanged(_:))

        sizeControl = segmented(from: MatrixRainSettings.glyphSizeOptions.map(\.label))
        sizeControl.target = self
        sizeControl.action = #selector(controlChanged(_:))

        densitySlider = NSSlider(value: 0.9,
                                 minValue: MatrixRainSettings.densityRange.lowerBound,
                                 maxValue: MatrixRainSettings.densityRange.upperBound,
                                 target: self, action: #selector(densityChanged(_:)))
        densitySlider.isContinuous = true

        densityValueLabel = NSTextField(labelWithString: "90%")
        densityValueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        densityValueLabel.alignment = .right
        densityValueLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true

        colorControl = NSPopUpButton(frame: .zero, pullsDown: false)
        for preset in MatrixRainSettings.ColorPreset.allCases {
            colorControl.addItem(withTitle: preset.label)
            colorControl.lastItem?.tag   = preset.rawValue
            colorControl.lastItem?.image = swatch(preset.foregroundColor)
        }
        colorControl.target = self
        colorControl.action = #selector(controlChanged(_:))

        glowCheckbox = NSButton(checkboxWithTitle: "Enable glow on the leading glyph",
                                target: self, action: #selector(controlChanged(_:)))
        denseCheckbox = NSButton(checkboxWithTitle: "Classic dense mode  (overrides density & trail)",
                                 target: self, action: #selector(controlChanged(_:)))

        let rows: [NSView] = [
            row(label: "Speed",      control: speedControl),
            densityRow(),
            row(label: "Glyph Size", control: sizeControl),
            row(label: "Color",      control: colorControl),
            row(label: "Glow",       control: glowCheckbox),
            row(label: "Dense Mode", control: denseCheckbox),
        ]

        let startBtn  = NSButton(title: "▶  Start Now", target: self, action: #selector(startNow))
        startBtn.bezelStyle = .rounded
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.keyEquivalent = "\u{1b}"
        let okBtn = NSButton(title: "OK", target: self, action: #selector(ok))
        okBtn.keyEquivalent = "\r"
        okBtn.bezelStyle = .rounded

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        btnRow.addView(startBtn,  in: .leading)
        btnRow.addView(cancelBtn, in: .trailing)
        btnRow.addView(okBtn,     in: .trailing)

        let divider = NSBox(); divider.boxType = .separator

        // Controls column — fixed width, vertically stacked
        let controlsStack = NSStackView(views: rows + [divider, btnRow])
        controlsStack.orientation = .vertical
        controlsStack.spacing     = 12
        controlsStack.alignment   = .leading
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(controlsStack)

        // ── Vertical separator ────────────────────────────────────────

        let vSep = NSView()
        vSep.wantsLayer = true
        vSep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        vSep.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(vSep)

        // ── Live preview ──────────────────────────────────────────────

        previewRainView = MatrixRainView(frame: .zero)
        previewRainView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(previewRainView)

        let previewLabel = NSTextField(labelWithString: "Live Preview")
        previewLabel.font       = .systemFont(ofSize: 10, weight: .medium)
        previewLabel.textColor  = .tertiaryLabelColor
        previewLabel.alignment  = .center
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(previewLabel)

        // ── Explicit layout ───────────────────────────────────────────

        let margin: CGFloat = 20
        let gap:    CGFloat = 14

        NSLayoutConstraint.activate([
            // Controls column: left side, fixed width
            controlsStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            controlsStack.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            controlsStack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -margin),
            controlsStack.widthAnchor.constraint(equalToConstant: 460),

            // Separator: 1 px wide, full height
            vSep.leadingAnchor.constraint(equalTo: controlsStack.trailingAnchor, constant: gap),
            vSep.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            vSep.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            vSep.widthAnchor.constraint(equalToConstant: 1),

            // Preview: fills remaining width, top-to-above-label
            previewRainView.leadingAnchor.constraint(equalTo: vSep.trailingAnchor, constant: gap),
            previewRainView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            previewRainView.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            previewRainView.bottomAnchor.constraint(equalTo: previewLabel.topAnchor, constant: -6),

            // Label: centred below preview
            previewLabel.centerXAnchor.constraint(equalTo: previewRainView.centerXAnchor),
            previewLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),
        ])

        previewRainView.startAnimation()
    }

    // MARK: - Helpers

    private func segmented(from labels: [String]) -> NSSegmentedControl {
        NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
    }

    private func swatch(_ color: NSColor) -> NSImage {
        let sz: CGFloat = 12
        let image = NSImage(size: NSSize(width: sz, height: sz))
        image.lockFocus()
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: sz, height: sz),
                     xRadius: 2.5, yRadius: 2.5).fill()
        image.unlockFocus()
        return image
    }

    private func densityRow() -> NSStackView {
        let lbl = NSTextField(labelWithString: "Density:")
        lbl.font = .systemFont(ofSize: NSFont.systemFontSize)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 82).isActive = true

        let h = NSStackView(views: [lbl, densitySlider, densityValueLabel])
        h.orientation = .horizontal
        h.spacing     = 12
        h.alignment   = .centerY
        return h
    }

    private func row(label text: String, control: NSView) -> NSStackView {
        let lbl = NSTextField(labelWithString: text + ":")
        lbl.font = .systemFont(ofSize: NSFont.systemFontSize)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 82).isActive = true

        let h = NSStackView(views: [lbl, control])
        h.orientation = .horizontal
        h.spacing     = 12
        h.alignment   = .centerY
        return h
    }

    // MARK: - Populate / collect

    private func populate(from s: MatrixRainSettings) {
        speedControl.selectedSegment  = MatrixRainSettings.nearest(in: MatrixRainSettings.speedOptions,     to: s.speedMultiplier)
        sizeControl.selectedSegment   = MatrixRainSettings.nearest(in: MatrixRainSettings.glyphSizeOptions, to: s.glyphSize)
        densitySlider.doubleValue     = s.density
        densityValueLabel.stringValue = densityText(s.density)
        colorControl.selectItem(withTag: s.colorPreset.rawValue)
        glowCheckbox.state  = s.showGlow         ? .on : .off
        denseCheckbox.state = s.classicDenseMode ? .on : .off
        previewRainView?.settings = s
    }

    private func collect() -> MatrixRainSettings {
        var s = originalSettings
        s.speedMultiplier  = MatrixRainSettings.speedOptions[speedControl.selectedSegment].value
        s.density          = densitySlider.doubleValue
        s.glyphSize        = MatrixRainSettings.glyphSizeOptions[sizeControl.selectedSegment].value
        s.colorPreset      = MatrixRainSettings.ColorPreset(rawValue: colorControl.selectedTag()) ?? .matrixGreen
        s.showGlow         = glowCheckbox.state  == .on
        s.classicDenseMode = denseCheckbox.state == .on
        return s
    }

    // MARK: - Actions

    @objc private func controlChanged(_ sender: Any) {
        previewRainView.settings = collect()
    }

    @objc private func densityChanged(_ sender: NSSlider) {
        densityValueLabel.stringValue = densityText(sender.doubleValue)
        previewRainView.settings = collect()
    }

    private func densityText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    @objc private func ok() {
        onApply?(collect())
        dismiss()
    }

    @objc private func cancel() {
        dismiss()
    }

    @objc private func startNow() {
        onApply?(collect())
        dismiss()
        onStartNow?()
    }

    private func dismiss() {
        previewRainView.stopAnimation()
        guard let sheet = window else { return }
        if let parent = sheet.sheetParent {
            parent.endSheet(sheet)
        } else {
            sheet.orderOut(nil)
        }
    }
}
