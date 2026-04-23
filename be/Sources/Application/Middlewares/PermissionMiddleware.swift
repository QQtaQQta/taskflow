import Fluent
import Vapor

struct RequirePermissionMiddleware: AsyncMiddleware {
    let permission: String

    init(_ permission: String) {
        self.permission = permission
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let token = request.auth.get(AccessTokenPayload.self), let userId = token.userId else {
            throw AppError.unauthorized
        }
        let allowed = try await RBACService.hasPermission(userId: userId, permission: permission, on: request.db)
        guard allowed else { throw AppError.forbidden }
        return try await next.respond(to: request)
    }
}

struct RequireAdminMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let token = request.auth.get(AccessTokenPayload.self), let userId = token.userId else {
            throw AppError.unauthorized
        }
        let isAdmin = try await RBACService.isAdmin(userId: userId, on: request.db)
        guard isAdmin else { throw AppError.forbidden }
        return try await next.respond(to: request)
    }
}
