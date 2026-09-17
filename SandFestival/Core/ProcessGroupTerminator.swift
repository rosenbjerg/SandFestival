import Darwin
import Foundation

enum ProcessGroupTerminator {

    enum SignalTarget: Equatable {
        case group(pid_t)
        case single(pid_t)
    }

    // The start time is what stops a re-signal on a later sweep from hitting
    // a recycled pid.
    nonisolated struct TrackedProcess: Hashable {
        let pid: pid_t
        let startSeconds: Int64
        let startMicroseconds: Int32
    }

    // A pgid that isn't the pid means a recycled pid or an unexpected spawn
    // shape, and its group may belong to strangers — never group-kill it.
    nonisolated static func target(leader pid: pid_t, processGroup: pid_t?) -> SignalTarget? {
        guard pid > 0 else { return nil }
        guard let processGroup, processGroup == pid else { return .single(pid) }
        return .group(pid)
    }

    @discardableResult
    nonisolated static func signalGroup(leader pid: pid_t, signal: Int32) -> Bool {
        switch resolvedTarget(leader: pid) {
        case .group(let group):
            killpg(group, signal)
            return true
        case .single(let single):
            kill(single, signal)
            return true
        case nil:
            return false
        }
    }

    nonisolated private static func resolvedTarget(leader pid: pid_t) -> SignalTarget? {
        let pgid = getpgid(pid)
        return target(leader: pid, processGroup: pgid == -1 ? nil : pgid)
    }

    // Tracked pids individually, never their groups: only the pids themselves
    // are proven ours.
    @discardableResult
    nonisolated static func signalAll(
        leader pid: pid_t,
        tracked: Set<TrackedProcess>,
        signal: Int32
    ) -> Bool {
        let signalled = signalGroup(leader: pid, signal: signal)
        for entry in tracked where isStillAlive(entry) {
            kill(entry.pid, signal)
        }
        return signalled
    }

    nonisolated static func descendants(ofAnyOf roots: Set<pid_t>) -> Set<TrackedProcess> {
        let roots = roots.filter { $0 > 0 }
        guard !roots.isEmpty, let all = fetchProcesses(selector: KERN_PROC_ALL, value: 0) else { return [] }

        var byPid: [pid_t: kinfo_proc] = [:]
        var childrenByParent: [pid_t: [pid_t]] = [:]
        for process in all where process.kp_proc.p_stat != SZOMB {
            byPid[process.kp_proc.p_pid] = process
            childrenByParent[process.kp_eproc.e_ppid, default: []].append(process.kp_proc.p_pid)
        }

        var found: Set<TrackedProcess> = []
        var visited: Set<pid_t> = []
        var queue = Array(roots)
        while let pid = queue.popLast() {
            guard visited.insert(pid).inserted else { continue }
            if let process = byPid[pid] { found.insert(identity(of: process)) }
            queue.append(contentsOf: childrenByParent[pid] ?? [])
        }
        return found
    }

    nonisolated static func descendants(of pid: pid_t) -> Set<TrackedProcess> {
        descendants(ofAnyOf: [pid])
    }

    nonisolated private static func identity(of process: kinfo_proc) -> TrackedProcess {
        let started = process.kp_proc.p_un.__p_starttime
        return TrackedProcess(
            pid: process.kp_proc.p_pid,
            startSeconds: Int64(started.tv_sec),
            startMicroseconds: Int32(started.tv_usec)
        )
    }

    nonisolated private static func isStillAlive(_ entry: TrackedProcess) -> Bool {
        guard let processes = fetchProcesses(selector: KERN_PROC_PID, value: entry.pid) else { return true }
        guard let process = processes.first(where: { $0.kp_proc.p_pid == entry.pid }),
              process.kp_proc.p_stat != SZOMB
        else { return false }
        return identity(of: process) == entry
    }

    nonisolated static func liveMembers(leader pid: pid_t) -> [pid_t] {
        liveMembers(leader: pid, tracked: [])
    }

    // Must resolve the same target `signalGroup` does: KERN_PROC_PGRP on a
    // `.single` pid matches nothing, and an empty sweep reads as "confirmed gone".
    nonisolated static func liveMembers(leader pid: pid_t, tracked: Set<TrackedProcess>) -> [pid_t] {
        var survivors: Set<pid_t> = []
        switch resolvedTarget(leader: pid) {
        case .group(let group):
            survivors.formUnion(livePids(fetchProcesses(selector: KERN_PROC_PGRP, value: group), whenUnknown: pid))
        case .single(let single):
            survivors.formUnion(livePids(fetchProcesses(selector: KERN_PROC_PID, value: single), whenUnknown: pid))
        case nil:
            break
        }
        for entry in tracked where isStillAlive(entry) {
            survivors.insert(entry.pid)
        }
        return Array(survivors)
    }

    // A failed lookup is "alive", not empty: a false empty deletes a worktree
    // under a live agent. Zombies are dead — no fds, no cwd — and waiting on
    // them stalls on reaping nobody needs.
    nonisolated private static func livePids(_ processes: [kinfo_proc]?, whenUnknown pid: pid_t) -> [pid_t] {
        guard let processes else { return [pid] }
        return processes
            .filter { $0.kp_proc.p_stat != SZOMB }
            .map(\.kp_proc.p_pid)
    }

    nonisolated private static func fetchProcesses(selector: Int32, value: pid_t) -> [kinfo_proc]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, selector, value]
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0..<sysctlAttempts {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else {
                return errno == ESRCH ? [] : nil
            }
            guard size > 0 else { return [] }
            // The table can grow between the sizing call and the fetch; ENOMEM means retry.
            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + sysctlSlack)
            var actual = buffer.count * stride
            let result = buffer.withUnsafeMutableBytes { raw in
                sysctl(&mib, u_int(mib.count), raw.baseAddress, &actual, nil, 0)
            }
            if result == 0 { return Array(buffer.prefix(actual / stride)) }
            guard errno == ENOMEM else { return errno == ESRCH ? [] : nil }
        }
        return nil
    }

    nonisolated private static let sysctlAttempts = 3
    nonisolated private static let sysctlSlack = 8
}
