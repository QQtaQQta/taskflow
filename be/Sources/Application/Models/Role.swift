import Fluent
import Vapor

final class Role: Model, Content, @unchecked Sendable {
    static let schema = "roles"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "description")
    var description: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$role)
    var users: [User]

    @Siblings(through: RolePermission.self, from: \.$role, to: \.$permission)
    var permissions: [Permission]

    init() {}

    init(id: UUID? = nil, name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }
}

final class Permission: Model, Content, @unchecked Sendable {
    static let schema = "permissions"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "key")
    var key: String

    @Field(key: "description")
    var description: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Siblings(through: RolePermission.self, from: \.$permission, to: \.$role)
    var roles: [Role]

    init() {}

    init(id: UUID? = nil, key: String, description: String) {
        self.id = id
        self.key = key
        self.description = description
    }
}

final class RolePermission: Model, @unchecked Sendable {
    static let schema = "role_permissions"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "role_id")
    var role: Role

    @Parent(key: "permission_id")
    var permission: Permission

    init() {}

    init(id: UUID? = nil, roleID: UUID, permissionID: UUID) {
        self.id = id
        self.$role.id = roleID
        self.$permission.id = permissionID
    }
}
