import Fluent
import Vapor

final class Attachment: Model, Content, @unchecked Sendable {
    static let schema = "attachments"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "task_id")
    var task: WorkTask

    @Parent(key: "uploaded_by_id")
    var uploadedBy: User

    @Field(key: "file_name")
    var fileName: String

    @Field(key: "file_url")
    var fileUrl: String

    @Field(key: "mime_type")
    var mimeType: String

    @Field(key: "file_size")
    var fileSize: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        taskID: UUID,
        uploadedByID: UUID,
        fileName: String,
        fileUrl: String,
        mimeType: String,
        fileSize: Int
    ) {
        self.id = id
        self.$task.id = taskID
        self.$uploadedBy.id = uploadedByID
        self.fileName = fileName
        self.fileUrl = fileUrl
        self.mimeType = mimeType
        self.fileSize = fileSize
    }
}
