import Fluent
import Vapor

enum AuditService {
    static func log(
        db: Database,
        actorId: UUID?,
        entityType: String,
        entityId: UUID,
        action: String,
        beforeJson: String? = nil,
        afterJson: String? = nil
    ) async throws {
        let row = AuditLog(
            actorID: actorId,
            entityType: entityType,
            entityId: entityId,
            action: action,
            beforeJson: beforeJson,
            afterJson: afterJson
        )
        try await row.save(on: db)
    }
}
