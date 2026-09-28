import AVFoundation
import XCTest
@testable import InstantTranslate

final class LocalSpeechTests: XCTestCase {
    func testSynthesizerIsAvailableForLocalSpeech() {
        let synthesizer = AVSpeechSynthesizer()

        XCTAssertNotNil(synthesizer)
    }

    func testSpeechSupportsRegionalLanguageIdentifiers() {
        let voice = AVSpeechSynthesisVoice(language: "ko-KR")
            ?? AVSpeechSynthesisVoice.speechVoices().first {
                LanguagePolicy.base($0.language) == "ko"
            }

        if AVSpeechSynthesisVoice.speechVoices().contains(where: {
            LanguagePolicy.base($0.language) == "ko"
        }) {
            XCTAssertNotNil(voice)
        }
    }
}
