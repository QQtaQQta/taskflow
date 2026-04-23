import Fluent
import Vapor

/// Production-flavoured demo seed.
///
/// Populates every moving part of the system with 3–4 representative
/// examples so a reviewer can walk the entire product surface right after
/// `docker compose up` without having to click through creation flows first.
/// The seed is idempotent — it only runs against an empty schema (no roles
/// present) and writes everything in one go.
///
/// Test credentials (every account shares the same password so demos can
/// log in as any role quickly):
///   * admin@demo.local              — Demo Admin, role `admin`
///   * elena.kuznetsova@taskflow.dev — Mobile lead,   role `manager`
///   * dmitry.orlov@taskflow.dev     — Backend lead,  role `manager`
///   * olga.pavlova@taskflow.dev     — Marketing PM,  role `manager`
///   * ivan.petrov@taskflow.dev      — iOS engineer,  role `assignee`
///   * anna.smirnova@taskflow.dev    — Android eng.,  role `assignee`
///   * sergey.volkov@taskflow.dev    — Backend eng.,  role `assignee`
///   * maria.kozlova@taskflow.dev    — QA engineer,   role `assignee`
///   * pavel.egorov@taskflow.dev     — UI designer,   role `assignee`
///   * natalia.morozova@taskflow.dev — Product owner, role `viewer`
///   * kirill.lebedev@taskflow.dev   — Stakeholder,   role `viewer`
///   * marina.zaitseva@taskflow.dev  — ex-employee,   `viewer` (deactivated)
/// Password for every account: `Password123!`.
struct SeedRBACAndDemo: AsyncMigration {
    func prepare(on db: Database) async throws {
        if try await Role.query(on: db).count() > 0 { return }

        // ─── Roles & permissions ────────────────────────────────────────────
        let roles = try await seedRoles(on: db)
        let permissions = try await seedPermissions(on: db)
        try await attachPermissions(roles: roles, permissions: permissions, on: db)

        // ─── Users ──────────────────────────────────────────────────────────
        let users = try await seedUsers(roles: roles, on: db)

        // ─── Projects (3 active, 1 archived to demonstrate archival) ────────
        let projects = try await seedProjects(users: users, on: db)
        try await seedProjectMembers(projects: projects, users: users, roles: roles, on: db)

        // ─── Epics, boards, columns ─────────────────────────────────────────
        let epics = try await seedEpics(projects: projects, on: db)
        let boards = try await seedBoardsAndColumns(projects: projects, on: db)

        // ─── Tasks + placements on boards ───────────────────────────────────
        let tasks = try await seedTasks(projects: projects, epics: epics, users: users, on: db)
        try await placeTasksOnBoards(boards: boards, tasks: tasks, on: db)

        // ─── Collaboration artefacts ────────────────────────────────────────
        try await seedComments(tasks: tasks, users: users, on: db)
        try await seedTimeEntries(tasks: tasks, users: users, on: db)
        try await seedNotifications(tasks: tasks, users: users, projects: projects, on: db)
        try await seedAuditLogs(tasks: tasks, users: users, projects: projects, epics: epics, on: db)
    }

    func revert(on db: Database) async throws {}
}

// MARK: - Role / permission seeding

private struct SeedRoles: Sendable {
    let admin: Role
    let manager: Role
    let assignee: Role
    let viewer: Role
}

private struct SeedUsers: Sendable {
    let admin: User
    let elena: User
    let dmitry: User
    let olga: User
    let ivan: User
    let anna: User
    let sergey: User
    let maria: User
    let pavel: User
    let natalia: User
    let kirill: User
    let marina: User

    var allActive: [User] { [admin, elena, dmitry, olga, ivan, anna, sergey, maria, pavel, natalia, kirill] }
    var allIncludingDeactivated: [User] { allActive + [marina] }
}

private struct SeedProjects: Sendable {
    let mobile: Project
    let backend: Project
    let marketing: Project
    let devops: Project

    var active: [Project] { [mobile, backend, marketing] }
}

private struct SeedEpics: Sendable {
    /// Epics keyed by project id for quick access during task seeding.
    let byProject: [UUID: [Epic]]
}

private struct SeedBoards: Sendable {
    /// First board per project plus all columns keyed by column key.
    struct BoardBundle: Sendable {
        let board: Board
        let columns: [String: BoardColumn]
    }

    let mobileMain: BoardBundle
    let mobileSprint: BoardBundle
    let backendMain: BoardBundle
    let marketingMain: BoardBundle
}

private extension SeedRBACAndDemo {

    func seedRoles(on db: Database) async throws -> SeedRoles {
        let admin = Role(name: RoleName.admin, description: "Полный доступ к системе")
        let manager = Role(name: RoleName.manager, description: "Управление проектом: эпики, задачи, доски")
        let assignee = Role(name: RoleName.assignee, description: "Исполнение задач, комментарии, учёт времени")
        let viewer = Role(name: RoleName.viewer, description: "Только просмотр")
        try await admin.save(on: db)
        try await manager.save(on: db)
        try await assignee.save(on: db)
        try await viewer.save(on: db)
        return SeedRoles(admin: admin, manager: manager, assignee: assignee, viewer: viewer)
    }

    func seedPermissions(on db: Database) async throws -> [String: Permission] {
        var perms: [String: Permission] = [:]
        for key in PermissionKey.all {
            let p = Permission(key: key, description: humanisedPermission(key))
            try await p.save(on: db)
            perms[key] = p
        }
        return perms
    }

