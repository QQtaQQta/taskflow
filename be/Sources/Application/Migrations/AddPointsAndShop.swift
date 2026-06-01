import Fluent

struct AddPointsAndShop: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(User.schema)
            .field("points_balance", .int, .required, .sql(.default(0)))
            .update()

        try await database.schema(PointCredit.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("time_entry_id", .uuid, .required, .references(TimeEntry.schema, .id, onDelete: .cascade))
            .field("minutes", .int, .required)
            .field("points", .int, .required)
            .field("created_at", .datetime)
            .unique(on: "time_entry_id")
            .create()

        try await database.schema(ShopItem.schema)
            .id()
            .field("name", .string, .required)
            .field("description", .string, .required)
            .field("price_points", .int, .required)
            .field("is_active", .bool, .required)
            .field("is_obsolete", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(ShopOrder.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("item_id", .uuid, .required, .references(ShopItem.schema, .id, onDelete: .restrict))
            .field("delivery_address", .string, .required)
            .field("status", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        let items: [(String, String, Int)] = [
            ("Футболка TaskFlow", "Брендированная футболка с логотипом проекта.", 120),
            ("Термокружка", "Кружка 350 мл с двойными стенками.", 80),
            ("Наушники", "Беспроводные наушники для работы и отдыха.", 350),
            ("Рюкзак", "Городской рюкзак для ноутбука до 15 дюймов.", 280),
        ]
        for (name, desc, price) in items {
            let item = ShopItem(name: name, description: desc, pricePoints: price, isActive: true)
            try await item.save(on: database)
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema(ShopOrder.schema).delete()
        try await database.schema(ShopItem.schema).delete()
        try await database.schema(PointCredit.schema).delete()
        try await database.schema(User.schema).deleteField("points_balance")
    }
}
