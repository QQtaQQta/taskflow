import Foundation

actor MemoryCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    func value(for key: Key) -> Value? { storage[key] }
    func set(_ value: Value, for key: Key) { storage[key] = value }
}

protocol AuthRepository: Sendable {
    func login(email: String, password: String) async throws -> LoginResponse
    func me() async throws -> User
}

protocol ProjectRepository: Sendable {
    func list(page: Int, search: String?) async throws -> [Project]
    func detail(id: UUID) async throws -> Project
    func create(_ request: CreateProjectRequest) async throws -> Project
    func update(id: UUID, request: UpdateProjectRequest) async throws -> Project
    func archive(id: UUID) async throws
}

protocol TaskRepository: Sendable {
    func list(projectId: UUID?, epicId: UUID?, page: Int, search: String?) async throws -> [WorkTask]
    func detail(id: UUID) async throws -> WorkTask
    func create(_ request: CreateTaskRequest) async throws
    func update(id: UUID, request: UpdateTaskRequest) async throws -> WorkTask
    func archive(id: UUID) async throws
    func assign(taskId: UUID, assigneeId: UUID) async throws
    func estimate(taskId: UUID, minutes: Int) async throws
    func changeStatus(taskId: UUID, status: String) async throws
}

protocol EpicRepository: Sendable {
    func list(projectId: UUID) async throws -> [Epic]
    func create(projectId: UUID, request: CreateEpicRequest) async throws
    func update(id: UUID, request: UpdateEpicRequest) async throws
    func archive(id: UUID) async throws
    func linkTask(epicId: UUID, taskId: UUID) async throws
}

protocol BoardRepository: Sendable {
    func list(projectId: UUID?) async throws -> [Board]
    func detail(id: UUID) async throws -> Board
    func create(projectId: UUID, name: String, description: String, isDefault: Bool) async throws -> BoardCreatedResponse
    func update(id: UUID, name: String, description: String) async throws -> BoardUpdatedResponse
    func archive(id: UUID) async throws
    func createColumn(boardId: UUID, name: String, key: String, orderIndex: Int, wipLimit: Int?, isDoneColumn: Bool) async throws
    func deleteColumn(columnId: UUID) async throws
    func moveTask(boardId: UUID, taskId: UUID, columnId: UUID, orderIndex: Int) async throws
}

protocol TimeTrackingRepository: Sendable {
    func list(taskId: UUID) async throws -> [TimeEntry]
    func create(taskId: UUID, spentMinutes: Int, comment: String) async throws -> TimeEntry
}

protocol AdminRepository: Sendable {
    func users(search: String?) async throws -> [UserListItem]
    func roles(search: String?) async throws -> [Role]
    func createUser(_ request: CreateUserRequest) async throws
    func updateUserRole(userId: UUID, roleId: UUID) async throws
    func updateRolePermissions(roleId: UUID, permissions: [String]) async throws
}

final class AuthRepositoryImpl: AuthRepository, @unchecked Sendable {
    private let client: APIClient
    init(client: APIClient) { self.client = client }

    func login(email: String, password: String) async throws -> LoginResponse {
        try await client.request(.login(.init(email: email, password: password)))
    }

    func me() async throws -> User {
        try await client.request(.me)
    }
}

final class ProjectRepositoryImpl: ProjectRepository, @unchecked Sendable {
    private let client: APIClient
    private let cache = MemoryCache<UUID, Project>()

    init(client: APIClient) {
        self.client = client
    }

    func list(page: Int, search: String?) async throws -> [Project] {
        let rows: [ProjectResponse] = try await client.request(.projects(page: page, perPage: 20, search: search))
        return rows.map {
            Project(
                id: $0.id,
                key: $0.key,
                name: $0.name,
                description: $0.description,
                isArchived: $0.isArchived,
                tasksCount: $0.tasksCount,
                epicsCount: $0.epicsCount
            )
        }
    }

    func detail(id: UUID) async throws -> Project {
        if let cached = await cache.value(for: id) { return cached }
        let row: ProjectDetailResponse = try await client.request(.project(id: id))
        let value = Project(
            id: row.id,
            key: row.key,
            name: row.name,
            description: row.description,
            isArchived: false,
            tasksCount: row.tasksCount,
            epicsCount: row.epicsCount
        )
        await cache.set(value, for: id)
        return value
    }

    func create(_ request: CreateProjectRequest) async throws -> Project {
        let row: ProjectResponse = try await client.request(.createProject(request))
        return Project(
            id: row.id,
            key: row.key,
            name: row.name,
            description: row.description,
            isArchived: row.isArchived,
            tasksCount: row.tasksCount,
            epicsCount: row.epicsCount
        )
    }

    func update(id: UUID, request: UpdateProjectRequest) async throws -> Project {
        let row: ProjectResponse = try await client.request(.updateProject(id: id, request: request))
        return Project(
            id: row.id,
            key: row.key,
            name: row.name,
            description: row.description,
            isArchived: row.isArchived,
            tasksCount: row.tasksCount,
            epicsCount: row.epicsCount
        )
    }

    func archive(id: UUID) async throws {
        let _: ProjectOperationResponse = try await client.request(.archiveProject(id: id))
    }
}

final class TaskRepositoryImpl: TaskRepository, @unchecked Sendable {
    private let client: APIClient
    init(client: APIClient) { self.client = client }

    func list(projectId: UUID?, epicId: UUID?, page: Int, search: String?) async throws -> [WorkTask] {
        try await client.request(.tasks(projectId: projectId, epicId: epicId, page: page, perPage: 20, search: search))
    }

    func detail(id: UUID) async throws -> WorkTask {
        try await client.request(.task(id: id))
    }

