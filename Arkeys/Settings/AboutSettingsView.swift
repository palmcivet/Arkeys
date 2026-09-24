import SwiftUI
import AppUpdates

struct AboutSettingsView: View {
    @EnvironmentObject private var updates: AppUpdateController

    private var versionString: String {
        let short = AppUpdate.currentVersion() ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("about.version") {
                    Text(versionString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button {
                    Task {
                        await updates.checkManually()
                    }
                } label: {
                    if updates.isChecking {
                        Text("about.checkUpdate.checking")
                    } else {
                        Text("about.checkUpdate")
                    }
                }
                .disabled(updates.isChecking)

                HStack(spacing: 8) {
                    Link("about.source", destination: AppLinks.repository)
                    Text(verbatim: "·")
                        .foregroundStyle(.secondary)
                    Link("about.issues", destination: AppLinks.issues)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}
