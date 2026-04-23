import Fluent
import JWT
import SQLKit
import Vapor

public func routes(_ app: Application) async throws {
    // Vapor installs RouteLoggingMiddleware and ErrorMiddleware.default the first
    // time `app.middleware` is accessed. The default ErrorMiddleware transforms
    // thrown AbortErrors into a raw `{"error":true,"reason":"..."}` response
    // that does NOT match the mobile client's APIEnvelope<T> contract,
    // which then surfaces as "Ошибка обработки ответа сервера".
    //
    // By appending ErrorEnvelopeMiddleware at the end of the list we position
    // it CLOSER to the route than the default ErrorMiddleware, so our
    // middleware catches every AppError/AbortError first and rewrites it into
    // the contracted envelope before the default middleware is ever invoked.
    app.middleware.use(ErrorEnvelopeMiddleware())

    let v1 = app.grouped("api", "v1")

    v1.get("health") { req async throws -> Response in
        var dbStatus = "disconnected"
        do {
            if let sql = req.db as? any SQLDatabase {
                try await sql.raw("SELECT 1").run()
                dbStatus = "connected"
            }
        } catch {
            dbStatus = "disconnected"
        }
        let data = HealthResponseData(status: "ok", service: "api", database: dbStatus)
        return try Response.json(envelopeOk(data, meta: nil))
    }

    let auth = v1.grouped("auth")
    auth.post("login", use: AuthController.login)
    auth.post("refresh", use: AuthController.refresh)
    let authBearer = auth.grouped(JWTAuthMiddleware())
    authBearer.post("logout", use: AuthController.logout)
    authBearer.get("me", use: AuthController.me)

    let jwt = v1.grouped(JWTAuthMiddleware())

    let roles = jwt.grouped("roles")
    roles.get(use: RoleController.list)
    roles.post(use: RoleController.create)
    roles.group(":roleId") { r in
        r.patch(use: RoleController.update)
        r.delete(use: RoleController.delete)
        r.put("permissions", use: RoleController.replacePermissions)
    }

    let users = jwt.grouped("users")
    users.get(use: UserController.list)
    users.post(use: UserController.create)
    users.group(":userId") { u in
        u.get(use: UserController.get)
        u.patch(use: UserController.update)
        u.delete(use: UserController.delete)
    }

    let projects = jwt.grouped("projects")
    projects.get(use: ProjectController.list)
    projects.post(use: ProjectController.create)
    projects.group(":projectId") { p in
        p.get(use: ProjectController.get)
        p.patch(use: ProjectController.update)
        p.delete(use: ProjectController.archive)
        p.post("members", use: ProjectController.addMember)
        p.delete("members", ":memberUserId", use: ProjectController.removeMember)
        p.get("epics", use: EpicController.listForProject)
        p.post("epics", use: EpicController.createForProject)
    }

    jwt.get("epics", ":epicId", use: EpicController.get)
    jwt.patch("epics", ":epicId", use: EpicController.update)
    jwt.delete("epics", ":epicId", use: EpicController.archive)
    jwt.post("epics", ":epicId", "tasks", ":taskId", use: EpicController.linkTask)
    jwt.delete("epics", ":epicId", "tasks", ":taskId", use: EpicController.unlinkTask)

    let tasks = jwt.grouped("tasks")
    tasks.get(use: TaskController.list)
    tasks.post(use: TaskController.create)
    tasks.group(":taskId") { t in
        t.get(use: TaskController.get)
        t.patch(use: TaskController.update)
        t.delete(use: TaskController.archive)
        t.post("assign", use: TaskController.assign)
        t.post("estimate", use: TaskController.estimate)
        t.post("status", use: TaskController.status)
        t.post("subtasks", use: TaskController.createSubtask)
        t.get("subtasks", use: TaskController.listSubtasks)
        t.get("comments", use: CommentController.listForTask)
        t.post("comments", use: CommentController.createForTask)
        t.get("time-entries", use: TimeEntryController.listForTask)
        t.post("time-entries", use: TimeEntryController.createForTask)
    }

    jwt.patch("time-entries", ":timeEntryId", use: TimeEntryController.update)
    jwt.delete("time-entries", ":timeEntryId", use: TimeEntryController.delete)

    let boards = jwt.grouped("boards")
    boards.get(use: BoardController.list)
    boards.post(use: BoardController.create)
    boards.group(":boardId") { b in
        b.get(use: BoardController.get)
        b.patch(use: BoardController.update)
        b.delete(use: BoardController.archive)
        b.get("columns", use: BoardController.listColumns)
        b.post("columns", use: BoardController.createColumn)
        b.post("tasks", ":taskId", "move", use: BoardController.moveTask)
        b.post("tasks", ":taskId", "reorder", use: BoardController.reorderTask)
    }

    jwt.patch("columns", ":columnId", use: BoardController.updateColumn)
    jwt.delete("columns", ":columnId", use: BoardController.deleteColumn)

    jwt.get("notifications", use: NotificationController.list)
    jwt.patch("notifications", ":notificationId", "read", use: NotificationController.markRead)
    jwt.post("notifications", "read-all", use: NotificationController.readAll)

    jwt.get("search", use: SearchController.search)
}

struct HealthResponseData: Encodable {
    var status: String
    var service: String
    var database: String
}
