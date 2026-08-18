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

    @Test("liveMembers sees a leader and its child; the group kill takes both")
    func killsWholeGroupIncludingGrandchild() async throws {
        // Mirrors the session's shape: a setsid leader (stand-in for nono)
        // that forks a long-lived child (stand-in for claude) and then waits,
        // which is precisely the arrangement where signalling the leader alone
        // leaves the child running.
        let leader = try spawnDetachedLeaderWithChild()

        let members = try await pollUntil(timeout: .seconds(3)) {
            let live = ProcessGroupTerminator.liveMembers(leader: leader)
            return live.count >= 2 ? live : nil
        }
        #expect(members.contains(leader))

        ProcessGroupTerminator.signalGroup(leader: leader, signal: SIGKILL)

        let cleared = try await pollUntil(timeout: .seconds(3)) {
            ProcessGroupTerminator.liveMembers(leader: leader).isEmpty ? true : nil
        }
        #expect(cleared)
        // Reap the leader so the test doesn't leave a zombie for the runner.
        var status: Int32 = 0
        waitpid(leader, &status, WNOHANG)
    }

    @Test("liveMembers is empty for a pid that isn't running")
    func noMembersForUnknownGroup() throws {
        // `0` stops at the `pid > 0` guard; the high pid is the one that
        // actually reaches sysctl. Nothing to kill, and — more importantly —
        // no false "still running" that would block a removal.
        #expect(ProcessGroupTerminator.liveMembers(leader: 0).isEmpty)
        #expect(ProcessGroupTerminator.liveMembers(leader: try unusedPid()).isEmpty)
    }

    @Test("A live pid that isn't its own group leader still reports as running")
    func nonLeaderIsReportedLive() async throws {
        // Regression: the sweep used to query KERN_PROC_PGRP unconditionally.
        // A non-leader owns no group, so that query came back empty and
        // `forceStopAndWait` reported a confirmed kill for a process that was
        // still very much alive — clearing the way for `git worktree remove` to
        // run underneath it.
        let child = try spawnChildInOurGroup()
        defer { reap(child) }

        try #require(getpgid(child) != child, "child must not be its own group leader")
        #expect(ProcessGroupTerminator.target(leader: child, processGroup: getpgid(child)) == .single(child))

        let seen = try await pollUntil(timeout: .seconds(3)) {
            ProcessGroupTerminator.liveMembers(leader: child).contains(child) ? true : nil
        }
        #expect(seen)
    }

    @Test("A single-target kill is confirmed once the pid is gone")
    func singleTargetClearsAfterKill() async throws {
        let child = try spawnChildInOurGroup()
        _ = try await pollUntil(timeout: .seconds(3)) {
            ProcessGroupTerminator.liveMembers(leader: child).contains(child) ? true : nil
        }

        ProcessGroupTerminator.signalGroup(leader: child, signal: SIGKILL)
        reap(child)

        let cleared = try await pollUntil(timeout: .seconds(3)) {
            ProcessGroupTerminator.liveMembers(leader: child).isEmpty ? true : nil
        }
        #expect(cleared)
    }

    // MARK: - Descendant tracking

    @Test("The snapshot covers the whole descendant tree, stamped")
    func descendantsIncludeGrandchild() async throws {
        let leader = try spawnDetachedLeaderWithChild()
        var captured: Set<ProcessGroupTerminator.TrackedProcess> = []
        defer { cleanUp(leader: leader, tracked: captured) }

        let tracked = try await pollUntil(timeout: .seconds(3)) {
            let found = ProcessGroupTerminator.descendants(of: leader)
            return found.count >= 2 ? found : nil
        }
        captured = tracked

        #expect(tracked.contains { $0.pid == leader })
        // An unstamped entry would defeat the recycled-pid guard entirely.
        #expect(tracked.allSatisfy { $0.startSeconds > 0 })
    }

    @Test("A setsid escapee is invisible to the group query but caught by tracking")
    func escapeeIsInvisibleToGroupQueryButTracked() async throws {
        try requirePython3()
        let leader = try spawnLeaderWithEscapee()
        var captured: Set<ProcessGroupTerminator.TrackedProcess> = []
        defer { cleanUp(leader: leader, tracked: captured) }

        let (tracked, escapee) = try await escapeeOf(leader: leader)
        captured = tracked

        #expect(!ProcessGroupTerminator.liveMembers(leader: leader).contains(escapee))
        #expect(ProcessGroupTerminator.liveMembers(leader: leader, tracked: tracked).contains(escapee))
    }

    @Test("A tracked escapee is killed and the sweep clears")
    func escapeeIsKilledAndSweepClears() async throws {
        try requirePython3()
        let leader = try spawnLeaderWithEscapee()
        var captured: Set<ProcessGroupTerminator.TrackedProcess> = []
        defer { cleanUp(leader: leader, tracked: captured) }

        let (tracked, escapee) = try await escapeeOf(leader: leader)
        captured = tracked

        ProcessGroupTerminator.signalAll(leader: leader, tracked: tracked, signal: SIGKILL)
        var status: Int32 = 0
        waitpid(leader, &status, WNOHANG)

        // Probe the escapee with `kill(_, 0)` rather than asking `liveMembers`.
        // The sweep is the thing under test, so it cannot also be the evidence:
        // a sweep that ignores `tracked` reports "clear" the moment the group
        // dies, and this test would pass while the escapee ran on.
        let gone = try await pollUntil(timeout: .seconds(5)) {
            kill(escapee, 0) == -1 && errno == ESRCH ? true : nil
        }
        #expect(gone)
    }

    @Test("A single-target kill takes verified descendants with it")
    func singleTargetKillsVerifiedDescendants() async throws {
        let child = try spawnChildWithGrandchildInOurGroup()
        var captured: Set<ProcessGroupTerminator.TrackedProcess> = []
        defer { cleanUp(leader: child, tracked: captured) }

        try #require(getpgid(child) != child, "child must not be its own group leader")

        let tracked = try await pollUntil(timeout: .seconds(3)) {
            let found = ProcessGroupTerminator.descendants(of: child)
            return found.count >= 2 ? found : nil
        }
        captured = tracked
        let grandchild = try #require(tracked.map(\.pid).first { $0 != child })

        // The `.single` query sees only the leader — the grandchild sits in the
        // runner's group, which we deliberately refuse to sweep.
        #expect(!ProcessGroupTerminator.liveMembers(leader: child).contains(grandchild))
        #expect(ProcessGroupTerminator.liveMembers(leader: child, tracked: tracked).contains(grandchild))

        ProcessGroupTerminator.signalAll(leader: child, tracked: tracked, signal: SIGKILL)
        var status: Int32 = 0
        waitpid(child, &status, WNOHANG)

        let cleared = try await pollUntil(timeout: .seconds(3)) {
            ProcessGroupTerminator.liveMembers(leader: child, tracked: tracked).isEmpty ? true : nil
        }
        #expect(cleared)
    }

    @Test("A tracked entry whose start time no longer matches is ignored")
    func staleIdentityIsNeverSignalled() async throws {
        let child = try spawnChildInOurGroup()
        defer { reap(child) }

        let real = try await pollUntil(timeout: .seconds(3)) {
            ProcessGroupTerminator.descendants(of: child).first { $0.pid == child }
        }
        let stale = ProcessGroupTerminator.TrackedProcess(
            pid: real.pid,
            startSeconds: real.startSeconds - 1,
            startMicroseconds: real.startMicroseconds
        )

        // Same live pid, different stamp: this is the recycled-pid case, and
        // treating it as a survivor would aim a SIGKILL at a stranger.
        let absent = try unusedPid()
        #expect(ProcessGroupTerminator.liveMembers(leader: absent, tracked: [stale]).isEmpty)
        #expect(ProcessGroupTerminator.liveMembers(leader: absent, tracked: [real]) == [child])
    }

    // MARK: - Helpers

    /// Finds a descendant of `leader` that has left its process group — the
    /// escapee — returning the snapshot alongside it.
    private func escapeeOf(
        leader: pid_t
    ) async throws -> (Set<ProcessGroupTerminator.TrackedProcess>, pid_t) {
        try await pollUntil(timeout: .seconds(10)) {
            let tracked = ProcessGroupTerminator.descendants(of: leader)
            let inGroup = Set(ProcessGroupTerminator.liveMembers(leader: leader))
            guard let escapee = tracked.map(\.pid).first(where: { !inGroup.contains($0) }) else { return nil }
            return (tracked, escapee)
        }
    }

    /// `posix_spawn`s a `POSIX_SPAWN_SETSID` leader that forks a child which
    /// calls `setsid` for itself, so it leaves the leader's group while staying
    /// its descendant by parent link. macOS ships no `setsid(1)`, hence python.
    private func spawnLeaderWithEscapee() throws -> pid_t {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        let escapee = "/usr/bin/python3 -c 'import os, time; os.setsid(); time.sleep(30)'"
        let args = ["/bin/sh", "-c", "\(escapee) & wait"]
        var pid: pid_t = 0
        let spawned = args.withCStringArray { argv in
            posix_spawn(&pid, "/bin/sh", nil, &attr, argv, nil)
        }
        try #require(spawned == 0, "posix_spawn failed with \(spawned)")
        try #require(pid > 0)
        return pid
    }

    /// A child in the runner's group that forks a grandchild — the `.single`
    /// shape where the descendant is invisible to the target query.
    private func spawnChildWithGrandchildInOurGroup() throws -> pid_t {
        let args = ["/bin/sh", "-c", "sleep 30 & wait"]
        var pid: pid_t = 0
        let spawned = args.withCStringArray { argv in
            posix_spawn(&pid, "/bin/sh", nil, nil, argv, nil)
        }
        try #require(spawned == 0, "posix_spawn failed with \(spawned)")
        try #require(pid > 0)
        return pid
    }

    private func requirePython3() throws {
        try #require(
            FileManager.default.isExecutableFile(atPath: "/usr/bin/python3"),
            "/usr/bin/python3 is required to produce a setsid escapee"
        )
    }

    /// Kills the group *and* anything tracked, so an escapee can't outlive the
    /// test as a 30-second stray.
    private func cleanUp(leader: pid_t, tracked: Set<ProcessGroupTerminator.TrackedProcess>) {
        ProcessGroupTerminator.signalAll(leader: leader, tracked: tracked, signal: SIGKILL)
        var status: Int32 = 0
        waitpid(leader, &status, WNOHANG)
    }

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

    /// `posix_spawn`s `sleep 30` *without* `POSIX_SPAWN_SETSID`, so the child
    /// stays in the test runner's process group and is therefore not its own
    /// group leader — the shape that resolves to `.single`.
    private func spawnChildInOurGroup() throws -> pid_t {
        let args = ["/bin/sh", "-c", "sleep 30"]
        var pid: pid_t = 0
        let spawned = args.withCStringArray { argv in
            posix_spawn(&pid, "/bin/sh", nil, nil, argv, nil)
        }
        try #require(spawned == 0, "posix_spawn failed with \(spawned)")
        try #require(pid > 0)
        return pid
    }

    /// A pid that is valid but genuinely not in use. Probed rather than
    /// guessed: `ESRCH` from `kill(pid, 0)` is the only thing that actually
    /// says "no such process" (`EPERM` means it exists and we may not signal
    /// it), and pids are handed out well below the 99999 ceiling.
    private func unusedPid() throws -> pid_t {
        for candidate in stride(from: pid_t(99_998), through: pid_t(50_000), by: -1)
        where kill(candidate, 0) == -1 && errno == ESRCH {
            return candidate
        }
        Issue.record("no unused pid found in the probed range")
        throw ProbeError.noUnusedPid
    }

    private enum ProbeError: Error {
        case noUnusedPid
    }

    private func reap(_ pid: pid_t) {
        kill(pid, SIGKILL)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
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
