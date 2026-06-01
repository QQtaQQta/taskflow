import Fluent
import Vapor

final class PointCredit: Model, @unchecked Sendable {
    static let schema = "point_credits"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Parent(key: "time_entry_id")
    var timeEntry: TimeEntry

    @Field(key: "minutes")
    var minutes: Int

    @Field(key: "points")
    var points: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userID: UUID, timeEntryID: UUID, minutes: Int, points: Int) {
        self.id = id
        self.$user.id = userID
        self.$timeEntry.id = timeEntryID
        self.minutes = minutes
        self.points = points
    }
}
