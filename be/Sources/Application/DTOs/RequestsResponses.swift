import Foundation
import Vapor

// MARK: - Auth

struct LoginRequest: Content {
    var email: String
    var password: String
}

struct RefreshRequest: Content {
    var refreshToken: String
}

struct LogoutRequest: Content {
    var refreshToken: String
}

// MARK: - Roles

struct RoleCreateRequest: Content {
    var name: String
    var description: String
}

struct RoleUpdateRequest: Content {
    var name: String?
    var description: String?
}

struct RolePermissionsPutRequest: Content {
    var permissions: [String]
}

// MARK: - Users

struct UserCreateRequest: Content {
    var email: String
    var password: String
    var fullName: String
    var roleId: UUID
    var isActive: Bool?
}

struct UserUpdateRequest: Content {
    var fullName: String?
    var avatarUrl: String?
    var roleId: UUID?
    var isActive: Bool?
}

struct UserListQuery: Content {
    var page: Int?
    var perPage: Int?
    var sortBy: String?
    var sortOrder: String?
    var search: String?
    var roleId: UUID?
}

// MARK: - Projects

struct ProjectCreateRequest: Content {
    var key: String
    var name: String
    var description: String
}

struct ProjectUpdateRequest: Content {
    var name: String?
    var description: String?
}

struct ProjectMemberRequest: Content {
    var userId: UUID
    var roleId: UUID
}

struct ProjectListQuery: Content {
    var page: Int?
    var perPage: Int?
    var sortBy: String?
    var sortOrder: String?
    var search: String?
}

// MARK: - Epics

struct EpicCreateRequest: Content {
    var key: String
    var title: String
    var description: String
    var startDate: Date?
    var dueDate: Date?
}

struct EpicUpdateRequest: Content {
    var projectId: UUID?
    var title: String?
    var description: String?
    var status: String?
    var startDate: Date?
    var dueDate: Date?
}

struct EpicListQuery: Content {
    var page: Int?
    var perPage: Int?
    var sortBy: String?
    var sortOrder: String?
    var search: String?
}

// MARK: - Tasks

struct TaskCreateRequest: Content {
    var projectId: UUID
    var epicId: UUID?
    var parentTaskId: UUID?
    var title: String
    var description: String
    var issueType: String
    var priority: String
    var assigneeId: UUID?
    var reporterId: UUID
    var estimateMinutes: Int
    var dueDate: Date?
}

struct TaskUpdateRequest: Content {
    var title: String?
    var description: String?
    var priority: String?
    var dueDate: Date?
}

struct TaskListQuery: Content {
    var page: Int?
    var perPage: Int?
    var sortBy: String?
    var sortOrder: String?
    var search: String?
    var projectId: UUID?
    var assigneeId: UUID?
    var status: String?
    var epicId: UUID?
}

struct TaskAssignRequest: Content {
    var assigneeId: UUID
}

struct TaskEstimateRequest: Content {
    var estimateMinutes: Int
}

struct TaskStatusRequest: Content {
    var status: String
    var comment: String?
}

struct SubtaskCreateRequest: Content {
    var title: String
    var description: String?
    var issueType: String
    var assigneeId: UUID?
    var estimateMinutes: Int?
}

// MARK: - Comments

struct CommentCreateRequest: Content {
    var body: String
}

// MARK: - Time

struct TimeEntryCreateRequest: Content {
    var spentMinutes: Int
    var comment: String
    var startedAt: Date
}

struct TimeEntryUpdateRequest: Content {
    var spentMinutes: Int?
    var comment: String?
}

// MARK: - Boards

struct BoardCreateRequest: Content {
    var projectId: UUID
    var name: String
    var description: String
    var isDefault: Bool?
}

struct BoardUpdateRequest: Content {
    var name: String?
    var description: String?
}

struct BoardListQuery: Content {
    var projectId: UUID?
}

struct BoardColumnCreateRequest: Content {
    var name: String
    var key: String
    var orderIndex: Int
    var wipLimit: Int?
    var isDoneColumn: Bool?
}

struct BoardColumnUpdateRequest: Content {
    var name: String?
    var orderIndex: Int?
    var wipLimit: Int?
}

struct BoardMoveRequest: Content {
    var boardColumnId: UUID
    var orderIndex: Int
}

struct BoardReorderRequest: Content {
    var orderIndex: Int
}

// MARK: - Search

struct SearchQuery: Content {
    var q: String?
    var type: String?
}
