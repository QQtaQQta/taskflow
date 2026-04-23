import Fluent
import Vapor

enum ProjectController {
    static func list(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        try await req.requirePermission(PermissionKey.projectView)
        let q = try req.query.decode(ProjectListQuery.self)
        let lq = ListQuery(page: q.page, perPage: q.perPage, sortBy: q.sortBy, sortOrder: q.sortOrder, search: q.search)
        var base = Project.query(on: req.db).filter(\.$isArchived == false)
        if try await !RBACService.isAdmin(userId: uid, on: req.db) {
            let pids = try await ProjectMember.query(on: req.db).filter(\.$user.$id == uid).all().map(\.$project.id)
            let owned = try await Project.query(on: req.db).filter(\.$owner.$id == uid).all().map(\.id!)
            let ids = Array(Set(pids + owned))
            if ids.isEmpty {
                let meta = APIMetaDTO(page: lq.normalizedPage, perPage: lq.normalizedPerPage, total: 0)
                return try Response.json(envelopeOk([ProjectRowDTO](), meta: meta))
            }
            base = base.filter(\.$id ~~ ids)
        }
        if let s = lq.search, !s.isEmpty {
            let p = "%\(s)%"
            base = base.group(.or) { g in
                g.filter(\.$name, .custom("ILIKE"), p)
                g.filter(\.$key, .custom("ILIKE"), p)
            }
        }
        let total = try await base.count()
        let sorted = base.sort(\.$name, lq.ascending ? .ascending : .descending)
        let projects = try await lq.applyPagination(to: sorted).all()
        let rows = projects.map {
            ProjectRowDTO(id: $0.id!, key: $0.key, name: $0.name, description: $0.description, isArchived: $0.isArchived)
        }
        let meta = APIMetaDTO(page: lq.normalizedPage, perPage: lq.normalizedPerPage, total: total)
        return try Response.json(envelopeOk(rows, meta: meta))
    }

    static func create(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        try await req.requirePermission(PermissionKey.projectCreate)
        let body = try req.content.decode(ProjectCreateRequest.self)
        let key = body.key.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 2, key.count <= 16 else { throw AppError.validation(["Invalid project key"]) }
        if try await Project.query(on: req.db).filter(\.$key == key).first() != nil {
            throw AppError.conflict("Project key exists")
        }
        let p = Project(key: key, name: body.name, description: body.description, ownerID: uid)
        try await p.save(on: req.db)
        let member = ProjectMember(projectID: p.id!, userID: uid, roleID: try await defaultManagerRoleId(on: req.db))
        try await member.save(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "project", entityId: p.id!, action: "create")
        let dto = ProjectRowDTO(id: p.id!, key: p.key, name: p.name, description: p.description, isArchived: p.isArchived)
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func get(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let pid = try req.parameters.require("projectId", as: UUID.self)
        guard try await RBACService.canAccessProject(userId: uid, projectId: pid, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.projectView)
        guard let p = try await Project.find(pid, on: req.db) else { throw AppError.notFound("Project not found") }
        try await p.$owner.load(on: req.db)
        let members = try await ProjectMember.query(on: req.db).filter(\.$project.$id == pid).count()
        let tasks = try await WorkTask.query(on: req.db).filter(\.$project.$id == pid).filter(\.$isArchived == false).count()
        let epics = try await Epic.query(on: req.db).filter(\.$project.$id == pid).filter(\.$isArchived == false).count()
        let boards = try await Board.query(on: req.db).filter(\.$project.$id == pid).filter(\.$isArchived == false).count()
        let dto = ProjectDetailDTO(
            id: p.id!,
            key: p.key,
            name: p.name,
            description: p.description,
            owner: OwnerRefDTO(id: p.owner.id!, fullName: p.owner.fullName),
            membersCount: members,
            tasksCount: tasks,
            epicsCount: epics,
            boardsCount: boards,
            isArchived: p.isArchived
        )
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func update(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let pid = try req.parameters.require("projectId", as: UUID.self)
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: pid, permission: PermissionKey.projectEdit, on: req.db)
        else { throw AppError.forbidden }
        guard let p = try await Project.find(pid, on: req.db), !p.isArchived else { throw AppError.notFound("Project not found") }
        let body = try req.content.decode(ProjectUpdateRequest.self)
        if let n = body.name { p.name = n }
        if let d = body.description { p.description = d }
        try await p.save(on: req.db)
        let dto = ProjectRowDTO(id: p.id!, key: p.key, name: p.name, description: p.description, isArchived: p.isArchived)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "project", entityId: pid, action: "update")
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func archive(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let pid = try req.parameters.require("projectId", as: UUID.self)
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: pid, permission: PermissionKey.projectArchive, on: req.db)
        else { throw AppError.forbidden }
        guard let p = try await Project.find(pid, on: req.db) else { throw AppError.notFound("Project not found") }
        try await p.delete(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "project", entityId: pid, action: "delete")
        return try Response.json(envelopeOk(MessageData(message: "Project deleted"), meta: nil))
    }

    static func addMember(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let pid = try req.parameters.require("projectId", as: UUID.self)
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: pid, permission: PermissionKey.projectMembersManage, on: req.db)
        else { throw AppError.forbidden }
        let body = try req.content.decode(ProjectMemberRequest.self)
        guard try await User.query(on: req.db).excludingDeleted().filter(\.$id == body.userId).first() != nil else {
            throw AppError.validation(["Invalid userId"])
        }
        guard try await Role.find(body.roleId, on: req.db) != nil else { throw AppError.validation(["Invalid roleId"]) }
        if try await ProjectMember.query(on: req.db).filter(\.$project.$id == pid).filter(\.$user.$id == body.userId).first() != nil {
            throw AppError.conflict("User already member")
        }
        let m = ProjectMember(projectID: pid, userID: body.userId, roleID: body.roleId)
        try await m.save(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "project_member", entityId: m.id!, action: "create")
        let dto = ProjectMemberDataDTO(projectId: pid, userId: body.userId, roleId: body.roleId)
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func removeMember(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let pid = try req.parameters.require("projectId", as: UUID.self)
        let mid = try req.parameters.require("memberUserId", as: UUID.self)
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: pid, permission: PermissionKey.projectMembersManage, on: req.db)
        else { throw AppError.forbidden }
        guard let m = try await ProjectMember.query(on: req.db).filter(\.$project.$id == pid).filter(\.$user.$id == mid).first()
        else { throw AppError.notFound("Member not found") }
        try await m.delete(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "project_member", entityId: pid, action: "delete")
        return try Response.json(envelopeOk(MessageData(message: "Member removed"), meta: nil))
    }

    private static func defaultManagerRoleId(on db: Database) async throws -> UUID {
        guard let r = try await Role.query(on: db).filter(\.$name == RoleName.manager).first(), let id = r.id else {
            throw AppError.internalError("Manager role missing")
        }
        return id
    }
}
