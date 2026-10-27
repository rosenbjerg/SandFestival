import Foundation
import Testing
@testable import SandFestival

@Suite("MicrophoneLevel")
struct MicrophoneLevelTests {

    @Test("silence and the noise floor read as zero, full scale as one")
    func endpoints() {
        #expect(MicrophoneLevel.normalized(rms: 0) == 0)
        #expect(MicrophoneLevel.normalized(rms: 0.0001) == 0)
        #expect(MicrophoneLevel.normalized(rms: 1) == 1)
        #expect(MicrophoneLevel.normalized(rms: 2) == 1)
    }

    @Test("the scale is linear in decibels")
    func linearInDecibels() {
        let halfway = Float(pow(10, -27.5 / 20))

        #expect(abs(MicrophoneLevel.normalized(rms: halfway) - 0.5) < 0.001)
    }

    @Test("rises immediately and falls gradually")
    func attackAndRelease() {
        #expect(MicrophoneLevel.smoothed(previous: 0.2, next: 0.9) == 0.9)
        #expect(abs(MicrophoneLevel.smoothed(previous: 1, next: 0) - 0.6) < 0.0001)
    }
}
