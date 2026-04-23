import Fluent
import Vapor

enum TaskController {
    static func list(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        try await req.requirePermission(PermissionKey.taskView)
        let q = try req.query.decode(TaskListQuery.self)
        let lq = ListQuery(page: q.page, perPage: q.perPage, sortBy: q.sortBy, sortOrder: q.sortOrder, search: q.search)
        var base = WorkTask.query(on: req.db).filter(\.$isArchived == false)
        if let pid = q.projectId {
            base = base.filter(\.$project.$id == pid)
            guard try await RBACService.canAccessProject(userId: uid, projectId: pid, on: req.db) else { throw AppError.forbidden }
        } else if try await !RBACService.isAdmin(userId: uid, on: req.db) {
            let pids = try await accessibleProjectIds(userId: uid, on: req.db)
            if pids.isEmpty {
                let meta = APIMetaDTO(page: lq.normalizedPage, perPage: lq.normalizedPerPage, total: 0)
                return try Response.json(envelopeOk([TaskListRowDTO](), meta: meta))
            }
            base = base.filter(\.$project.$id ~~ pids)
        }
        if let aid = q.assigneeId { base = base.filter(\.$assignee.$id == aid) }
        if let st = q.status { base = base.filter(\.$status == st) }
        if let eid = q.epicId { base = base.filter(\.$epic.$id == eid) }
        if let s = lq.search, !s.isEmpty {
            let p = "%\(s)%"
            base = base.group(.or) { g in
                g.filter(\.$title, .custom("ILIKE"), p)
                g.filter(\.$key, .custom("ILIKE"), p)
            }
        }
        let total = try await base.count()
        let sortField = lq.sortBy ?? "createdAt"
        let sorted: QueryBuilder<WorkTask> = {
            switch sortField {
            case "priority": return base.sort(\.$priority, lq.ascending ? .ascending : .descending)
            case "status": return base.sort(\.$status, lq.ascending ? .ascending : .descending)
            default: return base.sort(\.$createdAt, lq.ascending ? .ascending : .descending)
            }
        }()
        let tasks = try await lq.applyPagination(to: sorted)
            .with(\.$assignee)
            .with(\.$epic)
            .all()
        var rows: [TaskListRowDTO] = []
        for t in tasks {
            let assignee: AssigneeRefDTO? = t.assignee.flatMap { a in
                guard let id = a.id else { return nil }
                return AssigneeRefDTO(id: id, fullName: a.fullName)
            }
            let epicMini: EpicMiniDTO? = t.epic.flatMap { e in
                guard let id = e.id else { return nil }
                return EpicMiniDTO(id: id, key: e.key, title: e.title)
            }
            rows.append(
                TaskListRowDTO(
                    id: t.id!,
                    key: t.key,
                    title: t.title,
                    status: t.status,
                    priority: t.priority,
                    assignee: assignee,
                    epic: epicMini,
                    estimateMinutes: t.estimateMinutes,
                    spentMinutes: t.spentMinutes
                )
            )
        }
        let meta = APIMetaDTO(page: lq.normalizedPage, perPage: lq.normalizedPerPage, total: total)
        return try Response.json(envelopeOk(rows, meta: meta))
    }

