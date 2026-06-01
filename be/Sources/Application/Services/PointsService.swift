import Fluent
import Vapor

enum PointsService {
    static func pointsFromMinutes(_ minutes: Int) -> Int {
        max(0, minutes / 60)
    }

    static func awardForTimeEntry(_ entry: TimeEntry, on db: Database) async throws {
        guard let entryId = entry.id else { return }
        guard let task = try await WorkTask.find(entry.$task.id, on: db) else { return }
        guard task.status == "done" || task.status == "closed" else { return }
        try await creditTimeEntry(entryId: entryId, userId: entry.$user.id, minutes: entry.spentMinutes, on: db)
    }

    static func awardForTaskCompletion(taskId: UUID, on db: Database) async throws {
        guard let task = try await WorkTask.find(taskId, on: db) else { return }
        guard task.status == "done" || task.status == "closed" else { return }
        let entries = try await TimeEntry.query(on: db).filter(\.$task.$id == taskId).all()
        for entry in entries {
            guard let entryId = entry.id else { continue }
            try await creditTimeEntry(entryId: entryId, userId: entry.$user.id, minutes: entry.spentMinutes, on: db)
        }
    }

    static func recreditTimeEntry(_ entry: TimeEntry, on db: Database) async throws {
        guard let entryId = entry.id else { return }
        if let existing = try await PointCredit.query(on: db).filter(\.$timeEntry.$id == entryId).first() {
            if let user = try await User.find(existing.$user.id, on: db) {
                user.pointsBalance = max(0, user.pointsBalance - existing.points)
                try await user.save(on: db)
            }
            try await existing.delete(on: db)
        }
        try await awardForTimeEntry(entry, on: db)
    }

    static func revokeTimeEntry(_ entryId: UUID, on db: Database) async throws {
        guard let existing = try await PointCredit.query(on: db).filter(\.$timeEntry.$id == entryId).first() else { return }
        if let user = try await User.find(existing.$user.id, on: db) {
            user.pointsBalance = max(0, user.pointsBalance - existing.points)
            try await user.save(on: db)
        }
        try await existing.delete(on: db)
    }

    private static func creditTimeEntry(entryId: UUID, userId: UUID, minutes: Int, on db: Database) async throws {
        if try await PointCredit.query(on: db).filter(\.$timeEntry.$id == entryId).first() != nil { return }
        let points = pointsFromMinutes(minutes)
        guard points > 0 else { return }
        guard let user = try await User.find(userId, on: db) else { return }
        user.pointsBalance += points
        try await user.save(on: db)
        let credit = PointCredit(userID: userId, timeEntryID: entryId, minutes: minutes, points: points)
        try await credit.save(on: db)
    }
}
