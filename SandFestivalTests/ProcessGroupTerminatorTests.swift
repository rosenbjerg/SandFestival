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
        #expect(ProcessGroupTerminator.target(leader: 4242, processGroup: 17) == .single(4242))
    }

    @Test("A failed getpgid lookup degrades to a single-pid signal")
    func singleTargetWhenLookupFailed() {
        #expect(ProcessGroupTerminator.target(leader: 4242, processGroup: nil) == .single(4242))
    }

    @Test("Non-positive pids resolve to no target at all")
    func noTargetForInvalidPid() {
        #expect(ProcessGroupTerminator.target(leader: 0, processGroup: 0) == nil)
        #expect(ProcessGroupTerminator.target(leader: -1, processGroup: -1) == nil)
        #expect(ProcessGroupTerminator.signalGroup(leader: 0, signal: SIGKILL) == false)
    }

    // MARK: - Real process group (integration)

    @Test("liveMembers sees a leader and its child; the group kill takes both")
    func killsWholeGroupIncludingGrandchild() async throws {
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
        var status: Int32 = 0
        waitpid(leader, &status, WNOHANG)
    }

    @Test("liveMembers is empty for a pid that isn't running")
    func noMembersForUnknownGroup() throws {
        #expect(ProcessGroupTerminator.liveMembers(leader: 0).isEmpty)
        #expect(ProcessGroupTerminator.liveMembers(leader: try unusedPid()).isEmpty)
    }

    @Test("A live pid that isn't its own group leader still reports as running")
    func nonLeaderIsReportedLive() async throws {
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

        // kill(_, 0), not liveMembers: the sweep is the thing under test, so
        // it cannot also be the evidence.
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

        let absent = try unusedPid()
        #expect(ProcessGroupTerminator.liveMembers(leader: absent, tracked: [stale]).isEmpty)
        #expect(ProcessGroupTerminator.liveMembers(leader: absent, tracked: [real]) == [child])
    }

    // MARK: - Helpers

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

    // python because macOS ships no setsid(1).
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

    private func cleanUp(leader: pid_t, tracked: Set<ProcessGroupTerminator.TrackedProcess>) {
        ProcessGroupTerminator.signalAll(leader: leader, tracked: tracked, signal: SIGKILL)
        var status: Int32 = 0
        waitpid(leader, &status, WNOHANG)
    }

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

    // ESRCH only: EPERM from kill(pid, 0) means the process exists.
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

    // Every liveness assertion must poll: the process table lags the SIGKILL.
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
    func withCStringArray<R>(_ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
        var pointers: [UnsafeMutablePointer<CChar>?] = map { strdup($0) }
        pointers.append(nil)
        defer { pointers.forEach { free($0) } }
        return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }
}
