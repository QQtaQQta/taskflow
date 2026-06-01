import Fluent
import Vapor

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "email")
    var email: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Field(key: "full_name")
    var fullName: String

    @OptionalField(key: "avatar_url")
    var avatarUrl: String?

    @Parent(key: "role_id")
    var role: Role

    @Field(key: "is_active")
    var isActive: Bool

    @Field(key: "points_balance")
    var pointsBalance: Int

    @OptionalField(key: "deleted_at")
    var deletedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        email: String,
        passwordHash: String,
        fullName: String,
        avatarUrl: String? = nil,
        roleID: UUID,
        isActive: Bool = true,
        pointsBalance: Int = 0
    ) {
        self.id = id
        self.email = email
        self.passwordHash = passwordHash
        self.fullName = fullName
        self.avatarUrl = avatarUrl
        self.$role.id = roleID
        self.isActive = isActive
        self.pointsBalance = pointsBalance
    }
}

final class RefreshToken: Model, @unchecked Sendable {
    static let schema = "refresh_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "jti")
    var jti: UUID

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "revoked_at")
    var revokedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, userID: UUID, jti: UUID, expiresAt: Date) {
        self.id = id
        self.$user.id = userID
        self.jti = jti
        self.expiresAt = expiresAt
    }
}
