import Fluent
import XCTVapor
import XCTest
@testable import Application

private struct AssignReq: Content { let assigneeId: UUID }
private struct EstimateReq: Content { let estimateMinutes: Int }
private struct TimeReq: Content { let spentMinutes: Int; let comment: String; let startedAt: Date }
private struct MoveReq: Content { let boardColumnId: UUID; let orderIndex: Int }
private struct TaskCreateReq2: Content {
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
private struct TaskCreateData: Decodable { let id: UUID }
private struct TaskCreateEnvelope: Decodable { let success: Bool; let data: TaskCreateData?; let error: TestError? }
private struct LoginReq2: Content { let email: String; let password: String }
private struct TokenData2: Decodable { let accessToken: String; let refreshToken: String }
private struct LoginEnvelope2: Decodable { let success: Bool; let data: TokenData2?; let error: TestError? }
private struct EpicPatchReq: Content {
    let projectId: UUID?
    let title: String?
    let description: String?
    let status: String?
    let startDate: Date?
    let dueDate: Date?
}
private struct EpicCreateReq: Content {
    let key: String
    let title: String
    let description: String
    let startDate: Date?
    let dueDate: Date?
}
private struct EpicCreateData: Decodable { let id: UUID }
private struct EpicCreateEnvelope: Decodable { let success: Bool; let data: EpicCreateData?; let error: TestError? }

final class IntegrationTaskBoardTests: XCTestCase {
    private func loginToken(_ app: Application) async throws -> String {
        let tester = try app.testable()
        var token = ""
        try await tester.test(.POST, "/api/v1/auth/login", beforeRequest: { req async throws in
            try req.content.encode(LoginReq2(email: "admin@demo.local", password: "Password123!"))
        }, afterResponse: { res async throws in
            let env = try res.decode(LoginEnvelope2.self)
            token = try XCTUnwrap(env.data?.accessToken)
        })
        return token
    }

    private func createTask(app: Application, token: String) async throws -> UUID {
        let tester = try app.testable()
        let project = try await Project.query(on: app.db).first()
        let admin = try await User.query(on: app.db).filter(\User.$email == "admin@demo.local").first()
        var taskId: UUID?
        let body = TaskCreateReq2(
            projectId: try XCTUnwrap(project?.id),
            epicId: nil,
            parentTaskId: nil,
            title: "Task for tests",
            description: "sample",
            issueType: "task",
            priority: "medium",
            assigneeId: try XCTUnwrap(admin?.id),
            reporterId: try XCTUnwrap(admin?.id),
            estimateMinutes: 120,
            dueDate: nil
        )
        try await tester.test(.POST, "/api/v1/tasks", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(body)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            let env = try res.decode(TaskCreateEnvelope.self)
            taskId = env.data?.id
        })
        return try XCTUnwrap(taskId)
    }

