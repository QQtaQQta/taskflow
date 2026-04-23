import Foundation
import Vapor

struct RoleRefDTO: Encodable {
    var id: UUID
    var name: String
}

struct LoginUserDTO: Encodable {
    var id: UUID
    var email: String
    var fullName: String
    var role: RoleRefDTO
}

struct LoginDataDTO: Encodable {
    var user: LoginUserDTO
    var accessToken: String
    var refreshToken: String
}

struct RefreshDataDTO: Encodable {
    var accessToken: String
    var refreshToken: String
}

struct MeDataDTO: Encodable {
    var id: UUID
    var email: String
    var fullName: String
    var avatarUrl: String?
    var role: RoleRefDTO
    var permissions: [String]
}

struct RoleRowDTO: Encodable {
    var id: UUID
    var name: String
    var description: String
}

struct RolePermissionsDataDTO: Encodable {
    var roleId: UUID
    var permissions: [String]
}

struct UserRowDTO: Encodable {
    var id: UUID
    var email: String
    var fullName: String
    var isActive: Bool
    var role: RoleRefDTO
}

struct UserDetailDTO: Encodable {
    var id: UUID
    var email: String
    var fullName: String
    var avatarUrl: String?
    var isActive: Bool
    var role: RoleRefDTO
    var projectsCount: Int
}

struct UserPatchDataDTO: Encodable {
    var id: UUID
    var email: String
    var fullName: String
    var avatarUrl: String?
    var isActive: Bool
}

struct ProjectRowDTO: Encodable {
    var id: UUID
    var key: String
    var name: String
    var description: String
    var isArchived: Bool
}

struct OwnerRefDTO: Encodable {
    var id: UUID
    var fullName: String
}

struct ProjectDetailDTO: Encodable {
    var id: UUID
    var key: String
    var name: String
    var description: String
    var owner: OwnerRefDTO
    var membersCount: Int
    var tasksCount: Int
    var epicsCount: Int
    var boardsCount: Int
    var isArchived: Bool
}

struct ProjectMemberDataDTO: Encodable {
    var projectId: UUID
    var userId: UUID
    var roleId: UUID
}

struct EpicRowDTO: Encodable {
    var id: UUID
    var projectId: UUID
    var key: String
    var title: String
    var status: String
}

struct EpicDetailDTO: Encodable {
    var id: UUID
    var projectId: UUID
    var key: String
    var title: String
    var description: String
    var status: String
    var progress: Int
    var tasksCount: Int
    var doneTasksCount: Int
}

struct EpicLinkDataDTO: Encodable {
    var epicId: UUID
    var taskId: UUID
}

struct AssigneeRefDTO: Encodable {
    var id: UUID
    var fullName: String
}

struct TaskListRowDTO: Encodable {
    var id: UUID
    var key: String
    var title: String
    var status: String
    var priority: String
    var assignee: AssigneeRefDTO?
    // Included so the mobile Kanban board can label cards with their
    // epic without performing a detail fetch per task (defect 3b).
    var epic: EpicMiniDTO?
    var estimateMinutes: Int
    var spentMinutes: Int
}

struct ProjectMiniDTO: Encodable {
    var id: UUID
    var key: String
    var name: String
}

struct EpicMiniDTO: Encodable {
    var id: UUID
    var key: String
    var title: String
}

struct TaskDetailDTO: Encodable {
    var id: UUID
    var key: String
    var title: String
    var description: String
    var issueType: String
    var priority: String
    var status: String
    var project: ProjectMiniDTO
    var epic: EpicMiniDTO?
    var parentTaskId: UUID?
    var assignee: AssigneeRefDTO?
    var reporter: AssigneeRefDTO
    var estimateMinutes: Int
    var spentMinutes: Int
    var dueDate: Date?
    var subtasksCount: Int
    var commentsCount: Int
}

struct CommentRowDTO: Encodable {
    var id: UUID
    var author: AssigneeRefDTO
    var body: String
    var createdAt: Date?
}

struct TimeEntryRowDTO: Encodable {
    var id: UUID
    var userId: UUID
    var userFullName: String
    var spentMinutes: Int
    var comment: String
    var startedAt: Date
}

struct BoardRowDTO: Encodable {
    var id: UUID
    var projectId: UUID
    var name: String
    var isDefault: Bool
}

struct BoardColumnDTO: Encodable {
    var id: UUID
    var name: String
    var key: String
    var orderIndex: Int
    var wipLimit: Int?
    var isDoneColumn: Bool
}

struct BoardDetailDTO: Encodable {
    var id: UUID
    var projectId: UUID
    var name: String
    var columns: [BoardColumnDTO]
}

struct NotificationRowDTO: Encodable {
    var id: UUID
    var type: String
    var title: String
    var body: String
    var isRead: Bool
    var createdAt: Date?
}

struct SearchHitTaskDTO: Encodable {
    var id: UUID
    var key: String
    var title: String
}

struct SearchDataDTO: Encodable {
    var projects: [ProjectRowDTO]
    var epics: [EpicRowDTO]
    var tasks: [SearchHitTaskDTO]
    var users: [UserRowDTO]
}
