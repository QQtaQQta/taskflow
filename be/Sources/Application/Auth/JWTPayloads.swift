import Foundation
import JWT
import Vapor

struct AccessTokenPayload: JWTPayload, Authenticatable {
    var subject: SubjectClaim
    var exp: ExpirationClaim
    var typ: String

    enum CodingKeys: String, CodingKey {
        case subject
        case exp
        case typ = "type"
    }

    func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }

    var userId: UUID? {
        UUID(uuidString: subject.value)
    }
}

struct RefreshTokenPayload: JWTPayload {
    var subject: SubjectClaim
    var exp: ExpirationClaim
    var typ: String
    var jti: UUID

    enum CodingKeys: String, CodingKey {
        case subject
        case exp
        case typ = "type"
        case jti
    }

    func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }

    var userId: UUID? {
        UUID(uuidString: subject.value)
    }
}
