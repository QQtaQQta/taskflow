import Fluent
import Vapor

final class Project: Model, Content, @unchecked Sendable {
    static let schema = "projects"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "key")
    var key: String

    @Field(key: "name")
    var name: String

    @Field(key: "description")
    var description: String

    @Parent(key: "owner_id")
    var owner: User

    @Field(key: "is_archived")
    var isArchived: Bool

    @Field(key: "next_epic_number")
    var nextEpicNumber: Int

    @Field(key: "next_task_number")
    var nextTaskNumber: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$project)
    var members: [ProjectMember]

    init() {}

    init(
        id: UUID? = nil,
        key: String,
        name: String,
        description: String,
        ownerID: UUID,
        isArchived: Bool = false,
        nextEpicNumber: Int = 1,
        nextTaskNumber: Int = 1
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.description = description
        self.$owner.id = ownerID
        self.isArchived = isArchived
        self.nextEpicNumber = nextEpicNumber
        self.nextTaskNumber = nextTaskNumber
    }
}

final class ProjectMember: Model, Content, @unchecked Sendable {
    static let schema = "project_members"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Parent(key: "user_id")
    var user: User

    @Parent(key: "role_id")
    var role: Role

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, projectID: UUID, userID: UUID, roleID: UUID) {
        self.id = id
        self.$project.id = projectID
        self.$user.id = userID
        self.$role.id = roleID
    }
}
