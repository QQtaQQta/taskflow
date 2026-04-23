import Fluent
import Vapor

enum NotificationService {
    static func taskAssigned(taskId: UUID, taskTitle: String, userId: UUID, on db: Database) async throws {
        let n = UserNotification(
            userID: userId,
            type: "task_assigned",
            title: "You were assigned a task",
            body: taskTitle,
            entityType: "task",
            entityId: taskId,
            isRead: false
        )
        try await n.save(on: db)
    }
}
