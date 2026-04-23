import Fluent
import Vapor

enum CommentController {
    static func listForTask(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        guard let task = try await WorkTask.find(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: task.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.taskView)
        let list = try await Comment.query(on: req.db).filter(\.$task.$id == tid).with(\.$author).sort(\.$createdAt, .ascending).all()
        let rows: [CommentRowDTO] = list.compactMap { c in
            guard let aid = c.author.id else { return nil }
            return CommentRowDTO(
                id: c.id!,
                author: AssigneeRefDTO(id: aid, fullName: c.author.fullName),
                body: c.body,
                createdAt: c.createdAt
            )
        }
        return try Response.json(envelopeOk(rows, meta: nil))
    }

    static func createForTask(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        let body = try req.content.decode(CommentCreateRequest.self)
        guard body.body.count >= 1 else { throw AppError.validation(["body required"]) }
        guard let task = try await WorkTask.find(tid, on: req.db), !task.isArchived else { throw AppError.notFound("Task not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: task.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.commentCreate)
        let c = Comment(taskID: tid, authorID: uid, body: body.body)
        try await c.save(on: req.db)
        struct Out: Encodable {
            var id: UUID
            var taskId: UUID
            var authorId: UUID
            var body: String
        }
        let dto = Out(id: c.id!, taskId: tid, authorId: uid, body: c.body)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "comment", entityId: c.id!, action: "create")
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }
}
