import AVFoundation
import Foundation
import Speech

nonisolated enum SpeechEngineEvent: Equatable, Sendable {
    case audioAdvanced(to: TimeInterval)
    case result(text: String, isFinal: Bool, rangeEnd: TimeInterval)
}

nonisolated enum DictationError: LocalizedError, Equatable {
    case microphoneDenied
    case noMicrophone
    case unsupportedLanguage(String)
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            String(localized: "dictation.error.microphone_denied")
        case .noMicrophone:
            String(localized: "dictation.error.no_microphone")
        case .unsupportedLanguage(let identifier):
            String(format: String(localized: "dictation.error.unsupported_language"), identifier)
        case .audioFormatUnavailable:
            String(localized: "dictation.error.audio_format")
        }
    }
}

nonisolated protocol SpeechEngine: AnyObject, Sendable {
    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws
    func start() async throws -> AsyncThrowingStream<SpeechEngineEvent, any Error>
    func finish() async
    func cancel() async
}

actor SpeechAnalyzerEngine: SpeechEngine {
    private let locale: Locale
    private var transcriber: Transcriber?
    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var eventContinuation: AsyncThrowingStream<SpeechEngineEvent, any Error>.Continuation?
    private var resultsTask: Task<Void, Never>?

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await Self.requireMicrophoneAccess()
        let transcriber = try await Transcriber.make(for: locale)
        let modules = [transcriber.module]
        if await AssetInventory.status(forModules: modules) < .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            let progress = request.progress
            let reporter = Task {
                while !Task.isCancelled {
                    onProgress(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { reporter.cancel() }
            try await request.downloadAndInstall()
        }
        self.transcriber = transcriber
    }

    func start() async throws -> AsyncThrowingStream<SpeechEngineEvent, any Error> {
        guard let transcriber else { throw CancellationError() }
        let modules = [transcriber.module]
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let micFormat = inputNode.outputFormat(forBus: 0)
        guard micFormat.channelCount > 0, micFormat.sampleRate > 0 else {
            throw DictationError.noMicrophone
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                  compatibleWith: modules,
                  considering: micFormat
              ),
              let converter = AnalyzerInputConverter(from: micFormat, to: analyzerFormat)
        else { throw DictationError.audioFormatUnavailable }

        let analyzer = SpeechAnalyzer(
            modules: modules,
            options: .init(priority: .userInitiated, modelRetention: .lingering)
        )
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let (events, eventContinuation) = AsyncThrowingStream<SpeechEngineEvent, any Error>.makeStream()
        try await analyzer.start(inputSequence: inputStream)

        Self.installTap(
            on: inputNode,
            format: micFormat,
            converter: converter,
            input: inputContinuation,
            events: eventContinuation
        )
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            inputContinuation.finish()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        self.audioEngine = audioEngine
        self.analyzer = analyzer
        self.inputContinuation = inputContinuation
        self.eventContinuation = eventContinuation
        resultsTask = Task {
            do {
                try await transcriber.forwardResults(to: eventContinuation)
                eventContinuation.finish()
            } catch {
                eventContinuation.finish(throwing: error)
            }
        }
        return events
    }

    func finish() async {
        stopAudio()
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            await analyzer?.cancelAndFinishNow()
        }
        await resultsTask?.value
        eventContinuation?.finish()
        clear()
    }

    func cancel() async {
        stopAudio()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        eventContinuation?.finish()
        clear()
    }

    private func stopAudio() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        inputContinuation?.finish()
    }

    private func clear() {
        audioEngine = nil
        analyzer = nil
        inputContinuation = nil
        eventContinuation = nil
        resultsTask = nil
    }

    private static func requireMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw DictationError.microphoneDenied
            }
        default:
            throw DictationError.microphoneDenied
        }
    }

    // Static so the tap block isn't actor-isolated: Core Audio calls it on its real-time thread.
    private static func installTap(
        on node: AVAudioInputNode,
        format: AVAudioFormat,
        converter: AnalyzerInputConverter,
        input: AsyncStream<AnalyzerInput>.Continuation,
        events: AsyncThrowingStream<SpeechEngineEvent, any Error>.Continuation
    ) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let (analyzerInput, audioTime) = converter.convert(buffer) else { return }
            input.yield(analyzerInput)
            events.yield(.audioAdvanced(to: audioTime))
        }
    }
}

private nonisolated enum Transcriber: Sendable {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    static func make(for locale: Locale) async throws -> Transcriber {
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speech(SpeechTranscriber(locale: supported, preset: .progressiveTranscription))
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictation(DictationTranscriber(locale: supported, preset: .progressiveLongDictation))
        }
        throw DictationError.unsupportedLanguage(locale.identifier)
    }

    var module: any SpeechModule {
        switch self {
        case .speech(let transcriber): transcriber
        case .dictation(let transcriber): transcriber
        }
    }

    func forwardResults(
        to continuation: AsyncThrowingStream<SpeechEngineEvent, any Error>.Continuation
    ) async throws {
        switch self {
        case .speech(let transcriber):
            for try await result in transcriber.results {
                continuation.yield(Self.event(text: result.text, result: result))
            }
        case .dictation(let transcriber):
            for try await result in transcriber.results {
                continuation.yield(Self.event(text: result.text, result: result))
            }
        }
    }

    private static func event(text: AttributedString, result: some SpeechModuleResult) -> SpeechEngineEvent {
        .result(text: String(text.characters), isFinal: result.isFinal, rangeEnd: result.range.end.seconds)
    }
}

// The tap block is its only caller, and Core Audio invokes that block serially.
private nonisolated final class AnalyzerInputConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private var framesEmitted: AVAudioFramePosition = 0

    init?(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        self.converter = converter
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> (AnalyzerInput, TimeInterval)? {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        // The converter calls the input block synchronously, inside convert(to:error:withInputFrom:).
        nonisolated(unsafe) let source = buffer
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard !consumed else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        framesEmitted += AVAudioFramePosition(output.frameLength)
        return (AnalyzerInput(buffer: output), Double(framesEmitted) / outputFormat.sampleRate)
    }
}
