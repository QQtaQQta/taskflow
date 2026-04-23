import Fluent
import Vapor

enum UserRepository {
    static func findActiveByEmail(_ email: String, on db: Database) async throws -> User? {
        try await User.query(on: db)
            .excludingDeleted()
            .filter(\.$email == email)
            .with(\.$role)
            .first()
    }

    static func findActive(_ id: UUID, on db: Database) async throws -> User? {
        try await User.query(on: db)
            .excludingDeleted()
            .filter(\.$id == id)
            .first()
    }

    static func findActiveWithRole(_ id: UUID, on db: Database) async throws -> User? {
        try await User.query(on: db)
            .excludingDeleted()
            .filter(\.$id == id)
            .with(\.$role)
            .first()
    }
}
