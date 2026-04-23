import Fluent
import Vapor

enum NotificationController {
    static func list(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let list = try await UserNotification.query(on: req.db).filter(\.$user.$id == uid).sort(\.$createdAt, .descending).offset(0).limit(200).all()
        let rows = list.map {
            NotificationRowDTO(
                id: $0.id!,
                type: $0.type,
                title: $0.title,
                body: $0.body,
                isRead: $0.isRead,
                createdAt: $0.createdAt
            )
        }
        return try Response.json(envelopeOk(rows, meta: nil))
    }

    static func markRead(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let nid = try req.parameters.require("notificationId", as: UUID.self)
        guard let n = try await UserNotification.find(nid, on: req.db), n.$user.id == uid else { throw AppError.notFound("Notification not found") }
        n.isRead = true
        try await n.save(on: req.db)
        struct Out: Encodable { var id: UUID; var isRead: Bool }
        return try Response.json(envelopeOk(Out(id: nid, isRead: true), meta: nil))
    }

    static func readAll(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let list = try await UserNotification.query(on: req.db).filter(\.$user.$id == uid).filter(\.$isRead == false).all()
        for n in list {
            n.isRead = true
            try await n.save(on: req.db)
        }
        return try Response.json(envelopeOk(MessageData(message: "All notifications marked as read"), meta: nil))
    }
}
