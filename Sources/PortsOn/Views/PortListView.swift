import SwiftUI

/// Main window: the active-listener table. Native macOS table + toolbar search.
/// States: loading, empty, error, loaded (per ui-taste "operate" surface).
struct PortListView: View {
    @Bindable var viewModel: PortListViewModel
    @State private var confirmStop: PortListViewModel.Row?
    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if case .error(let message) = viewModel.phase {
                errorBanner(message)
            }
            tableOrState
            statusBar
        }
        .searchable(text: $viewModel.filter, prompt: "Filter by port, process, or service")
        .navigationTitle("Listening Ports")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh list")
            }
        }
        .confirmationDialog(
            stopTitle,
            isPresented: Binding(
                get: { confirmStop != nil },
                set: { if !$0 { confirmStop = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Stop Process", role: .destructive) {
                if let row = confirmStop {
                    Task { await performStop(row) }
                }
                confirmStop = nil
            }
            Button("Cancel", role: .cancel) { confirmStop = nil }
        } message: {
            Text("This sends SIGTERM to the process holding port \(confirmStop?.entry.port ?? 0). You can only stop processes you own.")
        }
    }

    private var stopTitle: String {
        guard let row = confirmStop else { return "Stop process?" }
        return "Stop “\(row.serviceLabel)” (port \(row.entry.port))?"
    }

    @ViewBuilder
    private var tableOrState: some View {
        switch viewModel.phase {
        case .loading where viewModel.rows.isEmpty:
            ProgressView("Scanning listening ports…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error where viewModel.rows.isEmpty:
            ContentUnavailableView("No Port Data", systemImage: "exclamationmark.triangle", description: Text(statusMessage ?? "Could not scan ports."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            if viewModel.filteredRows.isEmpty {
                ContentUnavailableView.search(text: viewModel.filter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                portsTable
            }
        }
    }

    private var portsTable: some View {
        Table(viewModel.filteredRows, selection: .constant(nil)) {
            TableColumn("Port") { row in
                Text("\(row.entry.port)")
                    .monospacedDigit()
                    .font(.body.weight(.medium))
            }
            TableColumn("Service") { row in
                Label(row.serviceLabel, systemImage: iconName(for: row))
                    .lineLimit(1)
            }
            TableColumn("Process") { row in
                Text(row.entry.processName ?? "—")
            }
            TableColumn("PID") { row in
                Text(row.entry.pid.map(String.init) ?? "—")
                    .monospacedDigit()
            }
            TableColumn("Bind") { row in
                Text(row.entry.isPubliclyBound ? row.entry.bindAddress : "\(row.entry.bindAddress)")
                    .foregroundStyle(row.entry.isPubliclyBound ? .primary : .secondary)
                    .help(row.entry.isPubliclyBound
                          ? "Bound to all interfaces (reachable from other machines)"
                          : "Bound to loopback or a specific interface")
            }
            TableColumn("User") { row in
                Text(row.entry.user ?? "—")
            }
            TableColumn("Actions") { row in
                if row.canStop {
                    Button("Stop", role: .destructive) { confirmStop = row }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Stop process on port \(row.entry.port)")
                } else {
                    Image(systemName: "lock")
                        .foregroundStyle(.tertiary)
                        .help("Only your own processes can be stopped")
                }
            }
        }
    }

    private func iconName(for row: PortListViewModel.Row) -> String {
        switch row.serviceId {
        case "nginx": return "server.rack"
        case "docker": return "shippingbox"
        case "nodejs", "nextjs", "astro", "vite": return "curlybraces"
        case "postgres", "mysql", "mongodb", "redis": return "cylinder"
        case "airplay": return "airplayaudio"
        case "sshd": return "lock.shield"
        default: return "dot"
        }
    }

    private var statusBar: some View {
        HStack {
            if let status = statusMessage {
                Label(status, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            Text(lastUpdatedText)
                .foregroundStyle(.secondary)
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var lastUpdatedText: String {
        guard let date = viewModel.lastUpdated else { return "" }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return "Updated \(formatter.string(from: date)) · \(viewModel.activeCount) listeners"
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.top, 10)
    }

    private func performStop(_ row: PortListViewModel.Row) async {
        let result = await viewModel.stop(row)
        switch result {
        case .stopped:
            withAnimation { statusMessage = "Stopped process on port \(row.entry.port)" }
        case .denied(let name):
            statusMessage = "Refused: “\(name)” is protected"
        case .notPermitted:
            statusMessage = "Refused: you don't own that process"
        case .notRunning:
            statusMessage = "Process already exited"
        case .failed(let reason):
            statusMessage = "Stop failed: \(reason)"
        }
    }
}
