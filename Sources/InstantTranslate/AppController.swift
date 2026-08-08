import AppKit
import SwiftUI

/// The translation panel's window.
///
/// It must accept key status *without* the app being active. `.nonactivatingPanel`
/// lets the panel render and take keystrokes while another app stays frontmost, but an
/// `NSTextView` only draws its insertion point in a **key** window — so if the panel
/// declines key status, opening it with the global hotkey from another app gives you a
/// panel with no visible caret. Overriding `canBecomeKey` states the requirement
/// outright rather than relying on `NSPanel`'s style-mask-derived default.
final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    /// Still not a main window — it's an accessory panel, and becoming main would make
    /// the (hidden) title bar draw as an active document window.
    override var canBecomeMain: Bool { false }
}

/// Owns the app's menu-bar presence and the resizable translation panel.
///
/// Replaces `MenuBarExtra` with an `NSStatusItem` + a resizable `NSPanel` (hosting
/// the SwiftUI `PanelView`). A user-resizable panel and reliable input focus both
/// require this — a `MenuBarExtra` popover supports neither. The same controller
/// will drive the Phase 2 global hotkey (show + focus the panel from anywhere).
final class AppController: NSObject, NSApplicationDelegate, ObservableObject {
    let model: TranslationModel
    let languageCatalog = LanguageCatalog()

    /// Bumped whenever the panel should focus its input field; observed by `PanelView`.
    @Published private(set) var focusToken = 0

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var hotKey: GlobalHotKey?
    private var currentCombo: HotKeyCombo?
    private var lastShownAt = Date.distantPast