    func create(_ request: CreateTaskRequest) async throws {
        try await client.requestVoid(.createTask(request))
    }

    func update(id: UUID, request: UpdateTaskRequest) async throws -> WorkTask {
        let response: TaskPatchResponse = try await client.request(.updateTask(id: id, request: request))
        return WorkTask(
            id: response.id,
            key: nil,
            title: response.title,
            description: response.description,
            status: "todo",
            priority: response.priority,
            estimateMinutes: nil,
            spentMinutes: nil,
            assignee: nil,
            reporter: nil,
            dueDate: response.dueDate,
            epic: nil,
            parentTaskId: nil
        )
    }

    func assign(taskId: UUID, assigneeId: UUID) async throws {
        let _: EmptyResponse = try await client.request(.assignTask(id: taskId, request: .init(assigneeId: assigneeId)))
    }

    func estimate(taskId: UUID, minutes: Int) async throws {
        let _: EmptyResponse = try await client.request(.estimateTask(id: taskId, request: .init(estimateMinutes: minutes)))
    }

    func archive(id: UUID) async throws {
        let _: EmptyResponse = try await client.request(.archiveTask(id: id))
    }

    func changeStatus(taskId: UUID, status: String) async throws {
        let _: EmptyResponse = try await client.request(.changeTaskStatus(id: taskId, request: .init(status: status)))
    }
}

final class EpicRepositoryImpl: EpicRepository, @unchecked Sendable {
    private let client: APIClient
    init(client: APIClient) { self.client = client }

    func list(projectId: UUID) async throws -> [Epic] {
        try await client.request(.projectEpics(projectId: projectId))
    }

    func create(projectId: UUID, request: CreateEpicRequest) async throws {
        try await client.requestVoid(.createEpic(projectId: projectId, request: request))
    }

    func update(id: UUID, request: UpdateEpicRequest) async throws {
        try await client.requestVoid(.updateEpic(id: id, request: request))
    }

    func linkTask(epicId: UUID, taskId: UUID) async throws {
        let _: EmptyResponse = try await client.request(.linkTaskToEpic(epicId: epicId, taskId: taskId))
    }

    func archive(id: UUID) async throws {
        let _: EmptyResponse = try await client.request(.archiveEpic(id: id))
    }
}

final class BoardRepositoryImpl: BoardRepository, @unchecked Sendable {
    private let client: APIClient
    init(client: APIClient) { self.client = client }

    func list(projectId: UUID?) async throws -> [Board] {
        try await client.request(.boards(projectId: projectId))
    }

    func detail(id: UUID) async throws -> Board {
        try await client.request(.board(id: id))
    }

    func create(projectId: UUID, name: String, description: String, isDefault: Bool) async throws -> BoardCreatedResponse {
        try await client.request(.createBoard(.init(projectId: projectId, name: name, description: description, isDefault: isDefault)))
    }

    func update(id: UUID, name: String, description: String) async throws -> BoardUpdatedResponse {
        try await client.request(.updateBoard(id: id, request: .init(name: name, description: description)))
    }

    func archive(id: UUID) async throws {
        let _: EmptyResponse = try await client.request(.archiveBoard(id: id))
    }

    func createColumn(boardId: UUID, name: String, key: String, orderIndex: Int, wipLimit: Int?, isDoneColumn: Bool) async throws {
        try await client.requestVoid(.createBoardColumn(boardId: boardId, request: .init(name: name, key: key, orderIndex: orderIndex, wipLimit: wipLimit, isDoneColumn: isDoneColumn)))
    }

    func deleteColumn(columnId: UUID) async throws {
        let _: EmptyResponse = try await client.request(.deleteBoardColumn(columnId: columnId))
    }

    func moveTask(boardId: UUID, taskId: UUID, columnId: UUID, orderIndex: Int) async throws {
        let _: EmptyResponse = try await client.request(
            .moveTask(boardId: boardId, taskId: taskId, request: .init(boardColumnId: columnId, orderIndex: orderIndex))
        )
    }
}

final class TimeTrackingRepositoryImpl: TimeTrackingRepository, @unchecked Sendable {
    private let client: APIClient
    init(client: APIClient) { self.client = client }

    func list(taskId: UUID) async throws -> [TimeEntry] {
        try await client.request(.taskTimeEntries(id: taskId))
    }

    func create(taskId: UUID, spentMinutes: Int, comment: String) async throws -> TimeEntry {
        try await client.request(
            .createTimeEntry(id: taskId, request: .init(spentMinutes: spentMinutes, comment: comment, startedAt: Date()))
        )
    }
}

final class AdminRepositoryImpl: AdminRepository, @unchecked Sendable {
    private let client: APIClient
    init(client: APIClient) { self.client = client }

    func users(search: String?) async throws -> [UserListItem] {
        try await client.request(.users(page: 1, perPage: 100, search: search))
    }

    func roles(search: String?) async throws -> [Role] {
        try await client.request(.roles(page: 1, perPage: 100, search: search))
    }

    func createUser(_ request: CreateUserRequest) async throws {
        try await client.requestVoid(.createUser(request))
    }

    func updateUserRole(userId: UUID, roleId: UUID) async throws {
        let _: EmptyResponse = try await client.request(
            .updateUser(id: userId, request: .init(fullName: nil, avatarUrl: nil, roleId: roleId, isActive: nil))
        )
    }

    func updateRolePermissions(roleId: UUID, permissions: [String]) async throws {
        let _: RolePermissionsResponse = try await client.request(
            .replaceRolePermissions(roleId: roleId, request: .init(permissions: permissions))
        )
    }
}
