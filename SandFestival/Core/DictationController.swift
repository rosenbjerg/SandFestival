import Foundation
import Observation

@MainActor
protocol DictationTarget: AnyObject {
    var id: Project.ID { get }
    var isReadyForDictation: Bool { get }
    var canReceiveText: Bool { get }
    func canSubmitDictation(_ submit: DictationSubmit) -> Bool
    func insertDictatedText(_ text: String, submit: DictationSubmit)
    func dictationVocabulary() async -> [String]
}

@MainActor
@Observable
final class DictationController {
    enum Phase: Equatable {
        case idle
        case preparing(progress: Double?)
        case listening
        case finishing
        case refining
        case held(String)
        case failed(message: String, offersPrivacySettings: Bool)

        var isBusy: Bool {
            switch self {
            case .preparing, .listening, .finishing, .refining: true
            case .idle, .held, .failed: false
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = DictationTranscript()
    @ObservationIgnored private(set) var endpointer = DictationEndpointer()
    private(set) var inputLevel: Double = 0
    private(set) var targetID: Project.ID?

    @ObservationIgnored private weak var target: (any DictationTarget)?
    @ObservationIgnored private var engine: (any SpeechEngine)?
    @ObservationIgnored private(set) var runTask: Task<Void, Never>?
    @ObservationIgnored private let makeEngine: () -> any SpeechEngine
    @ObservationIgnored var refinerProvider: (() -> (any TranscriptRefiner)?)?
    @ObservationIgnored var endpointConfigurationProvider: (() -> DictationEndpointer.Configuration)?
    @ObservationIgnored var submitProvider: (() -> DictationSubmit)?
    @ObservationIgnored private var refiner: (any TranscriptRefiner)?
    @ObservationIgnored private var vocabularyTask: Task<[String], Never>?
    @ObservationIgnored private var refineTask: Task<String?, Never>?
    @ObservationIgnored private var lastAudioAt = ContinuousClock.now
    @ObservationIgnored private var stallWatch: Task<Void, Never>?

    init(makeEngine: (() -> any SpeechEngine)? = nil) {
        self.makeEngine = makeEngine ?? { SpeechAnalyzerEngine() }
    }

    func isActive(for id: Project.ID) -> Bool {
        targetID == id && phase.isBusy
    }

    func canToggle(for id: Project.ID) -> Bool {
        switch phase {
        case .idle, .failed: true
        case .held: target == nil
        case .preparing, .listening, .refining: targetID == id
        case .finishing: false
        }
    }

    var isHoldingText: Bool {
        guard case .held = phase else { return false }
        return target != nil
    }

    var targetCanReceiveText: Bool {
        target?.canReceiveText == true
    }

    func toggle(for target: any DictationTarget) {
        guard canToggle(for: target.id) else { return }
        switch phase {
        case .listening:
            finish()
        case .preparing:
            discard()
        case .refining:
            skipRefinement()
        case .finishing:
            break
        case .idle, .held, .failed:
            start(target)
        }
    }

    func finish() {
        guard phase == .listening, let engine else { return }
        phase = .finishing
        Task { await engine.finish() }
    }

    func skipRefinement() {
        refineTask?.cancel()
    }

    func discard() {
        runTask?.cancel()
        runTask = nil
        refineTask?.cancel()
        vocabularyTask?.cancel()
        if let engine {
            Task { await engine.cancel() }
        }
        reset()
    }

    func pasteHeldText() {
        guard case .held(let text) = phase, let target, target.canReceiveText else { return }
        target.insertDictatedText(Self.insertion(for: text), submit: .off)
        reset()
    }

    private func start(_ target: any DictationTarget) {
        discard()
        self.target = target
        targetID = target.id
        phase = .preparing(progress: nil)
        endpointer = DictationEndpointer(configuration: endpointConfigurationProvider?() ?? .init())
        refiner = refinerProvider?()
        if refiner != nil {
            vocabularyTask = Task { await target.dictationVocabulary() }
        }
        let engine = makeEngine()
        self.engine = engine
        runTask = Task { await run(engine) }
    }

    private func run(_ engine: any SpeechEngine) async {
        do {
            try await engine.prepare { progress in
                Task { @MainActor in self.reportProgress(progress) }
            }
            try Task.checkCancellation()
            let events = try await engine.start()
            if Task.isCancelled {
                // discard() may have cancelled the engine before start() had anything to stop.
                await engine.cancel()
                return
            }
            phase = .listening
            lastAudioAt = .now
            stallWatch = watchForStalledAudio()
            for try await event in events {
                apply(event)
            }
            try Task.checkCancellation()
            let text = await refinedText(transcript.text)
            try Task.checkCancellation()
            deliver(text)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            await engine.cancel()
            fail(error)
        }
    }

    private func reportProgress(_ progress: Double) {
        guard case .preparing = phase else { return }
        phase = .preparing(progress: progress)
    }

    private func apply(_ event: SpeechEngineEvent) {
        guard phase == .listening || phase == .finishing else { return }
        guard target != nil else {
            discard()
            return
        }
        switch event {
        case .audioAdvanced(let time):
            lastAudioAt = .now
            endpointer.audioAdvanced(to: time)
        case .inputLevel(let rms):
            inputLevel = MicrophoneLevel.smoothed(previous: inputLevel, next: MicrophoneLevel.normalized(rms: rms))
        case .result(let text, let isFinal, let rangeEnd):
            let wordsBefore = transcript.words
            transcript.apply(text: text, isFinal: isFinal)
            let finalHasWords = isFinal && !DictationTranscript.words(in: text).isEmpty
            if transcript.words != wordsBefore || finalHasWords {
                endpointer.speechObserved(through: rangeEnd)
            }
        }
        guard phase == .listening else { return }
        switch endpointer.decision {
        case .listening:
            break
        case .finish:
            finish()
        case .discardNoSpeech:
            discard()
        }
    }

    private func refinedText(_ text: String) async -> String {
        guard !text.isEmpty, let refiner else { return text }
        phase = .refining
        let vocabularyTask = vocabularyTask
        let task = Task {
            await Self.refine(text, with: refiner, vocabulary: await vocabularyTask?.value ?? [])
        }
        refineTask = task
        let refined = await task.value
        refineTask = nil
        return refined.flatMap { TranscriptRefinement.accept($0, original: text) } ?? text
    }

    private func watchForStalledAudio() -> Task<Void, Never> {
        let timeout = Duration.seconds(endpointer.configuration.audioStallTimeout)
        return Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: timeout / 4)
                guard let self, self.phase == .listening else { return }
                if self.lastAudioAt.duration(to: .now) >= timeout {
                    self.finish()
                    return
                }
            }
        }
    }

