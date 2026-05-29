import AppKit
import Carbon

/// Registers and manages a single application-wide keyboard shortcut using the
/// Carbon RegisterEventHotKey API. No Accessibility permission required.
final class HotkeyManager {

    /// Fired on the main thread when the registered hotkey is pressed.
    var onTriggered: (() -> Void)?

    private var hotKeyRef:       EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // MARK: - Registration

    enum RegistrationError: LocalizedError {
        case eventHandlerFailed(OSStatus)
        case hotkeyFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .eventHandlerFailed(let status):
                return "Could not install the keyboard shortcut handler. (OSStatus \(status))"
            case .hotkeyFailed(let status):
                return "That keyboard shortcut could not be registered. It may already be used by macOS or another app. (OSStatus \(status))"
            }
        }
    }

    /// Register (or re-register) the hotkey. Call with keyCode = -1 to clear.
    func update(keyCode: Int, carbonModifiers: UInt32) throws {
        unregister()
        guard keyCode >= 0 else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed))

        // Pass self through userData — the C callback captures nothing directly.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var newEventHandlerRef: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async { mgr.onTriggered?() }
                return noErr
            },
            1, &spec, selfPtr, &newEventHandlerRef)
        guard handlerStatus == noErr else {
            throw RegistrationError.eventHandlerFailed(handlerStatus)
        }

        // Signature "CYRN" as a FourCharCode.
        let sig: FourCharCode = 0x4359_524E
        let hotKeyID = EventHotKeyID(signature: sig, id: 1)
        var newHotKeyRef: EventHotKeyRef?
        let hotkeyStatus = RegisterEventHotKey(
            UInt32(keyCode), carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0, &newHotKeyRef)
        guard hotkeyStatus == noErr else {
            if let ref = newEventHandlerRef { RemoveEventHandler(ref) }
            throw RegistrationError.hotkeyFailed(hotkeyStatus)
        }

        eventHandlerRef = newEventHandlerRef
        hotKeyRef = newHotKeyRef
    }

    func unregister() {
        if let ref = hotKeyRef       { UnregisterEventHotKey(ref); hotKeyRef       = nil }
        if let ref = eventHandlerRef { RemoveEventHandler(ref);    eventHandlerRef = nil }
    }

    deinit { unregister() }
}

// MARK: - Modifier conversion

/// Converts NSEvent.ModifierFlags to the Carbon modifier bit-mask expected by
/// RegisterEventHotKey (cmdKey, shiftKey, optionKey, controlKey).
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var c: UInt32 = 0
    if flags.contains(.command) { c |= UInt32(cmdKey)     }
    if flags.contains(.shift)   { c |= UInt32(shiftKey)   }
    if flags.contains(.option)  { c |= UInt32(optionKey)  }
    if flags.contains(.control) { c |= UInt32(controlKey) }
    return c
}
