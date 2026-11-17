import SwiftUI

@main
struct PortsOnApp: App {
    @State private var viewModel = PortListViewModel()
    @State private var settings = SettingsStore.shared


    var body: some Scene {
        Window("Listening Ports", id: "main") {
            PortListView(viewModel: viewModel)
                .environment(settings)
                .frame(minWidth: 640, minHeight: 420)
                .task {
                    viewModel.startPolling(interval: settings.refreshIntervalSeconds)
                }
                .onDisappear {
                    viewModel.stopPolling()
                }
                // Restart the poll loop when the interval changes in Settings.
                .onChange(of: settings.refreshIntervalSeconds) { _, newInterval in
                    viewModel.startPolling(interval: newInterval)
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 860, height: 560)
        // Keep the main window available; reveal it from the menu bar via openWindow.
        .restorationBehavior(.disabled)

        MenuBarExtra("Ports On", systemImage: "point.3.connected.trianglepath.dotted") {
            MenuBarView(viewModel: viewModel)
                .environment(settings)
        }

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
