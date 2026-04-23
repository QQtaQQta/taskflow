import Fluent
import Foundation
import JWT
import Vapor

enum TokenService {
    static let accessTtlSeconds: TimeInterval = 15 * 60
    static let refreshTtlSeconds: TimeInterval = 30 * 24 * 60 * 60

    static func issuePair(for userId: UUID, on db: Database, req: Request) async throws -> (access: String, refresh: String) {
        let access = AccessTokenPayload(
            subject: SubjectClaim(value: userId.uuidString),
            exp: ExpirationClaim(value: Date().addingTimeInterval(accessTtlSeconds)),
            typ: "access"
        )
        let accessToken = try req.jwt.sign(access, kid: "default")

        let jti = UUID()
        let refresh = RefreshTokenPayload(
            subject: SubjectClaim(value: userId.uuidString),
            exp: ExpirationClaim(value: Date().addingTimeInterval(refreshTtlSeconds)),
            typ: "refresh",
            jti: jti
        )
        let refreshToken = try req.jwt.sign(refresh, kid: "default")

        let row = RefreshToken(userID: userId, jti: jti, expiresAt: Date().addingTimeInterval(refreshTtlSeconds))
        try await RetryPolicy.withTimeout(seconds: 2.0) {
            try await RetryPolicy.withRetry {
                try await row.save(on: db)
            }
        }
        return (accessToken, refreshToken)
    }

    static func revokeRefresh(jti: UUID, on db: Database) async throws {
        guard let row = try await RefreshToken.query(on: db).filter(\.$jti == jti).first() else { return }
        row.revokedAt = Date()
        try await RetryPolicy.withRetry {
            try await row.save(on: db)
        }
    }

    static func assertRefreshValid(jti: UUID, on db: Database) async throws -> RefreshToken {
        guard let row = try await RefreshToken.query(on: db).filter(\.$jti == jti).first() else {
            throw AppError.unauthorized
        }
        if row.revokedAt != nil { throw AppError.unauthorized }
        if row.expiresAt < Date() { throw AppError.unauthorized }
        return row
    }
}
