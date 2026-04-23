import Fluent
import Vapor

final class Comment: Model, Content, @unchecked Sendable {
    static let schema = "comments"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "task_id")
    var task: WorkTask

    @Parent(key: "author_id")
    var author: User

    @Field(key: "body")
    var body: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, taskID: UUID, authorID: UUID, body: String) {
        self.id = id
        self.$task.id = taskID
        self.$author.id = authorID
        self.body = body
    }
}
