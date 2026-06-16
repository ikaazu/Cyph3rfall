import AppKit

/// Preferences panel for Cyph3rfall.
/// Left side: pill-tabbed controls. Right side: live Cyph3rfallView preview.
final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate,
                                          NSTableViewDelegate, NSTableViewDataSource {

    var onApply:           ((Cyph3rfallSettings) -> Void)?
    var onStartNow:        (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

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
    private var clockFontButton:   NSButton!
    private var clockFontName:     String = "Gill Sans"
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

    private static let messageLimit    = 30
    private static let customMessageTag = 99
    private var originalSettings: Cyph3rfallSettings

    // Sidebar navigation
    private var sidebarTable: NSTableView!
    private let sidebarItems: [(label: String, symbol: String)] = [
        ("General",       "gearshape"),
        ("Message",       "text.bubble"),
        ("Clock",         "clock"),
        ("Import/Export", "arrow.up.arrow.down"),
        ("About",         "info.circle"),
    ]
    private var tabContentArea = NSView()
    private var tabContentViews: [NSView] = []
    private var currentTabIndex = 0

    // MARK: - Init

    init(settings: Cyph3rfallSettings) {
        self.originalSettings = settings

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
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

        clockFontButton = NSButton(title: "Gill Sans", target: self,
                                   action: #selector(chooseFontClicked))
        clockFontButton.bezelStyle = .rounded

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

        clockColorPresetCheckbox = NSButton(checkboxWithTitle: "Match clock color to rain preset",
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
        messagePresetControl.addItem(withTitle: "Custom…")
        messagePresetControl.lastItem?.tag = Self.customMessageTag
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

        // ── Info-wrapped controls ─────────────────────────────────────

        let denseControl = withInfo(denseCheckbox,
            tooltip: "Replicates the classic Matrix screensaver look. Density and Trail Length are overridden (those controls are disabled while active). Speed is set to a minimum of 1.5× — selecting Fast still increases it further.")
        let lockControl = withInfo(lockCheckbox,
            tooltip: "When activated by idle timeout: password is required immediately.\nWhen started manually via Start Now: password is only required once your configured idle timeout has elapsed with no activity.")

        // ── Build tab content views ───────────────────────────────────

        let generalContent = makeTabContent(rows: [
            row(label: "Shortcut", control: withInfo(hotkeyRecorder,
                tooltip: "A global keyboard shortcut that starts the screensaver from anywhere, even when another app is in front. Click the field to record a combo, or press Delete to clear it. Requires at least one modifier key (⌘, ⌥, ⌃, or ⇧).")),
            sectionHeader("Animation"),
            row(label: "Speed",        control: speedControl),
            densityRow(),
            row(label: "Glyph Size",   control: sizeControl),
            row(label: "Trail Length", control: trailControl),
            row(label: "Columns",      control: columnSpacingControl),
            row(label: "Dense Mode",   control: denseControl),
            sectionHeader("Color"),
            row(label: "Color",       control: colorControl),
            row(label: "Glow",         control: glowCheckbox),
            row(label: "Chromafall",   control: withInfo(colorZonesCheckbox,
                tooltip: "Gives every falling stream its own randomly chosen colour. The colour is re-picked each time a stream wraps from the bottom back to the top, so the screen is always in motion.")),
            row(label: "Spectrafall",  control: withInfo(spectrafallCheckbox,
                tooltip: "Slowly drifts the entire rain through every colour preset, blending smoothly from one to the next. The cycle starts from your selected colour. White is skipped to keep the rain saturated. Enabling Spectrafall turns off Chromafall — the two modes can't run together.")),
            row(label: "Cycle Speed",  control: spectrafallSpeedControl),
            sectionHeader("Display & Security"),
            row(label: "Overlays",     control: primaryDisplayOnlyCheckbox),
            row(label: "Lock",         control: lockControl),
        ])

        let messageContent = makeTabContent(rows: [
            messageCheckbox,
            row(label: "Preset",   control: messagePresetControl),
            messageFieldRow(),
            messageNote(),
        ])

        let clockContent = makeTabContent(rows: [
            clockCheckbox,
            row(label: "Font",   control: clockFontButton),
            clockSizeRow(),
            row(label: "Date",   control: dateCheckbox),
            row(label: "Color", control: clockColorPresetCheckbox),
        ])

        let filesContent = makeFilesTabContent()

        let aboutContent = makeAboutTabContent()
        tabContentViews = [generalContent, messageContent, clockContent, filesContent, aboutContent]

        // ── Sidebar ───────────────────────────────────────────────────

        let sidebar = NSTableView()
        sidebar.style                   = .sourceList
        sidebar.headerView              = nil
        sidebar.rowHeight            = 36
        sidebar.allowsEmptySelection = false
        let sidebarCol = NSTableColumn(identifier: .init("sidebar"))
        sidebarCol.isEditable = false
        sidebar.addTableColumn(sidebarCol)
        sidebar.dataSource = self
        sidebar.delegate   = self
        sidebarTable = sidebar

        let sidebarScroll = NSScrollView()
        sidebarScroll.hasVerticalScroller   = false
        sidebarScroll.hasHorizontalScroller = false
        sidebarScroll.drawsBackground       = false
        sidebarScroll.documentView          = sidebar
        sidebarScroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebarScroll)

        let sidebarSep = NSView()
        sidebarSep.wantsLayer = true
        sidebarSep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sidebarSep.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebarSep)

        sidebar.reloadData()
        sidebar.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

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
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.alignment = .center
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(previewLabel)

        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let versionLabel = NSTextField(labelWithString: "Cyph3rfall \(versionString)")
        versionLabel.font      = .systemFont(ofSize: 10, weight: .regular)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(versionLabel)

        // ── Layout ────────────────────────────────────────────────────

        let margin:   CGFloat = 16
        let sidebarW: CGFloat = 180
        let contentW: CGFloat = 460

        NSLayoutConstraint.activate([
            // Sidebar — left edge, full height
            sidebarScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebarScroll.topAnchor.constraint(equalTo: content.topAnchor),
            sidebarScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarScroll.widthAnchor.constraint(equalToConstant: sidebarW),

            // Sidebar separator
            sidebarSep.leadingAnchor.constraint(equalTo: sidebarScroll.trailingAnchor),
            sidebarSep.topAnchor.constraint(equalTo: content.topAnchor),
            sidebarSep.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebarSep.widthAnchor.constraint(equalToConstant: 1),

            // Tab content area
            tabContentArea.leadingAnchor.constraint(equalTo: sidebarSep.trailingAnchor, constant: margin),
            tabContentArea.widthAnchor.constraint(equalToConstant: contentW),
            tabContentArea.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            tabContentArea.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -10),

            // Divider — above buttons
            divider.leadingAnchor.constraint(equalTo: sidebarSep.trailingAnchor, constant: margin),
            divider.widthAnchor.constraint(equalToConstant: contentW),
            divider.bottomAnchor.constraint(equalTo: btnRow.topAnchor, constant: -10),

            // Button row
            btnRow.leadingAnchor.constraint(equalTo: sidebarSep.trailingAnchor, constant: margin),
            btnRow.widthAnchor.constraint(equalToConstant: contentW),
            btnRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),

            // Vertical separator — between content and preview
            vSep.leadingAnchor.constraint(equalTo: tabContentArea.trailingAnchor, constant: margin),
            vSep.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            vSep.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            vSep.widthAnchor.constraint(equalToConstant: 1),

            // Preview
            previewRainView.leadingAnchor.constraint(equalTo: vSep.trailingAnchor, constant: margin),
            previewRainView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            previewRainView.topAnchor.constraint(equalTo: content.topAnchor, constant: margin),
            previewRainView.bottomAnchor.constraint(equalTo: previewLabel.topAnchor, constant: -6),

            // Labels
            previewLabel.centerXAnchor.constraint(equalTo: previewRainView.centerXAnchor),
            previewLabel.bottomAnchor.constraint(equalTo: versionLabel.topAnchor, constant: -2),
            versionLabel.centerXAnchor.constraint(equalTo: previewRainView.centerXAnchor),
            versionLabel.bottomAnchor.constraint(equalTo: btnRow.bottomAnchor),
        ])

        previewRainView.startAnimation()
    }

    // MARK: - Tab switching

    private func switchTab(to index: Int) {
        guard index != currentTabIndex, index < tabContentViews.count else { return }
        tabContentViews[currentTabIndex].isHidden = true
        currentTabIndex = index
        tabContentViews[index].isHidden = false
    }

    // MARK: - NSTableViewDataSource / NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int { sidebarItems.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let item = sidebarItems[row]
        let cell = NSTableCellView()

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let img = NSImage(systemSymbolName: item.symbol,
                          accessibilityDescription: nil)?
                  .withSymbolConfiguration(config)
        let imageView = NSImageView(image: img ?? NSImage())
        imageView.contentTintColor = .controlAccentColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: item.label)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = label
        cell.imageView = imageView

        cell.addSubview(imageView)
        cell.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
        ])

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let idx = sidebarTable.selectedRow
        guard idx >= 0 else { return }
        switchTab(to: idx)
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

    private func sectionHeader(_ title: String) -> NSView {
        let lbl = NSTextField(labelWithString: title)
        lbl.font      = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false

        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
            lbl.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            lbl.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            lbl.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
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
        stack.spacing     = 10
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

    private func makeAboutTabContent() -> NSView {
        let iconView = NSImageView(image: NSApp.applicationIconImage)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.widthAnchor.constraint(equalToConstant: 96).isActive  = true
        iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let nameLabel = NSTextField(labelWithString: "Cyph3rfall")
        nameLabel.font      = .systemFont(ofSize: 22, weight: .bold)
        nameLabel.alignment = .center

        let appVersion   = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let versionLabel = NSTextField(labelWithString: "Version \(appVersion)")
        versionLabel.font      = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        let updateBtn = NSButton(title: "Check for Updates…",
                                 target: self,
                                 action: #selector(triggerCheckForUpdates))
        updateBtn.bezelStyle = .rounded
        updateBtn.controlSize = .regular

        let taglineLabel = NSTextField(labelWithString: "Ambient digital rain for macOS")
        taglineLabel.font      = .systemFont(ofSize: 12)
        taglineLabel.textColor = .secondaryLabelColor
        taglineLabel.alignment = .center

        let siteRow  = makeAboutLinkView(icon: "link",     title: "cyph3rfall.app",    action: #selector(openWebsite))
        let emailRow = makeAboutLinkView(icon: "envelope", title: "dev@cyph3rfall.app", action: #selector(openContactEmail))
        let linksRow = NSStackView(views: [siteRow, emailRow])
        linksRow.orientation = .horizontal
        linksRow.spacing     = 22
        linksRow.alignment   = .centerY

        let creditsLabel = NSTextField(wrappingLabelWithString:
            "Built with Swift & AppKit\n\n" +
            "Inspired by The Matrix (1999) and MatrixMania for Windows by StrongGames.\n\n" +
            "I used MatrixMania for decades, once gave feedback that improved it, " +
            "missed that feeling on modern macOS, and built my own spiritual successor.\n\n" +
            "No screensaver frameworks were harmed.")
        creditsLabel.font                    = .systemFont(ofSize: 12)
        creditsLabel.textColor               = .secondaryLabelColor
        creditsLabel.alignment               = .center
        creditsLabel.maximumNumberOfLines    = 0
        creditsLabel.preferredMaxLayoutWidth = 380

        let copyrightLabel = NSTextField(labelWithString: "© 2026 Greg Stock")
        copyrightLabel.font      = .systemFont(ofSize: 11)
        copyrightLabel.textColor = .tertiaryLabelColor
        copyrightLabel.alignment = .center

        let stack = NSStackView(views: [
            iconView, nameLabel, versionLabel, updateBtn,
            taglineLabel, linksRow, creditsLabel, copyrightLabel,
        ])
        stack.orientation = .vertical
        stack.alignment   = .centerX
        stack.spacing     = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.setCustomSpacing(14, after: iconView)
        stack.setCustomSpacing(2,  after: nameLabel)
        stack.setCustomSpacing(20, after: versionLabel)
        stack.setCustomSpacing(20, after: updateBtn)
        stack.setCustomSpacing(14, after: taglineLabel)
        stack.setCustomSpacing(18, after: linksRow)
        stack.setCustomSpacing(16, after: creditsLabel)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            stack.widthAnchor.constraint(equalToConstant: 392),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
        ])
        return container
    }

    private func makeAboutLinkView(icon: String, title: String, action: Selector) -> NSView {
        let config  = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let img     = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
                          .withSymbolConfiguration(config)
        let imgView = NSImageView(image: img ?? NSImage())
        imgView.contentTintColor = .linkColor

        let btn = NSButton(title: title, target: self, action: action)
        btn.isBordered     = false
        btn.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.linkColor,
                         .font: NSFont.systemFont(ofSize: 13)])

        let h = NSStackView(views: [imgView, btn])
        h.orientation = .horizontal
        h.spacing     = 4
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
        clockFontName = s.clockFontName
        applyClockFontToButton(s.clockFontName)
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
        s.clockFontSize = CGFloat(clockSizeSlider.doubleValue)
        s.clockFontName = clockFontName
        return s
    }

    // MARK: - Actions

    @objc private func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://cyph3rfall.app")!)
    }

    @objc private func openContactEmail() {
        NSWorkspace.shared.open(URL(string: "mailto:dev@cyph3rfall.app")!)
    }

    @objc private func triggerCheckForUpdates() {
        onCheckForUpdates?()
    }

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

    @objc private func chooseFontClicked() {
        let fm = NSFontManager.shared
        fm.target = self
        let current = NSFont(name: clockFontName, size: 13)
                   ?? NSFont.systemFont(ofSize: 13)
        fm.setSelectedFont(current, isMultiple: false)
        fm.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: Any?) {
        guard let font = (sender as? NSFontManager)?.selectedFont else { return }
        clockFontName = font.fontName
        applyClockFontToButton(font.fontName)
        previewRainView.settings = collect()
    }

    @objc private func messageToggled(_ sender: NSButton) {
        updateMessageControlsEnabled(sender.state == .on)
        previewRainView.settings = collect()
    }

    private func updateMessageControlsEnabled(_ enabled: Bool) {
        messagePresetControl.isEnabled = enabled
        messageCountLabel.isEnabled    = enabled
        updateMessageFieldEnabled()
    }

    private func updateMessageFieldEnabled() {
        let messageOn = messageCheckbox.state == .on
        let isCustom  = messagePresetControl.selectedTag() == Self.customMessageTag
        messageField.isEnabled = messageOn && isCustom
    }

    @objc private func messagePresetSelected(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        if tag >= 0, tag < Cyph3rfallSettings.messagePresets.count {
            let preset = Cyph3rfallSettings.messagePresets[tag]
            messageField.stringValue = preset
            updateMessageCount(preset.count)
        }
        updateMessageFieldEnabled()
        previewRainView.settings = collect()
    }

    private func syncPresetPopup(to text: String) {
        if let idx = Cyph3rfallSettings.messagePresets.firstIndex(of: text) {
            messagePresetControl.selectItem(withTag: idx)
        } else {
            messagePresetControl.selectItem(withTag: Self.customMessageTag)
        }
        updateMessageFieldEnabled()
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

    private func applyClockFontToButton(_ fontName: String) {
        let display = NSFont(name: fontName, size: 13)?.displayName ?? fontName
        let font    = NSFont(name: fontName, size: 13) ?? NSFont.systemFont(ofSize: 13)
        clockFontButton.attributedTitle = NSAttributedString(string: display,
                                                             attributes: [.font: font])
    }

    private func updateClockControlsEnabled(_ enabled: Bool) {
        clockFontButton.isEnabled          = enabled
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