    override init() {
        // Defaults must be registered before the model reads them.
        SettingsKey.registerDefaults()
        self.model = TranslationModel()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "character.bubble",
                                   accessibilityDescription: "instant-translate")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePanel)
        }
        statusItem = item

        // Global hotkey (default ⌥⌘T): open + optionally translate the clipboard.
        let hk = GlobalHotKey { [weak self] in self?.hotKeyPressed() }
        let combo = HotKeyCombo.current()
        hk.register(combo)
        hotKey = hk
        currentCombo = combo

        // Re-register when the user changes the shortcut in Settings.
        NotificationCenter.default.addObserver(
            self, selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil)

        // Load the OS-supported language set (async) so the pickers are accurate.
        languageCatalog.load()

        // Pre-warm the panel so the first open pays no construction cost.
        _ = ensurePanel()
    }

    @objc private func defaultsChanged() {
        let combo = HotKeyCombo.current()
        guard combo != currentCombo else { return }
        currentCombo = combo
        hotKey?.register(combo)
    }

    /// Dismiss the translation panel when the app loses focus (click-away behaviour),
    /// via an explicit orderOut so `isVisible` stays accurate for togglePanel.
    ///
    /// A short grace period after showing prevents a launch/login focus bounce from
    /// hiding the panel right after it opens (the "won't open just after launch" bug).
    func applicationDidResignActive(_ notification: Notification) {
        // A short grace period after showing prevents a launch/login focus bounce from
        // hiding the just-opened panel.
        if Date().timeIntervalSince(lastShownAt) < 0.5 { return }
        hidePanel()
    }

    // MARK: - Panel lifecycle

    /// Status-item click: plain open/close (no clipboard seeding).
    @objc func togglePanel() { toggle(seedClipboard: false) }

    /// Global hotkey: open/close, seeding the source from the clipboard on open (when
    /// enabled) so you can hit ⌥⌘T and immediately translate what you copied.
    func hotKeyPressed() { toggle(seedClipboard: true) }

    private func toggle(seedClipboard: Bool) {
        let p = ensurePanel()
        if p.isVisible { p.orderOut(nil) } else { showPanel(seedClipboard: seedClipboard) }
    }

    /// Show the panel anchored under the status item, activate the app, and focus
    /// the input. When `seedClipboard` is set (and the setting is on), fill the source
    /// from the clipboard — which the auto-translate path then picks up.
    func showPanel(seedClipboard: Bool = false) {
        let p = ensurePanel()
        position(p)
        NSApp.activate()
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()   // come to front even if the app couldn't activate
        p.makeKey()                // key status is what makes the text caret blink
        lastShownAt = Date()
        if seedClipboard, SettingsStore.current().clipboardAutoTranslate,
           let s = NSPasteboard.general.string(forType: .string)?
               .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            model.sourceText = s
        }
        focusInput()
        // Activation is asynchronous, and macOS can deny it outright while another app
        // is frontmost — which is exactly the hotkey case. Re-assert key status and
        // focus one runloop turn later so the caret still appears when the panel is
        // opened from another app (the panel is `.nonactivatingPanel`, so it can hold
        // key status without the app ever becoming active).
        DispatchQueue.main.async { [weak self] in
            p.makeKey()
            self?.focusInput()
        }
    }

    func hidePanel() { panel?.orderOut(nil) }

    /// Ask `PanelView` to focus its input field (via `focusToken`).
    func focusInput() { focusToken &+= 1 }

    /// Open the settings in a separate window (AppKit-managed, not the SwiftUI
    /// `Settings` scene / `showSettingsWindow:`, which is unreliable for a menu-only
    /// `LSUIElement` app). Reliable and conventional; replaces the earlier in-panel
    /// flip whose 3D-rotated Back button couldn't be clicked.
    func openSettings() {
        hidePanel()
        let window = ensureSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    // MARK: - Panel construction

    private func ensureSettingsWindow() -> NSWindow {
        if let settingsWindow { return settingsWindow }
        // Fixed size — settings has a small, stable set of controls, so it doesn't
        // need to be resizable.
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        w.title = "instant-translate Settings"
        w.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SettingsView().environmentObject(languageCatalog))
        host.autoresizingMask = [.width, .height]
        w.contentView = host
        settingsWindow = w
        return w
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        // `.nonactivatingPanel` is essential: without it the panel depends on the app
        // being active to actually render, but macOS 14+ focus-stealing prevention can
        // deny `NSApp.activate(ignoringOtherApps:)` for ~30 s after launch — so the
        // panel was "visible" (isVisible=true) yet not shown on screen until the app
        // finally activated. A non-activating panel renders + accepts input without
        // requiring app activation (this is why NSPopover-based menu-bar apps don't hit
        // this — see load-spinner).
        let p = TranslationPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.isFloatingPanel = true
        p.level = .floating
        // NB: do NOT set hidesOnDeactivate — it auto-hides the panel on deactivation
        // WITHOUT clearing `isVisible`, so togglePanel would then see a stale `true`
        // and `orderOut` (a no-op) instead of showing. We dismiss on deactivation
        // ourselves via applicationDidResignActive (an explicit orderOut).
        p.isReleasedWhenClosed = false
        p.animationBehavior = .utilityWindow
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        // Height leaves room for the always-present status row on top of the two
        // 80 pt text areas; below this the panel starts squashing them.
        p.minSize = NSSize(width: 320, height: 320)
        p.setFrameAutosaveName("InstantTranslatePanel")   // remembers the user's chosen size

        let host = NSHostingView(rootView:
            PanelView()
                .environmentObject(model)
                .environmentObject(self)
                .environmentObject(languageCatalog))
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        panel = p
        return p
    }

    /// Anchor the panel under the status-bar button and keep it fully on-screen.
    /// The size comes from the autosaved frame but is clamped to the current screen,
    /// so an over-large saved size (e.g. from a bigger external display) can't push
    /// the panel off a smaller screen.
    private func position(_ panel: NSPanel) {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        let vis = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var size = panel.frame.size
        size.width = min(size.width, vis.width - 16)
        size.height = min(size.height, vis.height - 16)

        let inScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(x: inScreen.midX - size.width / 2,
                             y: inScreen.minY - size.height - 6)
        origin.x = min(max(origin.x, vis.minX + 8), vis.maxX - size.width - 8)
        origin.y = min(max(origin.y, vis.minY + 8), vis.maxY - size.height - 8)

        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
