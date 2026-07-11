import SwiftUI

@main
struct strikerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var inputMonitor = InputMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(inputMonitor)
                .onAppear {
                    appDelegate.bind(inputMonitor: inputMonitor)
                }
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置") {
                    appDelegate.openSettings()
                }
            }
        }
    }
}
