import Fluent
import Vapor

enum ShopOrderService {
    static func canTransition(
        from current: OrderStatus,
        to next: OrderStatus,
        actorId: UUID,
        orderUserId: UUID,
        isAdmin: Bool
    ) -> Bool {
        switch (current, next) {
        case (.assembling, .shipped):
            return isAdmin
        case (.shipped, .received):
            return actorId == orderUserId
        default:
            return false
        }
    }

    static func allowedNextStatuses(
        current: OrderStatus,
        actorId: UUID,
        orderUserId: UUID,
        isAdmin: Bool
    ) -> [OrderStatus] {
        switch current {
        case .assembling:
            return isAdmin ? [.shipped] : []
        case .shipped:
            return actorId == orderUserId ? [.received] : []
        case .received:
            return []
        }
    }
}
