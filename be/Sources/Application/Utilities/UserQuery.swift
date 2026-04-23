import Fluent
import SQLKit

extension QueryBuilder where Model == User {
    func excludingDeleted() -> Self {
        filter(.sql(unsafeRaw: "deleted_at IS NULL"))
    }
}
