import Foundation

nonisolated enum MicrophoneLevel {
    static let floorDecibels: Float = -55

    static func normalized(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return Double(min(max((decibels - floorDecibels) / -floorDecibels, 0), 1))
    }

    static func smoothed(previous: Double, next: Double) -> Double {
        next >= previous ? next : previous * 0.6 + next * 0.4
    }
}
