import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A click-to-record control for a global hotkey. Clicking starts capture; the next
/// key press with at least one modifier becomes the combo. Esc cancels. While
/// recording, key events are swallowed (a local monitor returning nil) so they don't
/// type into the settings window.
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo
    @State private var recording = false
    @State private var monitor: Any?
    @State private var timeoutTask: Task<Void, Never>?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Press shortcut…" : (combo.isValid ? combo.displayString : "None"))
                .monospaced()
                .frame(minWidth: 96)
        }
        .help(recording ? "Press a shortcut, or wait 5s to clear" : "Click to change the shortcut")
        .onDisappear(perform: stop)
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let mods = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .intersection([.command, .option, .control, .shift])
            let candidate = HotKeyCombo(keyCode: event.keyCode, modifiers: mods.rawValue)
            if candidate.isValid {
                combo = candidate
                stop()
            }
            return nil   // swallow all keys while recording
        }
        
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            combo = .empty
            stop()
        }
    }

    private func stop() {
        recording = false
        timeoutTask?.cancel()
        timeoutTask = nil
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
