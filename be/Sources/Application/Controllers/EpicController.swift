import Fluent
import Vapor

enum EpicController {
    static func listForProject(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let pid = try req.parameters.require("projectId", as: UUID.self)
        guard try await RBACService.canAccessProject(userId: uid, projectId: pid, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.epicView)
        let q = try req.query.decode(EpicListQuery.self)
        let lq = ListQuery(page: q.page, perPage: q.perPage, sortBy: q.sortBy, sortOrder: q.sortOrder, search: q.search)
        var base = Epic.query(on: req.db).filter(\.$project.$id == pid).filter(\.$isArchived == false)
        if let s = lq.search, !s.isEmpty {
            let p = "%\(s)%"
            base = base.group(.or) { g in
                g.filter(\.$title, .custom("ILIKE"), p)
                g.filter(\.$key, .custom("ILIKE"), p)
            }
        }
        let total = try await base.count()
        let items = try await lq.applyPagination(to: base.sort(\.$createdAt, .descending)).all()
        let rows = items.map { EpicRowDTO(id: $0.id!, projectId: pid, key: $0.key, title: $0.title, status: $0.status) }
        let meta = APIMetaDTO(page: lq.normalizedPage, perPage: lq.normalizedPerPage, total: total)
        return try Response.json(envelopeOk(rows, meta: meta))
    }

    static func createForProject(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let pid = try req.parameters.require("projectId", as: UUID.self)
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: pid, permission: PermissionKey.epicCreate, on: req.db)
        else { throw AppError.forbidden }
        guard let project = try await Project.find(pid, on: req.db) else { throw AppError.notFound("Project not found") }
        let body = try req.content.decode(EpicCreateRequest.self)
        let key = body.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if try await Epic.query(on: req.db).filter(\.$project.$id == pid).filter(\.$key == key).first() != nil {
            throw AppError.conflict("Epic key exists in project")
        }
        let epic = Epic(
            projectID: pid,
            key: key,
            title: body.title,
            description: body.description,
            status: "open",
            startDate: body.startDate,
            dueDate: body.dueDate,
            isArchived: false
        )
        try await epic.save(on: req.db)
        project.nextEpicNumber += 1
        try await project.save(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "epic", entityId: epic.id!, action: "create")
        struct EpicCreateData: Encodable {
            var id: UUID
            var projectId: UUID
            var key: String
            var title: String
            var description: String
            var status: String
            var startDate: Date?
            var dueDate: Date?
        }
        let dto = EpicCreateData(
            id: epic.id!,
            projectId: pid,
            key: epic.key,
            title: epic.title,
            description: epic.description,
            status: epic.status,
            startDate: epic.startDate,
            dueDate: epic.dueDate
        )
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func get(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let eid = try req.parameters.require("epicId", as: UUID.self)
        guard let epic = try await Epic.find(eid, on: req.db), !epic.isArchived else { throw AppError.notFound("Epic not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: epic.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.epicView)
        let tasks = try await WorkTask.query(on: req.db).filter(\.$epic.$id == eid).filter(\.$isArchived == false).all()
        let total = tasks.count
        let done = tasks.filter { $0.status == "done" || $0.status == "closed" }.count
        let progress = total == 0 ? 0 : Int((Double(done) / Double(total)) * 100)
        let dto = EpicDetailDTO(
            id: epic.id!,
            projectId: epic.$project.id,
            key: epic.key,
            title: epic.title,
            description: epic.description,
            status: epic.status,
            progress: progress,
            tasksCount: total,
            doneTasksCount: done
        )
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func update(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let eid = try req.parameters.require("epicId", as: UUID.self)
        guard let epic = try await Epic.find(eid, on: req.db), !epic.isArchived else { throw AppError.notFound("Epic not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: epic.$project.id, permission: PermissionKey.epicEdit, on: req.db)
        else { throw AppError.forbidden }
        let body = try req.content.decode(EpicUpdateRequest.self)
        if let newProjectId = body.projectId, newProjectId != epic.$project.id {
            guard try await Project.find(newProjectId, on: req.db) != nil else {
                throw AppError.validation(["Invalid projectId"])
            }
            guard try await RBACService.canManageProjectScoped(
                userId: uid,
                projectId: newProjectId,
                permission: PermissionKey.epicEdit,
                on: req.db
            ) else {
                throw AppError.forbidden
            }
            epic.$project.id = newProjectId
        }
        if let t = body.title { epic.title = t }
        if let d = body.description { epic.description = d }
        if let s = body.status { epic.status = s }
        if let sd = body.startDate { epic.startDate = sd }
        if let dd = body.dueDate { epic.dueDate = dd }
        try await epic.save(on: req.db)
        struct EpicPatch: Encodable {
            var id: UUID
            var title: String
            var status: String
        }
        let dto = EpicPatch(id: epic.id!, title: epic.title, status: epic.status)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "epic", entityId: eid, action: "update")
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func archive(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let eid = try req.parameters.require("epicId", as: UUID.self)
        guard let epic = try await Epic.find(eid, on: req.db), !epic.isArchived else { throw AppError.notFound("Epic not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: epic.$project.id, permission: PermissionKey.epicArchive, on: req.db)
        else { throw AppError.forbidden }
        try await epic.delete(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "epic", entityId: eid, action: "delete")
        return try Response.json(envelopeOk(MessageData(message: "Epic deleted"), meta: nil))
    }

    static func linkTask(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let eid = try req.parameters.require("epicId", as: UUID.self)
        let tid = try req.parameters.require("taskId", as: UUID.self)
        guard let epic = try await Epic.find(eid, on: req.db), !epic.isArchived else { throw AppError.notFound("Epic not found") }
        guard let task = try await WorkTask.find(tid, on: req.db), !task.isArchived else { throw AppError.notFound("Task not found") }
        guard task.$project.id == epic.$project.id else { throw AppError.validation(["Task must belong to same project"]) }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: epic.$project.id, permission: PermissionKey.taskEdit, on: req.db)
        else { throw AppError.forbidden }
        task.$epic.id = eid
        try await task.save(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "task", entityId: tid, action: "link_epic")
        return try Response.json(envelopeOk(EpicLinkDataDTO(epicId: eid, taskId: tid), meta: nil))
    }

    static func unlinkTask(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let eid = try req.parameters.require("epicId", as: UUID.self)
        let tid = try req.parameters.require("taskId", as: UUID.self)
        guard let epic = try await Epic.find(eid, on: req.db) else { throw AppError.notFound("Epic not found") }
        guard let task = try await WorkTask.find(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        guard task.$epic.id == eid else { throw AppError.validation(["Task not linked to epic"]) }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: epic.$project.id, permission: PermissionKey.taskEdit, on: req.db)
        else { throw AppError.forbidden }
        task.$epic.id = nil
        try await task.save(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "task", entityId: tid, action: "unlink_epic")
        return try Response.json(envelopeOk(MessageData(message: "Task unlinked from epic"), meta: nil))
    }
}
