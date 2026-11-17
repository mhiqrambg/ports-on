import SwiftUI

/// Menu bar popover: the active port count plus actions. No list here — the window is the
/// detail surface.
struct MenuBarView: View {
    @Bindable var viewModel: PortListViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(verbatim: String(viewModel.activeCount))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("active port\(viewModel.activeCount == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()

            Button {
                // Reliable on modern macOS: reveal the named window, then bring the app forward.
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 220)
        .task { await viewModel.refresh() }
    }
}
