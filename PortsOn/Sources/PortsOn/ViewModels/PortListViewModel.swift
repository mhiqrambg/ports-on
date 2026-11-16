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

    public struct Row: Identifiable, Hashable {
        public let entry: PortEntry
        public let serviceLabel: String
        public let serviceId: String?
        public let canStop: Bool

        public var id: String { entry.id }
    }

    @ObservationIgnored private let enumerator: PortEnumerating
    private let resolver = ServiceResolver()
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
            $0.serviceLabel.lowercased().contains(q)
            || String($0.entry.port).contains(q)
            || ($0.entry.processName?.lowercased().contains(q) ?? false)
        }
    }

    public var activeCount: Int { rows.count }

    public func startPolling(interval: TimeInterval = 2.0) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
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
                let (label, svc) = resolver.resolve(entry)
                let canStop = entry.user == currentUsername
                return Row(entry: entry, serviceLabel: label,
                           serviceId: svc?.id, canStop: canStop)
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
