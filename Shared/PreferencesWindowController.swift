import AppKit

/// Preferences panel for Cyph3rfall.
/// Left side: controls. Right side: live Cyph3rfallView preview.
final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate {

    var onApply:    ((Cyph3rfallSettings) -> Void)?
    var onStartNow: (() -> Void)?

    private var speedControl:      NSSegmentedControl!
    private var densitySlider:     NSSlider!
    private var densityValueLabel: NSTextField!
    private var sizeControl:          NSSegmentedControl!
    private var trailControl:         NSSegmentedControl!
    private var columnSpacingControl: NSSegmentedControl!
    private var colorControl:      NSPopUpButton!
    private var glowCheckbox:       NSButton!
    private var colorZonesCheckbox: NSButton!
    private var denseCheckbox:      NSButton!
    private var lockCheckbox:      NSButton!
    private var clockCheckbox:     NSButton!
    private var clockFontControl:  NSPopUpButton!
    private var clockSizeSlider:   NSSlider!
    private var clockSizeLabel:    NSTextField!
    private var dateCheckbox:            NSButton!
    private var clockColorPresetCheckbox: NSButton!
    private var messageCheckbox:      NSButton!
    private var messagePresetControl: NSPopUpButton!
    private var messageField:         NSTextField!
    private var messageCountLabel:    NSTextField!
    private var hotkeyRecorder:    HotkeyRecorderView!
    private var previewRainView:   Cyph3rfallView!

    private static let messageLimit = 30

    private var originalSettings: Cyph3rfallSettings

    // MARK: - Init

    init(settings: Cyph3rfallSettings) {
        self.originalSettings = settings

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 740),
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

    func refresh(from settings: Cyph3rfallSettings) {
        originalSettings = settings
        populate(from: settings)
        if !previewRainView.isAnimating { previewRainView.startAnimation() }
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // ── Controls ──────────────────────────────────────────────────

        hotkeyRecorder = HotkeyRecorderView(frame: .zero)
        hotkeyRecorder.onChange = { [weak self] _, _, _ in
            // No live-preview effect for hotkey changes; just keep collect() fresh.
            _ = self?.collect()
        }

        speedControl = segmented(from: Cyph3rfallSettings.speedOptions.map(\.label))
        speedControl.target = self
        speedControl.action = #selector(controlChanged(_:))

        sizeControl = segmented(from: Cyph3rfallSettings.glyphSizeOptions.map(\.label))
        sizeControl.target = self
        sizeControl.action = #selector(controlChanged(_:))

        trailControl = segmented(from: Cyph3rfallSettings.trailLengthOptions.map(\.label))
        trailControl.target = self
        trailControl.action = #selector(controlChanged(_:))

        columnSpacingControl = segmented(from: Cyph3rfallSettings.columnSpacingOptions.map(\.label))
        columnSpacingControl.target = self
        columnSpacingControl.action = #selector(controlChanged(_:))

        densitySlider = NSSlider(value: 1.5,
                                 minValue: Cyph3rfallSettings.densityRange.lowerBound,
                                 maxValue: Cyph3rfallSettings.densityRange.upperBound,
                                 target: self, action: #selector(densityChanged(_:)))
        densitySlider.isContinuous = true

        densityValueLabel = NSTextField(labelWithString: "150%")
        densityValueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        densityValueLabel.alignment = .right
        densityValueLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true

        colorControl = NSPopUpButton(frame: .zero, pullsDown: false)
        for preset in Cyph3rfallSettings.ColorPreset.allCases {
            colorControl.addItem(withTitle: preset.label)
            colorControl.lastItem?.tag   = preset.rawValue
            colorControl.lastItem?.image = swatch(preset.foregroundColor)
        }
        colorControl.target = self
        colorControl.action = #selector(controlChanged(_:))

        glowCheckbox = NSButton(checkboxWithTitle: "Enable glow on the leading glyph",
                                target: self, action: #selector(controlChanged(_:)))

        colorZonesCheckbox = NSButton(checkboxWithTitle: "Enable Chromafall",
                                      target: self, action: #selector(controlChanged(_:)))

        denseCheckbox = NSButton(checkboxWithTitle: "Classic dense mode",
                                 target: self, action: #selector(denseModeToggled(_:)))

        // ── Clock controls ────────────────────────────────────────────────
        clockCheckbox = NSButton(checkboxWithTitle: "Show clock overlay",
                                 target: self, action: #selector(clockToggled(_:)))

        clockFontControl = NSPopUpButton(frame: .zero, pullsDown: false)  // default selection set in populate()
        for option in Cyph3rfallSettings.clockFontOptions {
            let item = NSMenuItem(title: option.label, action: nil, keyEquivalent: "")
            // Render each menu item in its own font so users can preview the style.
            if let f = NSFont(name: option.name, size: 13) {
                item.attributedTitle = NSAttributedString(
                    string: option.label, attributes: [.font: f])
            }
            clockFontControl.menu?.addItem(item)
        }
        clockFontControl.target = self
        clockFontControl.action = #selector(controlChanged(_:))

        let sizeRange = Cyph3rfallSettings.clockFontSizeRange
        clockSizeSlider = NSSlider(value: 80,
                                   minValue: Double(sizeRange.lowerBound),
                                   maxValue: Double(sizeRange.upperBound),
                                   target: self, action: #selector(clockSizeChanged(_:)))
        clockSizeSlider.isContinuous = true

        clockSizeLabel = NSTextField(labelWithString: "80 pt")
        clockSizeLabel.font      = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        clockSizeLabel.alignment = .right
        clockSizeLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true

        dateCheckbox = NSButton(checkboxWithTitle: "Show date below clock",
                                target: self, action: #selector(controlChanged(_:)))

        clockColorPresetCheckbox = NSButton(checkboxWithTitle: "Match clock colour to rain preset",
                                            target: self, action: #selector(controlChanged(_:)))

        // ── Custom message ────────────────────────────────────────────────

        messageCheckbox = NSButton(checkboxWithTitle: "Show message overlay",
                                   target: self, action: #selector(messageToggled(_:)))

        // Preset picker — selecting an item copies the preset into the text field.
        messagePresetControl = NSPopUpButton(frame: .zero, pullsDown: false)
        for (i, preset) in Cyph3rfallSettings.messagePresets.enumerated() {
            messagePresetControl.addItem(withTitle: preset)
            messagePresetControl.lastItem?.tag = i
        }
        messagePresetControl.menu?.addItem(.separator())
        messagePresetControl.addItem(withTitle: "Clear message")
        messagePresetControl.lastItem?.tag = -1
        messagePresetControl.target = self
        messagePresetControl.action = #selector(messagePresetSelected(_:))

        let msgFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // Width: 32 character slots (30-char limit + 1 visible margin each side).
        let charW      = ("W" as NSString).size(withAttributes: [.font: msgFont]).width
        let fieldWidth = ceil(charW * 32) + 10   // +10 for NSTextField's internal padding

        messageField = NSTextField(string: "")
        messageField.placeholderString = "Type a custom message…"
        messageField.delegate          = self
        messageField.font              = msgFont
        messageField.maximumNumberOfLines = 1
        messageField.widthAnchor.constraint(equalToConstant: fieldWidth).isActive = true
        messageField.setContentHuggingPriority(.required, for: .horizontal)

        messageCountLabel = NSTextField(labelWithString: "0/\(Self.messageLimit)")
        messageCountLabel.font      = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        messageCountLabel.textColor = .tertiaryLabelColor
        messageCountLabel.alignment = .right
        messageCountLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true

        // ── Lock control ──────────────────────────────────────────────────
        lockCheckbox = NSButton(checkboxWithTitle: "Require password to dismiss",
                                target: self, action: #selector(controlChanged(_:)))

        // Thin separators between sections
        let shortcutSep = NSBox(); shortcutSep.boxType = .separator
        let messageSep  = NSBox(); messageSep.boxType  = .separator
        let lockSep     = NSBox(); lockSep.boxType     = .separator
        let clockSep    = NSBox(); clockSep.boxType    = .separator

        let denseControl = withInfo(
            denseCheckbox,
            tooltip: "Replicates the classic Matrix screensaver look. Density and Trail Length are overridden (those controls are disabled while active). Speed is set to a minimum of 1.5× — selecting Fast still increases it further.")

        let lockControl = withInfo(
            lockCheckbox,
            tooltip: "When activated by idle timeout: password is required immediately.\nWhen started manually via Start Now: password is only required once your configured idle timeout has elapsed with no activity.")

        let rows: [NSView] = [
            row(label: "Shortcut", control: withInfo(
                hotkeyRecorder,
                tooltip: "A global keyboard shortcut that starts the screensaver from anywhere, even when another app is in front. Click the field to record a combo, or press Delete to clear it. Requires at least one modifier key (⌘, ⌥, ⌃, or ⇧).")),
            shortcutSep,
            row(label: "Speed",        control: speedControl),
            densityRow(),
            row(label: "Glyph Size",   control: sizeControl),
            row(label: "Trail Length", control: trailControl),
            row(label: "Columns",      control: columnSpacingControl),
            row(label: "Color",        control: colorControl),
            row(label: "Chromafall",   control: withInfo(
                colorZonesCheckbox,
                tooltip: "Gives every falling stream its own randomly chosen colour. The colour is re-picked each time a stream wraps from the bottom back to the top, so the screen is always in motion.")),
            row(label: "Glow",         control: glowCheckbox),
            row(label: "Dense Mode",   control: denseControl),
            messageSep,
            row(label: "Message", control: messageCheckbox),
            row(label: "Preset",  control: messagePresetControl),
            messageFieldRow(),
            messageNote(),
            lockSep,
            row(label: "Lock",         control: lockControl),
            clockSep,
            row(label: "Clock",        control: clockCheckbox),
            row(label: "Font",         control: clockFontControl),
            clockSizeRow(),
            row(label: "Date",         control: dateCheckbox),
            row(label: "Clock Colour", control: clockColorPresetCheckbox),
        ]

        let startBtn  = NSButton(title: "▶  Start Now", target: self, action: #selector(startNow))
        startBtn.bezelStyle = .rounded
        let resetBtn  = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        resetBtn.bezelStyle = .rounded
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.keyEquivalent = "\u{1b}"
        let okBtn = NSButton(title: "OK", target: self, action: #selector(ok))
        okBtn.keyEquivalent = "\r"
        okBtn.bezelStyle = .rounded

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        btnRow.addView(startBtn,  in: .leading)
        btnRow.addView(resetBtn,  in: .leading)
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

        previewRainView = Cyph3rfallView(frame: .zero)
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

        // Wrap slider + tick-label bar so they share the same width
        let tickBar = DensityTickBar(slider: densitySlider)
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        densitySlider.translatesAutoresizingMaskIntoConstraints = false
        tickBar.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(densitySlider)
        wrapper.addSubview(tickBar)
        NSLayoutConstraint.activate([
            densitySlider.topAnchor.constraint(equalTo: wrapper.topAnchor),
            densitySlider.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            densitySlider.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            tickBar.topAnchor.constraint(equalTo: densitySlider.bottomAnchor, constant: 0),
            tickBar.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            tickBar.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            tickBar.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            tickBar.heightAnchor.constraint(equalToConstant: 14),
        ])

        let h = NSStackView(views: [lbl, wrapper, densityValueLabel])
        h.orientation = .horizontal
        h.spacing     = 12
        h.alignment   = .centerY
        return h
    }

    /// Wraps a control in a horizontal stack with a small ⓘ icon to its right.
    /// Hovering over the icon shows `tooltip` as a native macOS tooltip.
    private func withInfo(_ control: NSView, tooltip: String) -> NSStackView {
        // Use SymbolConfiguration to size the icon — avoids activating explicit
        // constraints before the view is in a hierarchy, which caused the
        // "-layoutSubtreeIfNeeded on a view already being laid out" recursion warning.
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image  = NSImage(systemSymbolName: "info.circle",
                             accessibilityDescription: "Information")?
                     .withSymbolConfiguration(config)
        let icon = NSImageView(image: image ?? NSImage())
        icon.contentTintColor = .tertiaryLabelColor
        icon.toolTip = tooltip

        let stack = NSStackView(views: [control, icon])
        stack.orientation = .horizontal
        stack.spacing     = 6
        stack.alignment   = .centerY
        return stack
    }

    /// Small footnote nudging users to raise density for the message effect.
    private func messageNote() -> NSView {
        let note = NSTextField(labelWithString:
            "⬆ For the best message effect, set Density to 200% or higher.")
        note.font      = .systemFont(ofSize: 10.5, weight: .regular)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 0

        // Indent to align with the control column (past the 82 pt label + 12 pt gap).
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 94).isActive = true

        let h = NSStackView(views: [spacer, note])
        h.orientation = .horizontal
        h.spacing     = 0
        h.alignment   = .top
        return h
    }

    /// Indented row containing the editable text field, character count, and ⓘ icon.
    /// Sits directly below the preset-picker row, aligned with the control column.
    private func messageFieldRow() -> NSView {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let img    = NSImage(systemSymbolName: "info.circle",
                             accessibilityDescription: "Information")?
                    .withSymbolConfiguration(config)
        let icon = NSImageView(image: img ?? NSImage())
        icon.contentTintColor = .tertiaryLabelColor
        icon.toolTip = "A short phrase (up to \(Self.messageLimit) characters) that materializes in the rain — each character lights up as a falling column passes through it, then slowly fades. Uppercase is applied automatically; longer phrases may be clipped on smaller screens."

        // Spacer aligns the field with the control column (82 pt label + 12 pt gap).
        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 94).isActive = true

        let h = NSStackView(views: [spacer, messageField, messageCountLabel, icon])
        h.orientation = .horizontal
        h.spacing     = 8
        h.alignment   = .centerY
        return h
    }

    private func clockSizeRow() -> NSStackView {
        let lbl = NSTextField(labelWithString: "Size:")
        lbl.font = .systemFont(ofSize: NSFont.systemFontSize)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 82).isActive = true

        let h = NSStackView(views: [lbl, clockSizeSlider, clockSizeLabel])
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

    private func populate(from s: Cyph3rfallSettings) {
        hotkeyRecorder.configure(
            keyCode:       s.hotkeyCode,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(s.hotkeyModifiers)),
            character:     s.hotkeyCharacter)

        speedControl.selectedSegment  = Cyph3rfallSettings.nearest(in: Cyph3rfallSettings.speedOptions,     to: s.speedMultiplier)
        sizeControl.selectedSegment          = Cyph3rfallSettings.nearest(in: Cyph3rfallSettings.glyphSizeOptions, to: s.glyphSize)
        columnSpacingControl.selectedSegment = s.columnSpacingIndex
        trailControl.selectedSegment  = Cyph3rfallSettings.trailLengthOptions
            .enumerated()
            .min(by: { abs($0.element.value - s.trailLength) < abs($1.element.value - s.trailLength) })?
            .offset ?? 1
        densitySlider.doubleValue     = s.density
        densityValueLabel.stringValue = densityText(s.density)
        colorControl.selectItem(withTag: s.colorPreset.rawValue)
        glowCheckbox.state       = s.showGlow         ? .on : .off
        colorZonesCheckbox.state = s.colorZonesEnabled ? .on : .off
        denseCheckbox.state      = s.classicDenseMode  ? .on : .off
        lockCheckbox.state  = s.requirePassword   ? .on : .off
        updateDenseModeControlsEnabled(!s.classicDenseMode)
        messageCheckbox.state = s.messageEnabled ? .on : .off
        updateMessageControlsEnabled(s.messageEnabled)
        messageField.stringValue = s.customMessage
        updateMessageCount(s.customMessage.count)
        syncPresetPopup(to: s.customMessage)

        // Clock
        clockCheckbox.state            = s.showClock              ? .on : .off
        dateCheckbox.state             = s.showDate               ? .on : .off
        clockColorPresetCheckbox.state = s.clockColorTiedToPreset ? .on : .off
        clockSizeSlider.doubleValue = Double(s.clockFontSize)
        clockSizeLabel.stringValue  = "\(Int(s.clockFontSize)) pt"
        let fontIdx = Cyph3rfallSettings.clockFontOptions
            .firstIndex(where: { $0.name == s.clockFontName }) ?? 0
        clockFontControl.selectItem(at: fontIdx)
        updateClockControlsEnabled(s.showClock)

        previewRainView?.settings = s
    }

    private func collect() -> Cyph3rfallSettings {
        var s = originalSettings
        s.speedMultiplier  = Cyph3rfallSettings.speedOptions[speedControl.selectedSegment].value
        s.density          = densitySlider.doubleValue
        s.glyphSize          = Cyph3rfallSettings.glyphSizeOptions[sizeControl.selectedSegment].value
        s.trailLength        = Cyph3rfallSettings.trailLengthOptions[trailControl.selectedSegment].value
        s.columnSpacingIndex = columnSpacingControl.selectedSegment
        s.colorPreset      = Cyph3rfallSettings.ColorPreset(rawValue: colorControl.selectedTag()) ?? .matrixGreen
        s.showGlow          = glowCheckbox.state       == .on
        s.colorZonesEnabled = colorZonesCheckbox.state == .on
        s.classicDenseMode  = denseCheckbox.state      == .on
        s.requirePassword   = lockCheckbox.state  == .on
        s.messageEnabled   = messageCheckbox.state == .on
        s.customMessage    = String(messageField.stringValue.uppercased().prefix(30))
        s.hotkeyCode       = hotkeyRecorder.keyCode
        s.hotkeyModifiers  = Int(hotkeyRecorder.modifierFlags.rawValue)
        s.hotkeyCharacter  = hotkeyRecorder.character
        s.showClock              = clockCheckbox.state            == .on
        s.showDate               = dateCheckbox.state             == .on
        s.clockColorTiedToPreset = clockColorPresetCheckbox.state == .on
        s.clockFontSize    = CGFloat(clockSizeSlider.doubleValue)
        let fi = clockFontControl.indexOfSelectedItem
        if fi >= 0 && fi < Cyph3rfallSettings.clockFontOptions.count {
            s.clockFontName = Cyph3rfallSettings.clockFontOptions[fi].name
        }
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

    @objc private func denseModeToggled(_ sender: NSButton) {
        let on = sender.state == .on
        updateDenseModeControlsEnabled(!on)
        previewRainView.settings = collect()
    }

    @objc private func clockToggled(_ sender: NSButton) {
        let on = sender.state == .on
        updateClockControlsEnabled(on)
        previewRainView.settings = collect()
    }

    func controlTextDidChange(_ obj: Notification) {
        // Enforce limit and auto-uppercase as the user types.
        var text = messageField.stringValue.uppercased()
        if text.count > Self.messageLimit { text = String(text.prefix(Self.messageLimit)) }
        if messageField.stringValue != text { messageField.stringValue = text }
        updateMessageCount(text.count)
        // Keep the preset popup in sync — if the user types a preset verbatim,
        // highlight it; otherwise leave the popup showing whatever was last selected.
        syncPresetPopup(to: text)
        previewRainView.settings = collect()
    }

    @objc private func clockSizeChanged(_ sender: NSSlider) {
        clockSizeLabel.stringValue = "\(Int(sender.doubleValue)) pt"
        previewRainView.settings = collect()
    }

    @objc private func messageToggled(_ sender: NSButton) {
        updateMessageControlsEnabled(sender.state == .on)
        previewRainView.settings = collect()
    }

    private func updateMessageControlsEnabled(_ enabled: Bool) {
        messagePresetControl.isEnabled = enabled
        messageField.isEnabled         = enabled
        messageCountLabel.isEnabled    = enabled
    }

    @objc private func messagePresetSelected(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        if tag == -1 {
            // "Clear message" — wipe the text field.
            messageField.stringValue = ""
            updateMessageCount(0)
        } else if tag >= 0, tag < Cyph3rfallSettings.messagePresets.count {
            let preset = Cyph3rfallSettings.messagePresets[tag]
            messageField.stringValue = preset
            updateMessageCount(preset.count)
        }
        previewRainView.settings = collect()
    }

    /// Selects the matching preset in the popup if `text` equals one of the
    /// preset strings exactly. Call this whenever the text field changes so
    /// the two controls stay in sync.
    private func syncPresetPopup(to text: String) {
        guard let idx = Cyph3rfallSettings.messagePresets.firstIndex(of: text) else { return }
        messagePresetControl.selectItem(withTag: idx)
    }

    private func updateMessageCount(_ count: Int) {
        messageCountLabel.stringValue = "\(count)/\(Self.messageLimit)"
        messageCountLabel.textColor   = count == Self.messageLimit ? .systemOrange : .tertiaryLabelColor
    }

    private func updateDenseModeControlsEnabled(_ enabled: Bool) {
        densitySlider.isEnabled     = enabled
        densityValueLabel.isEnabled = enabled
        trailControl.isEnabled      = enabled
    }

    private func updateClockControlsEnabled(_ enabled: Bool) {
        clockFontControl.isEnabled         = enabled
        clockSizeSlider.isEnabled          = enabled
        clockSizeLabel.isEnabled           = enabled
        dateCheckbox.isEnabled             = enabled
        clockColorPresetCheckbox.isEnabled = enabled
    }

    private func densityText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    @objc private func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText     = "Reset All Settings?"
        alert.informativeText = "This will restore every setting to its default value. Click OK to apply, or Cancel to go back. Nothing is saved until you click OK in the settings window."
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        populate(from: .default)
        previewRainView.settings = collect()
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
        // Pause the preview while the screensaver runs, but leave the window
        // open so the user can continue tweaking settings after dismissing.
        previewRainView.stopAnimation()
        onStartNow?()
    }

    /// Called by AppDelegate when the screensaver dismisses. Restarts the
    /// preview and brings the settings window back to the front.
    func resumePreview() {
        guard window?.isVisible == true else { return }
        if !previewRainView.isAnimating { previewRainView.startAnimation() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

// MARK: - Density tick-label bar

/// Draws labelled reference markers below the density slider at the exact
/// proportional positions for 100 %, 200 %, 300 %, 400 %, and Max (500 %).
/// Positions are recomputed in every layout pass so they track the slider
/// perfectly regardless of window resizing or font scaling.
private final class DensityTickBar: NSView {

    private struct Tick { let fraction: CGFloat; let label: NSTextField }

    private weak var slider: NSSlider?
    private var ticks: [Tick] = []

    init(slider: NSSlider) {
        self.slider = slider
        super.init(frame: .zero)

        let range  = Cyph3rfallSettings.densityRange          // 0.1 … 5.0
        let span   = range.upperBound - range.lowerBound
        let stops: [(Double, String)] = [
            (1.0, "100%"), (2.0, "200%"), (3.0, "300%"), (4.0, "400%"), (5.0, "Max")
        ]

        for (value, text) in stops {
            let fraction = CGFloat((value - range.lowerBound) / span)

            // Tick line — a hairline indicator above the label text
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.tertiaryLabelColor.cgColor
            addSubview(line)

            let tf = NSTextField(labelWithString: text)
            tf.font      = .systemFont(ofSize: 8.5, weight: .regular)
            tf.textColor = .tertiaryLabelColor
            tf.alignment = .center
            addSubview(tf)

            ticks.append(Tick(fraction: fraction, label: tf))
            _ = line   // kept as subview; we'll position both in layout()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard let slider = slider, bounds.width > 0 else { return }

        // Approximate the NSSlider track inset: the knob centre sits at the
        // slider edge when at min/max, and the knob is roughly as wide as
        // the slider is tall, so inset ≈ sliderHeight / 2.
        let inset  = slider.bounds.height / 2.0
        let trackW = bounds.width - 2.0 * inset

        // Sub-views are interleaved: line₀, label₀, line₁, label₁ …
        for (i, tick) in ticks.enumerated() {
            let centerX = inset + tick.fraction * trackW

            // Tick line: 1 pt wide, 5 pt tall, flush against the slider above
            let line = subviews[i * 2]
            line.frame = CGRect(x: centerX - 0.5, y: bounds.height - 5, width: 1, height: 5)

            // Label: immediately below the tick line
            let lbl = tick.label
            lbl.sizeToFit()
            let sz = lbl.frame.size
            let y  = bounds.height - 5 - sz.height - 1
            lbl.frame = CGRect(x: centerX - sz.width / 2,
                               y: max(0, y),
                               width: sz.width, height: sz.height)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 18)
    }
}
