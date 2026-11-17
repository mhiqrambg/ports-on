import SwiftUI

/// Settings window. Every control here drives a real preference in SettingsStore.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings: SettingsStore

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Interval", selection: intervalBinding) {
                    ForEach(SettingsStore.refreshIntervals, id: \.seconds) { option in
                        Text(verbatim: option.label).tag(option.seconds)
                    }
                }
                .pickerStyle(.segmented)
                Text("How often the port list re-scans. Shorter = fresher, uses more CPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                Toggle("Check for updates automatically", isOn: autoUpdateBinding)
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tertiary)
                    Text("Auto-update needs a signed, notarized build with Sparkle. Placeholder for now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .navigationTitle("Settings")
    }

    // Bindings that write through SettingsStore's methods (it's @Observable, not @AppStorage).
    private var intervalBinding: Binding<Double> {
        Binding(
            get: { settings.refreshIntervalSeconds },
            set: { settings.setRefreshInterval($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { settings.setLaunchAtLogin($0) }
        )
    }

    private var autoUpdateBinding: Binding<Bool> {
        Binding(
            get: { settings.autoUpdateEnabled },
            set: { settings.setAutoUpdate($0) }
        )
    }
}
