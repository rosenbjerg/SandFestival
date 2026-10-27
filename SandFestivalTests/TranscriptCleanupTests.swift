import Testing
@testable import SandFestival

@Suite("TranscriptCleanup")
struct TranscriptCleanupTests {

    @Test("automatic prefers the on-device model")
    func automaticPrefersOnDevice() {
        #expect(TranscriptCleanup.automatic.source(onDeviceAvailable: true, agentModelAvailable: true) == .onDevice)
    }

    @Test("automatic falls back to the agent's model when on-device is unavailable")
    func automaticFallsBackToAgent() {
        #expect(TranscriptCleanup.automatic.source(onDeviceAvailable: false, agentModelAvailable: true) == .agentModel)
    }

    @Test("automatic cleans nothing when neither model is available")
    func automaticWithNothing() {
        #expect(TranscriptCleanup.automatic.source(onDeviceAvailable: false, agentModelAvailable: false) == nil)
    }

    @Test("explicit choices never substitute the other model")
    func explicitChoicesDontSubstitute() {
        #expect(TranscriptCleanup.onDevice.source(onDeviceAvailable: false, agentModelAvailable: true) == nil)
        #expect(TranscriptCleanup.agentModel.source(onDeviceAvailable: true, agentModelAvailable: false) == nil)
        #expect(TranscriptCleanup.agentModel.source(onDeviceAvailable: true, agentModelAvailable: true) == .agentModel)
    }

    @Test("off never cleans")
    func offNeverCleans() {
        #expect(TranscriptCleanup.off.source(onDeviceAvailable: true, agentModelAvailable: true) == nil)
    }
}
