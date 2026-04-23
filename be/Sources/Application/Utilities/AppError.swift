import Vapor

enum AppError: Error {
    case unauthorized
    case forbidden
    case notFound(String)
    case validation([String])
    case conflict(String)
    case badRequest(String)
    case internalError(String)
}

extension AppError: AbortError {
    var status: HTTPResponseStatus {
        switch self {
        case .unauthorized: .unauthorized
        case .forbidden: .forbidden
        case .notFound: .notFound
        case .validation: .badRequest
        case .conflict: .conflict
        case .badRequest: .badRequest
        case .internalError: .internalServerError
        }
    }

    var reason: String {
        switch self {
        case .unauthorized: "Unauthorized"
        case .forbidden: "Forbidden"
        case .notFound(let r): r
        case .validation(let d): d.joined(separator: "; ")
        case .conflict(let r): r
        case .badRequest(let r): r
        case .internalError(let r): r
        }
    }
}

extension AppError {
    var code: String {
        switch self {
        case .unauthorized: "UNAUTHORIZED"
        case .forbidden: "FORBIDDEN"
        case .notFound: "NOT_FOUND"
        case .validation: "VALIDATION_ERROR"
        case .conflict: "CONFLICT"
        case .badRequest: "BAD_REQUEST"
        case .internalError: "INTERNAL_ERROR"
        }
    }

    var details: [String] {
        switch self {
        case .validation(let d): d
        default: []
        }
    }
}
