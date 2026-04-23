import Vapor

struct APIMetaDTO: Encodable {
    var page: Int?
    var perPage: Int?
    var total: Int?
}

struct APIEnvelope<T: Encodable>: Encodable {
    var success: Bool
    var data: T?
    var meta: APIMetaDTO?
    var error: APIErrorBody?

    struct APIErrorBody: Encodable {
        var code: String
        var message: String
        var details: [String]
    }

    static func fail(code: String, message: String, details: [String] = []) -> APIEnvelope<Empty?> {
        APIEnvelope<Empty?>(
            success: false,
            data: nil,
            meta: nil,
            error: .init(code: code, message: message, details: details)
        )
    }
}

struct Empty: Codable, Sendable {}

extension APIEnvelope where T == Empty? {
    static func okEmpty(meta: APIMetaDTO? = nil) -> APIEnvelope<Empty?> {
        APIEnvelope<Empty?>(success: true, data: nil, meta: meta, error: nil)
    }
}

struct MessageData: Encodable {
    var message: String
}

func envelopeOk<D: Encodable>(_ data: D, meta: APIMetaDTO? = nil) -> APIEnvelope<D> {
    APIEnvelope<D>(success: true, data: data, meta: meta, error: nil)
}
