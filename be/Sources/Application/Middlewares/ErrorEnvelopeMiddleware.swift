import Vapor

struct ErrorEnvelopeMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let error as AppError {
            let env = APIEnvelope<Empty?>.fail(code: error.code, message: error.reason, details: error.details)
            return try Response.json(env, status: error.status)
        } catch let abort as AbortError {
            let env = APIEnvelope<Empty?>.fail(
                code: "HTTP_ERROR",
                message: abort.reason,
                details: []
            )
            return try Response.json(env, status: abort.status)
        } catch {
            request.logger.report(error: error)
            let env = APIEnvelope<Empty?>.fail(
                code: "INTERNAL_ERROR",
                message: "An unexpected error occurred",
                details: []
            )
            return try Response.json(env, status: .internalServerError)
        }
    }
}

extension Response {
    static func json<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok) throws -> Response {
        let data = try JSONEncoder.api.encode(value)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: status, headers: headers, body: .init(data: data))
    }
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
