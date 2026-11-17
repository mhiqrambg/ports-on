import SwiftUI

/// Menu bar popover, kept deliberately simple: the active port count plus a button
/// to open the full window. No list here — the window is the detail surface.
struct MenuBarView: View {
    @Bindable var viewModel: PortListViewModel

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
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
            .keyboardShortcut(.defaultAction)
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
