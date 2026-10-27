import Foundation
import FoundationModels

nonisolated struct OnDeviceTranscriptRefiner: TranscriptRefiner {
    var timeout: Duration { .seconds(5) }

    func refine(_ transcript: String, vocabulary: [String]) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { throw TranscriptRefinerError.unavailable }
        let session = LanguageModelSession(model: model, instructions: TranscriptRefinement.instructions)
        let response = try await session.respond(
            to: TranscriptRefinement.prompt(transcript: transcript, vocabulary: vocabulary),
            generating: CleanedTranscript.self,
            options: GenerationOptions(
                sampling: .greedy,
                maximumResponseTokens: TranscriptRefinement.maximumResponseTokens(for: transcript)
            )
        )
        return response.content.text
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            String(localized: "preferences.dictation.on_device.unavailable.device")
        case .unavailable(.appleIntelligenceNotEnabled):
            String(localized: "preferences.dictation.on_device.unavailable.disabled")
        case .unavailable(.modelNotReady):
            String(localized: "preferences.dictation.on_device.unavailable.not_ready")
        case .unavailable:
            String(localized: "preferences.dictation.on_device.unavailable.other")
        }
    }
}

@Generable
nonisolated struct CleanedTranscript {
    @Guide(description: "The dictated text with misheard words, filler words and false starts fixed. Same meaning, same speaker, same language.")
    var text: String
}
