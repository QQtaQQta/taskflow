import Fluent
import Vapor

final class UserNotification: Model, Content, @unchecked Sendable {
    static let schema = "notifications"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "type")
    var type: String

    @Field(key: "title")
    var title: String

    @Field(key: "body")
    var body: String

    @OptionalField(key: "entity_type")
    var entityType: String?

    @OptionalField(key: "entity_id")
    var entityId: UUID?

    @Field(key: "is_read")
    var isRead: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        type: String,
        title: String,
        body: String,
        entityType: String? = nil,
        entityId: UUID? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.$user.id = userID
        self.type = type
        self.title = title
        self.body = body
        self.entityType = entityType
        self.entityId = entityId
        self.isRead = isRead
    }
}
