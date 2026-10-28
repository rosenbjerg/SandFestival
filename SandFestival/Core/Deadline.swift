import Foundation

nonisolated enum Deadline {
    static func value<T: Sendable>(
        within timeout: Duration,
        of work: @escaping @Sendable () async throws -> T
    ) async -> T? {
        // Not a task group: it would wait out work that ignores cancellation, defeating the deadline.
        let (outcomes, continuation) = AsyncStream<T?>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let task = Task { continuation.yield(try? await work()) }
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            continuation.yield(nil)
        }
        defer {
            task.cancel()
            deadline.cancel()
        }
        for await outcome in outcomes {
            return outcome
        }
        return nil
    }
}
