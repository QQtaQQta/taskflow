import XCTVapor
import Fluent
import FluentSQLiteDriver
@testable import Application
import JWT
import Vapor

enum TestAppFactory {
    static func make() async throws -> Application {
        let app = try await Application.make(.testing)
        app.passwords.use(.bcrypt)
        app.jwt.signers.use(.hs256(key: "test-secret-key-1234567890123456"), kid: "default")
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.databases.default(to: .sqlite)
        app.migrations.add(CreateSchema())
        app.migrations.add(SeedRBACAndDemo())
        try await app.autoMigrate()
        try await routes(app)
        return app
    }
}

extension XCTHTTPResponse {
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: body)
    }
}

struct TestEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let meta: TestMeta?
    let error: TestError?
}

struct TestMeta: Decodable {
    let page: Int?
    let perPage: Int?
    let total: Int?
}

struct TestError: Decodable {
    let code: String
    let message: String
    let details: [String]
}
