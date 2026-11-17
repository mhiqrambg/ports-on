import Foundation
import SwiftUI
import Observation

/// View model: owns the poll loop and exposes the UI's real states.
@MainActor
@Observable
public final class PortListViewModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case error(String)
    }
    public struct Row: Identifiable, Hashable, Comparable {
        public let entry: PortEntry
        public let canStop: Bool

        public var id: String { entry.id }

        /// Display name: the real process name as lsof reported it. No guessed service labels.
        public var displayName: String {
            entry.processName ?? "unknown"
        }

        // Sort keys (used by Table column-title sorting).
        public var port: UInt16 { entry.port }
        public var pid: pid_t { entry.pid ?? pid_t.max }
        public var bindAddress: String { entry.bindAddress }
        public var user: String { entry.user ?? "" }

        public static func < (lhs: Row, rhs: Row) -> Bool { lhs.port < rhs.port }
    }

    @ObservationIgnored private let enumerator: PortEnumerating
    private let currentUID = getuid()
    private let stopService = StopService()

    public private(set) var rows: [Row] = []
    public private(set) var phase: Phase = .loading
    public private(set) var lastUpdated: Date?
    public var filter: String = ""

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(enumerator: PortEnumerating = LsofPortEnumerator()) {
        self.enumerator = enumerator
    }

    public var filteredRows: [Row] {
        guard !filter.isEmpty else { return rows }
        let q = filter.lowercased()
        return rows.filter {
            String($0.entry.port).contains(q)
            || $0.displayName.lowercased().contains(q)
            || ($0.entry.user?.lowercased().contains(q) ?? false)
        }
    }

    public var activeCount: Int { rows.count }

    /// Start the poll loop. Cancels any prior loop and waits for it to finish, so changing
    /// the interval from Settings never leaves two loops running at once.
    public func startPolling(interval: TimeInterval = 2.0) {
        pollTask?.cancel()
        let previous = pollTask
        pollTask = Task { [weak self] in
            _ = await previous?.value
            await self?.pollLoop(interval: interval)
        }
    }

    private func pollLoop(interval: TimeInterval) async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { break }
            await refresh()
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refresh() async {
        do {
            let entries = try await enumerator.listListeningTCP()
            let currentUsername = ProcessInfo.processInfo.userName
            rows = entries.map { entry in
                Row(entry: entry, canStop: entry.user == currentUsername)
            }
            lastUpdated = Date()
            phase = .loaded
        } catch PortScanError.lsofFailed(let msg) {
            phase = .error("lsof failed: \(msg)")
        } catch {
            phase = .error("Unable to scan ports: \(error.localizedDescription)")
        }
    }

    /// Stop a process we own. Delegates to the security-gated StopService.
    public func stop(_ row: Row) async -> StopService.StopResult {
        guard let pid = row.entry.pid else { return .notRunning }
        let result = stopService.stop(pid: pid, name: row.entry.processName, uid: currentUID)
        await refresh()
        return result
    }
}
