import Fluent
import Vapor

enum OrderStatus: String, Codable {
    case assembling
    case shipped
    case received

    var localizedTitle: String {
        switch self {
        case .assembling: return "В сборке"
        case .shipped: return "Отправлен"
        case .received: return "Получен"
        }
    }
}

final class ShopItem: Model, Content, @unchecked Sendable {
    static let schema = "shop_items"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "description")
    var description: String

    @Field(key: "price_points")
    var pricePoints: Int

    @Field(key: "is_active")
    var isActive: Bool

    @Field(key: "is_obsolete")
    var isObsolete: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {
        self.name = ""
        self.description = ""
        self.pricePoints = 0
        self.isActive = true
        self.isObsolete = false
    }

    init(
        id: UUID? = nil,
        name: String,
        description: String,
        pricePoints: Int,
        isActive: Bool = true,
        isObsolete: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.pricePoints = pricePoints
        self.isActive = isActive
        self.isObsolete = isObsolete
    }
}

final class ShopOrder: Model, Content, @unchecked Sendable {
    static let schema = "shop_orders"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Parent(key: "item_id")
    var item: ShopItem

    @Field(key: "delivery_address")
    var deliveryAddress: String

    @Field(key: "status")
    var status: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, userID: UUID, itemID: UUID, deliveryAddress: String, status: String = OrderStatus.assembling.rawValue) {
        self.id = id
        self.$user.id = userID
        self.$item.id = itemID
        self.deliveryAddress = deliveryAddress
        self.status = status
    }

    var orderStatus: OrderStatus? {
        OrderStatus(rawValue: status)
    }
}
