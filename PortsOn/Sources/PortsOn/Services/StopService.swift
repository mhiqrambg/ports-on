import Foundation

/// Security-gated stop of a process the current user owns.
///
/// Invariants (07-security, RISK-02/03/09):
/// - Never signals a process not owned by the current user (no elevation in v1).
/// - Re-validates (pid, uid, name) immediately before signalling to shrink the
///   PID-reuse TOCTOU window.
/// - Refuses a fixed deny list of critical system processes outright.
/// - Uses only `kill(2)` with SIGTERM — no arbitrary-path execution.
public struct StopService: Sendable {
    public let denyList: Set<String>

    public init(denyList: Set<String> = StopService.defaultDenyList) {
        self.denyList = denyList
    }

    public enum StopResult: Sendable, Equatable {
        case stopped
        case notPermitted
        case denied(String)   // name of the protected process
        case notRunning
        case failed(String)
    }

    /// Stop an owned process identified by a validated (pid, name) pair.
    public func stop(pid: pid_t, name: String?, uid: uid_t) -> StopResult {
        let currentUID = getuid()
        guard uid == currentUID else { return .notPermitted }
        let lowerName = (name ?? "").lowercased()
        guard !denyList.contains(lowerName) else { return .denied(name ?? "protected") }

        // Re-validate identity immediately before the signal.
        guard let (verifiedUID, verifiedName) = Self.identity(of: pid) else {
            return .notRunning
        }
        guard verifiedUID == currentUID else { return .notPermitted }
        guard !denyList.contains(verifiedName.lowercased()) else {
            return .denied(verifiedName)
        }

        let result = kill(pid, SIGTERM)
        if result == 0 { return .stopped }
        if errno == EPERM { return .notPermitted }
        if errno == ESRCH { return .notRunning }
        return .failed(String(cString: strerror(errno)))
    }

    /// Read (uid, name) for a pid via libproc. Returns nil if the process is gone.
    static func identity(of pid: pid_t) -> (uid_t, String)? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.size else {
            return nil
        }
        let uid = info.kp_eproc.e_ucred.cr_uid
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { ptr -> String in
            let chars = ptr.bindMemory(to: CChar.self)
            return String(cString: chars.baseAddress!)
        }
        return (uid, name)
    }

    public static let defaultDenyList: Set<String> = [
        "launchd", "windowserver", "loginwindow", "kernel_task", "dock",
        "finder", "systemuiserver", "coreservicesd", "hidd", "installd",
        "cfprefsd", "powerd", "xpc", "xpcproxy", "mds", "mds_stores",
    ]
}