    static func create(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        try await req.requirePermission(PermissionKey.taskCreate)
        let body = try req.content.decode(TaskCreateRequest.self)
        guard try await RBACService.canAccessProject(userId: uid, projectId: body.projectId, on: req.db) else { throw AppError.forbidden }
        guard let project = try await Project.find(body.projectId, on: req.db) else { throw AppError.notFound("Project not found") }
        if let eid = body.epicId {
            guard let epic = try await Epic.find(eid, on: req.db), epic.$project.id == body.projectId else {
                throw AppError.validation(["Invalid epic"])
            }
        }
        if let parent = body.parentTaskId {
            guard let pt = try await WorkTask.find(parent, on: req.db), pt.$project.id == body.projectId else {
                throw AppError.validation(["Invalid parentTask"])
            }
        }
        let num = project.nextTaskNumber
        let key = "\(project.key)-\(num)"
        project.nextTaskNumber += 1
        try await project.save(on: req.db)
        let task = WorkTask(
            projectID: body.projectId,
            epicID: body.epicId,
            parentTaskID: body.parentTaskId,
            key: key,
            title: body.title,
            description: body.description,
            issueType: body.issueType,
            priority: body.priority,
            status: "todo",
            assigneeID: body.assigneeId,
            reporterID: body.reporterId,
            estimateMinutes: body.estimateMinutes,
            spentMinutes: 0,
            dueDate: body.dueDate,
            isArchived: false
        )
        try await task.save(on: req.db)
        if let aid = body.assigneeId {
            try await NotificationService.taskAssigned(taskId: task.id!, taskTitle: task.title, userId: aid, on: req.db)
        }
        try await AuditService.log(db: req.db, actorId: uid, entityType: "task", entityId: task.id!, action: "create")
        struct TaskCreateRes: Encodable {
            var id: UUID
            var key: String
            var projectId: UUID
            var epicId: UUID?
            var parentTaskId: UUID?
            var title: String
            var description: String
            var issueType: String
            var priority: String
            var status: String
            var assigneeId: UUID?
            var reporterId: UUID
            var estimateMinutes: Int
            var spentMinutes: Int
            var dueDate: Date?
            var createdAt: Date?
            var updatedAt: Date?
        }
        let dto = TaskCreateRes(
            id: task.id!,
            key: task.key,
            projectId: task.$project.id,
            epicId: task.$epic.id,
            parentTaskId: task.$parent.id,
            title: task.title,
            description: task.description,
            issueType: task.issueType,
            priority: task.priority,
            status: task.status,
            assigneeId: task.assignee?.id,
            reporterId: task.$reporter.id,
            estimateMinutes: task.estimateMinutes,
            spentMinutes: task.spentMinutes,
            dueDate: task.dueDate,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func get(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        guard let task = try await TaskRepository.findVisible(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: task.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.taskView)
        try await task.$project.load(on: req.db)
        try await task.$epic.load(on: req.db)
        try await task.$assignee.load(on: req.db)
        try await task.$reporter.load(on: req.db)
        let subs = try await WorkTask.query(on: req.db).filter(\.$parent.$id == tid).filter(\.$isArchived == false).count()
        let comments = try await Comment.query(on: req.db).filter(\.$task.$id == tid).count()
        let epicDto: EpicMiniDTO? = task.epic.map { EpicMiniDTO(id: $0.id!, key: $0.key, title: $0.title) }
        let dto = TaskDetailDTO(
            id: task.id!,
            key: task.key,
            title: task.title,
            description: task.description,
            issueType: task.issueType,
            priority: task.priority,
            status: task.status,
            project: ProjectMiniDTO(id: task.project.id!, key: task.project.key, name: task.project.name),
            epic: epicDto,
            parentTaskId: task.$parent.id,
            assignee: task.assignee.map { AssigneeRefDTO(id: $0.id!, fullName: $0.fullName) },
            reporter: AssigneeRefDTO(id: task.reporter.id!, fullName: task.reporter.fullName),
            estimateMinutes: task.estimateMinutes,
            spentMinutes: task.spentMinutes,
            dueDate: task.dueDate,
            subtasksCount: subs,
            commentsCount: comments
        )
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func update(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        guard let task = try await TaskRepository.findVisible(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        try await ensureTaskEdit(userId: uid, task: task, on: req.db)
        let body = try req.content.decode(TaskUpdateRequest.self)
        if let t = body.title { task.title = t }
        if let d = body.description { task.description = d }
        if let p = body.priority { task.priority = p }
        if let dd = body.dueDate { task.dueDate = dd }
        try await task.save(on: req.db)
        struct TPatch: Encodable {
            var id: UUID
            var title: String
            var description: String
            var priority: String
            var dueDate: Date?
        }
        let dto = TPatch(id: task.id!, title: task.title, description: task.description, priority: task.priority, dueDate: task.dueDate)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "task", entityId: tid, action: "update")
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func archive(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        guard let task = try await TaskRepository.findVisible(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: task.$project.id, permission: PermissionKey.taskArchive, on: req.db)
        else { throw AppError.forbidden }
        task.isArchived = true
        task.closedAt = Date()
        try await task.save(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "task", entityId: tid, action: "archive")
        return try Response.json(envelopeOk(MessageData(message: "Task archived"), meta: nil))
    }

    static func assign(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        let body = try req.content.decode(TaskAssignRequest.self)
        guard let task = try await TaskRepository.findVisible(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        guard try await UserRepository.findActive(body.assigneeId, on: req.db) != nil else { throw AppError.notFound("User not found") }
        let canAssignScoped = try await RBACService.canManageProjectScoped(
            userId: uid,
            projectId: task.$project.id,
            permission: PermissionKey.taskAssign,
            on: req.db
        )
        let isCurrentAssignee = task.$assignee.id == uid
        guard canAssignScoped || isCurrentAssignee else { throw AppError.forbidden }
        task.$assignee.id = body.assigneeId
        try await task.save(on: req.db)
        try await NotificationService.taskAssigned(taskId: tid, taskTitle: task.title, userId: body.assigneeId, on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "task", entityId: tid, action: "assign")
        struct A: Encodable { var taskId: UUID; var assigneeId: UUID }
        return try Response.json(envelopeOk(A(taskId: tid, assigneeId: body.assigneeId), meta: nil))
    }

    static func estimate(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        let body = try req.content.decode(TaskEstimateRequest.self)
        guard body.estimateMinutes >= 0 else { throw AppError.validation(["estimateMinutes must be >= 0"]) }
        guard let task = try await TaskRepository.findVisible(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        try await ensureTaskEdit(userId: uid, task: task, on: req.db)
        task.estimateMinutes = body.estimateMinutes
        try await task.save(on: req.db)
        struct E: Encodable { var taskId: UUID; var estimateMinutes: Int }
        try await AuditService.log(db: req.db, actorId: uid, entityType: "task", entityId: tid, action: "estimate")
        return try Response.json(envelopeOk(E(taskId: tid, estimateMinutes: body.estimateMinutes), meta: nil))
    }

    static func status(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        let body = try req.content.decode(TaskStatusRequest.self)
        guard let task = try await TaskRepository.findVisible(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        try await ensureTaskEdit(userId: uid, task: task, on: req.db)
        task.status = body.status
        if body.status == "done" || body.status == "closed" { task.closedAt = Date() }
        try await task.save(on: req.db)
        if let c = body.comment, !c.isEmpty {
            let com = Comment(taskID: tid, authorID: uid, body: c)
            try await com.save(on: req.db)
        }
        struct S: Encodable { var taskId: UUID; var status: String }
        try await AuditService.log(db: req.db, actorId: uid, entityType: "task", entityId: tid, action: "status")
        return try Response.json(envelopeOk(S(taskId: tid, status: body.status), meta: nil))
    }

    static func createSubtask(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        let body = try req.content.decode(SubtaskCreateRequest.self)
        guard let parent = try await WorkTask.find(tid, on: req.db), !parent.isArchived else { throw AppError.notFound("Task not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: parent.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.taskCreate)
        guard let project = try await Project.find(parent.$project.id, on: req.db) else { throw AppError.internalError("Project missing") }
        let num = project.nextTaskNumber
        let key = "\(project.key)-\(num)"
        project.nextTaskNumber += 1
        try await project.save(on: req.db)
        let st = WorkTask(
            projectID: parent.$project.id,
            epicID: parent.$epic.id,
            parentTaskID: tid,
            key: key,
            title: body.title,
            description: body.description ?? "",
            issueType: body.issueType,
            priority: parent.priority,
            status: "todo",
            assigneeID: body.assigneeId,
            reporterID: uid,
            estimateMinutes: body.estimateMinutes ?? 0,
            spentMinutes: 0,
            dueDate: nil,
            isArchived: false
        )
        try await st.save(on: req.db)
        struct SubOut: Encodable {
            var id: UUID
            var parentTaskId: UUID
            var title: String
            var estimateMinutes: Int
        }
        let dto = SubOut(id: st.id!, parentTaskId: tid, title: st.title, estimateMinutes: st.estimateMinutes)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "task", entityId: st.id!, action: "create_subtask")
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func listSubtasks(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let tid = try req.parameters.require("taskId", as: UUID.self)
        guard let parent = try await WorkTask.find(tid, on: req.db) else { throw AppError.notFound("Task not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: parent.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.taskView)
        let subs = try await WorkTask.query(on: req.db).filter(\.$parent.$id == tid).filter(\.$isArchived == false).all()
        struct SubRow: Encodable { var id: UUID; var title: String; var status: String }
        let rows = subs.map { SubRow(id: $0.id!, title: $0.title, status: $0.status) }
        return try Response.json(envelopeOk(rows, meta: nil))
    }

    private static func accessibleProjectIds(userId: UUID, on db: Database) async throws -> [UUID] {
        let m = try await ProjectMember.query(on: db).filter(\.$user.$id == userId).all().map(\.$project.id)
        let o = try await Project.query(on: db).filter(\.$owner.$id == userId).all().map(\.id!)
        return Array(Set(m + o))
    }

    private static func ensureTaskEdit(userId: UUID, task: WorkTask, on db: Database) async throws {
        if try await RBACService.canManageProjectScoped(userId: userId, projectId: task.$project.id, permission: PermissionKey.taskEdit, on: db) {
            return
        }
        if task.$assignee.id == userId, try await RBACService.hasPermission(userId: userId, permission: PermissionKey.taskEdit, on: db) {
            return
        }
        throw AppError.forbidden
    }
}
