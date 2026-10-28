import Foundation

nonisolated struct ClaudeTurnSummarizer: TurnSummarizer {
    let launcher: AgentLauncher

    var timeout: Duration { .seconds(15) }

    func summarize(_ message: String) async throws -> String {
        try await ClaudeOneShot.run(
            launcher: launcher,
            systemPrompt: TurnSummary.instructions,
            prompt: TurnSummary.prompt(message: message)
        )
    }
}
