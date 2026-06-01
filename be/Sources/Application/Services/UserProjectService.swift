import Fluent
import Vapor

enum UserProjectService {
    static func defaultMemberRoleId(on db: Database) async throws -> UUID {
        guard let role = try await Role.query(on: db).filter(\.$name == RoleName.assignee).first(), let id = role.id else {
            throw AppError.internalError("Assignee role missing")
        }
        return id
    }

    static func fetchAssignableProjects(on db: Database) async throws -> [ProjectRefDTO] {
        let projects = try await Project.query(on: db).filter(\.$isArchived == false).sort(\.$name, .ascending).all()
        return projects.map { ProjectRefDTO(id: $0.id!, key: $0.key, name: $0.name) }
    }

    static func fetchUserProjects(userId: UUID, on db: Database) async throws -> [ProjectRefDTO] {
        let members = try await ProjectMember.query(on: db)
            .filter(\.$user.$id == userId)
            .with(\.$project)
            .all()
        return members.compactMap { member in
            let project = member.project
            guard let id = project.id else { return nil }
            return ProjectRefDTO(id: id, key: project.key, name: project.name)
        }
        .sorted { $0.name < $1.name }
    }

    static func syncMemberships(userId: UUID, projectIds: [UUID], on db: Database) async throws {
        let uniqueIds = Array(Set(projectIds))
        for pid in uniqueIds {
            guard let project = try await Project.find(pid, on: db), !project.isArchived else {
                throw AppError.validation(["Invalid or archived projectId: \(pid)"])
            }
        }

        let roleId = try await defaultMemberRoleId(on: db)
        let existing = try await ProjectMember.query(on: db).filter(\.$user.$id == userId).all()
        let existingIds = Set(existing.map(\.$project.id))
        let desired = Set(uniqueIds)

        for member in existing where !desired.contains(member.$project.id) {
            try await member.delete(on: db)
        }

        for pid in desired where !existingIds.contains(pid) {
            let member = ProjectMember(projectID: pid, userID: userId, roleID: roleId)
            try await member.save(on: db)
        }
    }
}
