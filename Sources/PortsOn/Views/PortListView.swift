import SwiftUI

/// Main window: the active-listener table. Native macOS table + toolbar search.
/// States: loading, empty, error, loaded (per ui-taste "operate" surface).
struct PortListView: View {
    @Bindable var viewModel: PortListViewModel
    @State private var confirmStop: PortListViewModel.Row?
    @State private var statusMessage: String?
    /// Column sort state, driven by clicking column titles. Empty = insertion order.
    @State private var sortOrder = [KeyPathComparator<PortListViewModel.Row>]()

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
        return "Stop “\(row.displayName)” (port \(row.entry.port))?"
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
        Table(sortOrder: $sortOrder) {
            TableColumn("Port", value: \.port) { row in
                Text(verbatim: String(row.entry.port))
                    .monospacedDigit()
                    .font(.body.weight(.medium))
            }
            TableColumn("Process", value: \.displayName) { row in
                Label(row.displayName, systemImage: iconName(for: row.displayName))
                    .lineLimit(1)
                    .help(row.displayName)
            }
            TableColumn("PID", value: \.pid) { row in
                Text(verbatim: row.entry.pid.map(String.init) ?? "—")
                    .monospacedDigit()
            }
            TableColumn("Bind", value: \.bindAddress) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.bindAddress)
                        .foregroundStyle(row.entry.isPubliclyBound ? .primary : .secondary)
                        .monospacedDigit()
                    Text(row.entry.familyLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .help(row.entry.isPubliclyBound
                      ? "Bound to all interfaces (reachable from other machines)"
                      : "Bound to loopback or a specific interface")
            }
            TableColumn("User", value: \.user) { row in
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
        } rows: {
            ForEach(sortedRows) { row in
                TableRow(row)
            }
        }
    }

    /// `filteredRows` re-ordered by the current column sort. Clicking a title toggles asc/desc.
    private var sortedRows: [PortListViewModel.Row] {
        viewModel.filteredRows.sorted(using: sortOrder)
    }

    /// Icon is a visual hint keyed off the real process name — purely cosmetic, not a claim
    /// about what the process is. Anything unrecognized gets a plain dot.
    private func iconName(for processName: String) -> String {
        let name = processName.lowercased()
        switch name {
        case "nginx": return "server.rack"
        case "docker", "dockerd", "com.docker.backend": return "shippingbox"
        case "node": return "hexagon"
        case "postgres", "mysqld", "mongod", "redis-server": return "cylinder"
        case "controlcenter": return "airplayaudio"
        case "sshd": return "lock.shield"
        case "workerd": return "cloud"
        case "omp", "opencode": return "cpu"
        default:
            // Browsers have long, versioned names — match by prefix.
            if name.hasPrefix("google chrome") || name.hasPrefix("chromium") {
                return "globe"
            }
            return "dot"
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
