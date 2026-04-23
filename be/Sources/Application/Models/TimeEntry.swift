import Fluent
import Vapor

final class TimeEntry: Model, Content, @unchecked Sendable {
    static let schema = "time_entries"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "task_id")
    var task: WorkTask

    @Parent(key: "user_id")
    var user: User

    @Field(key: "spent_minutes")
    var spentMinutes: Int

    @Field(key: "comment")
    var comment: String

    @Field(key: "started_at")
    var startedAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        taskID: UUID,
        userID: UUID,
        spentMinutes: Int,
        comment: String,
        startedAt: Date
    ) {
        self.id = id
        self.$task.id = taskID
        self.$user.id = userID
        self.spentMinutes = spentMinutes
        self.comment = comment
        self.startedAt = startedAt
    }
}
