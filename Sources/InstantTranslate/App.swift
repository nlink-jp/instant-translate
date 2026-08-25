import SwiftUI

struct InstantTranslateApp: App {
    // The menu-bar item + resizable translation panel are managed by AppController
    // (NSStatusItem + NSPanel). SwiftUI also injects the delegate into the
    // environment because it's an ObservableObject.
    @NSApplicationDelegateAdaptor(AppController.self) private var controller

    var body: some Scene {
        // Settings live on the back face of the panel (see PanelContainer), so this
        // app has no window scene. `Settings { EmptyView() }` is the required
        // placeholder for an otherwise window-less menu-bar app.
        Settings {
            EmptyView()
        }
    }
}