    func attachPermissions(roles: SeedRoles, permissions: [String: Permission], on db: Database) async throws {
        func attach(_ role: Role, _ keys: [String]) async throws {
            for k in keys {
                guard let p = permissions[k] else { continue }
                try await role.$permissions.attach(p, on: db)
            }
        }

        try await attach(roles.admin, PermissionKey.all)

        try await attach(roles.manager, [
            PermissionKey.projectCreate, PermissionKey.projectView, PermissionKey.projectEdit,
            PermissionKey.projectArchive, PermissionKey.projectMembersManage,
            PermissionKey.epicCreate, PermissionKey.epicView, PermissionKey.epicEdit, PermissionKey.epicArchive,
            PermissionKey.taskCreate, PermissionKey.taskView, PermissionKey.taskEdit,
            PermissionKey.taskAssign, PermissionKey.taskArchive, PermissionKey.taskStatus,
            PermissionKey.commentCreate, PermissionKey.timeLog,
            PermissionKey.boardView, PermissionKey.boardCreate, PermissionKey.boardEdit, PermissionKey.boardMove,
        ])

        try await attach(roles.assignee, [
            PermissionKey.projectView, PermissionKey.epicView, PermissionKey.taskView,
            PermissionKey.taskEdit, PermissionKey.taskAssign, PermissionKey.taskStatus,
            PermissionKey.commentCreate, PermissionKey.timeLog,
            PermissionKey.boardView, PermissionKey.boardMove,
        ])

        try await attach(roles.viewer, [
            PermissionKey.projectView, PermissionKey.epicView,
            PermissionKey.taskView, PermissionKey.boardView,
        ])
    }

    func humanisedPermission(_ key: String) -> String {
        // Produce a short, human-readable description per key so admins
        // browsing the permission list see something meaningful.
        switch key {
        case PermissionKey.projectCreate: return "Создание проектов"
        case PermissionKey.projectView: return "Просмотр проектов"
        case PermissionKey.projectEdit: return "Редактирование проектов"
        case PermissionKey.projectArchive: return "Удаление/архив проектов"
        case PermissionKey.projectMembersManage: return "Управление участниками проекта"
        case PermissionKey.epicCreate: return "Создание эпиков"
        case PermissionKey.epicView: return "Просмотр эпиков"
        case PermissionKey.epicEdit: return "Редактирование эпиков"
        case PermissionKey.epicArchive: return "Удаление/архив эпиков"
        case PermissionKey.taskCreate: return "Создание задач"
        case PermissionKey.taskView: return "Просмотр задач"
        case PermissionKey.taskEdit: return "Редактирование задач"
        case PermissionKey.taskAssign: return "Назначение исполнителя"
        case PermissionKey.taskArchive: return "Удаление задач"
        case PermissionKey.taskStatus: return "Смена статуса задачи"
        case PermissionKey.commentCreate: return "Добавление комментариев"
        case PermissionKey.timeLog: return "Списание времени"
        case PermissionKey.boardView: return "Просмотр досок"
        case PermissionKey.boardCreate: return "Создание досок"
        case PermissionKey.boardEdit: return "Редактирование досок/колонок"
        case PermissionKey.boardMove: return "Перемещение задач на доске"
        case PermissionKey.userManage: return "Управление пользователями"
        case PermissionKey.roleManage: return "Управление ролями"
        default: return key
        }
    }

    // MARK: - Users

    func seedUsers(roles: SeedRoles, on db: Database) async throws -> SeedUsers {
        let password = try Bcrypt.hash("Password123!")

        func user(
            _ email: String,
            _ fullName: String,
            _ roleID: UUID,
            isActive: Bool = true,
            avatarUrl: String? = nil
        ) -> User {
            User(
                email: email,
                passwordHash: password,
                fullName: fullName,
                avatarUrl: avatarUrl,
                roleID: roleID,
                isActive: isActive
            )
        }

        let adminID = roles.admin.id!
        let managerID = roles.manager.id!
        let assigneeID = roles.assignee.id!
        let viewerID = roles.viewer.id!

        let admin = user("admin@demo.local", "Demo Admin", adminID)
        let elena = user("elena.kuznetsova@taskflow.dev", "Елена Кузнецова", managerID,
                         avatarUrl: "https://i.pravatar.cc/150?u=elena")
        let dmitry = user("dmitry.orlov@taskflow.dev", "Дмитрий Орлов", managerID,
                          avatarUrl: "https://i.pravatar.cc/150?u=dmitry")
        let olga = user("olga.pavlova@taskflow.dev", "Ольга Павлова", managerID,
                        avatarUrl: "https://i.pravatar.cc/150?u=olga")
        let ivan = user("ivan.petrov@taskflow.dev", "Иван Петров", assigneeID,
                        avatarUrl: "https://i.pravatar.cc/150?u=ivan")
        let anna = user("anna.smirnova@taskflow.dev", "Анна Смирнова", assigneeID,
                        avatarUrl: "https://i.pravatar.cc/150?u=anna")
        let sergey = user("sergey.volkov@taskflow.dev", "Сергей Волков", assigneeID,
                          avatarUrl: "https://i.pravatar.cc/150?u=sergey")
        let maria = user("maria.kozlova@taskflow.dev", "Мария Козлова", assigneeID,
                         avatarUrl: "https://i.pravatar.cc/150?u=maria")
        let pavel = user("pavel.egorov@taskflow.dev", "Павел Егоров", assigneeID,
                         avatarUrl: "https://i.pravatar.cc/150?u=pavel")
        let natalia = user("natalia.morozova@taskflow.dev", "Наталья Морозова", viewerID,
                           avatarUrl: "https://i.pravatar.cc/150?u=natalia")
        let kirill = user("kirill.lebedev@taskflow.dev", "Кирилл Лебедев", viewerID,
                          avatarUrl: "https://i.pravatar.cc/150?u=kirill")
        let marina = user("marina.zaitseva@taskflow.dev", "Марина Зайцева", viewerID,
                          isActive: false,
                          avatarUrl: "https://i.pravatar.cc/150?u=marina")

        for u in [admin, elena, dmitry, olga, ivan, anna, sergey, maria, pavel, natalia, kirill, marina] {
            try await u.save(on: db)
        }

        return SeedUsers(
            admin: admin, elena: elena, dmitry: dmitry, olga: olga,
            ivan: ivan, anna: anna, sergey: sergey, maria: maria, pavel: pavel,
            natalia: natalia, kirill: kirill, marina: marina
        )
    }

