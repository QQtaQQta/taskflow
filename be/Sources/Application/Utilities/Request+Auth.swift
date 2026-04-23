import Vapor

extension Request {
    func requireUserId() throws -> UUID {
        guard let p = auth.get(AccessTokenPayload.self), let id = p.userId else {
            throw AppError.unauthorized
        }
        return id
    }

    func requirePermission(_ key: String) async throws {
        let uid = try requireUserId()
        guard try await RBACService.hasPermission(userId: uid, permission: key, on: db) else {
            throw AppError.forbidden
        }
    }

    func requireAdmin() async throws {
        let uid = try requireUserId()
        guard try await RBACService.isAdmin(userId: uid, on: db) else {
            throw AppError.forbidden
        }
    }
}
