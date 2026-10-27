import Foundation

nonisolated struct DictationEndpointer: Equatable {
    struct Configuration: Equatable {
        static let defaultSilenceTimeout: TimeInterval = 2.5
        static let silenceTimeoutRange: ClosedRange<TimeInterval> = 1.5...5

        var silenceTimeout: TimeInterval = defaultSilenceTimeout
        var noSpeechTimeout: TimeInterval = 8
        var maximumDuration: TimeInterval = 180
        var audioStallTimeout: TimeInterval = 2
    }

    enum Decision: Equatable {
        case listening
        case finish
        case discardNoSpeech
    }

    let configuration: Configuration
    private(set) var audioTime: TimeInterval = 0
    private(set) var lastSpeech: TimeInterval?

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func audioAdvanced(to time: TimeInterval) {
        audioTime = max(audioTime, time)
    }

    mutating func speechObserved(through time: TimeInterval) {
        lastSpeech = max(lastSpeech ?? time, time)
    }

    var decision: Decision {
        if audioTime >= configuration.maximumDuration {
            return .finish
        }
        guard let lastSpeech else {
            return audioTime >= configuration.noSpeechTimeout ? .discardNoSpeech : .listening
        }
        return audioTime - lastSpeech >= configuration.silenceTimeout ? .finish : .listening
    }
}
