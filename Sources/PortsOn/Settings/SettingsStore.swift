import Foundation
import SwiftUI
import Observation
import ServiceManagement

/// Persists user preferences in UserDefaults. Observable so the UI reacts live.
///
/// Uses @Observable with explicit UserDefaults accessors rather than @AppStorage, because
/// @AppStorage cannot be combined with @Observable on the same property.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    /// How often the port list re-polls (seconds).
    static let refreshIntervals: [(label: String, seconds: Double)] = [
        ("1s", 1), ("2s", 2), ("5s", 5), ("10s", 10), ("30s", 30),
    ]

    private enum Key {
        static let refreshInterval = "refreshIntervalSeconds"
        static let launchAtLogin = "launchAtLogin"
        static let autoUpdate = "autoUpdateEnabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Key.refreshInterval)
        refreshIntervalSeconds = SettingsStore.refreshIntervals.contains { $0.seconds == stored }
            ? stored : 2
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        autoUpdateEnabled = defaults.bool(forKey: Key.autoUpdate)
    }

    private(set) var refreshIntervalSeconds: Double {
        didSet { defaults.set(refreshIntervalSeconds, forKey: Key.refreshInterval) }
    }

    private(set) var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    private(set) var autoUpdateEnabled: Bool {
        didSet { defaults.set(autoUpdateEnabled, forKey: Key.autoUpdate) }
    }

    func setRefreshInterval(_ seconds: Double) {
        refreshIntervalSeconds = seconds
    }

    func setAutoUpdate(_ enabled: Bool) {
        autoUpdateEnabled = enabled
    }

    /// Register/unregister the app as a login item via SMAppService, then record the result.
    func setLaunchAtLogin(_ enabled: Bool) {
        guard SMAppService.mainApp.status != .notFound else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            // The system refused; reflect the true state so the toggle doesn't lie.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
