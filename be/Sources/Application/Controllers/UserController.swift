import Fluent
import Vapor

enum UserController {
    static func list(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let canManage = try await RBACService.hasPermission(userId: uid, permission: PermissionKey.userManage, on: req.db)
        let canAssign = try await RBACService.hasPermission(userId: uid, permission: PermissionKey.taskAssign, on: req.db)
        let isAdminUser = try await RBACService.isAdmin(userId: uid, on: req.db)
        guard canManage || canAssign || isAdminUser else {
            throw AppError.forbidden
        }
        let q = try req.query.decode(UserListQuery.self)
        let lq = ListQuery(page: q.page, perPage: q.perPage, sortBy: q.sortBy, sortOrder: q.sortOrder, search: q.search)
        var base = User.query(on: req.db).excludingDeleted()
        if let rid = q.roleId {
            base = base.filter(\.$role.$id == rid)
        }
        if let s = lq.search, !s.isEmpty {
            let pattern = "%\(s)%"
            base = base.group(.or) { g in
                g.filter(\.$email, .custom("ILIKE"), pattern)
                g.filter(\.$fullName, .custom("ILIKE"), pattern)
            }
        }
        let total = try await base.count()
        let sortField = lq.sortBy ?? "email"
        let sorted: QueryBuilder<User> = {
            switch sortField {
            case "fullName": return base.sort(\.$fullName, lq.ascending ? .ascending : .descending)
            case "createdAt": return base.sort(\.$createdAt, lq.ascending ? .ascending : .descending)
            default: return base.sort(\.$email, lq.ascending ? .ascending : .descending)
            }
        }()
        let users = try await lq.applyPagination(to: sorted).with(\.$role).all()
        let rows: [UserRowDTO] = try users.map { u in
            try UserRowDTO(
                id: u.requireID(),
                email: u.email,
                fullName: u.fullName,
                isActive: u.isActive,
                role: RoleRefDTO(id: u.role.requireID(), name: u.role.name)
            )
        }
        let meta = APIMetaDTO(page: lq.normalizedPage, perPage: lq.normalizedPerPage, total: total)
        return try Response.json(envelopeOk(rows, meta: meta))
    }

    static func create(req: Request) async throws -> Response {
        try await req.requirePermission(PermissionKey.userManage)
        let body = try req.content.decode(UserCreateRequest.self)
        let email = body.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), body.password.count >= 8 else {
            throw AppError.validation(["Invalid email or password"])
        }
        if try await User.query(on: req.db).excludingDeleted().filter(\.$email == email).first() != nil {
            throw AppError.conflict("Email already in use")
        }
        guard try await Role.find(body.roleId, on: req.db) != nil else {
            throw AppError.validation(["Invalid roleId"])
        }
        let hash = try req.password.hash(body.password)
        let user = User(
            email: email,
            passwordHash: hash,
            fullName: body.fullName,
            roleID: body.roleId,
            isActive: body.isActive ?? true
        )
        try await user.save(on: req.db)
        try await user.$role.load(on: req.db)
        let dto = UserRowDTO(
            id: user.id!,
            email: user.email,
            fullName: user.fullName,
            isActive: user.isActive,
            role: RoleRefDTO(id: user.role.id!, name: user.role.name)
        )
        try await AuditService.log(
            db: req.db,
            actorId: try req.requireUserId(),
            entityType: "user",
            entityId: user.id!,
            action: "create",
            afterJson: "{\"email\":\"\(email)\"}"
        )
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func get(req: Request) async throws -> Response {
        try await req.requirePermission(PermissionKey.userManage)
        let id = try req.parameters.require("userId", as: UUID.self)
        guard let user = try await User.query(on: req.db).excludingDeleted().filter(\.$id == id).with(\.$role).first()
        else { throw AppError.notFound("User not found") }
        let pcount = try await ProjectMember.query(on: req.db).filter(\.$user.$id == id).count()
        let dto = UserDetailDTO(
            id: user.id!,
            email: user.email,
            fullName: user.fullName,
            avatarUrl: user.avatarUrl,
            isActive: user.isActive,
            role: RoleRefDTO(id: user.role.id!, name: user.role.name),
            projectsCount: pcount
        )
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func update(req: Request) async throws -> Response {
        try await req.requirePermission(PermissionKey.userManage)
        let id = try req.parameters.require("userId", as: UUID.self)
        guard let user = try await User.query(on: req.db).excludingDeleted().filter(\.$id == id).first()
        else { throw AppError.notFound("User not found") }
        let body = try req.content.decode(UserUpdateRequest.self)
        if let fn = body.fullName { user.fullName = fn }
        if let a = body.avatarUrl { user.avatarUrl = a }
        if let r = body.roleId {
            guard try await Role.find(r, on: req.db) != nil else { throw AppError.validation(["Invalid roleId"]) }
            user.$role.id = r
        }
        if let active = body.isActive { user.isActive = active }
        try await user.save(on: req.db)
        let dto = UserPatchDataDTO(
            id: user.id!,
            email: user.email,
            fullName: user.fullName,
            avatarUrl: user.avatarUrl,
            isActive: user.isActive
        )
        try await AuditService.log(db: req.db, actorId: try req.requireUserId(), entityType: "user", entityId: id, action: "update")
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func delete(req: Request) async throws -> Response {
        try await req.requirePermission(PermissionKey.userManage)
        let id = try req.parameters.require("userId", as: UUID.self)
        guard let user = try await User.query(on: req.db).excludingDeleted().filter(\.$id == id).first()
        else { throw AppError.notFound("User not found") }
        user.deletedAt = Date()
        user.isActive = false
        try await user.save(on: req.db)
        try await AuditService.log(db: req.db, actorId: try req.requireUserId(), entityType: "user", entityId: id, action: "soft_delete")
        return try Response.json(envelopeOk(MessageData(message: "User archived"), meta: nil))
    }
}

extension User {
    func requireID() throws -> UUID {
        guard let id = id else { throw AppError.internalError("Missing id") }
        return id
    }
}

extension Role {
    func requireID() throws -> UUID {
        guard let id = id else { throw AppError.internalError("Missing id") }
        return id
    }
}
