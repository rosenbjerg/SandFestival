import Darwin
import Foundation
import Testing
@testable import SandFestival

@Suite("ProcessGroupTerminator")
struct ProcessGroupTerminatorTests {

    // MARK: - Target resolution (pure)

    @Test("A forkpty child — its own group leader — is signalled as a group")
    func groupTargetWhenLeaderOwnsGroup() {
        #expect(ProcessGroupTerminator.target(leader: 4242, processGroup: 4242) == .group(4242))
    }

    @Test("A pid that isn't its own group leader is signalled alone")
    func singleTargetWhenGroupBelongsToSomeoneElse() {
        // This is the recycled-pid / unexpected-spawn-shape case: the group
        // now belongs to processes we never spawned, so killpg would be a
        // stranger's problem.
        #expect(ProcessGroupTerminator.target(leader: 4242, processGroup: 17) == .single(4242))
    }

    @Test("A failed getpgid lookup degrades to a single-pid signal")
    func singleTargetWhenLookupFailed() {
        #expect(ProcessGroupTerminator.target(leader: 4242, processGroup: nil) == .single(4242))
    }

    @Test("Non-positive pids resolve to no target at all")
    func noTargetForInvalidPid() {
        // kill(0, …) signals our own process group and kill(-1, …) signals
        // everything we own — both catastrophic, so they must never resolve.
        #expect(ProcessGroupTerminator.target(leader: 0, processGroup: 0) == nil)
        #expect(ProcessGroupTerminator.target(leader: -1, processGroup: -1) == nil)
        #expect(ProcessGroupTerminator.signalGroup(leader: 0, signal: SIGKILL) == false)
    }

    // MARK: - Real process group (integration)

    @Test("liveGroupMembers sees a leader and its child; the group kill takes both")
    func killsWholeGroupIncludingGrandchild() async throws {
        // Mirrors the session's shape: a setsid leader (stand-in for nono)
        // that forks a long-lived child (stand-in for claude) and then waits,
        // which is precisely the arrangement where signalling the leader alone
        // leaves the child running.
        let leader = try spawnDetachedLeaderWithChild()

        let members = try await pollUntil(timeout: .seconds(3)) {
            let live = ProcessGroupTerminator.liveGroupMembers(leader: leader)
            return live.count >= 2 ? live : nil
        }
        #expect(members.contains(leader))

        ProcessGroupTerminator.signalGroup(leader: leader, signal: SIGKILL)

        let cleared = try await pollUntil(timeout: .seconds(3)) {
            ProcessGroupTerminator.liveGroupMembers(leader: leader).isEmpty ? true : nil
        }
        #expect(cleared)
        // Reap the leader so the test doesn't leave a zombie for the runner.
        var status: Int32 = 0
        waitpid(leader, &status, WNOHANG)
    }

    @Test("liveGroupMembers is empty for a group that never existed")
    func noMembersForUnknownGroup() {
        // An unused-but-plausible pid: no group, so nothing to kill and — more
        // importantly — no false "still running" that would block a removal.
        #expect(ProcessGroupTerminator.liveGroupMembers(leader: 0).isEmpty)
    }

    // MARK: - Helpers

    /// `posix_spawn`s `sh -c 'sleep 30 & wait'` with `POSIX_SPAWN_SETSID` so the
    /// child becomes its own session and group leader, exactly like a forkpty
    /// child. The `sleep` it backgrounds inherits that group.
    private func spawnDetachedLeaderWithChild() throws -> pid_t {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        let args = ["/bin/sh", "-c", "sleep 30 & wait"]
        var pid: pid_t = 0
        let spawned = args.withCStringArray { argv in
            posix_spawn(&pid, "/bin/sh", nil, &attr, argv, nil)
        }
        try #require(spawned == 0, "posix_spawn failed with \(spawned)")
        try #require(pid > 0)
        return pid
    }

    /// Polls `body` until it returns a value or the timeout expires. Process
    /// teardown is asynchronous — SIGKILL is delivered immediately but the
    /// process table entry disappears a moment later — so every assertion about
    /// liveness has to be a poll rather than a single sample.
    private func pollUntil<T>(
        timeout: Duration,
        _ body: () -> T?
    ) async throws -> T {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if let value = body() { return value }
            try #require(ContinuousClock.now < deadline, "condition never held within \(timeout)")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private extension [String] {
    /// Builds a NULL-terminated argv for `posix_spawn`, valid for the duration
    /// of `body`.
    func withCStringArray<R>(_ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        var pointers: [UnsafeMutablePointer<CChar>?] = map { strdup($0) }
        pointers.append(nil)
        defer { pointers.forEach { free($0) } }
        return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }
}
