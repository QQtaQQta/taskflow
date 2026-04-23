import Foundation
import Vapor

private struct TraceIDStorage: StorageKey {
    typealias Value = String
}

extension Request {
    var traceID: String {
        get { storage[TraceIDStorage.self] ?? "" }
        set { storage[TraceIDStorage.self] = newValue }
    }
}

struct TraceIDMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let incoming = request.headers.first(name: "X-Trace-Id")
        let traceID = incoming?.isEmpty == false ? incoming! : UUID().uuidString
        request.traceID = traceID
        var response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: "X-Trace-Id", value: traceID)
        return response
    }
}

struct RequestLoggingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let start = DispatchTime.now().uptimeNanoseconds
        request.logger.info("request start", metadata: [
            "trace_id": .string(request.traceID),
            "method": .string(request.method.string),
            "path": .string(request.url.path),
        ])
        do {
            let response = try await next.respond(to: request)
            let end = DispatchTime.now().uptimeNanoseconds
            let ms = Double(end - start) / 1_000_000
            request.logger.info("request end", metadata: [
                "trace_id": .string(request.traceID),
                "status": .string(response.status.code.description),
                "duration_ms": .string(String(format: "%.2f", ms)),
            ])
            return response
        } catch {
            request.logger.error("request failed", metadata: [
                "trace_id": .string(request.traceID),
                "error": .string(String(reflecting: error)),
            ])
            throw error
        }
    }
}
