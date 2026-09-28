import AVFoundation

/// Speaks text using the macOS on-device speech synthesizer.
final class LocalSpeechSynthesizer {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, language: String) {
        guard !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: language)
        synthesizer.speak(utterance)
    }

    private static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let base = LanguagePolicy.base(language)
        return AVSpeechSynthesisVoice(language: language)
            ?? AVSpeechSynthesisVoice.speechVoices().first {
                LanguagePolicy.base($0.language) == base
            }
    }
}
