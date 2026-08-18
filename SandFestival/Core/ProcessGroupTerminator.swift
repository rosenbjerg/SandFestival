import Darwin
import Foundation

/// Kills a PTY child *and everything it spawned*, then confirms the kill
/// landed instead of trusting the signal.
///
/// Sessions are spawned through `forkpty`, whose child calls `setsid` — so the
/// pid we hold is a session leader whose process-group id equals its own pid,
/// and every descendant inherits that group unless it deliberately leaves.
/// That makes the group the right unit to signal: the pid we hold is the
/// *wrapper* (`nono`), not the agent. Signalling the wrapper alone is not
/// enough for a destructive flow:
///
/// - `nono` outlives its child on purpose. After the agent dies it can sit on
///   the still-attached PTY asking whether denied paths should be added to the
///   profile — a prompt nobody is going to answer once the project is gone.
/// - A SIGKILLed wrapper leaves the agent orphaned. It gets reparented to
///   launchd, keeps its cwd open, and only dies if it happens to honor the
///   SIGHUP the kernel sends the foreground group when the session leader
///   exits. Process group membership survives reparenting, so a group kill
///   still reaches it.
enum ProcessGroupTerminator {

    /// Which pid `kill` should be pointed at for a given leader.
    enum SignalTarget: Equatable {
        /// Signal the whole process group (`killpg`).
        case group(pid_t)
        /// Signal just this pid — the leader isn't its own group leader, so
        /// group-killing would hit processes we didn't spawn.
        case single(pid_t)
    }

    /// Pure target resolution, split out so the safety rule is testable
    /// without spawning anything. `processGroup` is `getpgid`'s answer, or
    /// `nil` when the lookup failed.
    ///
    /// The `processGroup == pid` requirement is the safety net: a `forkpty`
    /// child is always its own group leader, so a mismatch means either an
    /// unexpected spawn shape or — worse — a recycled pid whose group now
    /// belongs to unrelated processes. Degrade to a single-pid signal rather
    /// than risk killing a stranger's group.
    nonisolated static func target(leader pid: pid_t, processGroup: pid_t?) -> SignalTarget? {
        guard pid > 0 else { return nil }
        guard let processGroup, processGroup == pid else { return .single(pid) }
        return .group(pid)
    }

    /// Sends `signal` to `pid`'s whole process group when that's safe, else to
    /// `pid` alone. Returns false when there was nothing to signal.
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

    /// Pids still able to execute code after `signalGroup` pointed a signal at
    /// `pid` — the sweep that turns "the signal was queued" into "it landed".
    ///
    /// **This must resolve the same target `signalGroup` does.** Querying the
    /// group unconditionally looks equivalent and isn't: `KERN_PROC_PGRP`
    /// filters by pgid, so for a pid that *isn't* its own group leader — the
    /// `.single` case — nothing matches and the sweep reports an empty group
    /// while the process is alive and unkilled. Callers read empty as
    /// "confirmed gone" and go on to delete the worktree underneath it.
    ///
    /// Zombies are excluded deliberately: an exited-but-unreaped process holds
    /// no file descriptors and no cwd, so it can't keep a worktree busy or
    /// answer a prompt. Ours is reaped moments later by SwiftTerm's exit
    /// monitor, and orphaned descendants are reaped by launchd — waiting for
    /// them to disappear from the table would stall on bookkeeping we don't
    /// care about.
    ///
    /// The group is the outer bound of what we can see: a descendant that
    /// called `setsid` for itself left the group and won't appear here. Chasing
    /// those would mean walking every process on the machine by parent pid, and
    /// that chain breaks the instant the parent dies (orphans reparent to
    /// launchd). Neither nono nor the agent does this today.
    nonisolated static func liveMembers(leader pid: pid_t) -> [pid_t] {
        let processes: [kinfo_proc]?
        switch resolvedTarget(leader: pid) {
        case .group(let group): processes = fetchProcesses(selector: KERN_PROC_PGRP, value: group)
        case .single(let single): processes = fetchProcesses(selector: KERN_PROC_PID, value: single)
        case nil: return []
        }
        // A lookup we couldn't complete is reported as "still alive", not as an
        // empty group: the caller's failure mode for a false empty is deleting
        // a worktree out from under a live agent, and for a false survivor it's
        // a refused removal the user can retry.
        guard let processes else { return [pid] }
        return processes
            .filter { $0.kp_proc.p_stat != SZOMB }
            .map(\.kp_proc.p_pid)
    }

    /// `sysctl(KERN_PROC_*)` — the matching processes in one call, no `ps` fork
    /// and no walking every process on the machine looking for parents.
    /// Returns nil when the lookup itself failed, which is distinct from a
    /// successful lookup that found nothing.
    nonisolated private static func fetchProcesses(selector: Int32, value: pid_t) -> [kinfo_proc]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, selector, value]
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0..<sysctlAttempts {
            var size = 0
            guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0 else {
                return errno == ESRCH ? [] : nil
            }
            guard size > 0 else { return [] }
            // Size the buffer generously: the set can grow between the sizing
            // call and the fetch, and a short buffer makes the second sysctl
            // fail with ENOMEM. Retry rather than trust the slack.
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
