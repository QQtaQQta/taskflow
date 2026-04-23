import Fluent
import XCTVapor
import XCTest
@testable import Application

private struct LoginReq: Content { let email: String; let password: String }
private struct CreateUserReq: Content { let email: String; let password: String; let fullName: String; let roleId: UUID; let isActive: Bool }
private struct CreateTaskReq: Content {
    let projectId: UUID
    let epicId: UUID?
    let parentTaskId: UUID?
    let title: String
    let description: String
    let issueType: String
    let priority: String
    let assigneeId: UUID?
    let reporterId: UUID
    let estimateMinutes: Int
    let dueDate: Date?
}
private struct TokenData: Decodable { let accessToken: String; let refreshToken: String }
private struct LoginEnvelope: Decodable { let success: Bool; let data: TokenData?; let error: TestError? }

final class IntegrationAuthAndValidationTests: XCTestCase {
    private func loginToken(using app: Application, email: String = "admin@demo.local", password: String = "Password123!") async throws -> String {
        let tester = try app.testable()
        var token = ""
        try await tester.test(.POST, "/api/v1/auth/login", beforeRequest: { req async throws in
            try req.content.encode(LoginReq(email: email, password: password))
        }, afterResponse: { res async throws in
            let envelope = try res.decode(LoginEnvelope.self)
            token = try XCTUnwrap(envelope.data?.accessToken)
        })
        return token
    }

    func testLoginWrongPasswordReturns401() async throws {
        let app = try await TestAppFactory.make()
        let tester = try app.testable()
        try await tester.test(.POST, "/api/v1/auth/login", beforeRequest: { req async throws in
            try req.content.encode(LoginReq(email: "admin@demo.local", password: "wrong-password"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        })
        try await app.asyncShutdown()
    }

    func testRefreshInvalidTokenReturns401() async throws {
        let app = try await TestAppFactory.make()
        let tester = try app.testable()
        try await tester.test(.POST, "/api/v1/auth/refresh", beforeRequest: { req async throws in
            try req.content.encode(RefreshRequest(refreshToken: "invalid.token.value"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        })
        try await app.asyncShutdown()
    }

    func testProjectsWithoutTokenReturns401() async throws {
        let app = try await TestAppFactory.make()
        let tester = try app.testable()
        try await tester.test(.GET, "/api/v1/projects", afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
        })
        try await app.asyncShutdown()
    }

    func testDuplicateUserEmailReturns409() async throws {
        let app = try await TestAppFactory.make()
        let tester = try app.testable()
        let token = try await loginToken(using: app)
        let role = try await Role.query(on: app.db).filter(\Role.$name == RoleName.viewer).first()
        let roleId = try XCTUnwrap(role?.id)
        let payload = CreateUserReq(email: "dup@example.com", password: "Password123!", fullName: "Dup User", roleId: roleId, isActive: true)

        try await tester.test(.POST, "/api/v1/users", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(payload)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
        })

        try await tester.test(.POST, "/api/v1/users", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(payload)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .conflict)
        })
        try await app.asyncShutdown()
    }

    func testViewerCannotCreateTaskReturns403() async throws {
        let app = try await TestAppFactory.make()
        let tester = try app.testable()

        let viewerRole = try await Role.query(on: app.db).filter(\Role.$name == RoleName.viewer).first()
        let admin = try await User.query(on: app.db).filter(\User.$email == "admin@demo.local").first()
        let project = try await Project.query(on: app.db).first()
        let viewer = User(email: "viewer@example.com", passwordHash: try Bcrypt.hash("Password123!"), fullName: "Viewer", roleID: try XCTUnwrap(viewerRole?.id), isActive: true)
        try await viewer.save(on: app.db)
        let member = ProjectMember(projectID: try XCTUnwrap(project?.id), userID: try XCTUnwrap(viewer.id), roleID: try XCTUnwrap(viewerRole?.id))
        try await member.save(on: app.db)

        let viewerToken = try await loginToken(using: app, email: "viewer@example.com", password: "Password123!")
        let body = CreateTaskReq(
            projectId: try XCTUnwrap(project?.id),
            epicId: nil,
            parentTaskId: nil,
            title: "No access task",
            description: "blocked",
            issueType: "task",
            priority: "medium",
            assigneeId: nil,
            reporterId: try XCTUnwrap(admin?.id),
            estimateMinutes: 60,
            dueDate: nil
        )

        try await tester.test(.POST, "/api/v1/tasks", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: viewerToken)
            try req.content.encode(body)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .forbidden)
        })
        try await app.asyncShutdown()
    }
}
