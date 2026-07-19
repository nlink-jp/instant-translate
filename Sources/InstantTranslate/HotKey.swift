import AppKit
import Carbon.HIToolbox

/// A global hotkey combination — a virtual key code plus modifier flags. Persisted
/// as two `UserDefaults` ints; rendered as "⌥⌘T" etc.; converted to Carbon masks for
/// `RegisterEventHotKey`. No external dependency (Carbon HIToolbox is a system API).
struct HotKeyCombo: Equatable {
    /// Virtual key code (e.g. `kVK_ANSI_T`).
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw value, masked to command/option/control/shift.
    var modifiers: UInt

    /// The default: ⌥⌘T ("Translate").
    static let `default` = HotKeyCombo(
        keyCode: UInt16(kVK_ANSI_T),
        modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Carbon modifier mask for `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var c: UInt32 = 0
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        if flags.contains(.option)  { c |= UInt32(optionKey) }
        if flags.contains(.control) { c |= UInt32(controlKey) }
        if flags.contains(.shift)   { c |= UInt32(shiftKey) }
        return c
    }

    /// A hotkey needs at least one of command/option/control (shift alone is unsafe).
    var isValid: Bool {
        !flags.intersection([.command, .option, .control]).isEmpty
    }

    /// Menu-style rendering, e.g. "⌥⌘T" (modifier order matches macOS: ⌃⌥⇧⌘).
    var displayString: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.shift)   { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + HotKeyCombo.keyName(keyCode)
    }

    // MARK: Persistence

    static func current(_ d: UserDefaults = .standard) -> HotKeyCombo {
        guard let kc = d.object(forKey: SettingsKey.hotKeyKeyCode) as? Int,
              let mods = d.object(forKey: SettingsKey.hotKeyModifiers) as? Int
        else { return .default }
        return HotKeyCombo(keyCode: UInt16(truncatingIfNeeded: kc), modifiers: UInt(bitPattern: mods))
    }

    func save(_ d: UserDefaults = .standard) {
        d.set(Int(keyCode), forKey: SettingsKey.hotKeyKeyCode)
        d.set(Int(bitPattern: modifiers), forKey: SettingsKey.hotKeyModifiers)
    }

    /// A readable name for a virtual key code (letters, digits, and common keys).
    static func keyName(_ code: UInt16) -> String {
        if let name = names[code] { return name }
        return "Key \(code)"
    }

    private static let names: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9",
        49: "Space", 36: "↩", 48: "⇥", 53: "⎋", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        // punctuation commonly used in shortcuts
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    ]
}

/// Registers a single system-wide hotkey via Carbon and invokes `handler` when it
/// fires. Re-`register` with a new combo to rebind; `unregister` / deinit cleans up.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void
    private let hotKeyID: UInt32

    init(id: UInt32 = 1, handler: @escaping () -> Void) {
        self.hotKeyID = id
        self.handler = handler
    }

    func register(_ combo: HotKeyCombo) {
        unregister()
        guard combo.isValid else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            var firedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &firedID)
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            if firedID.id == me.hotKeyID { me.handler() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x49545458 /* 'ITTX' */), id: hotKeyID)
        RegisterEventHotKey(UInt32(combo.keyCode), combo.carbonModifiers, id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
    }

    deinit { unregister() }
}