    // MARK: - Projects

    func seedProjects(users: SeedUsers, on db: Database) async throws -> SeedProjects {
        // Pre-size the auto-increment counters so the keys allocated to
        // seeded tasks/epics are consistent with what users will see.
        let mobile = Project(
            key: "TFM",
            name: "TaskFlow Mobile",
            description: "iOS-клиент трекера задач: аутентификация, канбан-доски, учёт времени.",
            ownerID: users.elena.id!,
            isArchived: false,
            nextEpicNumber: 5,
            nextTaskNumber: 13
        )
        let backend = Project(
            key: "TFB",
            name: "TaskFlow Backend",
            description: "Vapor API: проекты, задачи, права доступа, аудит.",
            ownerID: users.dmitry.id!,
            isArchived: false,
            nextEpicNumber: 4,
            nextTaskNumber: 10
        )
        let marketing = Project(
            key: "MKT",
            name: "Marketing Website",
            description: "Публичный лендинг и страницы документации для TaskFlow.",
            ownerID: users.olga.id!,
            isArchived: false,
            nextEpicNumber: 3,
            nextTaskNumber: 7
        )
        let devops = Project(
            key: "OPS",
            name: "DevOps Platform",
            description: "Архивный проект: инфраструктура этапа закрытого тестирования.",
            ownerID: users.dmitry.id!,
            isArchived: true,
            nextEpicNumber: 2,
            nextTaskNumber: 4
        )
        for p in [mobile, backend, marketing, devops] {
            try await p.save(on: db)
        }
        return SeedProjects(mobile: mobile, backend: backend, marketing: marketing, devops: devops)
    }

    func seedProjectMembers(
        projects: SeedProjects,
        users: SeedUsers,
        roles: SeedRoles,
        on db: Database
    ) async throws {
        // Each active project has: manager-owner, several assignees, one viewer.
        // The admin is intentionally NOT added as a project member — admins
        // have global access via `isAdmin`, so this also exercises that path.
        struct Membership {
            let project: Project
            let user: User
            let roleID: UUID
        }

        let m: [Membership] = [
            // TaskFlow Mobile
            .init(project: projects.mobile, user: users.elena, roleID: roles.manager.id!),
            .init(project: projects.mobile, user: users.ivan, roleID: roles.assignee.id!),
            .init(project: projects.mobile, user: users.anna, roleID: roles.assignee.id!),
            .init(project: projects.mobile, user: users.pavel, roleID: roles.assignee.id!),
            .init(project: projects.mobile, user: users.maria, roleID: roles.assignee.id!),
            .init(project: projects.mobile, user: users.natalia, roleID: roles.viewer.id!),

            // TaskFlow Backend
            .init(project: projects.backend, user: users.dmitry, roleID: roles.manager.id!),
            .init(project: projects.backend, user: users.sergey, roleID: roles.assignee.id!),
            .init(project: projects.backend, user: users.maria, roleID: roles.assignee.id!),
            .init(project: projects.backend, user: users.kirill, roleID: roles.viewer.id!),

            // Marketing Website
            .init(project: projects.marketing, user: users.olga, roleID: roles.manager.id!),
            .init(project: projects.marketing, user: users.pavel, roleID: roles.assignee.id!),
            .init(project: projects.marketing, user: users.natalia, roleID: roles.viewer.id!),
        ]
        for entry in m {
            let pm = ProjectMember(
                projectID: entry.project.id!,
                userID: entry.user.id!,
                roleID: entry.roleID
            )
            try await pm.save(on: db)
        }
    }

    // MARK: - Epics

    func seedEpics(projects: SeedProjects, on db: Database) async throws -> SeedEpics {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)

        func date(daysFromNow offset: Int) -> Date {
            cal.date(byAdding: .day, value: offset, to: now)!
        }

        struct EpicSpec {
            let project: Project
            let key: String
            let title: String
            let description: String
            let status: String
            let start: Date?
            let due: Date?
        }

        let specs: [EpicSpec] = [
            // Mobile
            .init(project: projects.mobile, key: "TFM-E1",
                  title: "Редизайн аутентификации",
                  description: "Полный редизайн экрана входа, восстановление пароля, биометрия.",
                  status: "done", start: date(daysFromNow: -60), due: date(daysFromNow: -10)),
            .init(project: projects.mobile, key: "TFM-E2",
                  title: "Офлайн-режим",
                  description: "Кеширование задач и досок, отложенная синхронизация при появлении сети.",
                  status: "in_progress", start: date(daysFromNow: -30), due: date(daysFromNow: 20)),
            .init(project: projects.mobile, key: "TFM-E3",
                  title: "Push-уведомления",
                  description: "APNs-интеграция и экран настроек уведомлений.",
                  status: "open", start: date(daysFromNow: 10), due: date(daysFromNow: 45)),
            .init(project: projects.mobile, key: "TFM-E4",
                  title: "Тёмная тема",
                  description: "Тёмная тема и переключатель акцентного цвета.",
                  status: "in_progress", start: date(daysFromNow: -7), due: date(daysFromNow: 30)),

            // Backend
            .init(project: projects.backend, key: "TFB-E1",
                  title: "Модуль RBAC",
                  description: "Роли, права, права уровня проекта.",
                  status: "done", start: date(daysFromNow: -90), due: date(daysFromNow: -30)),
            .init(project: projects.backend, key: "TFB-E2",
                  title: "Отчёты и аналитика",
                  description: "Эндпоинты агрегации по статусам и временным затратам.",
                  status: "in_progress", start: date(daysFromNow: -14), due: date(daysFromNow: 28)),
            .init(project: projects.backend, key: "TFB-E3",
                  title: "Оптимизация производительности",
                  description: "Индексы, ленивые загрузки связанных объектов, устранение N+1.",
                  status: "open", start: nil, due: date(daysFromNow: 60)),

            // Marketing
            .init(project: projects.marketing, key: "MKT-E1",
                  title: "Лендинг v2",
                  description: "Перезапуск главной страницы с новыми секциями и демо-видео.",
                  status: "in_progress", start: date(daysFromNow: -20), due: date(daysFromNow: 15)),
            .init(project: projects.marketing, key: "MKT-E2",
                  title: "SEO-контент",
                  description: "Блог и посадочные страницы по целевым запросам.",
                  status: "open", start: date(daysFromNow: 5), due: date(daysFromNow: 75)),
        ]

