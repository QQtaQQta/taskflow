import Foundation
import os

struct APIConfiguration {
    let baseURL: URL
    // Backend (Vapor) uses default JSON encoding/decoding which keeps
    // Swift property names as-is (camelCase) on the wire. Do NOT apply
    // snake_case conversion here: doing so would send fields such as
    // `full_name`/`role_id` that the backend cannot decode and would
    // silently drop optional fields like `dueDate` on PATCH requests.
    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

enum APIError: LocalizedError {
    case invalidRequest
    case network(URLError)
    case decoding(DecodingError)
    case server(code: String, message: String)
    case unauthorized
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "Некорректный запрос"
        case let .network(error): error.localizedDescription
        case .decoding: "Ошибка обработки ответа сервера"
        case let .server(_, message): message
        case .unauthorized: "Требуется авторизация"
        case .unknown: "Неизвестная ошибка"
        }
    }
}

struct EmptyResponse: Codable {}

struct APIEnvelope<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let meta: APIMeta?
    let error: APIEnvelopeError?
}

struct APIMeta: Codable {
    let page: Int?
    let perPage: Int?
    let total: Int?
}

struct APIEnvelopeError: Codable {
    let code: String
    let message: String
    let details: [String]
}

enum Endpoint {
    case login(LoginRequest)
    case refresh(RefreshTokenRequest)
    case me
    case projects(page: Int, perPage: Int, search: String?)
    case createProject(CreateProjectRequest)
    case updateProject(id: UUID, request: UpdateProjectRequest)
    case archiveProject(id: UUID)
    case project(id: UUID)
    case tasks(projectId: UUID?, epicId: UUID?, page: Int, perPage: Int, search: String?)
    case createTask(CreateTaskRequest)
    case task(id: UUID)
    case updateTask(id: UUID, request: UpdateTaskRequest)
    case archiveTask(id: UUID)
    case assignTask(id: UUID, request: AssignTaskRequest)
    case estimateTask(id: UUID, request: TaskEstimateRequest)
    case changeTaskStatus(id: UUID, request: ChangeStatusRequest)
    case taskTimeEntries(id: UUID)
    case createTimeEntry(id: UUID, request: CreateTimeEntryRequest)
    case projectEpics(projectId: UUID)
    case createEpic(projectId: UUID, request: CreateEpicRequest)
    case updateEpic(id: UUID, request: UpdateEpicRequest)
    case archiveEpic(id: UUID)
    case linkTaskToEpic(epicId: UUID, taskId: UUID)
    case boards(projectId: UUID?)
    case board(id: UUID)
    case createBoard(CreateBoardRequest)
    case updateBoard(id: UUID, request: UpdateBoardRequest)
    case archiveBoard(id: UUID)
    case createBoardColumn(boardId: UUID, request: CreateBoardColumnRequest)
    case updateBoardColumn(columnId: UUID, request: UpdateBoardColumnRequest)
    case deleteBoardColumn(columnId: UUID)
    case moveTask(boardId: UUID, taskId: UUID, request: MoveTaskRequest)
    case users(page: Int, perPage: Int, search: String?)
    case createUser(CreateUserRequest)
    case roles(page: Int, perPage: Int, search: String?)
    case updateUser(id: UUID, request: UpdateUserRequest)
    case replaceRolePermissions(roleId: UUID, request: RolePermissionUpdateRequest)

    var method: HTTPMethod {
        switch self {
        case .login, .refresh, .createProject, .createTask, .assignTask, .changeTaskStatus,
             .createTimeEntry, .createEpic, .moveTask, .linkTaskToEpic, .estimateTask,
             .createBoard, .createBoardColumn:
            .post
        case .createUser:
            .post
        case .replaceRolePermissions:
            .put
        case .updateTask, .updateUser, .updateProject, .updateEpic, .updateBoard, .updateBoardColumn:
            .patch
        case .archiveProject, .archiveTask, .archiveEpic, .archiveBoard, .deleteBoardColumn:
            .delete
        default:
            .get
        }
    }

