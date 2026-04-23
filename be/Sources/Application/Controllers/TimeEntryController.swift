import Fluent
import Vapor

enum TimeEntryController {
    static func listForTask(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        guard let task = try await WorkTask.find(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: task.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.taskView)
        let list = try await TimeEntry.query(on: req.db)
            .filter(\.$task.$id == tid)
            .sort(\.$startedAt, .descending)
            .with(\.$user)
            .all()
        let rows = list.map {
            TimeEntryRowDTO(
                id: $0.id!,
                userId: $0.$user.id,
                userFullName: $0.user.fullName,
                spentMinutes: $0.spentMinutes,
                comment: $0.comment,
                startedAt: $0.startedAt
            )
        }
        return try Response.json(envelopeOk(rows, meta: nil))
    }

    static func createForTask(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        let body = try req.content.decode(TimeEntryCreateRequest.self)
        guard body.spentMinutes > 0 else { throw AppError.validation(["spentMinutes must be positive"]) }
        guard body.spentMinutes <= 24 * 60 else { throw AppError.validation(["spentMinutes must be <= 1440"]) }
        guard let task = try await WorkTask.find(tid, on: req.db), !task.isArchived else { throw AppError.notFound("Task not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: task.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.timeLog)
        let e = TimeEntry(taskID: tid, userID: uid, spentMinutes: body.spentMinutes, comment: body.comment, startedAt: body.startedAt)
        try await e.save(on: req.db)
        try await resyncSpent(tid, on: req.db)
        let author = try await User.find(uid, on: req.db)
        struct Out: Encodable {
            var id: UUID
            var taskId: UUID
            var userId: UUID
            var userFullName: String
            var spentMinutes: Int
            var comment: String
            var startedAt: Date
        }
        let dto = Out(
            id: e.id!,
            taskId: tid,
            userId: uid,
            userFullName: author?.fullName ?? "",
            spentMinutes: e.spentMinutes,
            comment: e.comment,
            startedAt: e.startedAt
        )
        try await AuditService.log(db: req.db, actorId: uid, entityType: "time_entry", entityId: e.id!, action: "create")
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func update(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let eid = try req.parameters.require("timeEntryId", as: UUID.self)
        let body = try req.content.decode(TimeEntryUpdateRequest.self)
        guard let entry = try await TimeEntry.find(eid, on: req.db) else { throw AppError.notFound("Time entry not found") }
        let adminUser = try await RBACService.isAdmin(userId: uid, on: req.db)
        guard entry.$user.id == uid || adminUser else { throw AppError.forbidden }
        if let m = body.spentMinutes { entry.spentMinutes = m }
        if let c = body.comment { entry.comment = c }
        try await entry.save(on: req.db)
        try await resyncSpent(entry.$task.id, on: req.db)
        struct Out: Encodable { var id: UUID; var spentMinutes: Int; var comment: String }
        let dto = Out(id: eid, spentMinutes: entry.spentMinutes, comment: entry.comment)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "time_entry", entityId: eid, action: "update")
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func delete(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let eid = try req.parameters.require("timeEntryId", as: UUID.self)
        guard let entry = try await TimeEntry.find(eid, on: req.db) else { throw AppError.notFound("Time entry not found") }
        let adminUser = try await RBACService.isAdmin(userId: uid, on: req.db)
        guard entry.$user.id == uid || adminUser else { throw AppError.forbidden }
        let tid = entry.$task.id
        try await entry.delete(on: req.db)
        try await resyncSpent(tid, on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "time_entry", entityId: eid, action: "delete")
        return try Response.json(envelopeOk(MessageData(message: "Time entry deleted"), meta: nil))
    }

    private static func resyncSpent(_ taskId: UUID, on db: Database) async throws {
        let entries = try await TimeEntry.query(on: db).filter(\.$task.$id == taskId).all()
        let sum = entries.reduce(0) { $0 + $1.spentMinutes }
        guard let task = try await WorkTask.find(taskId, on: db) else { return }
        task.spentMinutes = sum
        try await task.save(on: db)
    }
}
