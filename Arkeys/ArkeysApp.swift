import SwiftUI
import InputRuntime

@main
struct ArkeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu-bar agent: no main window, no Dock icon (LSUIElement + .accessory).
        // Settings UI is hosted by AppDelegate's fixed-width panel.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("menu.settings") {
                    appDelegate.openSettings()
                }
            }
        }
    }
}
