import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "launch at login" toggle.
///
/// Registration only works from a proper `.app` bundle; when run as a bare binary the
/// calls throw, which is logged and swallowed. `SMAppService` is the source of truth —
/// no separate persisted flag (which could drift from the real state).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let status) where status != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            NSLog("instant-translate: failed to update login item: \(error.localizedDescription)")
        }
    }
}