    private nonisolated static func refine(
        _ text: String,
        with refiner: any TranscriptRefiner,
        vocabulary: [String]
    ) async -> String? {
        await Deadline.value(within: refiner.timeout) {
            try await refiner.refine(text, vocabulary: vocabulary)
        }
    }

    private func deliver(_ text: String) {
        engine = nil
        runTask = nil
        guard !text.isEmpty, let target else {
            reset()
            return
        }
        guard target.isReadyForDictation else {
            phase = .held(text)
            return
        }
        let submit = submitProvider?() ?? .off
        target.insertDictatedText(Self.insertion(for: text), submit: target.canSubmitDictation(submit) ? submit : .off)
        reset()
    }

    private func fail(_ error: any Error) {
        engine = nil
        runTask = nil
        phase = .failed(
            message: error.localizedDescription,
            offersPrivacySettings: (error as? DictationError) == .microphoneDenied
        )
    }

    private func reset() {
        stallWatch?.cancel()
        stallWatch = nil
        engine = nil
        refiner = nil
        vocabularyTask = nil
        refineTask = nil
        target = nil
        targetID = nil
        transcript = DictationTranscript()
        endpointer = DictationEndpointer()
        inputLevel = 0
        phase = .idle
    }

    private static func insertion(for text: String) -> String {
        DictationTranscript.prompt(from: text) + " "
    }
}
