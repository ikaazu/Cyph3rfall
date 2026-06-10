import AppKit

/// Preferences panel for Cyph3rfall.
/// Left side: pill-tabbed controls. Right side: live Cyph3rfallView preview.
final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate {

    var onApply:    ((Cyph3rfallSettings) -> Void)?
    var onStartNow: (() -> Void)?

    private var speedControl:      NSSegmentedControl!
    private var densitySlider:     NSSlider!
    private var densityValueLabel: NSTextField!
    private var densityPerfNote:   NSTextField!
    private var sizeControl:          NSSegmentedControl!
    private var trailControl:         NSSegmentedControl!
    private var columnSpacingControl: NSSegmentedControl!
    private var colorControl:      NSPopUpButton!
    private var glowCheckbox:       NSButton!
    private var colorZonesCheckbox: NSButton!
    private var spectrafallCheckbox:     NSButton!
    private var spectrafallSpeedControl: NSSegmentedControl!
    private var denseCheckbox:      NSButton!
    private var primaryDisplayOnlyCheckbox: NSButton!
    private var lockCheckbox:              NSButton!
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

    // Tab management
    private var pillTabBar:      PillTabBar!
    private var tabContentArea = NSView()
    private var tabContentViews: [NSView] = []
    private var currentTabIndex = 0

    // MARK: - Init

    init(settings: Cyph3rfallSettings) {
        self.originalSettings = settings

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
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
        hotkeyRecorder.onChange = { [weak self] _, _, _ in _ = self?.collect() }

        speedControl = segmented(from: Cyph3rfallSettings.speedOptions.map(\.label))
        speedControl.target = self; speedControl.action = #selector(controlChanged(_:))

        sizeControl = segmented(from: Cyph3rfallSettings.glyphSizeOptions.map(\.label))
        sizeControl.target = self; sizeControl.action = #selector(controlChanged(_:))

        trailControl = segmented(from: Cyph3rfallSettings.trailLengthOptions.map(\.label))
        trailControl.target = self; trailControl.action = #selector(controlChanged(_:))

        columnSpacingControl = segmented(from: Cyph3rfallSettings.columnSpacingOptions.map(\.label))
        columnSpacingControl.target = self; columnSpacingControl.action = #selector(controlChanged(_:))

        densitySlider = NSSlider(value: 1.5,
                                 minValue: Cyph3rfallSettings.densityRange.lowerBound,
                                 maxValue: Cyph3rfallSettings.densityRange.upperBound,
                                 target: self, action: #selector(densityChanged(_:)))
        densitySlider.isContinuous = true

        densityValueLabel = NSTextField(labelWithString: "150%")
        densityValueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        densityValueLabel.alignment = .right
        densityValueLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true

        densityPerfNote = NSTextField(labelWithString: "⚡ High density may affect performance.")
        densityPerfNote.font      = .systemFont(ofSize: 11)
        densityPerfNote.textColor = NSColor(calibratedRed: 0.85, green: 0.60, blue: 0.10, alpha: 1)
        densityPerfNote.isHidden  = true   // shown only when density > 151%

        colorControl = NSPopUpButton(frame: .zero, pullsDown: false)
        for preset in Cyph3rfallSettings.ColorPreset.allCases {
            colorControl.addItem(withTitle: preset.label)
            colorControl.lastItem?.tag   = preset.rawValue
            colorControl.lastItem?.image = swatch(preset.foregroundColor)
        }
        colorControl.target = self; colorControl.action = #selector(controlChanged(_:))

        glowCheckbox = NSButton(checkboxWithTitle: "Enable glow on the leading glyph",
                                target: self, action: #selector(controlChanged(_:)))

        colorZonesCheckbox = NSButton(checkboxWithTitle: "Enable Chromafall",
                                      target: self, action: #selector(chromafallToggled(_:)))

        spectrafallCheckbox = NSButton(checkboxWithTitle: "Enable Spectrafall",
                                       target: self, action: #selector(spectrafallToggled(_:)))

        spectrafallSpeedControl = segmented(from: Cyph3rfallSettings.spectrafallSpeedOptions.map(\.label))
        spectrafallSpeedControl.target = self
        spectrafallSpeedControl.action = #selector(controlChanged(_:))

        denseCheckbox = NSButton(checkboxWithTitle: "Classic dense mode",
                                 target: self, action: #selector(denseModeToggled(_:)))

        // Clock controls
        clockCheckbox = NSButton(checkboxWithTitle: "Show clock overlay",
                                 target: self, action: #selector(clockToggled(_:)))

        clockFontControl = NSPopUpButton(frame: .zero, pullsDown: false)
        for option in Cyph3rfallSettings.clockFontOptions {
            let item = NSMenuItem(title: option.label, action: nil, keyEquivalent: "")
            if let f = NSFont(name: option.name, size: 13) {
                item.attributedTitle = NSAttributedString(string: option.label, attributes: [.font: f])
            }
            clockFontControl.menu?.addItem(item)
        }
        clockFontControl.target = self; clockFontControl.action = #selector(controlChanged(_:))

        let sizeRange = Cyph3rfallSettings.clockFontSizeRange
        clockSizeSlider = NSSlider(value: 80,
                                   minValue: Double(sizeRange.lowerBound),
                                   maxValue: Double(sizeRange.upperBound),
                                   target: self, action: #selector(clockSizeChanged(_:)))
        clockSizeSlider.isContinuous = true

        clockSizeLabel = NSTextField(labelWithString: "80 pt")
        clockSizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        clockSizeLabel.alignment = .right
        clockSizeLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true

        dateCheckbox = NSButton(checkboxWithTitle: "Show date below clock",
                                target: self, action: #selector(controlChanged(_:)))

        clockColorPresetCheckbox = NSButton(checkboxWithTitle: "Match clock colour to rain preset",
                                            target: self, action: #selector(controlChanged(_:)))

        // Message controls
        messageCheckbox = NSButton(checkboxWithTitle: "Show message overlay",
                                   target: self, action: #selector(messageToggled(_:)))

        messagePresetControl = NSPopUpButton(frame: .zero, pullsDown: false)
        for (i, preset) in Cyph3rfallSettings.messagePresets.enumerated() {
            messagePresetControl.addItem(withTitle: preset)
            messagePresetControl.lastItem?.tag = i
        }
        messagePresetControl.menu?.addItem(.separator())
        messagePresetControl.addItem(withTitle: "Clear message")
        messagePresetControl.lastItem?.tag = -1
        messagePresetControl.target = self; messagePresetControl.action = #selector(messagePresetSelected(_:))

        let msgFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let charW      = ("W" as NSString).size(withAttributes: [.font: msgFont]).width
        let fieldWidth = ceil(charW * 32) + 10

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

        // Display control
        primaryDisplayOnlyCheckbox = NSButton(
            checkboxWithTitle: "Show clock and message on main display only",
            target: self, action: #selector(controlChanged(_:)))

        // Lock control
        lockCheckbox = NSButton(checkboxWithTitle: "Require password to dismiss",
                                target: self, action: #selector(controlChanged(_:)))

        // ── Separators & info-wrapped controls ────────────────────────

        let shortcutSep = NSBox(); shortcutSep.boxType = .separator
        let lockSep     = NSBox(); lockSep.boxType     = .separator

        let denseControl = withInfo(denseCheckbox,
            tooltip: "Replicates the classic Matrix screensaver look. Density and Trail Length are overridden (those controls are disabled while active). Speed is set to a minimum of 1.5× — selecting Fast still increases it further.")
        let lockControl = withInfo(lockCheckbox,
            tooltip: "When activated by idle timeout: password is required immediately.\nWhen started manually via Start Now: password is only required once your configured idle timeout has elapsed with no activity.")

        // ── Build tab content views ───────────────────────────────────

        let generalContent = makeTabContent(rows: [
            row(label: "Shortcut", control: withInfo(hotkeyRecorder,
                tooltip: "A global keyboard shortcut that starts the screensaver from anywhere, even when another app is in front. Click the field to record a combo, or press Delete to clear it. Requires at least one modifier key (⌘, ⌥, ⌃, or ⇧).")),
            shortcutSep,
            row(label: "Speed",        control: speedControl),
            densityRow(),
            row(label: "Glyph Size",   control: sizeControl),
            row(label: "Trail Length", control: trailControl),
            row(label: "Columns",      control: columnSpacingControl),
            row(label: "Color",        control: colorControl),
            row(label: "Chromafall",   control: withInfo(colorZonesCheckbox,
                tooltip: "Gives every falling stream its own randomly chosen colour. The colour is re-picked each time a stream wraps from the bottom back to the top, so the screen is always in motion.")),
            row(label: "Spectrafall",  control: withInfo(spectrafallCheckbox,
                tooltip: "Slowly drifts the entire rain through every colour preset, blending smoothly from one to the next. The cycle starts from your selected colour. White is skipped to keep the rain saturated. Enabling Spectrafall turns off Chromafall — the two modes can't run together.")),
            row(label: "Cycle Speed",  control: spectrafallSpeedControl),
            row(label: "Glow",         control: glowCheckbox),
            row(label: "Dense Mode",   control: denseControl),
            row(label: "Overlays",     control: primaryDisplayOnlyCheckbox),
            lockSep,
            row(label: "Lock",         control: lockControl),
        ])

        let messageContent = makeTabContent(rows: [
            row(label: "Message", control: messageCheckbox),
            row(label: "Preset",  control: messagePresetControl),
            messageFieldRow(),
            messageNote(),
        ])

        let clockContent = makeTabContent(rows: [
            row(label: "Clock",        control: clockCheckbox),
            row(label: "Font",         control: clockFontControl),
            clockSizeRow(),
            row(label: "Date",         control: dateCheckbox),
            row(label: "Clock Colour", control: clockColorPresetCheckbox),
        ])

        let filesContent = makeFilesTabContent()

        tabContentViews = [generalContent, messageContent, clockContent, filesContent]

        // ── Pill tab bar ──────────────────────────────────────────────

        pillTabBar = PillTabBar(labels: ["General", "Message", "Clock", "Import/Export"])
        pillTabBar.translatesAutoresizingMaskIntoConstraints = false
        pillTabBar.onSelect = { [weak self] index in self?.switchTab(to: index) }
        content.addSubview(pillTabBar)

        // ── Tab content area (layer-backed for CATransition) ──────────

        tabContentArea.translatesAutoresizingMaskIntoConstraints = false
        tabContentArea.wantsLayer = true
        tabContentArea.layer?.masksToBounds = true
        content.addSubview(tabContentArea)

        // Add all content views; clip via hidden flag — only index 0 visible initially.
        // The bottom constraint is required so the container has a defined height and
        // AppKit's hitTest can reach controls inside it (a zero-height container makes
        // all its subviews unresponsive even when they are visually rendered beyond it).
        for (i, view) in tabContentViews.enumerated() {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isHidden = i != 0
            tabContentArea.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: tabContentArea.topAnchor),
                view.leadingAnchor.constraint(equalTo: tabContentArea.leadingAnchor),
                view.widthAnchor.constraint(equalTo: tabContentArea.widthAnchor),
                view.bottomAnchor.constraint(equalTo: tabContentArea.bottomAnchor),
            ])
        }

        // ── Buttons ───────────────────────────────────────────────────

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
        btnRow.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(btnRow)

        let divider = NSBox(); divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(divider)

        // ── Vertical separator ────────────────────────────────────────

        let vSep = NSView()
        vSep.wantsLayer = true
        vSep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        vSep.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(vSep)

        // ── Live preview ──────────────────────────────────────────────

        previewRainView = Cyph3rfallView(frame: .zero)
        previewRainView.isPrimaryDisplay = true   // always show overlays in preview
        // Run the Spectrafall cycle 24× faster in the preview so the colour
        // drift is visible while configuring (Normal: full loop ≈ 15 s here).
        previewRainView.spectraTimeScale = 24
        previewRainView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(previewRainView)

        let previewLabel = NSTextField(labelWithString: "Live Preview")
        previewLabel.font      = .systemFont(ofSize: 10, weight: .medium)
        previewLabel.textColor = .tertiaryLabelColor
        previewLabel.alignment = .center
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(previewLabel)

        // ── Layout ────────────────────────────────────────────────────

        let margin: CGFloat = 20
        let gap:    CGFloat = 14
        let leftW:  CGFloat = 460

        NSLayoutConstraint.activate([
            // Pill tab bar — top-left
            pillTabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            pillTabBar.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            pillTabBar.widthAnchor.constraint(equalToConstant: leftW),

            // Tab content — fills left column between pill bar and divider
            tabContentArea.leadingAnchor.constraint(equalTo: pillTabBar.leadingAnchor),
            tabContentArea.widthAnchor.constraint(equalToConstant: leftW),
            tabContentArea.topAnchor.constraint(equalTo: pillTabBar.bottomAnchor, constant: 10),
            tabContentArea.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -10),

            // Divider — sits above buttons
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            divider.widthAnchor.constraint(equalToConstant: leftW),
            divider.bottomAnchor.constraint(equalTo: btnRow.topAnchor, constant: -10),

            // Button row — pinned to window bottom
            btnRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            btnRow.widthAnchor.constraint(equalToConstant: leftW),
            btnRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),

            // Vertical separator — full height
            vSep.leadingAnchor.constraint(equalTo: pillTabBar.trailingAnchor, constant: gap),
            vSep.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            vSep.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            vSep.widthAnchor.constraint(equalToConstant: 1),

            // Preview — right of separator, top aligned with pill bar
            previewRainView.leadingAnchor.constraint(equalTo: vSep.trailingAnchor, constant: gap),
            previewRainView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            previewRainView.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            previewRainView.bottomAnchor.constraint(equalTo: previewLabel.topAnchor, constant: -6),

            // Preview label — bottom aligned with button row bottom
            previewLabel.centerXAnchor.constraint(equalTo: previewRainView.centerXAnchor),
            previewLabel.bottomAnchor.constraint(equalTo: btnRow.bottomAnchor),
        ])

        previewRainView.startAnimation()
    }

    // MARK: - Tab switching

    private func switchTab(to index: Int) {
        guard index != currentTabIndex, index < tabContentViews.count else { return }

        let goingRight = index > currentTabIndex
        let oldView    = tabContentViews[currentTabIndex]
        let newView    = tabContentViews[index]
        currentTabIndex = index

        // CATransition: push the layer's rendered content before changing hidden state
        let transition = CATransition()
        transition.type            = .push
        transition.subtype         = goingRight ? .fromRight : .fromLeft
        transition.duration        = 0.22
        transition.timingFunction  = CAMediaTimingFunction(name: .easeInEaseOut)
        tabContentArea.layer?.add(transition, forKey: "tabSwitch")

        oldView.isHidden = true
        newView.isHidden = false
    }

    // MARK: - Export / Import

    @objc private func exportSettings() {
        guard let data = try? collect().jsonData() else { return }
        let panel = NSSavePanel()
        panel.title                = "Export Cyph3rfall Settings"
        panel.nameFieldStringValue = "cyph3rfall-settings.json"
        panel.allowedContentTypes  = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    @objc private func importSettings() {
        let panel = NSOpenPanel()
        panel.title                  = "Import Cyph3rfall Settings"
        panel.allowedContentTypes    = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url  = panel.url,
              let data = try? Data(contentsOf: url) else { return }

        if let imported = try? Cyph3rfallSettings.from(jsonData: data, base: collect()) {
            populate(from: imported)
            previewRainView.settings = collect()
        } else {
            let alert = NSAlert()
            alert.messageText     = "Import Failed"
            alert.informativeText = "The selected file could not be read as a valid Cyph3rfall settings file."
            alert.alertStyle      = .warning
            alert.runModal()
        }
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

    private func densityRow() -> NSView {
        let lbl = NSTextField(labelWithString: "Density:")
        lbl.font = .systemFont(ofSize: NSFont.systemFontSize)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 82).isActive = true

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

        let sliderRow = NSStackView(views: [lbl, wrapper, densityValueLabel])
        sliderRow.orientation = .horizontal
        sliderRow.spacing     = 12
        sliderRow.alignment   = .centerY

        // Performance note — indented to align with the slider, hidden until
        // density exceeds 200 %.
        densityPerfNote.translatesAutoresizingMaskIntoConstraints = false
        let noteIndent: CGFloat = 82 + 12   // matches label width + spacing
        let noteWrap = NSView()
        noteWrap.translatesAutoresizingMaskIntoConstraints = false
        noteWrap.addSubview(densityPerfNote)
        NSLayoutConstraint.activate([
            densityPerfNote.leadingAnchor.constraint(equalTo: noteWrap.leadingAnchor,
                                                     constant: noteIndent),
            densityPerfNote.topAnchor.constraint(equalTo: noteWrap.topAnchor),
            densityPerfNote.bottomAnchor.constraint(equalTo: noteWrap.bottomAnchor),
        ])

        let col = NSStackView(views: [sliderRow, noteWrap])
        col.orientation = .vertical
        col.spacing     = 4
        col.alignment   = .leading
        return col
    }

    private func withInfo(_ control: NSView, tooltip: String) -> NSStackView {
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

    private func messageNote() -> NSView {
        let note = NSTextField(labelWithString:
            "⬆ For the best message effect, set Density to 200% or higher.")
        note.font      = .systemFont(ofSize: 10.5, weight: .regular)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 0

        let spacer = NSView()
        spacer.widthAnchor.constraint(equalToConstant: 94).isActive = true

        let h = NSStackView(views: [spacer, note])
        h.orientation = .horizontal
        h.spacing     = 0
        h.alignment   = .top
        return h
    }

    private func messageFieldRow() -> NSView {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let img    = NSImage(systemSymbolName: "info.circle",
                             accessibilityDescription: "Information")?
                    .withSymbolConfiguration(config)
        let icon = NSImageView(image: img ?? NSImage())
        icon.contentTintColor = .tertiaryLabelColor
        icon.toolTip = "A short phrase (up to \(Self.messageLimit) characters) that materializes in the rain — each character lights up as a falling column passes through it, then slowly fades. Uppercase is applied automatically; longer phrases may be clipped on smaller screens."

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

    /// Wraps rows in a scrollable container suitable for use inside `tabContentArea`.
    private func makeTabContent(rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing     = 12
        stack.alignment   = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false

        // NSClipView is not flipped by default — content anchors to the bottom
        // when shorter than the scroll area. A flipped clip view fixes this.
        let clip = FlippedClipView()
        clip.drawsBackground  = false
        scrollView.contentView  = clip
        scrollView.documentView = stack

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: clip.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor, constant: 2),
            stack.widthAnchor.constraint(equalTo: clip.widthAnchor, constant: -2),
        ])
        return scrollView
    }

    private func makeFilesTabContent() -> NSView {
        let heading = NSTextField(labelWithString: "Import / Export Settings")
        heading.font = .systemFont(ofSize: 14, weight: .semibold)

        let description = NSTextField(wrappingLabelWithString:
            "Save your current settings to a JSON file or restore them from a " +
            "previously exported file. Exported files include all visual settings " +
            "but exclude your password lock and keyboard shortcut for security.")
        description.font      = .systemFont(ofSize: 12, weight: .regular)
        description.textColor = .secondaryLabelColor

        let exportBtn = NSButton(title: "Export Settings…", target: self, action: #selector(exportSettings))
        exportBtn.bezelStyle  = .rounded
        exportBtn.controlSize = .regular

        let importBtn = NSButton(title: "Import Settings…", target: self, action: #selector(importSettings))
        importBtn.bezelStyle  = .rounded
        importBtn.controlSize = .regular

        let btnStack = NSStackView(views: [exportBtn, importBtn])
        btnStack.orientation = .horizontal
        btnStack.spacing = 10

        let sep = NSBox(); sep.boxType = .separator

        let vStack = NSStackView(views: [heading, description, sep, btnStack])
        vStack.orientation = .vertical
        vStack.spacing     = 14
        vStack.alignment   = .leading
        vStack.translatesAutoresizingMaskIntoConstraints = false
        // Constrain the description's width so it wraps correctly
        description.widthAnchor.constraint(equalToConstant: 390).isActive = true
        sep.widthAnchor.constraint(equalToConstant: 390).isActive = true

        let container = NSView()
        container.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            vStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
        ])
        return container
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
        trailControl.selectedSegment  = Cyph3rfallSettings.nearest(
            in: Cyph3rfallSettings.trailLengthOptions, to: s.trailLength)
        densitySlider.doubleValue     = s.density
        densityValueLabel.stringValue = densityText(s.density)
        densityPerfNote.isHidden      = s.density <= 1.51
        colorControl.selectItem(withTag: s.colorPreset.rawValue)
        glowCheckbox.state       = s.showGlow         ? .on : .off
        colorZonesCheckbox.state = s.colorZonesEnabled ? .on : .off
        spectrafallCheckbox.state = s.spectrafallEnabled ? .on : .off
        spectrafallSpeedControl.selectedSegment = max(0, min(
            s.spectrafallSpeedIndex,
            Cyph3rfallSettings.spectrafallSpeedOptions.count - 1))
        spectrafallSpeedControl.isEnabled = s.spectrafallEnabled
        denseCheckbox.state      = s.classicDenseMode  ? .on : .off
        primaryDisplayOnlyCheckbox.state = s.primaryDisplayOnly ? .on : .off
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
        s.spectrafallEnabled    = spectrafallCheckbox.state == .on
        s.spectrafallSpeedIndex = max(0, spectrafallSpeedControl.selectedSegment)
        s.resolveExclusiveModes()
        s.classicDenseMode  = denseCheckbox.state      == .on
        s.primaryDisplayOnly = primaryDisplayOnlyCheckbox.state == .on
        s.requirePassword    = lockCheckbox.state == .on
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

    @objc private func spectrafallToggled(_ sender: NSButton) {
        if sender.state == .on {
            colorZonesCheckbox.state = .off   // Spectrafall wins
        }
        spectrafallSpeedControl.isEnabled = sender.state == .on
        previewRainView.settings = collect()
    }

    @objc private func chromafallToggled(_ sender: NSButton) {
        if sender.state == .on {
            spectrafallCheckbox.state = .off
            spectrafallSpeedControl.isEnabled = false
        }
        previewRainView.settings = collect()
    }

    @objc private func densityChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        densityValueLabel.stringValue = densityText(value)
        densityPerfNote.isHidden      = value <= 1.51
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
        var text = messageField.stringValue.uppercased()
        if text.count > Self.messageLimit { text = String(text.prefix(Self.messageLimit)) }
        if messageField.stringValue != text { messageField.stringValue = text }
        updateMessageCount(text.count)
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
            messageField.stringValue = ""
            updateMessageCount(0)
        } else if tag >= 0, tag < Cyph3rfallSettings.messagePresets.count {
            let preset = Cyph3rfallSettings.messagePresets[tag]
            messageField.stringValue = preset
            updateMessageCount(preset.count)
        }
        previewRainView.settings = collect()
    }

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
        // Hide the performance note when Classic Dense Mode overrides density.
        if !enabled { densityPerfNote.isHidden = true }
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

// MARK: - Pill tab bar

/// A custom tab bar with a dark rounded background and an animated sliding
/// pill highlight — styled after modern app tab bars.
///
/// The pill uses **frame-based** positioning (not constraints) so `layout()`
/// can reposition it without triggering a secondary layout pass.
private final class PillTabBar: NSView {

    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex: Int = 0

    /// The sliding pill highlight — layer-backed so frame animation works.
    private let pill    = NSView()
    private var buttons: [NSButton] = []
    private let labels:  [String]

    init(labels: [String]) {
        self.labels = labels
        super.init(frame: .zero)
        setupBar()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupBar() {
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
        heightAnchor.constraint(equalToConstant: 32).isActive = true

        // ── Pill (frame-based, not autolayout) ────────────────────────
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 7
        pill.layer?.backgroundColor = NSColor(white: 0.44, alpha: 1).cgColor
        addSubview(pill)         // translatesAutoresizingMaskIntoConstraints = true (default) — frame driven

        // ── Segment buttons (autolayout, equal widths) ────────────────
        let n = CGFloat(labels.count)
        for (i, label) in labels.enumerated() {
            let btn = NSButton(title: label, target: self, action: #selector(segTapped(_:)))
            btn.tag = i
            btn.isBordered = false
            btn.translatesAutoresizingMaskIntoConstraints = false
            setButtonAppearance(btn, selected: i == 0)
            addSubview(btn)
            buttons.append(btn)

            NSLayoutConstraint.activate([
                btn.topAnchor.constraint(equalTo: topAnchor),
                btn.bottomAnchor.constraint(equalTo: bottomAnchor),
                btn.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 1.0 / n),
            ])
            if i == 0 {
                btn.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            } else {
                btn.leadingAnchor.constraint(equalTo: buttons[i - 1].trailingAnchor).isActive = true
            }
        }
    }

    // MARK: Pill frame

    override func layout() {
        super.layout()
        // Directly set the pill frame — no constraint changes, so no re-layout loop.
        pill.frame = pillRect(for: selectedIndex)
    }

    private func pillRect(for index: Int) -> CGRect {
        guard bounds.width > 0 else { return .zero }
        let segW = bounds.width / CGFloat(labels.count)
        return CGRect(x: 3 + CGFloat(index) * segW,
                      y: 3,
                      width: segW - 6,
                      height: bounds.height - 6)
    }

    // MARK: Selection

    /// Programmatically select a tab; animated = false on first display.
    func select(index: Int, animated: Bool = true) {
        guard index < labels.count else { return }
        selectedIndex = index
        for (i, btn) in buttons.enumerated() {
            setButtonAppearance(btn, selected: i == index)
        }
        let target = pillRect(for: index)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration       = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                pill.animator().frame = target
            }
        } else {
            pill.frame = target
        }
    }

    /// Use `attributedTitle` for reliable text colour on borderless buttons
    /// across all macOS versions — `contentTintColor` can be inconsistent.
    private func setButtonAppearance(_ btn: NSButton, selected: Bool) {
        let color: NSColor = selected ? .white : NSColor(white: 0.60, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: color,
        ]
        btn.attributedTitle = NSAttributedString(string: btn.title, attributes: attrs)
    }

    @objc private func segTapped(_ sender: NSButton) {
        let idx = sender.tag
        guard idx != selectedIndex else { return }
        select(index: idx)
        onSelect?(idx)
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

        let inset  = slider.bounds.height / 2.0
        let trackW = bounds.width - 2.0 * inset

        for (i, tick) in ticks.enumerated() {
            let centerX = inset + tick.fraction * trackW

            let line = subviews[i * 2]
            line.frame = CGRect(x: centerX - 0.5, y: bounds.height - 5, width: 1, height: 5)

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

// NSClipView subclass that flips the coordinate system so scroll view content
// anchors to the top-left rather than the bottom-left.
private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}
