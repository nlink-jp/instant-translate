import Foundation

/// The app's own version, for display in the UI.
///
/// The value is `CFBundleShortVersionString`, which `make build-app` injects into the
/// bundle's `Info.plist` from `git describe` (so it carries the org's leading "v", and
/// a `-dirty` suffix on an uncommitted build — both worth showing verbatim when someone
/// is telling you which build they're running).
enum AppInfo {
    /// The version to display. `"dev"` when there's no bundle value, which is the
    /// `swift run` / `make run` case.
    static var version: String { version(fromBundleValue: bundleShortVersion) }

    /// The display rule, separated from the bundle lookup so it can be unit-tested.
    static func version(fromBundleValue value: String?) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return "dev" }
        return value
    }

    private static var bundleShortVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}
