import AppKit

/// A button-like NSView that displays the current global hotkey and lets the
/// user record a new one by clicking, then pressing a key combination.
///
/// Interaction:
///   • Click anywhere → enter recording mode ("Type a shortcut…")
///   • Press modifier(s) + key → records the combo and exits recording
///   • Escape in recording mode → cancel (keeps previous combo)
///   • Delete / Backspace alone → clears the hotkey
///   • ✕ button → clears the hotkey
final class HotkeyRecorderView: NSView {

    /// Called after the user records or clears a hotkey.
    /// keyCode == -1 means the hotkey was cleared.
    var onChange: ((_ keyCode: Int,
                    _ modifierFlags: NSEvent.ModifierFlags,
                    _ character: String) -> Void)?

    // MARK: - State

    private(set) var keyCode:       Int                     = -1
    private(set) var modifierFlags: NSEvent.ModifierFlags   = []
    private(set) var character:     String                  = ""
    private      var isRecording                            = false

    // MARK: - Subviews

    private let label       = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "✕", target: nil, action: nil)

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer          = true
        layer?.cornerRadius = 6
        layer?.borderWidth  = 1

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        addSubview(label)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isBordered  = false
        clearButton.font        = .systemFont(ofSize: 10)
        clearButton.target      = self
        clearButton.action      = #selector(clear)
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),

            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
        ])

        updateAppearance()
    }

    // MARK: - Public API

    /// Populate from saved settings — does not fire onChange.
    func configure(keyCode: Int,
                   modifierFlags: NSEvent.ModifierFlags,
                   character: String) {
        self.keyCode       = keyCode
        self.modifierFlags = modifierFlags
        self.character     = character
        isRecording        = false
        updateAppearance()
    }

    // MARK: - Actions

    @objc private func clear() {
        keyCode       = -1
        modifierFlags = []
        character     = ""
        isRecording   = false
        window?.makeFirstResponder(nil)
        updateAppearance()
        onChange?(-1, [], "")
    }

    // MARK: - Event handling

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Ignore clicks directly on the clear button — it has its own action.
        let loc = convert(event.locationInWindow, from: nil)
        guard !clearButton.frame.contains(loc) else { return }
        isRecording = true
        window?.makeFirstResponder(self)
        updateAppearance()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            updateAppearance()
        }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])

        switch event.keyCode {
        case 53 where mods.isEmpty:          // Escape — cancel, keep current
            isRecording = false
            window?.makeFirstResponder(nil)
            updateAppearance()
            return
        case 51 where mods.isEmpty,
             117 where mods.isEmpty:         // Delete / Forward-Delete — clear
            clear()
            return
        default:
            break
        }

        // Require at least one modifier (function keys F1–F19 are exempt).
        let isFunctionKey = (122 ... 160).contains(event.keyCode)
        guard !mods.isEmpty || isFunctionKey else { return }

        keyCode       = Int(event.keyCode)
        modifierFlags = mods
        character     = (event.charactersIgnoringModifiers ?? "").uppercased()
        isRecording   = false
        window?.makeFirstResponder(nil)
        updateAppearance()
        onChange?(keyCode, modifierFlags, character)
    }

    // MARK: - Appearance

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isRecording {
            label.stringValue = "Type a shortcut…"
            label.textColor   = .secondaryLabelColor
            label.font        = .systemFont(ofSize: NSFont.systemFontSize)
            layer?.borderColor     = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor
                .withAlphaComponent(dark ? 0.18 : 0.10).cgColor
        } else if keyCode >= 0 {
            label.stringValue = displayString()
            label.textColor   = .labelColor
            label.font        = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            layer?.borderColor     = NSColor.separatorColor.cgColor
            layer?.backgroundColor = (dark
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.black.withAlphaComponent(0.05)).cgColor
        } else {
            label.stringValue = "Click to record shortcut"
            label.textColor   = .placeholderTextColor
            label.font        = .systemFont(ofSize: NSFont.systemFontSize)
            layer?.borderColor     = NSColor.separatorColor.cgColor
            layer?.backgroundColor = (dark
                ? NSColor.white.withAlphaComponent(0.04)
                : NSColor.black.withAlphaComponent(0.03)).cgColor
        }

        clearButton.isHidden = (keyCode < 0 || isRecording)
        needsDisplay = true
    }

    private func displayString() -> String {
        var s = ""
        if modifierFlags.contains(.control) { s += "⌃" }
        if modifierFlags.contains(.option)  { s += "⌥" }
        if modifierFlags.contains(.shift)   { s += "⇧" }
        if modifierFlags.contains(.command) { s += "⌘" }
        s += character
        return s
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 22)
    }
}
