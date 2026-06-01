import Fluent
import JWT
import Vapor

enum AuthController {
    static func login(req: Request) async throws -> Response {
        let body = try req.content.decode(LoginRequest.self)
        let email = body.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty, body.password.count >= 8 else {
            throw AppError.validation(["Invalid email or password format"])
        }
        guard let user = try await UserRepository.findActiveByEmail(email, on: req.db)
        else { throw AppError.unauthorized }
        guard user.isActive else { throw AppError.unauthorized }
        let ok = try req.password.verify(body.password, created: user.passwordHash)
        guard ok else { throw AppError.unauthorized }

        let pair = try await TokenService.issuePair(for: user.id!, on: req.db, req: req)
        let dto = LoginDataDTO(
            user: LoginUserDTO(
                id: user.id!,
                email: user.email,
                fullName: user.fullName,
                role: RoleRefDTO(id: user.role.id!, name: user.role.name)
            ),
            accessToken: pair.access,
            refreshToken: pair.refresh
        )
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func refresh(req: Request) async throws -> Response {
        let body = try req.content.decode(RefreshRequest.self)
        do {
            let payload = try req.jwt.verify(body.refreshToken, as: RefreshTokenPayload.self)
            guard payload.typ == "refresh", let uid = payload.userId else { throw AppError.unauthorized }
            _ = try await TokenService.assertRefreshValid(jti: payload.jti, on: req.db)
            try await TokenService.revokeRefresh(jti: payload.jti, on: req.db)
            let pair = try await TokenService.issuePair(for: uid, on: req.db, req: req)
            let dto = RefreshDataDTO(accessToken: pair.access, refreshToken: pair.refresh)
            return try Response.json(envelopeOk(dto, meta: nil))
        } catch {
            throw AppError.unauthorized
        }
    }

    static func logout(req: Request) async throws -> Response {
        let body = try req.content.decode(LogoutRequest.self)
        if let payload = try? req.jwt.verify(body.refreshToken, as: RefreshTokenPayload.self) {
            try await TokenService.revokeRefresh(jti: payload.jti, on: req.db)
        }
        let msg = MessageData(message: "Logged out")
        return try Response.json(envelopeOk(msg, meta: nil))
    }

    static func me(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        guard let user = try await UserRepository.findActiveWithRole(uid, on: req.db)
        else { throw AppError.notFound("User not found") }
        try await user.role.$permissions.load(on: req.db)
        let keys = user.role.permissions.map(\.key).sorted()
        let dto = MeDataDTO(
            id: user.id!,
            email: user.email,
            fullName: user.fullName,
            avatarUrl: user.avatarUrl,
            role: RoleRefDTO(id: user.role.id!, name: user.role.name),
            permissions: keys,
            pointsBalance: user.pointsBalance
        )
        return try Response.json(envelopeOk(dto, meta: nil))
    }
}
