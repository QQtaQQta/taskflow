import Vapor
import JWT

struct JWTAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let bearer = request.headers.bearerAuthorization else {
            throw AppError.unauthorized
        }
        let payload = try request.jwt.verify(bearer.token, as: AccessTokenPayload.self)
        guard payload.typ == "access", let _ = payload.userId else {
            throw AppError.unauthorized
        }
        request.auth.login(payload)
        return try await next.respond(to: request)
    }
}

struct OptionalJWTAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        if let bearer = request.headers.bearerAuthorization,
           let payload = try? request.jwt.verify(bearer.token, as: AccessTokenPayload.self),
           payload.typ == "access",
           payload.userId != nil {
            request.auth.login(payload)
        }
        return try await next.respond(to: request)
    }
}