        var byProject: [UUID: [Epic]] = [:]
        for spec in specs {
            let epic = Epic(
                projectID: spec.project.id!,
                key: spec.key,
                title: spec.title,
                description: spec.description,
                status: spec.status,
                startDate: spec.start,
                dueDate: spec.due,
                isArchived: false
            )
            try await epic.save(on: db)
            byProject[spec.project.id!, default: []].append(epic)
        }
        return SeedEpics(byProject: byProject)
    }

    // MARK: - Boards & columns

    func seedBoardsAndColumns(projects: SeedProjects, on db: Database) async throws -> SeedBoards {
        func makeBoard(
            projectID: UUID,
            name: String,
            description: String,
            isDefault: Bool
        ) async throws -> SeedBoards.BoardBundle {
            let board = Board(
                projectID: projectID,
                name: name,
                description: description,
                isDefault: isDefault,
                isArchived: false
            )
            try await board.save(on: db)
            let specs: [(String, String, Int, Int?, Bool)] = [
                ("Backlog", "backlog", 1, nil, false),
                ("To Do", "todo", 2, 10, false),
                ("In Progress", "in_progress", 3, 5, false),
                ("Review", "review", 4, 4, false),
                ("Done", "done", 5, nil, true),
            ]
            var map: [String: BoardColumn] = [:]
            for s in specs {
                let col = BoardColumn(
                    boardID: board.id!,
                    name: s.0, key: s.1, orderIndex: s.2,
                    wipLimit: s.3, isDoneColumn: s.4
                )
                try await col.save(on: db)
                map[s.1] = col
            }
            return SeedBoards.BoardBundle(board: board, columns: map)
        }

        let mobileMain = try await makeBoard(
            projectID: projects.mobile.id!,
            name: "Основная доска",
            description: "Канбан для ежедневной работы мобильной команды.",
            isDefault: true
        )
        let mobileSprint = try await makeBoard(
            projectID: projects.mobile.id!,
            name: "Спринт 42",
            description: "Задачи текущего двухнедельного спринта.",
            isDefault: false
        )
        let backendMain = try await makeBoard(
            projectID: projects.backend.id!,
            name: "Бэкенд-канбан",
            description: "Проверка и релиз задач API.",
            isDefault: true
        )
        let marketingMain = try await makeBoard(
            projectID: projects.marketing.id!,
            name: "Кампания Q3",
            description: "Копирайтинг, дизайн и публикация материалов.",
            isDefault: true
        )
        return SeedBoards(
            mobileMain: mobileMain, mobileSprint: mobileSprint,
            backendMain: backendMain, marketingMain: marketingMain
        )
    }

    // MARK: - Tasks

    func seedTasks(
        projects: SeedProjects,
        epics: SeedEpics,
        users: SeedUsers,
        on db: Database
    ) async throws -> [UUID: [WorkTask]] {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        func due(_ days: Int) -> Date? { cal.date(byAdding: .day, value: days, to: now) }

        struct TaskSpec: Sendable {
            let project: Project
            let epicKey: String?          // match to an epic by its key
            let key: String
            let title: String
            let description: String
            let issueType: String          // task / bug / feature
            let priority: String
            let status: String
            let assignee: User?
            let reporter: User
            let estimate: Int
            let spent: Int
            let due: Date?
            let isArchived: Bool
            let parentKey: String?         // optional parent key for subtasks
        }

        let m = projects.mobile
        let b = projects.backend
        let mk = projects.marketing

        let specs: [TaskSpec] = [
            // ── TaskFlow Mobile ──────────────────────────────────────────
            .init(project: m, epicKey: "TFM-E1", key: "TFM-1",
                  title: "Экран входа в новом стиле",
                  description: "Обновить экран входа под бренд и добавить иллюстрацию.",
                  issueType: "feature", priority: "high", status: "done",
                  assignee: users.pavel, reporter: users.elena,
                  estimate: 240, spent: 220, due: due(-20), isArchived: false, parentKey: nil),

            .init(project: m, epicKey: "TFM-E1", key: "TFM-2",
                  title: "Biometric login (Face ID / Touch ID)",
                  description: "Интеграция LocalAuthentication и сохранение fallback pin-кода.",
                  issueType: "feature", priority: "high", status: "done",
                  assignee: users.ivan, reporter: users.elena,
                  estimate: 360, spent: 340, due: due(-14), isArchived: false, parentKey: nil),

            .init(project: m, epicKey: "TFM-E2", key: "TFM-3",
                  title: "Локальный кеш задач",
                  description: "SQLite-кеш + синхронизация при восстановлении сети.",
                  issueType: "task", priority: "high", status: "in_progress",
                  assignee: users.ivan, reporter: users.elena,
                  estimate: 480, spent: 260, due: due(14), isArchived: false, parentKey: nil),

            .init(project: m, epicKey: "TFM-E2", key: "TFM-4",
                  title: "Очередь отложенных операций",
                  description: "Отложенный PATCH/POST, повтор после появления сети.",
                  issueType: "task", priority: "medium", status: "todo",
                  assignee: users.ivan, reporter: users.elena,
                  estimate: 300, spent: 0, due: due(18), isArchived: false, parentKey: "TFM-3"),

            .init(project: m, epicKey: "TFM-E2", key: "TFM-5",
                  title: "Индикатор оффлайна на главном экране",
                  description: "Показ баннера и блокировка кнопок создания при отсутствии сети.",
                  issueType: "feature", priority: "low", status: "todo",
                  assignee: users.pavel, reporter: users.elena,
                  estimate: 120, spent: 0, due: due(21), isArchived: false, parentKey: nil),

            .init(project: m, epicKey: "TFM-E3", key: "TFM-6",
                  title: "Регистрация APNs токена на бэкенде",
                  description: "Отправлять device token при логине и обновлять при смене.",
                  issueType: "task", priority: "medium", status: "todo",
                  assignee: users.ivan, reporter: users.elena,
                  estimate: 180, spent: 0, due: due(35), isArchived: false, parentKey: nil),

            .init(project: m, epicKey: "TFM-E4", key: "TFM-7",
                  title: "Переключатель акцентного цвета",
                  description: "Пять цветов, alternate app icon, сохранение между запусками.",
                  issueType: "feature", priority: "medium", status: "in_progress",
                  assignee: users.pavel, reporter: users.elena,
                  estimate: 240, spent: 150, due: due(7), isArchived: false, parentKey: nil),

            .init(project: m, epicKey: "TFM-E4", key: "TFM-8",
                  title: "Контрастность текста в тёмной теме",
                  description: "Аудит цветов вторичного текста, фиксы.",
                  issueType: "bug", priority: "low", status: "review",
                  assignee: users.pavel, reporter: users.maria,
                  estimate: 90, spent: 90, due: due(3), isArchived: false, parentKey: nil),

            .init(project: m, epicKey: nil, key: "TFM-9",
                  title: "Падение при пустом ответе сервера",
                  description: "Воспроизводится при неверном токене: APIClient бросает decoding error.",
                  issueType: "bug", priority: "critical", status: "in_progress",
                  assignee: users.anna, reporter: users.maria,
                  estimate: 120, spent: 90, due: due(1), isArchived: false, parentKey: nil),

            .init(project: m, epicKey: nil, key: "TFM-10",
                  title: "Обновить README в GitHub",
                  description: "Инструкция запуска демо и скриншоты.",
                  issueType: "task", priority: "low", status: "todo",
                  assignee: nil, reporter: users.elena,
                  estimate: 60, spent: 0, due: nil, isArchived: false, parentKey: nil),

            .init(project: m, epicKey: nil, key: "TFM-11",
                  title: "Исправить опечатки в текстах",
                  description: "Архивная задача: исправлено в рамках TFM-1.",
                  issueType: "task", priority: "low", status: "done",
                  assignee: users.pavel, reporter: users.elena,
                  estimate: 30, spent: 30, due: due(-25), isArchived: true, parentKey: nil),

            .init(project: m, epicKey: "TFM-E4", key: "TFM-12",
                  title: "Добавить иконку приложения в сборку",
                  description: "Создать 5 вариантов иконок для каждого акцентного цвета.",
                  issueType: "feature", priority: "medium", status: "done",
                  assignee: users.pavel, reporter: users.elena,
                  estimate: 180, spent: 160, due: due(-2), isArchived: false, parentKey: nil),

            // ── TaskFlow Backend ─────────────────────────────────────────
            .init(project: b, epicKey: "TFB-E1", key: "TFB-1",
                  title: "Миграция ролей и прав",
                  description: "Seeds для admin/manager/assignee/viewer, permission keys.",
                  issueType: "task", priority: "high", status: "done",
                  assignee: users.sergey, reporter: users.dmitry,
                  estimate: 240, spent: 220, due: due(-45), isArchived: false, parentKey: nil),

            .init(project: b, epicKey: "TFB-E1", key: "TFB-2",
                  title: "JWT refresh + revoke",
                  description: "Выдача пары access/refresh, revoke по jti, rotation.",
                  issueType: "feature", priority: "high", status: "done",
                  assignee: users.sergey, reporter: users.dmitry,
                  estimate: 360, spent: 350, due: due(-35), isArchived: false, parentKey: nil),

            .init(project: b, epicKey: "TFB-E2", key: "TFB-3",
                  title: "Эндпоинт агрегации по статусам",
                  description: "GET /reports/status?projectId=... — count задач по каждому статусу.",
                  issueType: "feature", priority: "medium", status: "in_progress",
                  assignee: users.sergey, reporter: users.dmitry,
                  estimate: 300, spent: 180, due: due(10), isArchived: false, parentKey: nil),

            .init(project: b, epicKey: "TFB-E2", key: "TFB-4",
                  title: "Отчёт по времени за период",
                  description: "Сумма spent_minutes по пользователю/проекту с фильтром дат.",
                  issueType: "task", priority: "medium", status: "todo",
                  assignee: users.sergey, reporter: users.dmitry,
                  estimate: 240, spent: 0, due: due(21), isArchived: false, parentKey: "TFB-3"),

            .init(project: b, epicKey: "TFB-E3", key: "TFB-5",
                  title: "Добавить индексы для выборки задач по проекту",
                  description: "Explain-анализ текущих запросов и добавление индексов.",
                  issueType: "task", priority: "high", status: "review",
                  assignee: users.sergey, reporter: users.dmitry,
                  estimate: 180, spent: 160, due: due(4), isArchived: false, parentKey: nil),

            .init(project: b, epicKey: "TFB-E3", key: "TFB-6",
                  title: "Убрать N+1 в BoardController.get",
                  description: "Eager-load колонок и задач на доске одним запросом.",
                  issueType: "bug", priority: "high", status: "in_progress",
                  assignee: users.sergey, reporter: users.maria,
                  estimate: 150, spent: 60, due: due(6), isArchived: false, parentKey: nil),

            .init(project: b, epicKey: nil, key: "TFB-7",
                  title: "ErrorMiddleware: раскрытие details",
                  description: "Возвращать описание ошибки в details[] для отладки.",
                  issueType: "task", priority: "low", status: "done",
                  assignee: users.sergey, reporter: users.dmitry,
                  estimate: 60, spent: 50, due: due(-5), isArchived: false, parentKey: nil),

            .init(project: b, epicKey: nil, key: "TFB-8",
                  title: "Health check возвращает 500 при простое БД",
                  description: "При недоступности БД health должен возвращать disconnected, но 200 ok.",
                  issueType: "bug", priority: "medium", status: "todo",
                  assignee: users.sergey, reporter: users.maria,
                  estimate: 90, spent: 0, due: due(12), isArchived: false, parentKey: nil),

            .init(project: b, epicKey: nil, key: "TFB-9",
                  title: "Обновить Swagger-спеку",
                  description: "Отразить новые эндпоинты PATCH /boards и DELETE /columns.",
                  issueType: "task", priority: "low", status: "todo",
                  assignee: nil, reporter: users.dmitry,
                  estimate: 120, spent: 0, due: nil, isArchived: false, parentKey: nil),

            // ── Marketing Website ────────────────────────────────────────
            .init(project: mk, epicKey: "MKT-E1", key: "MKT-1",
                  title: "Дизайн-макет главной страницы",
                  description: "Figma-макет с 6 секциями и демо-видео.",
                  issueType: "task", priority: "high", status: "done",
                  assignee: users.pavel, reporter: users.olga,
                  estimate: 360, spent: 400, due: due(-10), isArchived: false, parentKey: nil),

            .init(project: mk, epicKey: "MKT-E1", key: "MKT-2",
                  title: "Вёрстка секции features",
                  description: "Responsive grid, тёмная тема.",
                  issueType: "task", priority: "medium", status: "in_progress",
                  assignee: users.pavel, reporter: users.olga,
                  estimate: 240, spent: 120, due: due(5), isArchived: false, parentKey: nil),

            .init(project: mk, epicKey: "MKT-E1", key: "MKT-3",
                  title: "Видео-скринкаст про канбан",
                  description: "90-секундный ролик для hero-секции.",
                  issueType: "task", priority: "medium", status: "todo",
                  assignee: nil, reporter: users.olga,
                  estimate: 180, spent: 0, due: due(9), isArchived: false, parentKey: nil),

            .init(project: mk, epicKey: "MKT-E2", key: "MKT-4",
                  title: "Статья «Как настроить RBAC»",
                  description: "Разобрать роли и права на примере демо-данных.",
                  issueType: "task", priority: "low", status: "todo",
                  assignee: users.pavel, reporter: users.olga,
                  estimate: 240, spent: 0, due: due(25), isArchived: false, parentKey: nil),

            .init(project: mk, epicKey: nil, key: "MKT-5",
                  title: "Баг: на iPhone SE ломается hero",
                  description: "Картинка уходит за пределы экрана.",
                  issueType: "bug", priority: "high", status: "review",
                  assignee: users.pavel, reporter: users.maria,
                  estimate: 60, spent: 50, due: due(2), isArchived: false, parentKey: nil),

            .init(project: mk, epicKey: nil, key: "MKT-6",
                  title: "Настроить аналитику",
                  description: "Подключить Plausible и цели на сабмит формы.",
                  issueType: "task", priority: "medium", status: "done",
                  assignee: users.olga, reporter: users.olga,
                  estimate: 90, spent: 80, due: due(-3), isArchived: false, parentKey: nil),
        ]

        // First pass creates every task without the parent link; the second
        // pass resolves parent keys now that every task id is known.
        var byKey: [String: WorkTask] = [:]
        for s in specs {
            let task = WorkTask(
                projectID: s.project.id!,
                epicID: s.epicKey.flatMap { k in epics.byProject[s.project.id!]?.first(where: { $0.key == k })?.id },
                parentTaskID: nil,
                key: s.key,
                title: s.title,
                description: s.description,
                issueType: s.issueType,
                priority: s.priority,
                status: s.status,
                assigneeID: s.assignee?.id,
                reporterID: s.reporter.id!,
                estimateMinutes: s.estimate,
                spentMinutes: s.spent,
                dueDate: s.due,
                isArchived: s.isArchived
            )
            if s.status == "done" || s.status == "closed" {
                task.closedAt = cal.date(byAdding: .day, value: -1, to: now)
            }
            try await task.save(on: db)
            byKey[s.key] = task
        }
        for s in specs where s.parentKey != nil {
            guard let child = byKey[s.key], let parent = byKey[s.parentKey!] else { continue }
            child.$parent.id = parent.id
            try await child.save(on: db)
        }

        var byProject: [UUID: [WorkTask]] = [:]
        for task in byKey.values {
            byProject[task.$project.id, default: []].append(task)
        }
        return byProject
    }

    // MARK: - Place tasks on boards

    func placeTasksOnBoards(
        boards: SeedBoards,
        tasks: [UUID: [WorkTask]],
        on db: Database
    ) async throws {
        func place(
            _ bundle: SeedBoards.BoardBundle,
            tasks: [WorkTask]
        ) async throws {
            var order: [String: Int] = [:]
            for task in tasks where !task.isArchived {
                let columnKey = boardKey(for: task.status)
                guard let column = bundle.columns[columnKey] else { continue }
                let next = (order[columnKey] ?? 0) + 1
                order[columnKey] = next
                let state = BoardTaskState(
                    boardID: bundle.board.id!,
                    taskID: task.id!,
                    boardColumnID: column.id!,
                    orderIndex: next
                )
                try await state.save(on: db)
            }
        }

        if let mobileTasks = tasks.first(where: { $0.value.first?.$project.id != nil })?.value {
            _ = mobileTasks // silence unused-let warning path
        }
        for (projectID, projectTasks) in tasks {
            let board: SeedBoards.BoardBundle
            switch projectID {
            case boards.mobileMain.board.$project.id:
                board = boards.mobileMain
            case boards.backendMain.board.$project.id:
                board = boards.backendMain
            case boards.marketingMain.board.$project.id:
                board = boards.marketingMain
            default:
                continue
            }
            try await place(board, tasks: projectTasks)
        }
        // Additionally put a subset of Mobile tasks on the sprint board to
        // demonstrate that the same task can belong to multiple boards.
        if let mobileTasks = tasks[boards.mobileMain.board.$project.id] {
            let inSprint = mobileTasks
                .filter { !$0.isArchived && ($0.status == "in_progress" || $0.status == "review" || $0.status == "todo") }
                .prefix(5)
            var order: [String: Int] = [:]
            for task in inSprint {
                let columnKey = boardKey(for: task.status)
                guard let column = boards.mobileSprint.columns[columnKey] else { continue }
                let next = (order[columnKey] ?? 0) + 1
                order[columnKey] = next
                let state = BoardTaskState(
                    boardID: boards.mobileSprint.board.id!,
                    taskID: task.id!,
                    boardColumnID: column.id!,
                    orderIndex: next
                )
                try await state.save(on: db)
            }
        }
    }

    func boardKey(for status: String) -> String {
        switch status {
        case "todo": return "todo"
        case "in_progress": return "in_progress"
        case "review": return "review"
        case "done", "closed": return "done"
        default: return "backlog"
        }
    }

    // MARK: - Comments

    func seedComments(tasks: [UUID: [WorkTask]], users: SeedUsers, on db: Database) async throws {
        // Pick a handful of tasks that clearly benefit from discussion to
        // avoid burying the UI in noise while still showing collaboration.
        let interesting = tasks.values.flatMap { $0 }.filter {
            ["in_progress", "review", "done"].contains($0.status) && !$0.isArchived
        }

        struct CommentSpec { let title: String; let author: User; let body: String }

        let palettes: [[CommentSpec]] = [
            [
                .init(title: "", author: users.maria,  body: "Прошла базовый smoke — всё ок, падений нет."),
                .init(title: "", author: users.elena,  body: "Принимаю. Ждём финальный дизайн от Павла и катим."),
                .init(title: "", author: users.pavel,  body: "Обновил макет, добавил тёмный вариант."),
                .init(title: "", author: users.natalia,body: "Продукт: согласован, релиз через неделю."),
            ],
            [
                .init(title: "", author: users.dmitry, body: "Нужно прогнать нагрузочный тест до релиза."),
                .init(title: "", author: users.sergey, body: "Запустил k6 — 95-й перцентиль 120ms, норма."),
                .init(title: "", author: users.maria,  body: "Подтверждаю: регрессов нет, apdex 0.98."),
            ],
            [
                .init(title: "", author: users.ivan,   body: "Воспроизвёл локально, готовлю PR."),
                .init(title: "", author: users.anna,   body: "Скинь дифф — посмотрю, мне надо для Android."),
                .init(title: "", author: users.ivan,   body: "Готово, PR открыт, жду ревью."),
                .init(title: "", author: users.elena,  body: "Смотрю."),
            ],
        ]

        for (idx, task) in interesting.prefix(12).enumerated() {
            let palette = palettes[idx % palettes.count]
            for spec in palette {
                let c = Comment(taskID: task.id!, authorID: spec.author.id!, body: spec.body)
                try await c.save(on: db)
            }
        }
    }

    // MARK: - Time entries

    func seedTimeEntries(tasks: [UUID: [WorkTask]], users: SeedUsers, on db: Database) async throws {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)

        let everyTask = tasks.values.flatMap { $0 }
        // Only log time for tasks that have a real assignee and aren't
        // archived — otherwise the history row looks wrong.
        let candidates = everyTask.filter { !$0.isArchived && $0.$assignee.id != nil && $0.spentMinutes > 0 }

        for task in candidates {
            // Split the recorded total across 2–3 realistic sessions so the
            // mobile time-tracking screen renders multiple history rows.
            let assigneeID = task.$assignee.id!
            let total = task.spentMinutes
            let sessions: [Int]
            switch total {
            case 0..<90: sessions = [total]
            case 90..<240: sessions = [Int(Double(total) * 0.6), total - Int(Double(total) * 0.6)]
            default:
                let first = Int(Double(total) * 0.4)
                let second = Int(Double(total) * 0.35)
                sessions = [first, second, total - first - second]
            }
            for (i, minutes) in sessions.enumerated() where minutes > 0 {
                let started = cal.date(byAdding: .day, value: -i - 1, to: now)!
                let te = TimeEntry(
                    taskID: task.id!,
                    userID: assigneeID,
                    spentMinutes: minutes,
                    comment: i == 0 ? "Работа по задаче" : "Продолжение",
                    startedAt: started
                )
                try await te.save(on: db)
            }
            // Add a QA session by Maria for tasks that went through review.
            if task.status == "review" || task.status == "done" {
                let te = TimeEntry(
                    taskID: task.id!,
                    userID: users.maria.id!,
                    spentMinutes: 30,
                    comment: "Проверка и smoke-тест",
                    startedAt: cal.date(byAdding: .hour, value: -12, to: now)!
                )
                try await te.save(on: db)
            }
        }
    }

    // MARK: - Notifications

    func seedNotifications(
        tasks: [UUID: [WorkTask]],
        users: SeedUsers,
        projects: SeedProjects,
        on db: Database
    ) async throws {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()

        // Build 3–4 notifications per active user so each account demonstrates
        // the notifications screen on first login.
        func assigned(user: User, task: WorkTask, ago days: Int, read: Bool) async throws {
            let n = UserNotification(
                userID: user.id!,
                type: "task_assigned",
                title: "На вас назначена задача",
                body: "\(task.key): \(task.title)",
                entityType: "task",
                entityId: task.id!,
                isRead: read
            )
            n.$user.id = user.id!
            try await n.save(on: db)
            if let created = cal.date(byAdding: .day, value: -days, to: now) {
                n.createdAt = created
                try await n.save(on: db)
            }
        }

        func mentioned(user: User, task: WorkTask, ago days: Int, read: Bool) async throws {
            let n = UserNotification(
                userID: user.id!,
                type: "comment_mention",
                title: "Упоминание в комментарии",
                body: "Коллеги обсуждают задачу \(task.key)",
                entityType: "task",
                entityId: task.id!,
                isRead: read
            )
            try await n.save(on: db)
            if let created = cal.date(byAdding: .day, value: -days, to: now) {
                n.createdAt = created
                try await n.save(on: db)
            }
        }

        func projectMembership(user: User, project: Project, ago days: Int, read: Bool) async throws {
            let n = UserNotification(
                userID: user.id!,
                type: "project_membership",
                title: "Вас добавили в проект",
                body: "\(project.key) · \(project.name)",
                entityType: "project",
                entityId: project.id!,
                isRead: read
            )
            try await n.save(on: db)
            if let created = cal.date(byAdding: .day, value: -days, to: now) {
                n.createdAt = created
                try await n.save(on: db)
            }
        }

        let allTasks = tasks.values.flatMap { $0 }
        let ivanTasks = allTasks.filter { $0.$assignee.id == users.ivan.id }
        let sergeyTasks = allTasks.filter { $0.$assignee.id == users.sergey.id }
        let pavelTasks = allTasks.filter { $0.$assignee.id == users.pavel.id }

        if let t = ivanTasks.first { try await assigned(user: users.ivan, task: t, ago: 0, read: false) }
        if ivanTasks.count > 1 { try await mentioned(user: users.ivan, task: ivanTasks[1], ago: 1, read: false) }
        if ivanTasks.count > 2 { try await assigned(user: users.ivan, task: ivanTasks[2], ago: 3, read: true) }
        try await projectMembership(user: users.ivan, project: projects.mobile, ago: 30, read: true)

        if let t = sergeyTasks.first { try await assigned(user: users.sergey, task: t, ago: 0, read: false) }
        if sergeyTasks.count > 1 { try await mentioned(user: users.sergey, task: sergeyTasks[1], ago: 2, read: true) }
        if sergeyTasks.count > 2 { try await assigned(user: users.sergey, task: sergeyTasks[2], ago: 4, read: true) }

        if let t = pavelTasks.first { try await assigned(user: users.pavel, task: t, ago: 0, read: false) }
        if pavelTasks.count > 1 { try await mentioned(user: users.pavel, task: pavelTasks[1], ago: 1, read: true) }

        try await projectMembership(user: users.maria, project: projects.backend, ago: 5, read: false)
        try await projectMembership(user: users.natalia, project: projects.marketing, ago: 7, read: true)
        try await projectMembership(user: users.kirill, project: projects.backend, ago: 2, read: false)
    }

    // MARK: - Audit logs

    func seedAuditLogs(
        tasks: [UUID: [WorkTask]],
        users: SeedUsers,
        projects: SeedProjects,
        epics: SeedEpics,
        on db: Database
    ) async throws {
        let allTasks = tasks.values.flatMap { $0 }

        // Project-level audit events.
        for (project, actor, action) in [
            (projects.mobile, users.elena, "create"),
            (projects.backend, users.dmitry, "create"),
            (projects.marketing, users.olga, "create"),
            (projects.devops, users.dmitry, "archive"),
        ] {
            let log = AuditLog(
                actorID: actor.id,
                entityType: "project",
                entityId: project.id!,
                action: action
            )
            try await log.save(on: db)
        }

        // Epic-level events (one per active project's first epic).
        for (_, eps) in epics.byProject {
            if let first = eps.first {
                let log = AuditLog(
                    actorID: users.admin.id,
                    entityType: "epic",
                    entityId: first.id!,
                    action: "create"
                )
                try await log.save(on: db)
            }
        }

        // Task-level events for the four most recently updated tasks.
        for task in allTasks.prefix(6) {
            try await AuditLog(
                actorID: task.$reporter.id,
                entityType: "task",
                entityId: task.id!,
                action: "create"
            ).save(on: db)
            if task.status == "done" {
                try await AuditLog(
                    actorID: task.$assignee.id,
                    entityType: "task",
                    entityId: task.id!,
                    action: "status",
                    afterJson: "{\"status\":\"done\"}"
                ).save(on: db)
            }
        }
    }
}