    var path: String {
        switch self {
        case .login: "/auth/login"
        case .refresh: "/auth/refresh"
        case .me: "/auth/me"
        case .projects: "/projects"
        case .createProject: "/projects"
        case let .updateProject(id, _): "/projects/\(id.uuidString)"
        case let .archiveProject(id): "/projects/\(id.uuidString)"
        case let .project(id): "/projects/\(id.uuidString)"
        case .tasks: "/tasks"
        case .createTask: "/tasks"
        case let .task(id): "/tasks/\(id.uuidString)"
        case let .updateTask(id, _): "/tasks/\(id.uuidString)"
        case let .archiveTask(id): "/tasks/\(id.uuidString)"
        case let .assignTask(id, _): "/tasks/\(id.uuidString)/assign"
        case let .estimateTask(id, _): "/tasks/\(id.uuidString)/estimate"
        case let .changeTaskStatus(id, _): "/tasks/\(id.uuidString)/status"
        case let .taskTimeEntries(id): "/tasks/\(id.uuidString)/time-entries"
        case let .createTimeEntry(id, _): "/tasks/\(id.uuidString)/time-entries"
        case let .projectEpics(id): "/projects/\(id.uuidString)/epics"
        case let .createEpic(id, _): "/projects/\(id.uuidString)/epics"
        case let .updateEpic(id, _): "/epics/\(id.uuidString)"
        case let .archiveEpic(id): "/epics/\(id.uuidString)"
        case let .linkTaskToEpic(epicId, taskId): "/epics/\(epicId.uuidString)/tasks/\(taskId.uuidString)"
        case .boards: "/boards"
        case let .board(id): "/boards/\(id.uuidString)"
        case .createBoard: "/boards"
        case let .updateBoard(id, _): "/boards/\(id.uuidString)"
        case let .archiveBoard(id): "/boards/\(id.uuidString)"
        case let .createBoardColumn(boardId, _): "/boards/\(boardId.uuidString)/columns"
        case let .updateBoardColumn(columnId, _): "/columns/\(columnId.uuidString)"
        case let .deleteBoardColumn(columnId): "/columns/\(columnId.uuidString)"
        case let .moveTask(boardId, taskId, _): "/boards/\(boardId.uuidString)/tasks/\(taskId.uuidString)/move"
        case .users: "/users"
        case .createUser: "/users"
        case .roles: "/roles"
        case let .updateUser(id, _): "/users/\(id.uuidString)"
        case let .replaceRolePermissions(roleId, _): "/roles/\(roleId.uuidString)/permissions"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case let .projects(page, perPage, search):
            return [
                .init(name: "page", value: "\(page)"),
                .init(name: "perPage", value: "\(perPage)"),
                .init(name: "search", value: search)
            ]
        case let .tasks(projectId, epicId, page, perPage, search):
            return [
                .init(name: "projectId", value: projectId?.uuidString),
                .init(name: "epicId", value: epicId?.uuidString),
                .init(name: "page", value: "\(page)"),
                .init(name: "perPage", value: "\(perPage)"),
                .init(name: "search", value: search)
            ]
        case let .boards(projectId):
            return [.init(name: "projectId", value: projectId?.uuidString)]
        case let .users(page, perPage, search), let .roles(page, perPage, search):
            return [
                .init(name: "page", value: "\(page)"),
                .init(name: "perPage", value: "\(perPage)"),
                .init(name: "search", value: search)
            ]
        default:
            return []
        }
    }

    func body(with encoder: JSONEncoder) throws -> Data? {
        switch self {
        case let .login(request): try encoder.encode(request)
        case let .refresh(request): try encoder.encode(request)
        case let .createProject(request): try encoder.encode(request)
        case let .updateProject(_, request): try encoder.encode(request)
        case let .createTask(request): try encoder.encode(request)
        case let .updateTask(_, request): try encoder.encode(request)
        case let .assignTask(_, request): try encoder.encode(request)
        case let .estimateTask(_, request): try encoder.encode(request)
        case let .changeTaskStatus(_, request): try encoder.encode(request)
        case let .createTimeEntry(_, request): try encoder.encode(request)
        case let .createEpic(_, request): try encoder.encode(request)
        case let .updateEpic(_, request): try encoder.encode(request)
        case let .createBoard(request): try encoder.encode(request)
        case let .updateBoard(_, request): try encoder.encode(request)
        case let .createBoardColumn(_, request): try encoder.encode(request)
        case let .updateBoardColumn(_, request): try encoder.encode(request)
        case let .moveTask(_, _, request): try encoder.encode(request)
        case let .updateUser(_, request): try encoder.encode(request)
        case let .createUser(request): try encoder.encode(request)
        case let .replaceRolePermissions(_, request): try encoder.encode(request)
        default: nil
        }
    }
}

