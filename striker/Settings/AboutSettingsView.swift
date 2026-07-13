import SwiftUI

struct AboutSettingsView: View {
    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
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

                Button("about.checkUpdate") {}
                    .disabled(true)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }
}
