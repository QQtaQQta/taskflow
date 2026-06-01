import Fluent

/// Adds `is_obsolete` for databases that ran `AddPointsAndShop` before the column
/// was included in that migration. Fresh installs already have the column.
struct AddShopItemObsolete: AsyncMigration {
    func prepare(on database: Database) async throws {
        do {
            try await database.schema(ShopItem.schema)
                .field("is_obsolete", .bool, .required, .sql(.default(false)))
                .update()
        } catch {
            // Column already exists on fresh installs.
        }
    }

    func revert(on database: Database) async throws {}
}
