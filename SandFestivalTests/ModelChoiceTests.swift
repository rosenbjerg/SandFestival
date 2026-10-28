import Testing
@testable import SandFestival

@Suite("ModelChoice")
struct ModelChoiceTests {

    @Test("automatic prefers the on-device model")
    func automaticPrefersOnDevice() {
        #expect(ModelChoice.automatic.source(onDeviceAvailable: true, agentModelAvailable: true) == .onDevice)
    }

    @Test("automatic falls back to the agent's model when on-device is unavailable")
    func automaticFallsBackToAgent() {
        #expect(ModelChoice.automatic.source(onDeviceAvailable: false, agentModelAvailable: true) == .agentModel)
    }

    @Test("automatic cleans nothing when neither model is available")
    func automaticWithNothing() {
        #expect(ModelChoice.automatic.source(onDeviceAvailable: false, agentModelAvailable: false) == nil)
    }

    @Test("explicit choices never substitute the other model")
    func explicitChoicesDontSubstitute() {
        #expect(ModelChoice.onDevice.source(onDeviceAvailable: false, agentModelAvailable: true) == nil)
        #expect(ModelChoice.agentModel.source(onDeviceAvailable: true, agentModelAvailable: false) == nil)
        #expect(ModelChoice.agentModel.source(onDeviceAvailable: true, agentModelAvailable: true) == .agentModel)
    }

    @Test("off never cleans")
    func offNeverCleans() {
        #expect(ModelChoice.off.source(onDeviceAvailable: true, agentModelAvailable: true) == nil)
    }
}
