import Foundation
import Testing
@testable import SandFestival

@Suite("GitStatus porcelain v2 parsing")
struct GitStatusTests {

    @Test("a tracking branch reports its divergence and every changed entry")
    func parsesFullStatus() {
        let output = """
        # branch.oid 8fcd9a1c2b3d4e5f60718293a4b5c6d7e8f90123
        # branch.head feature/login
        # branch.upstream origin/feature/login
        # branch.ab +2 -3
        1 .M N... 100644 100644 100644 aaaa bbbb Sources/App.swift
        1 M. N... 100644 100644 100644 cccc dddd README.md
        2 R. N... 100644 100644 100644 eeee ffff R100 new.txt\told.txt
        u UU N... 100644 100644 100644 100644 1111 2222 3333 conflict.txt
        ? scratch.log
        """
        let status = GitStatus.parse(porcelainV2: output)
        #expect(status.branch == "feature/login")
        #expect(status.comparisonRef == "origin/feature/login")
        #expect(status.ahead == 2)
        #expect(status.behind == 3)
        #expect(status.changedFiles == 5)
        #expect(status.isClean == false)
    }

    @Test("a branch with no upstream reports no divergence rather than zero-of-something")
    func parsesBranchWithoutUpstream() {
        let output = """
        # branch.oid 8fcd9a1c2b3d4e5f60718293a4b5c6d7e8f90123
        # branch.head feature/fresh
        """
        let status = GitStatus.parse(porcelainV2: output)
        #expect(status.branch == "feature/fresh")
        #expect(status.comparisonRef == nil)
        #expect(status.ahead == 0)
        #expect(status.behind == 0)
    }

    @Test("a detached head parses as no branch, not a branch called (detached)")
    func parsesDetachedHead() {
        let output = """
        # branch.oid 8fcd9a1c2b3d4e5f60718293a4b5c6d7e8f90123
        # branch.head (detached)
        """
        #expect(GitStatus.parse(porcelainV2: output).branch == nil)
    }

    @Test("a clean tree counts nothing")
    func parsesCleanTree() {
        let output = """
        # branch.oid 8fcd9a1c2b3d4e5f60718293a4b5c6d7e8f90123
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -0
        """
        let status = GitStatus.parse(porcelainV2: output)
        #expect(status.changedFiles == 0)
        #expect(status.isClean)
        #expect(status.comparisonRef == "origin/main")
    }

    @Test("header lines are never mistaken for changed entries")
    func headersAreNotEntries() {
        let output = """
        # branch.oid 8fcd9a1c2b3d4e5f60718293a4b5c6d7e8f90123
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +1 -0
        """
        #expect(GitStatus.parse(porcelainV2: output).changedFiles == 0)
    }

    @Test("empty output parses to an empty status rather than failing")
    func parsesEmptyOutput() {
        #expect(GitStatus.parse(porcelainV2: "") == GitStatus())
    }
}
