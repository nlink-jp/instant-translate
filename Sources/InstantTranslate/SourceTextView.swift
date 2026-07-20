import AppKit
import SwiftUI

/// The panel's source-text input: an `NSTextView` wrapped for SwiftUI.
///
/// SwiftUI's `TextEditor` isn't enough here, for two reasons:
///
///  1. **IME**: while an input method is composing (kana-kanji conversion, pinyin,
///     hangul…) the text view holds *marked* — uncommitted — text. Auto-translating
///     that half-converted string produces nonsense and derails language detection,
///     which in turn makes the OS put up its source-language picker on top of the
///     panel, interrupting typing. `TextEditor` exposes no way to see marked text; an
///     `NSTextView` does (`hasMarkedText`), so we surface it as `isComposing` and
///     hold auto-translate until the composition is committed.
///  2. **Caret**: the insertion point must be visible the moment the panel opens, even
///     with an empty field, so it's obvious that typing will land there. Owning the
///     text view lets us make it first responder directly rather than hoping SwiftUI's
///     `@FocusState` lands on whatever `TextEditor` builds.
struct SourceTextView: NSViewRepresentable {
    @Binding var text: String
    /// Mirrors the text view's IME state: true while an uncommitted composition is open.
    @Binding var isComposing: Bool
    /// Bumped by `AppController` whenever the panel opens; each new value re-focuses
    /// the text view (a plain `Bool` can't re-trigger focus when it's already `true`).
    var focusToken: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let tv = ComposingTextView()
        tv.delegate = context.coordinator
        tv.string = text
        tv.font = .preferredFont(forTextStyle: .body)
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        // Substitutions fight with IME input and with source text pasted verbatim.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 5, height: 6)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.onCompositionChange = { [weak tv] composing in
            // Composition state can settle *after* `textDidChange` (committing replaces
            // the marked run), and a commit that doesn't alter the string emits no
            // change at all — so report it from the input-method calls themselves.
            context.coordinator.report(composing: composing, text: tv?.string)
        }

        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? ComposingTextView else { return }

        // Never stomp on an in-flight composition — rewriting `string` would cancel it.
        if !tv.hasMarkedText(), tv.string != text {
            tv.string = text
            // Externally-set text (e.g. clipboard seeding) leaves the caret at the end.
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }

        if context.coordinator.appliedFocusToken != focusToken {
            context.coordinator.appliedFocusToken = focusToken
            // Deferred: during `updateNSView` the view may not be in a window yet.
            DispatchQueue.main.async {
                guard let window = tv.window else { return }
                window.makeFirstResponder(tv)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceTextView
        weak var textView: ComposingTextView?
        /// The last `focusToken` acted on, so focus is applied once per panel open.
        var appliedFocusToken = Int.min

        init(_ parent: SourceTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            report(composing: tv.hasMarkedText(), text: tv.string)
        }

        /// Push the text view's state back into SwiftUI. `isComposing` is written
        /// **before** `text` so that the source-text observer already sees the current
        /// composition state when it decides whether to arm auto-translate.
        func report(composing: Bool, text: String?) {
            if parent.isComposing != composing { parent.isComposing = composing }
            if let text, parent.text != text { parent.text = text }
        }
    }
}

/// An `NSTextView` that reports when an input method opens or closes a composition.
///
/// `textDidChange` alone is not a reliable signal: committing a composition can leave
/// the string byte-identical (so no change notification fires), and when it does fire
/// the marked range may not have settled yet. Overriding the `NSTextInputClient` entry
/// points gives an exact answer.
final class ComposingTextView: NSTextView {
    var onCompositionChange: ((Bool) -> Void)?

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionChange?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onCompositionChange?(false)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        onCompositionChange?(hasMarkedText())
    }
}
