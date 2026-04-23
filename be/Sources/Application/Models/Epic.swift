import Fluent
import Vapor

final class Epic: Model, Content, @unchecked Sendable {
    static let schema = "epics"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Field(key: "key")
    var key: String

    @Field(key: "title")
    var title: String

    @Field(key: "description")
    var description: String

    @Field(key: "status")
    var status: String

    @OptionalField(key: "start_date")
    var startDate: Date?

    @OptionalField(key: "due_date")
    var dueDate: Date?

    @Field(key: "is_archived")
    var isArchived: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        projectID: UUID,
        key: String,
        title: String,
        description: String,
        status: String = "open",
        startDate: Date? = nil,
        dueDate: Date? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.$project.id = projectID
        self.key = key
        self.title = title
        self.description = description
        self.status = status
        self.startDate = startDate
        self.dueDate = dueDate
        self.isArchived = isArchived
    }
}
