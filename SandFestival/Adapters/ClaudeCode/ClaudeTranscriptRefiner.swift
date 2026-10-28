import Foundation

nonisolated struct ClaudeTranscriptRefiner: TranscriptRefiner {
    let launcher: AgentLauncher

    var timeout: Duration { .seconds(10) }

    func refine(_ transcript: String, vocabulary: [String]) async throws -> String {
        try await ClaudeOneShot.run(
            launcher: launcher,
            systemPrompt: TranscriptRefinement.instructions,
            prompt: TranscriptRefinement.prompt(transcript: transcript, vocabulary: vocabulary)
        )
    }
}
