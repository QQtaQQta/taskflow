import Fluent
import XCTVapor
import XCTest
@testable import Application

// Additional coverage that exercises the CRUD endpoints exactly the way the
// mobile client calls them (camelCase JSON on the wire). These tests fail the
// moment the contract regresses to snake_case or the services stop persisting
// the received fields (e.g. silent task edit regression).
private struct LoginReqCRUD: Content { let email: String; let password: String }
private struct TokenDataCRUD: Decodable { let accessToken: String; let refreshToken: String }
private struct LoginEnvCRUD: Decodable { let success: Bool; let data: TokenDataCRUD?; let error: TestError? }

private struct ProjectCreateReqCRUD: Content {
    let key: String
    let name: String
    let description: String
}
private struct ProjectUpdateReqCRUD: Content {
    let name: String?
    let description: String?
}
private struct ProjectRowCRUD: Decodable {
    let id: UUID
    let key: String
    let name: String
    let description: String
    let isArchived: Bool
}
private struct ProjectRowEnv: Decodable { let success: Bool; let data: ProjectRowCRUD?; let error: TestError? }

private struct UserCreateReqCRUD: Content {
    let email: String
    let password: String
    let fullName: String
    let roleId: UUID
    let isActive: Bool
}
private struct UserRowCRUD: Decodable {
    let id: UUID
    let email: String
    let fullName: String
    let isActive: Bool
}
private struct UserRowEnv: Decodable { let success: Bool; let data: UserRowCRUD?; let error: TestError? }

private struct TaskCreateReqCRUD: Content {
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
private struct TaskUpdateReqCRUD: Content {
    let title: String?
    let description: String?
    let priority: String?
    let dueDate: Date?
}
private struct TaskMutationCRUD: Decodable {
    let id: UUID
    let key: String?
    let projectId: UUID?
    let title: String
    let description: String?
    let priority: String
    let status: String?
    let dueDate: Date?
}
private struct TaskMutationEnv: Decodable { let success: Bool; let data: TaskMutationCRUD?; let error: TestError? }

private struct EpicCreateReqCRUD: Content {
    let key: String
    let title: String
    let description: String
    let startDate: Date?
    let dueDate: Date?
}
private struct EpicCreateDataCRUD: Decodable { let id: UUID; let projectId: UUID }
private struct EpicCreateEnvCRUD: Decodable { let success: Bool; let data: EpicCreateDataCRUD?; let error: TestError? }

private struct BoardRowCRUD: Decodable { let id: UUID; let projectId: UUID; let name: String }
private struct BoardListEnvCRUD: Decodable { let success: Bool; let data: [BoardRowCRUD]?; let error: TestError? }

final class IntegrationCRUDTests: XCTestCase {
    private func login(_ app: Application, email: String = "admin@demo.local", password: String = "Password123!") async throws -> String {
        let tester = try app.testable()
        var token = ""
        try await tester.test(.POST, "/api/v1/auth/login", beforeRequest: { req async throws in
            try req.content.encode(LoginReqCRUD(email: email, password: password))
        }, afterResponse: { res async throws in
            token = try XCTUnwrap(try res.decode(LoginEnvCRUD.self).data?.accessToken)
        })
        return token
    }

    private func firstProjectId(_ app: Application) async throws -> UUID {
        let project = try await Project.query(on: app.db).first()
        return try XCTUnwrap(project?.id)
    }

    // MARK: - Project CRUD round-trip

    func testCreateProjectReturnsRowAndPersists() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()

        var createdId: UUID?
        try await tester.test(.POST, "/api/v1/projects", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(ProjectCreateReqCRUD(key: "NEWP", name: "New Project", description: "Desc"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            let env = try res.decode(ProjectRowEnv.self)
            XCTAssertTrue(env.success)
            XCTAssertEqual(env.data?.key, "NEWP")
            XCTAssertEqual(env.data?.name, "New Project")
            XCTAssertEqual(env.data?.isArchived, false)
            createdId = env.data?.id
        })

        let persisted = try await Project.find(try XCTUnwrap(createdId), on: app.db)
        XCTAssertEqual(persisted?.name, "New Project")
        try await app.asyncShutdown()
    }

    func testUpdateProjectPersistsChanges() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()
        let pid = try await firstProjectId(app)

        try await tester.test(.PATCH, "/api/v1/projects/\(pid.uuidString)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(ProjectUpdateReqCRUD(name: "Updated name", description: "Updated desc"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let env = try res.decode(ProjectRowEnv.self)
            XCTAssertEqual(env.data?.name, "Updated name")
            XCTAssertEqual(env.data?.description, "Updated desc")
        })

