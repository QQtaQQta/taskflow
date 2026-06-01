import Fluent
import Vapor

enum ShopController {
    static func listItems(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let isAdmin = try await RBACService.isAdmin(userId: uid, on: req.db)
        var query = ShopItem.query(on: req.db).filter(\.$isActive == true).sort(\.$name, .ascending)
        if !isAdmin {
            query = query.filter(\.$isObsolete == false)
        }
        let items = try await query.all()
        let rows = items.map { itemToDTO($0) }
        return try Response.json(envelopeOk(rows, meta: nil))
    }

    static func createItem(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        guard try await RBACService.isAdmin(userId: uid, on: req.db) else { throw AppError.forbidden }
        let body = try req.content.decode(ShopItemCreateRequest.self)
        guard !body.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.validation(["Name is required"])
        }
        guard body.pricePoints > 0 else { throw AppError.validation(["pricePoints must be positive"]) }
        let item = ShopItem(
            name: body.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: body.description,
            pricePoints: body.pricePoints,
            isActive: true,
            isObsolete: body.isObsolete ?? false
        )
        try await item.save(on: req.db)
        let dto = itemToDTO(item)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "shop_item", entityId: item.id!, action: "create")
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func updateItem(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        guard try await RBACService.isAdmin(userId: uid, on: req.db) else { throw AppError.forbidden }
        let iid = try req.parameters.require("itemId", as: UUID.self)
        guard let item = try await ShopItem.find(iid, on: req.db) else {
            throw AppError.notFound("Item not found")
        }
        let body = try req.content.decode(ShopItemUpdateRequest.self)
        if let name = body.name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AppError.validation(["Name is required"]) }
            item.name = trimmed
        }
        if let description = body.description { item.description = description }
        if let price = body.pricePoints {
            guard price > 0 else { throw AppError.validation(["pricePoints must be positive"]) }
            item.pricePoints = price
        }
        if let obsolete = body.isObsolete { item.isObsolete = obsolete }
        if let active = body.isActive { item.isActive = active }
        try await item.save(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "shop_item", entityId: iid, action: "update")
        return try Response.json(envelopeOk(itemToDTO(item), meta: nil))
    }

    static func deleteItem(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        guard try await RBACService.isAdmin(userId: uid, on: req.db) else { throw AppError.forbidden }
        let iid = try req.parameters.require("itemId", as: UUID.self)
        guard let item = try await ShopItem.find(iid, on: req.db) else { throw AppError.notFound("Item not found") }
        let ordersCount = try await ShopOrder.query(on: req.db).filter(\.$item.$id == iid).count()
        if ordersCount > 0 {
            item.isActive = false
            try await item.save(on: req.db)
        } else {
            try await item.delete(on: req.db)
        }
        try await AuditService.log(db: req.db, actorId: uid, entityType: "shop_item", entityId: iid, action: "delete")
        return try Response.json(envelopeOk(MessageData(message: "Item deleted"), meta: nil))
    }

    static func balance(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        guard let user = try await User.query(on: req.db).excludingDeleted().filter(\.$id == uid).first()
        else { throw AppError.notFound("User not found") }
        return try Response.json(envelopeOk(PointsBalanceDTO(pointsBalance: user.pointsBalance), meta: nil))
    }

    static func listOrders(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let orders = try await ShopOrder.query(on: req.db)
            .filter(\.$user.$id == uid)
            .with(\.$item)
            .with(\.$user)
            .sort(\.$createdAt, .descending)
            .all()
        return try Response.json(envelopeOk(orders.map(orderToDTO), meta: nil))
    }

    static func listAllOrders(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        guard try await RBACService.isAdmin(userId: uid, on: req.db) else { throw AppError.forbidden }
        let orders = try await ShopOrder.query(on: req.db)
            .with(\.$item)
            .with(\.$user)
            .sort(\.$createdAt, .descending)
            .all()
        return try Response.json(envelopeOk(orders.map(orderToDTO), meta: nil))
    }

    static func createOrder(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let body = try req.content.decode(ShopOrderCreateRequest.self)
        let address = body.deliveryAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.count >= 5 else { throw AppError.validation(["deliveryAddress is too short"]) }
        guard let item = try await ShopItem.find(body.itemId, on: req.db), item.isActive, !item.isObsolete else {
            throw AppError.notFound("Item not found")
        }
        guard let user = try await User.find(uid, on: req.db) else { throw AppError.notFound("User not found") }
        guard user.pointsBalance >= item.pricePoints else {
            throw AppError.validation(["Not enough points"])
        }
        user.pointsBalance -= item.pricePoints
        try await user.save(on: req.db)
        let order = ShopOrder(userID: uid, itemID: item.id!, deliveryAddress: address)
        try await order.save(on: req.db)
        try await order.$item.load(on: req.db)
        let dto = ShopOrderRowDTO(
            id: order.id!,
            itemId: item.id!,
            itemName: item.name,
            userId: uid,
            userFullName: user.fullName,
            deliveryAddress: order.deliveryAddress,
            status: order.status,
            createdAt: order.createdAt
        )
        try await AuditService.log(db: req.db, actorId: uid, entityType: "shop_order", entityId: order.id!, action: "create")
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func updateOrderStatus(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let oid = try req.parameters.require("orderId", as: UUID.self)
        let body = try req.content.decode(ShopOrderStatusRequest.self)
        guard let next = OrderStatus(rawValue: body.status) else {
            throw AppError.validation(["Invalid status"])
        }
        guard let order = try await ShopOrder.find(oid, on: req.db) else { throw AppError.notFound("Order not found") }
        guard let current = order.orderStatus else { throw AppError.validation(["Invalid current status"]) }
        let isAdmin = try await RBACService.isAdmin(userId: uid, on: req.db)
        guard ShopOrderService.canTransition(
            from: current,
            to: next,
            actorId: uid,
            orderUserId: order.$user.id,
            isAdmin: isAdmin
        ) else {
            throw AppError.forbidden
        }
        order.status = next.rawValue
        try await order.save(on: req.db)
        try await order.$item.load(on: req.db)
        try await order.$user.load(on: req.db)
        let dto = orderToDTO(order)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "shop_order", entityId: oid, action: "status")
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    private static func itemToDTO(_ item: ShopItem) -> ShopItemRowDTO {
        ShopItemRowDTO(
            id: item.id!,
            name: item.name,
            description: item.description,
            pricePoints: item.pricePoints,
            isObsolete: item.isObsolete,
            isActive: item.isActive
        )
    }

    private static func orderToDTO(_ order: ShopOrder) -> ShopOrderRowDTO {
        ShopOrderRowDTO(
            id: order.id!,
            itemId: order.$item.id,
            itemName: order.item.name,
            userId: order.$user.id,
            userFullName: order.user.fullName,
            deliveryAddress: order.deliveryAddress,
            status: order.status,
            createdAt: order.createdAt
        )
    }
}
