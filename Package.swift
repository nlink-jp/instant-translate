// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InstantTranslate",
    // macOS 26 baseline: the programmatic Translation API (TranslationSession).
    // The string form is used deliberately — the `.v26` platform enum case may
    // not exist in older toolchains, whereas "26.0" is accepted by any SwiftPM
    // whose SDK provides it. Building still requires the macOS 26 SDK.
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "InstantTranslate",
            path: "Sources/InstantTranslate"
        ),
        .testTarget(
            name: "InstantTranslateTests",
            dependencies: ["InstantTranslate"],
            path: "Tests/InstantTranslateTests"
        ),
    ]
)
