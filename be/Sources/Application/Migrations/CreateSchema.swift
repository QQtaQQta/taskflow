import Fluent
import SQLKit

struct CreateSchema: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Role.schema)
            .id()
            .field("name", .string, .required)
            .field("description", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "name")
            .create()

        try await database.schema(Permission.schema)
            .id()
            .field("key", .string, .required)
            .field("description", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "key")
            .create()

        try await database.schema(RolePermission.schema)
            .id()
            .field("role_id", .uuid, .required, .references(Role.schema, .id, onDelete: .cascade))
            .field("permission_id", .uuid, .required, .references(Permission.schema, .id, onDelete: .cascade))
            .unique(on: "role_id", "permission_id")
            .create()

        try await database.schema(User.schema)
            .id()
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("full_name", .string, .required)
            .field("avatar_url", .string)
            .field("role_id", .uuid, .required, .references(Role.schema, .id, onDelete: .restrict))
            .field("is_active", .bool, .required)
            .field("deleted_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        if let sql = database as? SQLDatabase {
            try await sql.raw(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_active
                ON \(unsafeRaw: User.schema) (email) WHERE deleted_at IS NULL
                """
            ).run()
        }

        try await database.schema(RefreshToken.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("jti", .uuid, .required)
            .field("expires_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "jti")
            .create()

        try await database.schema(Project.schema)
            .id()
            .field("key", .string, .required)
            .field("name", .string, .required)
            .field("description", .string, .required)
            .field("owner_id", .uuid, .required, .references(User.schema, .id, onDelete: .restrict))
            .field("is_archived", .bool, .required)
            .field("next_epic_number", .int, .required)
            .field("next_task_number", .int, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "key")
            .create()

        try await database.schema(ProjectMember.schema)
            .id()
            .field("project_id", .uuid, .required, .references(Project.schema, .id, onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("role_id", .uuid, .required, .references(Role.schema, .id, onDelete: .restrict))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "project_id", "user_id")
            .create()

        try await database.schema(Epic.schema)
            .id()
            .field("project_id", .uuid, .required, .references(Project.schema, .id, onDelete: .cascade))
            .field("key", .string, .required)
            .field("title", .string, .required)
            .field("description", .string, .required)
            .field("status", .string, .required)
            .field("start_date", .datetime)
            .field("due_date", .datetime)
            .field("is_archived", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(WorkTask.schema)
            .id()
            .field("project_id", .uuid, .required, .references(Project.schema, .id, onDelete: .cascade))
            .field("epic_id", .uuid, .references(Epic.schema, .id, onDelete: .setNull))
            .field("parent_task_id", .uuid, .references(WorkTask.schema, .id, onDelete: .setNull))
            .field("key", .string, .required)
            .field("title", .string, .required)
            .field("description", .string, .required)
            .field("issue_type", .string, .required)
            .field("priority", .string, .required)
            .field("status", .string, .required)
            .field("assignee_id", .uuid, .references(User.schema, .id, onDelete: .setNull))
            .field("reporter_id", .uuid, .required, .references(User.schema, .id, onDelete: .restrict))
            .field("estimate_minutes", .int, .required)
            .field("spent_minutes", .int, .required)
            .field("due_date", .datetime)
            .field("is_archived", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("closed_at", .datetime)
            .create()

        try await database.schema(TaskRelation.schema)
            .id()
            .field("from_task_id", .uuid, .required, .references(WorkTask.schema, .id, onDelete: .cascade))
            .field("to_task_id", .uuid, .required, .references(WorkTask.schema, .id, onDelete: .cascade))
            .field("relation_type", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(Board.schema)
            .id()
            .field("project_id", .uuid, .required, .references(Project.schema, .id, onDelete: .cascade))
            .field("name", .string, .required)
            .field("description", .string, .required)
            .field("is_default", .bool, .required)
            .field("is_archived", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(BoardColumn.schema)
            .id()
            .field("board_id", .uuid, .required, .references(Board.schema, .id, onDelete: .cascade))
            .field("name", .string, .required)
            .field("key", .string, .required)
            .field("order_index", .int, .required)
            .field("wip_limit", .int)
            .field("is_done_column", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(BoardTaskState.schema)
            .id()
            .field("board_id", .uuid, .required, .references(Board.schema, .id, onDelete: .cascade))
            .field("task_id", .uuid, .required, .references(WorkTask.schema, .id, onDelete: .cascade))
            .field("board_column_id", .uuid, .required, .references(BoardColumn.schema, .id, onDelete: .cascade))
            .field("order_index", .int, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "board_id", "task_id")
            .create()

        try await database.schema(Comment.schema)
            .id()
            .field("task_id", .uuid, .required, .references(WorkTask.schema, .id, onDelete: .cascade))
            .field("author_id", .uuid, .required, .references(User.schema, .id, onDelete: .restrict))
            .field("body", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(TimeEntry.schema)
            .id()
            .field("task_id", .uuid, .required, .references(WorkTask.schema, .id, onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .restrict))
            .field("spent_minutes", .int, .required)
            .field("comment", .string, .required)
            .field("started_at", .datetime, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(UserNotification.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("type", .string, .required)
            .field("title", .string, .required)
            .field("body", .string, .required)
            .field("entity_type", .string)
            .field("entity_id", .uuid)
            .field("is_read", .bool, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(AuditLog.schema)
            .id()
            .field("actor_id", .uuid, .references(User.schema, .id, onDelete: .setNull))
            .field("entity_type", .string, .required)
            .field("entity_id", .uuid, .required)
            .field("action", .string, .required)
            .field("before_json", .string)
            .field("after_json", .string)
            .field("created_at", .datetime)
            .create()

        try await database.schema(Attachment.schema)
            .id()
            .field("task_id", .uuid, .required, .references(WorkTask.schema, .id, onDelete: .cascade))
            .field("uploaded_by_id", .uuid, .required, .references(User.schema, .id, onDelete: .restrict))
            .field("file_name", .string, .required)
            .field("file_url", .string, .required)
            .field("mime_type", .string, .required)
            .field("file_size", .int, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        if let sql = database as? SQLDatabase {
            try await sql.raw(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS epic_key_per_project ON \(unsafeRaw: Epic.schema) (project_id, key)
                """
            ).run()
            try await sql.raw(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS task_key_per_project ON \(unsafeRaw: WorkTask.schema) (project_id, key)
                """
            ).run()
            try await sql.raw(
                """
                CREATE INDEX IF NOT EXISTS idx_tasks_project ON \(unsafeRaw: WorkTask.schema) (project_id)
                """
            ).run()
            try await sql.raw(
                """
                CREATE INDEX IF NOT EXISTS idx_tasks_epic ON \(unsafeRaw: WorkTask.schema) (epic_id)
                """
            ).run()
            try await sql.raw(
                """
                CREATE INDEX IF NOT EXISTS idx_tasks_assignee ON \(unsafeRaw: WorkTask.schema) (assignee_id)
                """
            ).run()
            try await sql.raw(
                """
                CREATE INDEX IF NOT EXISTS idx_tasks_status ON \(unsafeRaw: WorkTask.schema) (status)
                """
            ).run()
            try await sql.raw(
                """
                CREATE INDEX IF NOT EXISTS idx_boards_project ON \(unsafeRaw: Board.schema) (project_id)
                """
            ).run()
            try await sql.raw(
                """
                CREATE INDEX IF NOT EXISTS idx_board_columns_board ON \(unsafeRaw: BoardColumn.schema) (board_id)
                """
            ).run()
            try await sql.raw(
                """
                CREATE INDEX IF NOT EXISTS idx_board_task_state_lookup ON \(unsafeRaw: BoardTaskState.schema) (board_id, task_id, board_column_id)
                """
            ).run()
            try await sql.raw(
                """
                CREATE INDEX IF NOT EXISTS idx_time_entries_task ON \(unsafeRaw: TimeEntry.schema) (task_id)
                """
            ).run()
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema(Attachment.schema).delete()
        try await database.schema(AuditLog.schema).delete()
        try await database.schema(UserNotification.schema).delete()
        try await database.schema(TimeEntry.schema).delete()
        try await database.schema(Comment.schema).delete()
        try await database.schema(BoardTaskState.schema).delete()
        try await database.schema(BoardColumn.schema).delete()
        try await database.schema(Board.schema).delete()
        try await database.schema(TaskRelation.schema).delete()
        try await database.schema(WorkTask.schema).delete()
        try await database.schema(Epic.schema).delete()
        try await database.schema(ProjectMember.schema).delete()
        try await database.schema(Project.schema).delete()
        try await database.schema(RefreshToken.schema).delete()
        if let sql = database as? SQLDatabase {
            try await sql.raw("DROP INDEX IF EXISTS users_email_unique_active").run()
            try await sql.raw("DROP INDEX IF EXISTS epic_key_per_project").run()
            try await sql.raw("DROP INDEX IF EXISTS task_key_per_project").run()
            try await sql.raw("DROP INDEX IF EXISTS idx_tasks_project").run()
            try await sql.raw("DROP INDEX IF EXISTS idx_tasks_epic").run()
            try await sql.raw("DROP INDEX IF EXISTS idx_tasks_assignee").run()
            try await sql.raw("DROP INDEX IF EXISTS idx_tasks_status").run()
            try await sql.raw("DROP INDEX IF EXISTS idx_boards_project").run()
            try await sql.raw("DROP INDEX IF EXISTS idx_board_columns_board").run()
            try await sql.raw("DROP INDEX IF EXISTS idx_board_task_state_lookup").run()
            try await sql.raw("DROP INDEX IF EXISTS idx_time_entries_task").run()
        }
        try await database.schema(User.schema).delete()
        try await database.schema(RolePermission.schema).delete()
        try await database.schema(Permission.schema).delete()
        try await database.schema(Role.schema).delete()
    }
}
