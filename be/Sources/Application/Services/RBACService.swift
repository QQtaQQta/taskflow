import Fluent
import Vapor

enum RBACService {
    static func isAdmin(userId: UUID, on db: Database) async throws -> Bool {
        try await userRoleName(userId: userId, on: db) == RoleName.admin
    }

    static func userRoleName(userId: UUID, on db: Database) async throws -> String {
        guard let user = try await User.query(on: db)
            .excludingDeleted()
            .filter(\.$id == userId)
            .with(\.$role)
            .first()
        else { return "" }
        return user.role.name
    }

    static func permissionKeys(for userId: UUID, on db: Database) async throws -> [String] {
        guard let user = try await User.query(on: db)
            .excludingDeleted()
            .filter(\.$id == userId)
            .first()
        else { return [] }
        try await user.$role.load(on: db)
        try await user.role.$permissions.load(on: db)
        return user.role.permissions.map(\.key)
    }

    static func hasPermission(userId: UUID, permission: String, on db: Database) async throws -> Bool {
        let keys = try await permissionKeys(for: userId, on: db)
        return keys.contains(permission)
    }

    static func hasAny(userId: UUID, permissions: [String], on db: Database) async throws -> Bool {
        let keys = try await permissionKeys(for: userId, on: db)
        return permissions.contains(where: keys.contains)
    }

    static func canAccessProject(userId: UUID, projectId: UUID, on db: Database) async throws -> Bool {
        if try await isAdmin(userId: userId, on: db) { return true }
        if try await Project.query(on: db).filter(\.$id == projectId).filter(\.$owner.$id == userId).first() != nil {
            return true
        }
        return try await ProjectMember.query(on: db)
            .filter(\.$project.$id == projectId)
            .filter(\.$user.$id == userId)
            .first() != nil
    }

    static func projectMemberRoleName(userId: UUID, projectId: UUID, on db: Database) async throws -> String? {
        if try await isAdmin(userId: userId, on: db) { return RoleName.admin }
        if try await Project.query(on: db).filter(\.$id == projectId).filter(\.$owner.$id == userId).first() != nil {
            return RoleName.manager
        }
        guard let m = try await ProjectMember.query(on: db)
            .filter(\.$project.$id == projectId)
            .filter(\.$user.$id == userId)
            .with(\.$role)
            .first()
        else { return nil }
        return m.role.name
    }

    static func canManageProjectScoped(
        userId: UUID,
        projectId: UUID,
        permission: String,
        on db: Database
    ) async throws -> Bool {
        if try await isAdmin(userId: userId, on: db) { return true }
        guard try await hasPermission(userId: userId, permission: permission, on: db) else { return false }
        let pr = try await projectMemberRoleName(userId: userId, projectId: projectId, on: db)
        guard let pr else { return false }
        if pr == RoleName.manager { return true }
        if pr == RoleName.admin { return true }
        return false
    }
}
