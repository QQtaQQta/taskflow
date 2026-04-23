import Fluent
import Vapor

final class WorkTask: Model, Content, @unchecked Sendable {
    static let schema = "tasks"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @OptionalParent(key: "epic_id")
    var epic: Epic?

    @OptionalParent(key: "parent_task_id")
    var parent: WorkTask?

    @Field(key: "key")
    var key: String

    @Field(key: "title")
    var title: String

    @Field(key: "description")
    var description: String

    @Field(key: "issue_type")
    var issueType: String

    @Field(key: "priority")
    var priority: String

    @Field(key: "status")
    var status: String

    @OptionalParent(key: "assignee_id")
    var assignee: User?

    @Parent(key: "reporter_id")
    var reporter: User

    @Field(key: "estimate_minutes")
    var estimateMinutes: Int

    @Field(key: "spent_minutes")
    var spentMinutes: Int

    @OptionalField(key: "due_date")
    var dueDate: Date?

    @Field(key: "is_archived")
    var isArchived: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @OptionalField(key: "closed_at")
    var closedAt: Date?

    @Children(for: \.$parent)
    var subtasks: [WorkTask]

    init() {}

    init(
        id: UUID? = nil,
        projectID: UUID,
        epicID: UUID? = nil,
        parentTaskID: UUID? = nil,
        key: String,
        title: String,
        description: String,
        issueType: String,
        priority: String,
        status: String,
        assigneeID: UUID? = nil,
        reporterID: UUID,
        estimateMinutes: Int,
        spentMinutes: Int = 0,
        dueDate: Date? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.$project.id = projectID
        self.$epic.id = epicID
        self.$parent.id = parentTaskID
        self.key = key
        self.title = title
        self.description = description
        self.issueType = issueType
        self.priority = priority
        self.status = status
        self.$assignee.id = assigneeID
        self.$reporter.id = reporterID
        self.estimateMinutes = estimateMinutes
        self.spentMinutes = spentMinutes
        self.dueDate = dueDate
        self.isArchived = isArchived
    }
}

final class TaskRelation: Model, Content, @unchecked Sendable {
    static let schema = "task_relations"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "from_task_id")
    var fromTask: WorkTask

    @Parent(key: "to_task_id")
    var toTask: WorkTask

    @Field(key: "relation_type")
    var relationType: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, fromTaskID: UUID, toTaskID: UUID, relationType: String) {
        self.id = id
        self.$fromTask.id = fromTaskID
        self.$toTask.id = toTaskID
        self.relationType = relationType
    }
}
