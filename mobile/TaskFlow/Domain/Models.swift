import Foundation

struct Role: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String

    var localizedName: String {
        switch name.lowercased() {
        case "admin": return "Администратор"
        case "manager": return "Менеджер"
        case "assignee": return "Исполнитель"
        case "viewer": return "Наблюдатель"
        default: return name
        }
    }
}

struct User: Codable, Identifiable, Hashable {
    let id: UUID
    let email: String
    let fullName: String
    let role: Role
    let permissions: [String]?
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct LoginResponse: Codable {
    let user: User
    let accessToken: String
    let refreshToken: String
}

struct RefreshTokenRequest: Codable {
    let refreshToken: String
}

struct RefreshTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

struct Project: Codable, Identifiable, Hashable {
    let id: UUID
    let key: String
    let name: String
    let description: String?
    let isArchived: Bool
    let tasksCount: Int?
    let epicsCount: Int?
}

struct ProjectResponse: Codable {
    let id: UUID
    let key: String
    let name: String
    let description: String?
    let isArchived: Bool
    let tasksCount: Int?
    let epicsCount: Int?
}

struct ProjectDetailResponse: Codable {
    let id: UUID
    let key: String
    let name: String
    let description: String
    let tasksCount: Int
    let epicsCount: Int
}

struct CreateProjectRequest: Codable {
    let key: String
    let name: String
    let description: String
}

struct Assignee: Codable, Identifiable, Hashable {
    let id: UUID
    let fullName: String
}

struct TaskEpicMini: Codable, Hashable {
    let id: UUID
    let key: String
    let title: String
}

struct WorkTask: Codable, Identifiable, Hashable {
    let id: UUID
    let key: String?
    let title: String
    let description: String?
    let status: String
    let priority: String?
    let estimateMinutes: Int?
    let spentMinutes: Int?
    let assignee: Assignee?
    let reporter: Assignee?
    let dueDate: Date?
    // Backend `TaskDetailDTO` nests the epic under `epic: {id, key, title}`.
    // Keeping a mini struct lets the detail screen render the epic title
    // instead of the opaque UUID (defect 5).
    let epic: TaskEpicMini?
    let parentTaskId: UUID?

    /// Convenience accessor retained for call sites that still reason about
    /// the raw epic identifier (filters, link-to-epic pickers, etc.).
    var epicId: UUID? { epic?.id }
}

struct UserListItem: Codable, Identifiable, Hashable {
    let id: UUID
    let email: String
    let fullName: String
    let isActive: Bool?
    let role: Role
}

struct UpdateUserRequest: Codable {
    let fullName: String?
    let avatarUrl: String?
    let roleId: UUID?
    let isActive: Bool?
}

struct CreateUserRequest: Codable {
    let email: String
    let password: String
    let fullName: String
    let roleId: UUID
    let isActive: Bool?
}

struct RolePermissionUpdateRequest: Codable {
    let permissions: [String]
}

struct RolePermissionsResponse: Codable {
    let roleId: UUID
    let permissions: [String]
}

struct CreateTaskRequest: Codable {
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

struct UpdateTaskRequest: Codable {
    let title: String?
    let description: String?
    let priority: String?
    let dueDate: Date?
}

struct AssignTaskRequest: Codable {
    let assigneeId: UUID
}

struct TaskEstimateRequest: Codable {
    let estimateMinutes: Int
}

struct ChangeStatusRequest: Codable {
    let status: String
}

struct TaskMutationResponse: Codable {
    let id: UUID
    let key: String
    let projectId: UUID
    let epicId: UUID?
    let parentTaskId: UUID?
    let title: String
    let description: String
    let issueType: String?
    let priority: String
    let status: String
    let assigneeId: UUID?
    let reporterId: UUID?
    let estimateMinutes: Int
    let spentMinutes: Int
    let dueDate: Date?
}

struct TaskPatchResponse: Codable {
    let id: UUID
    let title: String
    let description: String
    let priority: String
    let dueDate: Date?
}

struct TimeEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID?
    let userFullName: String?
    let spentMinutes: Int
    let comment: String
    let startedAt: Date?
}

struct CreateTimeEntryRequest: Codable {
    let spentMinutes: Int
    let comment: String
    let startedAt: Date
}

struct Epic: Codable, Identifiable, Hashable {
    let id: UUID
    let projectId: UUID
    let key: String
    let title: String
    let description: String?
    let status: String
}

struct CreateEpicRequest: Codable {
    let key: String
    let title: String
    let description: String
}

struct UpdateEpicRequest: Codable {
    let projectId: UUID?
    let title: String?
    let description: String?
    let status: String?
    let startDate: Date?
    let dueDate: Date?
}

struct UpdateProjectRequest: Codable {
    let name: String?
    let description: String?
}

struct ProjectOperationResponse: Codable {
    let message: String
}

struct Board: Codable, Identifiable, Hashable {
    let id: UUID
    let projectId: UUID?
    let name: String
    let columns: [BoardColumn]?
}

struct CreateBoardRequest: Codable {
    let projectId: UUID
    let name: String
    let description: String
    let isDefault: Bool?
}

struct BoardCreatedResponse: Codable {
    let id: UUID
    let projectId: UUID
    let name: String
    let description: String
    let isDefault: Bool
}

struct UpdateBoardRequest: Codable {
    let name: String?
    let description: String?
}

struct BoardUpdatedResponse: Codable {
    let id: UUID
    let name: String
    let description: String
}

struct CreateBoardColumnRequest: Codable {
    let name: String
    let key: String
    let orderIndex: Int
    let wipLimit: Int?
    let isDoneColumn: Bool?
}

struct UpdateBoardColumnRequest: Codable {
    let name: String?
    let orderIndex: Int?
    let wipLimit: Int?
}

struct BoardColumn: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    /// Backend column identifier used for mapping tasks to the correct
    /// column (e.g. "todo", "in_progress", "done"). Optional for forward
    /// compatibility with responses that may omit it.
    let key: String?
    let orderIndex: Int
    let isDoneColumn: Bool?
}

struct MoveTaskRequest: Codable {
    let boardColumnId: UUID
    let orderIndex: Int
}
