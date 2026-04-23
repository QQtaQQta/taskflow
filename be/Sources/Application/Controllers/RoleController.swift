import Fluent
import Vapor

enum RoleController {
    static func list(req: Request) async throws -> Response {
        _ = try req.requireUserId()
        let q = try req.query.decode(ListQuery.self)
        let base = Role.query(on: req.db)
        let filtered: QueryBuilder<Role> = {
            if let s = q.search, !s.isEmpty {
                return base.filter(\.$name, .custom("ILIKE"), "%\(s)%")
            }
            return base
        }()
        let total = try await filtered.count()
        let items = try await q.applyPagination(to: filtered.sort(\.$name, q.ascending ? .ascending : .descending)).all()
        let rows = items.compactMap { r -> RoleRowDTO? in
            guard let id = r.id else { return nil }
            return RoleRowDTO(id: id, name: r.name, description: r.description)
        }
        let meta = APIMetaDTO(page: q.normalizedPage, perPage: q.normalizedPerPage, total: total)
        return try Response.json(envelopeOk(rows, meta: meta))
    }

    static func create(req: Request) async throws -> Response {
        try await req.requireAdmin()
        let body = try req.content.decode(RoleCreateRequest.self)
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AppError.validation(["name is required"]) }
        if try await Role.query(on: req.db).filter(\.$name == name).first() != nil {
            throw AppError.conflict("Role name already exists")
        }
        let role = Role(name: name, description: body.description)
        try await role.save(on: req.db)
        try await AuditService.log(
            db: req.db,
            actorId: try req.requireUserId(),
            entityType: "role",
            entityId: role.id!,
            action: "create",
            afterJson: "{\"name\":\"\(name)\"}"
        )
        let dto = RoleRowDTO(id: role.id!, name: role.name, description: role.description)
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func update(req: Request) async throws -> Response {
        try await req.requireAdmin()
        let id = try req.parameters.require("roleId", as: UUID.self)
        guard let role = try await Role.find(id, on: req.db) else { throw AppError.notFound("Role not found") }
        let body = try req.content.decode(RoleUpdateRequest.self)
        if let n = body.name {
            let name = n.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw AppError.validation(["name invalid"]) }
            role.name = name
        }
        if let d = body.description { role.description = d }
        try await role.save(on: req.db)
        let dto = RoleRowDTO(id: role.id!, name: role.name, description: role.description)
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func replacePermissions(req: Request) async throws -> Response {
        try await req.requireAdmin()
        let id = try req.parameters.require("roleId", as: UUID.self)
        guard let role = try await Role.find(id, on: req.db) else { throw AppError.notFound("Role not found") }
        let body = try req.content.decode(RolePermissionsPutRequest.self)
        let perms = try await Permission.query(on: req.db).filter(\.$key ~~ body.permissions).all()
        let foundKeys = Set(perms.map(\.key))
        let missing = body.permissions.filter { !foundKeys.contains($0) }
        if !missing.isEmpty {
            throw AppError.validation(["Unknown permissions: \(missing.joined(separator: ", "))"])
        }
        try await role.$permissions.detachAll(on: req.db)
        for p in perms {
            try await role.$permissions.attach(p, on: req.db)
        }
        let dto = RolePermissionsDataDTO(roleId: id, permissions: body.permissions.sorted())
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func delete(req: Request) async throws -> Response {
        try await req.requireAdmin()
        let id = try req.parameters.require("roleId", as: UUID.self)
        guard let role = try await Role.find(id, on: req.db) else { throw AppError.notFound("Role not found") }
        if try await User.query(on: req.db).filter(\.$role.$id == id).count() > 0 {
            throw AppError.conflict("Role is assigned to users")
        }
        try await role.delete(on: req.db)
        return try Response.json(envelopeOk(MessageData(message: "Role deleted"), meta: nil))
    }
}
