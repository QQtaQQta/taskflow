import Fluent
import Vapor

final class AuditLog: Model, Content, @unchecked Sendable {
    static let schema = "audit_logs"

    @ID(key: .id)
    var id: UUID?

    @OptionalParent(key: "actor_id")
    var actor: User?

    @Field(key: "entity_type")
    var entityType: String

    @Field(key: "entity_id")
    var entityId: UUID

    @Field(key: "action")
    var action: String

    @OptionalField(key: "before_json")
    var beforeJson: String?

    @OptionalField(key: "after_json")
    var afterJson: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        actorID: UUID?,
        entityType: String,
        entityId: UUID,
        action: String,
        beforeJson: String? = nil,
        afterJson: String? = nil
    ) {
        self.id = id
        self.$actor.id = actorID
        self.entityType = entityType
        self.entityId = entityId
        self.action = action
        self.beforeJson = beforeJson
        self.afterJson = afterJson
    }
}
