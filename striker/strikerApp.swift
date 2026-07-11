import SwiftUI
import InputRuntime

@main
struct strikerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var runtime = InputRuntime()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runtime)
                .onAppear {
                    appDelegate.bind(runtime: runtime)
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
