import Testing
@testable import SandFestival

@Suite("Project.abbreviatingHome")
struct ProjectDisplayPathTests {

    @Test("a path inside home collapses to ~")
    func insideHome() {
        #expect(Project.abbreviatingHome("/Users/ada/Code/app", home: "/Users/ada") == "~/Code/app")
    }

    @Test("the home directory itself is just ~")
    func exactlyHome() {
        #expect(Project.abbreviatingHome("/Users/ada", home: "/Users/ada") == "~")
    }

    @Test("a trailing slash on home doesn't leak into the result")
    func homeWithTrailingSlash() {
        #expect(Project.abbreviatingHome("/Users/ada/Code", home: "/Users/ada/") == "~/Code")
    }

    @Test("a sibling whose name merely starts with home is left alone")
    func siblingPrefix() {
        #expect(Project.abbreviatingHome("/Users/adamant/Code", home: "/Users/ada") == "/Users/adamant/Code")
    }

    @Test("a path outside home is left alone")
    func outsideHome() {
        #expect(Project.abbreviatingHome("/opt/src/app", home: "/Users/ada") == "/opt/src/app")
    }

    @Test("a root or empty home abbreviates nothing")
    func degenerateHome() {
        #expect(Project.abbreviatingHome("/opt/src", home: "/") == "/opt/src")
        #expect(Project.abbreviatingHome("/opt/src", home: "") == "/opt/src")
    }
}
