import Foundation
import Observation

extension ModelChoice {
    func makeRefiner(
        agent: AgentTranscriptRefinement?,
        launcher: @escaping AgentLauncher
    ) -> (any TranscriptRefiner)? {
        switch source(onDeviceAvailable: OnDeviceModel.isAvailable, agentModelAvailable: agent != nil) {
        case .onDevice: OnDeviceTranscriptRefiner()
        case .agentModel: agent?.makeRefiner(launcher)
        case nil: nil
        }
    }
}

enum DictationSubmit: Equatable {
    case off
    case whenIdle
    case whenIdleOrWorking

    func allows(_ state: SessionState) -> Bool {
        switch (self, state) {
        case (.whenIdle, .idle), (.whenIdleOrWorking, .idle), (.whenIdleOrWorking, .working): true
        default: false
        }
    }
}

@MainActor
@Observable
final class DictationPreferences {
    var cleanup: ModelChoice {
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

    var submitsAfterPaste: Bool {
        didSet {
            guard submitsAfterPaste != oldValue else { return }
            defaults.set(submitsAfterPaste, forKey: Keys.submitsAfterPaste)
        }
    }

    var submitsWhileWorking: Bool {
        didSet {
            guard submitsWhileWorking != oldValue else { return }
            defaults.set(submitsWhileWorking, forKey: Keys.submitsWhileWorking)
        }
    }

    var submit: DictationSubmit {
        guard submitsAfterPaste else { return .off }
        return submitsWhileWorking ? .whenIdleOrWorking : .whenIdle
    }

    var endpointConfiguration: DictationEndpointer.Configuration {
        DictationEndpointer.Configuration(silenceTimeout: silenceTimeout)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.cleanup: ModelChoice.automatic.rawValue,
            Keys.silenceTimeout: DictationEndpointer.Configuration.defaultSilenceTimeout,
        ])
        let stored = defaults.string(forKey: Keys.cleanup) ?? ""
        self.cleanup = ModelChoice(rawValue: stored) ?? .automatic
        let range = DictationEndpointer.Configuration.silenceTimeoutRange
        self.silenceTimeout = min(max(defaults.double(forKey: Keys.silenceTimeout), range.lowerBound), range.upperBound)
        self.submitsAfterPaste = defaults.bool(forKey: Keys.submitsAfterPaste)
        self.submitsWhileWorking = defaults.bool(forKey: Keys.submitsWhileWorking)
    }

    private enum Keys {
        static let cleanup = "dictation.cleanup"
        static let silenceTimeout = "dictation.silenceTimeout"
        static let submitsAfterPaste = "dictation.submitsAfterPaste"
        static let submitsWhileWorking = "dictation.submitsWhileWorking"
    }
}
