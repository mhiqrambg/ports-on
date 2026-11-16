import SwiftUI

@main
struct PortsOnApp: App {
    @State private var viewModel = PortListViewModel()

    var body: some Scene {
        WindowGroup {
            PortListView(viewModel: viewModel)
                .frame(minWidth: 640, minHeight: 420)
                .task {
                    viewModel.startPolling(interval: 2.0)
                }
                .onDisappear {
                    viewModel.stopPolling()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 860, height: 560)

        MenuBarExtra("Ports On", systemImage: "point.3.connected.trianglepath.dotted") {
            MenuBarView(viewModel: viewModel)
        }
    }
}
