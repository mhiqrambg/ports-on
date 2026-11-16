import SwiftUI

/// Menu bar popover: port count + the busiest few, with a jump-to-window affordance.
/// Matches decision D-7 (count + one-line summary) without duplicating the full table.
struct MenuBarView: View {
    @Bindable var viewModel: PortListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if viewModel.rows.isEmpty {
                Text("No listeners detected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.rows.prefix(6)) { row in
                    HStack {
                        Text("\(row.entry.port)")
                            .monospacedDigit()
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(row.serviceLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if viewModel.rows.count > 6 {
                    Text("+\(viewModel.rows.count - 6) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Divider()
            Button("Open Ports On") {
                // Bring the main window forward.
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .frame(width: 260)
        .task { await viewModel.refresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.activeCount)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("listening port\(viewModel.activeCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.tint)
                .font(.title3)
        }
    }
}
