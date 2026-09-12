import SwiftUI
import InputRuntime

@main
struct ArkeysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu-bar agent: the real Settings UI is hosted by AppDelegate's
        // fixed-width panel. This suppressed scene only provides SwiftUI's
        // application command infrastructure; it is not a second Settings
        // window. AppDelegate hides it from the Window menu if AppKit creates it.
        // Verbatim title: a LocalizedStringKey here is extracted into
        // Localizable.xcstrings as an empty "Arkeys" entry on every build.
        Window(Text(verbatim: "Arkeys"), id: "command-host") {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("menu.settings") {
                    appDelegate.openSettings()
                }
            }
        }
    }
}
