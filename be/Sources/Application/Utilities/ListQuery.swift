import Fluent
import Vapor

struct ListQuery: Content, Sendable {
    var page: Int?
    var perPage: Int?
    var sortBy: String?
    var sortOrder: String?
    var search: String?

    var normalizedPage: Int { max(1, page ?? 1) }
    var normalizedPerPage: Int { min(100, max(1, perPage ?? 20)) }
    var ascending: Bool { (sortOrder ?? "asc").lowercased() != "desc" }
}

struct PaginatedResult<T: Sendable>: Sendable {
    var items: [T]
    var total: Int
}

extension ListQuery {
    func applyPagination<T>(to query: QueryBuilder<T>) -> QueryBuilder<T> {
        let offset = (normalizedPage - 1) * normalizedPerPage
        return query.offset(offset).limit(normalizedPerPage)
    }
}