    func testAssignTaskToUnknownUserReturns404() async throws {
        let app = try await TestAppFactory.make()
        let token = try await loginToken(app)
        let taskId = try await createTask(app: app, token: token)
        let tester = try app.testable()

        try await tester.test(.POST, "/api/v1/tasks/\(taskId.uuidString)/assign", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(AssignReq(assigneeId: UUID()))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .notFound)
        })
        try await app.asyncShutdown()
    }

    func testNegativeEstimateReturns400() async throws {
        let app = try await TestAppFactory.make()
        let token = try await loginToken(app)
        let taskId = try await createTask(app: app, token: token)
        let tester = try app.testable()

        try await tester.test(.POST, "/api/v1/tasks/\(taskId.uuidString)/estimate", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(EstimateReq(estimateMinutes: -5))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        })
        try await app.asyncShutdown()
    }

    func testTimeEntryAbove24HoursReturns400() async throws {
        let app = try await TestAppFactory.make()
        let token = try await loginToken(app)
        let taskId = try await createTask(app: app, token: token)
        let tester = try app.testable()

        try await tester.test(.POST, "/api/v1/tasks/\(taskId.uuidString)/time-entries", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(TimeReq(spentMinutes: 1500, comment: "too much", startedAt: Date()))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .badRequest)
        })
        try await app.asyncShutdown()
    }

    func testMoveTaskToDoneColumnSetsTaskStatusDone() async throws {
        let app = try await TestAppFactory.make()
        let token = try await loginToken(app)
        let taskId = try await createTask(app: app, token: token)
        let tester = try app.testable()
        let board = try await Board.query(on: app.db).filter(\Board.$isDefault == true).first()
        let boardId = try XCTUnwrap(board?.id)
        let doneColumn = try await BoardColumn.query(on: app.db)
            .filter(\BoardColumn.$board.$id == boardId)
            .filter(\BoardColumn.$isDoneColumn == true)
            .first()

        try await tester.test(.POST, "/api/v1/boards/\(try XCTUnwrap(board?.id).uuidString)/tasks/\(taskId.uuidString)/move", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(MoveReq(boardColumnId: try XCTUnwrap(doneColumn?.id), orderIndex: 1))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
        })

        let updated = try await WorkTask.find(taskId, on: app.db)
        XCTAssertEqual(updated?.status, "done")
        try await app.asyncShutdown()
    }

    func testDeleteEpicNullifiesTaskEpicReference() async throws {
        let app = try await TestAppFactory.make()
        let token = try await loginToken(app)
        let tester = try app.testable()
        let project = try await Project.query(on: app.db).first()
        let projectId = try XCTUnwrap(project?.id)
        let taskId = try await createTask(app: app, token: token)
        var epicId: UUID?

        try await tester.test(.POST, "/api/v1/projects/\(projectId.uuidString)/epics", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(EpicCreateReq(key: "EP-1", title: "Epic", description: "desc", startDate: nil, dueDate: nil))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .created)
            epicId = try res.decode(EpicCreateEnvelope.self).data?.id
        })
        let eid = try XCTUnwrap(epicId)
        try await tester.test(.POST, "/api/v1/epics/\(eid.uuidString)/tasks/\(taskId.uuidString)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
        })
        try await tester.test(.DELETE, "/api/v1/epics/\(eid.uuidString)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
        })

        let task = try await WorkTask.find(taskId, on: app.db)
        XCTAssertNotNil(task)
        XCTAssertNil(task?.$epic.id)
        try await app.asyncShutdown()
    }

    func testDeleteProjectCascadesEpicsAndTasks() async throws {
        let app = try await TestAppFactory.make()
        let token = try await loginToken(app)
        let tester = try app.testable()
        let project = try await Project.query(on: app.db).first()
        let projectId = try XCTUnwrap(project?.id)
        let taskId = try await createTask(app: app, token: token)
        var epicId: UUID?

        try await tester.test(.POST, "/api/v1/projects/\(projectId.uuidString)/epics", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(EpicCreateReq(key: "EP-2", title: "Epic", description: "desc", startDate: nil, dueDate: nil))
        }, afterResponse: { res async throws in
            epicId = try res.decode(EpicCreateEnvelope.self).data?.id
        })

        try await tester.test(.DELETE, "/api/v1/projects/\(projectId.uuidString)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
        })

        let deletedProject = try await Project.find(projectId, on: app.db)
        let deletedTask = try await WorkTask.find(taskId, on: app.db)
        let deletedEpic = try await Epic.find(try XCTUnwrap(epicId), on: app.db)
        XCTAssertNil(deletedProject)
        XCTAssertNil(deletedTask)
        XCTAssertNil(deletedEpic)
        try await app.asyncShutdown()
    }

    func testEpicCanBeReassignedToAnotherProject() async throws {
        let app = try await TestAppFactory.make()
        let token = try await loginToken(app)
        let tester = try app.testable()
        let existing = try await Project.query(on: app.db).sort(\.$createdAt, .ascending).first()
        let sourceProjectId = try XCTUnwrap(existing?.id)
        let owner = try await User.query(on: app.db).filter(\.$email == "admin@demo.local").first()
        let targetProject = Project(key: "MOV", name: "Move target", description: "desc", ownerID: try XCTUnwrap(owner?.id))
        try await targetProject.save(on: app.db)
        var epicId: UUID?

        try await tester.test(.POST, "/api/v1/projects/\(sourceProjectId.uuidString)/epics", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(EpicCreateReq(key: "EP-MOVE", title: "Movable epic", description: "desc", startDate: nil, dueDate: nil))
        }, afterResponse: { res async throws in
            epicId = try res.decode(EpicCreateEnvelope.self).data?.id
        })
        let eid = try XCTUnwrap(epicId)

        try await tester.test(.PATCH, "/api/v1/epics/\(eid.uuidString)", beforeRequest: { req async throws in
            req.headers.bearerAuthorization = .init(token: token)
            try req.content.encode(EpicPatchReq(projectId: try XCTUnwrap(targetProject.id), title: nil, description: nil, status: nil, startDate: nil, dueDate: nil))
        }, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
        })

        let movedEpic = try await Epic.find(eid, on: app.db)
        XCTAssertEqual(movedEpic?.$project.id, targetProject.id)
        try await app.asyncShutdown()
    }
}