        let reloaded = try await Project.find(pid, on: app.db)
        XCTAssertEqual(reloaded?.name, "Updated name")
        try await app.asyncShutdown()
    }

    func testDeleteProjectRemovesProject() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()
        let pid = try await firstProjectId(app)

        try await tester.test(.DELETE, "/api/v1/projects/\(pid.uuidString)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
        })
        let reloaded = try await Project.find(pid, on: app.db)
        XCTAssertNil(reloaded)
        try await app.asyncShutdown()
    }

    // MARK: - User CRUD

    func testCreateUserAcceptsCamelCaseFullNameAndRoleId() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()
        let role = try await Role.query(on: app.db).filter(\.$name == RoleName.viewer).first()
        let roleId = try XCTUnwrap(role?.id)

        try await tester.test(.POST, "/api/v1/users", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(UserCreateReqCRUD(email: "crud.user@example.com", password: "Password123!", fullName: "Crud User", roleId: roleId, isActive: true))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            let env = try res.decode(UserRowEnv.self)
            XCTAssertEqual(env.data?.email, "crud.user@example.com")
            XCTAssertEqual(env.data?.fullName, "Crud User")
            XCTAssertEqual(env.data?.isActive, true)
        })
        try await app.asyncShutdown()
    }

    // MARK: - Task CRUD and silent-save regression

    func testUpdateTaskPersistsDueDate() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()
        let pid = try await firstProjectId(app)
        let admin = try await User.query(on: app.db).filter(\.$email == "admin@demo.local").first()
        let uid = try XCTUnwrap(admin?.id)

        var taskId: UUID?
        try await tester.test(.POST, "/api/v1/tasks", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(TaskCreateReqCRUD(
                projectId: pid, epicId: nil, parentTaskId: nil,
                title: "CRUD task", description: "D",
                issueType: "task", priority: "medium",
                assigneeId: uid, reporterId: uid, estimateMinutes: 30, dueDate: nil
            ))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            let env = try res.decode(TaskMutationEnv.self)
            taskId = env.data?.id
        })

        let tid = try XCTUnwrap(taskId)
        let due = Date(timeIntervalSince1970: 1_700_000_000)

        try await tester.test(.PATCH, "/api/v1/tasks/\(tid.uuidString)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(TaskUpdateReqCRUD(title: "New title", description: nil, priority: "high", dueDate: due))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let env = try res.decode(TaskMutationEnv.self)
            XCTAssertEqual(env.data?.title, "New title")
            XCTAssertEqual(env.data?.priority, "high")
            XCTAssertNotNil(env.data?.dueDate)
        })

        let reloaded = try await WorkTask.find(tid, on: app.db)
        XCTAssertEqual(reloaded?.title, "New title")
        XCTAssertEqual(reloaded?.priority, "high")
        XCTAssertNotNil(reloaded?.dueDate)
        try await app.asyncShutdown()
    }

    // MARK: - Board listing scoped by project (boards-by-project feature)

    func testBoardsFilteredByProjectIdReturnOnlyThatProject() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()
        let admin = try await User.query(on: app.db).filter(\.$email == "admin@demo.local").first()
        let owner = try XCTUnwrap(admin?.id)

        let seededProject = try await Project.query(on: app.db).first()
        let seededProjectId = try XCTUnwrap(seededProject?.id)

        let newProject = Project(key: "OTHER", name: "Other", description: "d", ownerID: owner)
        try await newProject.save(on: app.db)
        let otherId = try XCTUnwrap(newProject.id)
        let otherBoard = Board(projectID: otherId, name: "Other Board", description: "d", isDefault: false, isArchived: false)
        try await otherBoard.save(on: app.db)

        try await tester.test(.GET, "/api/v1/boards?projectId=\(otherId.uuidString)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let env = try res.decode(BoardListEnvCRUD.self)
            let boards = env.data ?? []
            XCTAssertTrue(boards.allSatisfy { $0.projectId == otherId })
            XCTAssertTrue(boards.contains(where: { $0.id == otherBoard.id }))
            XCTAssertFalse(boards.contains(where: { $0.projectId == seededProjectId }))
        })
        try await app.asyncShutdown()
    }

    // MARK: - Epic CRUD contract stability

    func testCreateEpicResponseIncludesProjectId() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()
        let pid = try await firstProjectId(app)

        try await tester.test(.POST, "/api/v1/projects/\(pid.uuidString)/epics", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(EpicCreateReqCRUD(key: "CRUD-EPIC", title: "Epic", description: "D", startDate: nil, dueDate: nil))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            let env = try res.decode(EpicCreateEnvCRUD.self)
            XCTAssertEqual(env.data?.projectId, pid)
        })
        try await app.asyncShutdown()
    }

    // MARK: - Time entries expose the author for history UI

    func testTimeEntryListExposesUserFullName() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()
        let pid = try await firstProjectId(app)
        let admin = try await User.query(on: app.db).filter(\.$email == "admin@demo.local").first()
        let uid = try XCTUnwrap(admin?.id)

        var taskId: UUID?
        try await tester.test(.POST, "/api/v1/tasks", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(TaskCreateReqCRUD(
                projectId: pid, epicId: nil, parentTaskId: nil,
                title: "TE task", description: "D", issueType: "task", priority: "low",
                assigneeId: uid, reporterId: uid, estimateMinutes: 30, dueDate: nil
            ))
        }, afterResponse: { res async throws in
            let env = try res.decode(TaskMutationEnv.self)
            taskId = env.data?.id
        })
        let tid = try XCTUnwrap(taskId)

        struct TimeCreateReq: Content {
            let spentMinutes: Int; let comment: String; let startedAt: Date
        }
        try await tester.test(.POST, "/api/v1/tasks/\(tid.uuidString)/time-entries", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(TimeCreateReq(spentMinutes: 45, comment: "session", startedAt: Date()))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
        })

        struct TimeRow: Decodable {
            let id: UUID
            let userId: UUID
            let userFullName: String
            let spentMinutes: Int
            let comment: String
        }
        struct TimeEnv: Decodable { let success: Bool; let data: [TimeRow]?; let error: TestError? }

        try await tester.test(.GET, "/api/v1/tasks/\(tid.uuidString)/time-entries", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let env = try res.decode(TimeEnv.self)
            let row = try XCTUnwrap(env.data?.first)
            XCTAssertEqual(row.userId, uid)
            XCTAssertEqual(row.userFullName, "Demo Admin")
            XCTAssertEqual(row.spentMinutes, 45)
        })
        try await app.asyncShutdown()
    }

    // MARK: - Board creation auto-seeds default columns (defect 3)

    func testCreateBoardAutoPopulatesDefaultColumns() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()
        let pid = try await firstProjectId(app)

        struct BoardCreateReqCRUD: Content {
            let projectId: UUID; let name: String; let description: String; let isDefault: Bool
        }
        struct BoardOut: Decodable { let id: UUID; let projectId: UUID; let name: String; let isDefault: Bool }
        struct BoardEnv: Decodable { let success: Bool; let data: BoardOut?; let error: TestError? }

        var createdId: UUID?
        try await tester.test(.POST, "/api/v1/boards", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(BoardCreateReqCRUD(projectId: pid, name: "Fresh board", description: "d", isDefault: false))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            createdId = try res.decode(BoardEnv.self).data?.id
        })
        let bid = try XCTUnwrap(createdId)

        struct ColRow: Decodable { let id: UUID; let name: String; let key: String; let orderIndex: Int; let isDoneColumn: Bool }
        struct ColEnv: Decodable { let success: Bool; let data: [ColRow]?; let error: TestError? }
        try await tester.test(.GET, "/api/v1/boards/\(bid.uuidString)/columns", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let cols = try res.decode(ColEnv.self).data ?? []
            XCTAssertEqual(cols.count, 5)
            XCTAssertEqual(cols.map(\.key), ["backlog", "todo", "in_progress", "review", "done"])
            XCTAssertTrue(cols.last?.isDoneColumn == true)
        })
        try await app.asyncShutdown()
    }

    func testCreateBoardForMissingProjectReturnsTypedNotFound() async throws {
        let app = try await TestAppFactory.make()
        let token = try await login(app)
        let tester = try app.testable()
        struct BoardCreateReqCRUD: Content {
            let projectId: UUID; let name: String; let description: String; let isDefault: Bool
        }
        try await tester.test(.POST, "/api/v1/boards", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(BoardCreateReqCRUD(projectId: UUID(), name: "Ghost", description: "d", isDefault: false))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
            struct Env: Decodable { let success: Bool; let error: TestError? }
            let env = try res.decode(Env.self)
            XCTAssertEqual(env.error?.code, "NOT_FOUND")
        })
        try await app.asyncShutdown()
    }

    // MARK: - Response envelope schema stability

    func testErrorResponseUsesEnvelope() async throws {
        let app = try await TestAppFactory.make()
        let tester = try app.testable()
        struct ErrorEnv: Decodable { let success: Bool; let error: TestError? }

        try await tester.test(.POST, "/api/v1/auth/login", beforeRequest: { req async throws in
            try req.content.encode(LoginReqCRUD(email: "admin@demo.local", password: "wrong-pass"))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .unauthorized)
            let env = try res.decode(ErrorEnv.self)
            XCTAssertEqual(env.success, false)
            XCTAssertNotNil(env.error)
            XCTAssertEqual(env.error?.code, "UNAUTHORIZED")
        })
        try await app.asyncShutdown()
    }
}