final class APIClient {
    private let configuration: APIConfiguration
    private let authManager: AuthManager
    private let session: URLSession
    private let logger = Logger(subsystem: "com.taskflow.mobile", category: "API")

    init(configuration: APIConfiguration, authManager: AuthManager, session: URLSession = .shared) {
        self.configuration = configuration
        self.authManager = authManager
        self.session = session
    }

    func request<T: Codable>(_ endpoint: Endpoint, responseType: T.Type = T.self) async throws -> T {
        do {
            let request = try await buildRequest(for: endpoint, withToken: true)
            return try await execute(request: request, endpoint: endpoint, responseType: T.self, allowRefresh: true)
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decoding(error)
        } catch {
            throw APIError.unknown
        }
    }

    func requestVoid(_ endpoint: Endpoint) async throws {
        struct AnyPayload: Codable {}
        let _: AnyPayload = try await request(endpoint, responseType: AnyPayload.self)
    }

    private func execute<T: Codable>(
        request: URLRequest,
        endpoint: Endpoint,
        responseType: T.Type,
        allowRefresh: Bool
    ) async throws -> T {
        do {
            logger.info("[\(request.httpMethod ?? "-")] \(request.url?.absoluteString ?? "-")")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.unknown }

            if http.statusCode == 401, allowRefresh {
                let refreshed = try await refreshTokens()
                guard refreshed else { throw APIError.unauthorized }
                let retryRequest = try await buildRequest(for: endpoint, withToken: true)
                return try await execute(request: retryRequest, endpoint: endpoint, responseType: T.self, allowRefresh: false)
            }

            let envelope: APIEnvelope<T>
            do {
                envelope = try configuration.decoder.decode(APIEnvelope<T>.self, from: data)
            } catch let decodingError as DecodingError {
                if let recovered: T = try recoverResponse(from: data) {
                    return recovered
                }
                throw APIError.decoding(decodingError)
            }
            if envelope.success, let payload = envelope.data {
                return payload
            }
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            if let error = envelope.error {
                throw APIError.server(code: error.code, message: error.message)
            }
            throw APIError.unknown
        } catch let error as URLError {
            throw APIError.network(error)
        }
    }

    private func recoverResponse<T: Codable>(from data: Data) throws -> T? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let success = json["success"] as? Bool
        else {
            return nil
        }

        if success {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as? T
            }
            if let payload = json["data"], JSONSerialization.isValidJSONObject(payload) {
                let payloadData = try JSONSerialization.data(withJSONObject: payload)
                return try configuration.decoder.decode(T.self, from: payloadData)
            }
            return nil
        }

        if
            let error = json["error"] as? [String: Any],
            let code = error["code"] as? String,
            let message = error["message"] as? String
        {
            throw APIError.server(code: code, message: message)
        }

        return nil
    }

    private func refreshTokens() async throws -> Bool {
        guard let refreshToken = authManager.refreshToken else { return false }
        let endpoint = Endpoint.refresh(.init(refreshToken: refreshToken))
        let request = try await buildRequest(for: endpoint, withToken: false)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let payload = try configuration.decoder.decode(APIEnvelope<RefreshTokenResponse>.self, from: data)
            guard payload.success, let data = payload.data else { return false }
            authManager.updateTokens(access: data.accessToken, refresh: data.refreshToken)
            return true
        } catch {
            return false
        }
    }

    private func buildRequest(for endpoint: Endpoint, withToken: Bool) async throws -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest
        }
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems.filter { $0.value != nil }
        }
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if withToken, let token = authManager.currentAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try endpoint.body(with: configuration.encoder)
        return request
    }
}
