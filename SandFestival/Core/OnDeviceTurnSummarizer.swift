import Foundation
import FoundationModels

nonisolated struct OnDeviceTurnSummarizer: TurnSummarizer {
    var timeout: Duration { .seconds(5) }

    func summarize(_ message: String) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else { throw TurnSummarizerError.unavailable }
        let session = LanguageModelSession(model: model, instructions: TurnSummary.instructions)
        let response = try await session.respond(
            to: TurnSummary.prompt(message: message),
            generating: GeneratedTurnSummary.self,
            options: GenerationOptions(
                sampling: .greedy,
                maximumResponseTokens: TurnSummary.maximumResponseTokens
            )
        )
        return response.content.status
    }
}

@Generable
nonisolated struct GeneratedTurnSummary {
    @Guide(description: "A status line of at most 10 words, in your own words, following the rules and examples.")
    var status: String
}
