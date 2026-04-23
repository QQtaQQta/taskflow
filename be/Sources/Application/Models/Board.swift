import Fluent
import Vapor

final class Board: Model, Content, @unchecked Sendable {
    static let schema = "boards"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "project_id")
    var project: Project

    @Field(key: "name")
    var name: String

    @Field(key: "description")
    var description: String

    @Field(key: "is_default")
    var isDefault: Bool

    @Field(key: "is_archived")
    var isArchived: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$board)
    var columns: [BoardColumn]

    init() {}

    init(
        id: UUID? = nil,
        projectID: UUID,
        name: String,
        description: String,
        isDefault: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.$project.id = projectID
        self.name = name
        self.description = description
        self.isDefault = isDefault
        self.isArchived = isArchived
    }
}

final class BoardColumn: Model, Content, @unchecked Sendable {
    static let schema = "board_columns"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "board_id")
    var board: Board

    @Field(key: "name")
    var name: String

    @Field(key: "key")
    var key: String

    @Field(key: "order_index")
    var orderIndex: Int

    @OptionalField(key: "wip_limit")
    var wipLimit: Int?

    @Field(key: "is_done_column")
    var isDoneColumn: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        boardID: UUID,
        name: String,
        key: String,
        orderIndex: Int,
        wipLimit: Int? = nil,
        isDoneColumn: Bool = false
    ) {
        self.id = id
        self.$board.id = boardID
        self.name = name
        self.key = key
        self.orderIndex = orderIndex
        self.wipLimit = wipLimit
        self.isDoneColumn = isDoneColumn
    }
}

final class BoardTaskState: Model, Content, @unchecked Sendable {
    static let schema = "board_task_states"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "board_id")
    var board: Board

    @Parent(key: "task_id")
    var task: WorkTask

    @Parent(key: "board_column_id")
    var column: BoardColumn

    @Field(key: "order_index")
    var orderIndex: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        boardID: UUID,
        taskID: UUID,
        boardColumnID: UUID,
        orderIndex: Int
    ) {
        self.id = id
        self.$board.id = boardID
        self.$task.id = taskID
        self.$column.id = boardColumnID
        self.orderIndex = orderIndex
    }
}
