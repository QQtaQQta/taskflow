import Foundation

enum PermissionKey {
    static let projectCreate = "project.create"
    static let projectView = "project.view"
    static let projectEdit = "project.edit"
    static let projectArchive = "project.archive"
    static let projectMembersManage = "project.members.manage"

    static let epicCreate = "epic.create"
    static let epicView = "epic.view"
    static let epicEdit = "epic.edit"
    static let epicArchive = "epic.archive"

    static let taskCreate = "task.create"
    static let taskView = "task.view"
    static let taskEdit = "task.edit"
    static let taskAssign = "task.assign"
    static let taskArchive = "task.archive"
    static let taskStatus = "task.status"

    static let commentCreate = "comment.create"
    static let timeLog = "time.log"

    static let boardView = "board.view"
    static let boardCreate = "board.create"
    static let boardEdit = "board.edit"
    static let boardMove = "board.move"

    static let userManage = "user.manage"
    static let roleManage = "role.manage"

    static let all: [String] = [
        projectCreate, projectView, projectEdit, projectArchive, projectMembersManage,
        epicCreate, epicView, epicEdit, epicArchive,
        taskCreate, taskView, taskEdit, taskAssign, taskArchive, taskStatus,
        commentCreate, timeLog,
        boardView, boardCreate, boardEdit, boardMove,
        userManage, roleManage,
    ]
}

enum RoleName {
    static let admin = "admin"
    static let manager = "manager"
    static let assignee = "assignee"
    static let viewer = "viewer"
}
