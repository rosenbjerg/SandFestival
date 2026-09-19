import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("SessionManager attention navigation")
struct SessionManagerAttentionNavigationTests {
    let a = UUID()
    let b = UUID()
    let c = UUID()

    @Test("advances to the next attention project and wraps")
    func forwardWraps() {
        #expect(SessionManager.nextAttentionProjectID(in: [a, b, c], after: a) == b)
        #expect(SessionManager.nextAttentionProjectID(in: [a, b, c], after: c) == a)
    }

    @Test("goes back to the previous attention project and wraps")
    func backwardWraps() {
        #expect(SessionManager.nextAttentionProjectID(in: [a, b, c], after: b, forward: false) == a)
        #expect(SessionManager.nextAttentionProjectID(in: [a, b, c], after: a, forward: false) == c)
    }

    @Test("a selection outside the attention set starts from the nearest end")
    func outsideSelectionStartsAtEnd() {
        let other = UUID()
        #expect(SessionManager.nextAttentionProjectID(in: [a, b], after: other) == a)
        #expect(SessionManager.nextAttentionProjectID(in: [a, b], after: nil) == a)
        #expect(SessionManager.nextAttentionProjectID(in: [a, b], after: other, forward: false) == b)
    }

    @Test("a single attention project cycles to itself")
    func singleCyclesToSelf() {
        #expect(SessionManager.nextAttentionProjectID(in: [a], after: a) == a)
        #expect(SessionManager.nextAttentionProjectID(in: [a], after: a, forward: false) == a)
    }

    @Test("nothing to focus when no project needs attention")
    func emptyIsNil() {
        #expect(SessionManager.nextAttentionProjectID(in: [], after: a) == nil)
        #expect(SessionManager.nextAttentionProjectID(in: [], after: nil) == nil)
    }
}
