import Fluent
import Vapor

enum TaskRepository {
    static func findVisible(_ id: UUID, on db: Database) async throws -> WorkTask? {
        guard let t = try await WorkTask.find(id, on: db), !t.isArchived else { return nil }
        return t
    }
}
