import Fluent
import Vapor

enum SearchController {
    static func search(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let q = try req.query.decode(SearchQuery.self)
        let term = q.q?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let typeFilter = q.type?.lowercased()
        if term.isEmpty {
            let empty = SearchDataDTO(projects: [], epics: [], tasks: [], users: [])
            return try Response.json(envelopeOk(empty, meta: nil))
        }
        let admin = try await RBACService.isAdmin(userId: uid, on: req.db)
        let pids = try await projectScope(userId: uid, admin: admin, on: req.db)

        var projects: [ProjectRowDTO] = []
        let like = "%\(term)%"
        if typeFilter == nil || typeFilter == "project" {
            var pq = Project.query(on: req.db).filter(\.$isArchived == false)
            if !admin { pq = pq.filter(\.$id ~~ pids) }
            pq = pq.group(.or) { g in
                g.filter(\.$name, .custom("ILIKE"), like)
                g.filter(\.$key, .custom("ILIKE"), like)
            }
            let pr = try await pq.offset(0).limit(20).all()
            projects = pr.map { ProjectRowDTO(id: $0.id!, key: $0.key, name: $0.name, description: $0.description, isArchived: $0.isArchived) }
        }

        var epics: [EpicRowDTO] = []
        if typeFilter == nil || typeFilter == "epic" {
            if admin || !pids.isEmpty {
                var eq = Epic.query(on: req.db).filter(\.$isArchived == false)
                if !admin { eq = eq.filter(\.$project.$id ~~ pids) }
                eq = eq.group(.or) { g in
                    g.filter(\.$title, .custom("ILIKE"), like)
                    g.filter(\.$key, .custom("ILIKE"), like)
                }
                let er = try await eq.offset(0).limit(20).all()
                epics = er.map { EpicRowDTO(id: $0.id!, projectId: $0.$project.id, key: $0.key, title: $0.title, status: $0.status) }
            }
        }

        var tasks: [SearchHitTaskDTO] = []
        if typeFilter == nil || typeFilter == "task" {
            if admin || !pids.isEmpty {
                var tq = WorkTask.query(on: req.db).filter(\.$isArchived == false)
                if !admin { tq = tq.filter(\.$project.$id ~~ pids) }
                tq = tq.group(.or) { g in
                    g.filter(\.$title, .custom("ILIKE"), like)
                    g.filter(\.$key, .custom("ILIKE"), like)
                }
                let tr = try await tq.offset(0).limit(20).all()
                tasks = tr.map { SearchHitTaskDTO(id: $0.id!, key: $0.key, title: $0.title) }
            }
        }

        var users: [UserRowDTO] = []
        if typeFilter == nil || typeFilter == "user" {
            let um = try await RBACService.hasPermission(userId: uid, permission: PermissionKey.userManage, on: req.db)
            let ta = try await RBACService.hasPermission(userId: uid, permission: PermissionKey.taskAssign, on: req.db)
            let canSeeUsers = um || ta
            if canSeeUsers {
                let uq = User.query(on: req.db).excludingDeleted().group(.or) { g in
                    g.filter(\.$email, .custom("ILIKE"), like)
                    g.filter(\.$fullName, .custom("ILIKE"), like)
                }
                let ur = try await uq.with(\.$role).offset(0).limit(20).all()
                users = try ur.map {
                    try UserRowDTO(
                        id: $0.requireID(),
                        email: $0.email,
                        fullName: $0.fullName,
                        isActive: $0.isActive,
                        role: RoleRefDTO(id: $0.role.requireID(), name: $0.role.name)
                    )
                }
            }
        }

        let dto = SearchDataDTO(projects: projects, epics: epics, tasks: tasks, users: users)
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    private static func projectScope(userId: UUID, admin: Bool, on db: Database) async throws -> [UUID] {
        if admin {
            return try await Project.query(on: db).all().map(\.id!)
        }
        let m = try await ProjectMember.query(on: db).filter(\.$user.$id == userId).all().map(\.$project.id)
        let o = try await Project.query(on: db).filter(\.$owner.$id == userId).all().map(\.id!)
        return Array(Set(m + o))
    }
}
