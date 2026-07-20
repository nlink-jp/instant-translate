import AppKit
import XCTest
@testable import InstantTranslate

final class TranslationPanelTests: XCTestCase {
    private func makePanel() -> TranslationPanel {
        TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
                         styleMask: [.titled, .closable, .resizable,
                                     .fullSizeContentView, .nonactivatingPanel],
                         backing: .buffered, defer: true)
    }

    func testPanelAcceptsKeyStatus() {
        // The text view only draws its caret in a *key* window. If the panel ever stops
        // accepting key status, opening it with the global hotkey from another app
        // gives a panel with no visible cursor.
        XCTAssertTrue(makePanel().canBecomeKey)
    }

    func testPanelIsNotAMainWindow() {
        // It's an accessory panel — becoming main would draw its (hidden) title bar as
        // an active document window.
        XCTAssertFalse(makePanel().canBecomeMain)
    }

    func testPanelDoesNotHideOnDeactivate() {
        // `hidesOnDeactivate` auto-hides without clearing `isVisible`, which makes
        // `AppController.toggle` no-op instead of opening. Dismissal is done explicitly
        // in `applicationDidResignActive`.
        XCTAssertFalse(makePanel().hidesOnDeactivate)
    }
}
