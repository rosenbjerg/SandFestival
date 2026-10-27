import Foundation
import Observation

enum TranscriptCleanup: String, CaseIterable, Identifiable {
    case automatic
    case onDevice
    case agentModel
    case off

    enum Source: Equatable {
        case onDevice
        case agentModel
    }

    var id: String { rawValue }

    func source(onDeviceAvailable: Bool, agentModelAvailable: Bool) -> Source? {
        switch self {
        case .automatic:
            if onDeviceAvailable { return .onDevice }
            return agentModelAvailable ? .agentModel : nil
        case .onDevice:
            return onDeviceAvailable ? .onDevice : nil
        case .agentModel:
            return agentModelAvailable ? .agentModel : nil
        case .off:
            return nil
        }
    }

    func makeRefiner(agent: AgentTranscriptRefinement?) -> (any TranscriptRefiner)? {
        switch source(onDeviceAvailable: OnDeviceTranscriptRefiner.isAvailable, agentModelAvailable: agent != nil) {
        case .onDevice: OnDeviceTranscriptRefiner()
        case .agentModel: agent?.refiner
        case nil: nil
        }
    }
}

@MainActor
@Observable
final class DictationPreferences {
    var cleanup: TranscriptCleanup {
        didSet {
            guard cleanup != oldValue else { return }
            defaults.set(cleanup.rawValue, forKey: Keys.cleanup)
        }
    }

    var silenceTimeout: TimeInterval {
        didSet {
            guard silenceTimeout != oldValue else { return }
            defaults.set(silenceTimeout, forKey: Keys.silenceTimeout)
        }
    }

    var endpointConfiguration: DictationEndpointer.Configuration {
        DictationEndpointer.Configuration(silenceTimeout: silenceTimeout)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.cleanup: TranscriptCleanup.automatic.rawValue,
            Keys.silenceTimeout: DictationEndpointer.Configuration.defaultSilenceTimeout,
        ])
        let stored = defaults.string(forKey: Keys.cleanup) ?? ""
        self.cleanup = TranscriptCleanup(rawValue: stored) ?? .automatic
        let range = DictationEndpointer.Configuration.silenceTimeoutRange
        self.silenceTimeout = min(max(defaults.double(forKey: Keys.silenceTimeout), range.lowerBound), range.upperBound)
    }

    private enum Keys {
        static let cleanup = "dictation.cleanup"
        static let silenceTimeout = "dictation.silenceTimeout"
    }
}
