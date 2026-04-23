import Foundation
import Vapor

enum RetryPolicy {
    static func withRetry<T>(
        maxAttempts: Int = 3,
        initialDelayMs: UInt64 = 50,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 1
        var delayMs = initialDelayMs
        while true {
            do {
                return try await operation()
            } catch {
                if attempt >= maxAttempts || !isTransient(error) {
                    throw error
                }
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                delayMs *= 2
                attempt += 1
            }
        }
    }

    static func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw Abort(.requestTimeout, reason: "Operation timeout")
            }
            guard let first = try await group.next() else {
                throw Abort(.internalServerError)
            }
            group.cancelAll()
            return first
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        let text = String(reflecting: error).lowercased()
        return text.contains("timeout") || text.contains("tempor") || text.contains("connection reset") || text.contains("could not connect")
    }
}
