import Fluent
import Vapor

enum BoardController {
    static func list(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        try await req.requirePermission(PermissionKey.boardView)
        let q = try req.query.decode(BoardListQuery.self)
        var base = Board.query(on: req.db).filter(\.$isArchived == false)
        if let pid = q.projectId {
            guard try await RBACService.canAccessProject(userId: uid, projectId: pid, on: req.db) else { throw AppError.forbidden }
            base = base.filter(\.$project.$id == pid)
        } else if try await !RBACService.isAdmin(userId: uid, on: req.db) {
            let pids = try await ProjectMember.query(on: req.db).filter(\.$user.$id == uid).all().map(\.$project.id)
            let owned = try await Project.query(on: req.db).filter(\.$owner.$id == uid).all().map(\.id!)
            let ids = Array(Set(pids + owned))
            if ids.isEmpty {
                return try Response.json(envelopeOk([BoardRowDTO](), meta: nil))
            }
            base = base.filter(\.$project.$id ~~ ids)
        }
        let boards = try await base.sort(\.$name, .ascending).all()
        let rows = boards.map { BoardRowDTO(id: $0.id!, projectId: $0.$project.id, name: $0.name, isDefault: $0.isDefault) }
        return try Response.json(envelopeOk(rows, meta: nil))
    }

    static func create(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let body = try req.content.decode(BoardCreateRequest.self)
        // Explicitly validate the referenced project exists so we return a
        // typed 404 (AppError) instead of letting Fluent throw a raw
        // foreign-key failure that surfaces to the mobile client as an
        // opaque "unexpected error occurred" (defect 3a).
        guard try await Project.find(body.projectId, on: req.db) != nil else {
            throw AppError.notFound("Project not found")
        }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: body.projectId, permission: PermissionKey.boardCreate, on: req.db)
        else { throw AppError.forbidden }
        if body.isDefault == true {
            let existing = try await Board.query(on: req.db).filter(\.$project.$id == body.projectId).filter(\.$isDefault == true).all()
            for b in existing {
                b.isDefault = false
                try await b.save(on: req.db)
            }
        }
        let b = Board(
            projectID: body.projectId,
            name: body.name,
            description: body.description,
            isDefault: body.isDefault ?? false,
            isArchived: false
        )
        try await b.save(on: req.db)
        // Defect 3b: auto-seed a standard set of columns so a freshly
        // created board is immediately populated in the Kanban view and
        // moving/ordering tasks has meaningful destinations. Without this,
        // the mobile Kanban renders an empty board because
        // `board.columns` is empty.
        guard let boardId = b.id else { throw AppError.internalError("Board id missing after save") }
        let defaultColumns: [(name: String, key: String, order: Int, isDone: Bool)] = [
            ("Backlog", "backlog", 1, false),
            ("To Do", "todo", 2, false),
            ("In Progress", "in_progress", 3, false),
            ("Review", "review", 4, false),
            ("Done", "done", 5, true),
        ]
        for col in defaultColumns {
            let entity = BoardColumn(
                boardID: boardId,
                name: col.name,
                key: col.key,
                orderIndex: col.order,
                wipLimit: nil,
                isDoneColumn: col.isDone
            )
            try await entity.save(on: req.db)
        }
        struct Out: Encodable {
            var id: UUID
            var projectId: UUID
            var name: String
            var description: String
            var isDefault: Bool
        }
        let dto = Out(id: boardId, projectId: body.projectId, name: b.name, description: b.description, isDefault: b.isDefault)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "board", entityId: boardId, action: "create")
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func get(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let bid = try req.parameters.require("boardId", as: UUID.self)
        guard let board = try await Board.find(bid, on: req.db), !board.isArchived else { throw AppError.notFound("Board not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: board.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.boardView)
        let cols = try await BoardColumn.query(on: req.db).filter(\.$board.$id == bid).sort(\.$orderIndex, .ascending).all()
        let cdto = cols.map {
            BoardColumnDTO(id: $0.id!, name: $0.name, key: $0.key, orderIndex: $0.orderIndex, wipLimit: $0.wipLimit, isDoneColumn: $0.isDoneColumn)
        }
        let dto = BoardDetailDTO(id: board.id!, projectId: board.$project.id, name: board.name, columns: cdto)
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func update(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let bid = try req.parameters.require("boardId", as: UUID.self)
        guard let board = try await Board.find(bid, on: req.db), !board.isArchived else { throw AppError.notFound("Board not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: board.$project.id, permission: PermissionKey.boardEdit, on: req.db)
        else { throw AppError.forbidden }
        let body = try req.content.decode(BoardUpdateRequest.self)
        if let n = body.name { board.name = n }
        if let d = body.description { board.description = d }
        try await board.save(on: req.db)
        struct Out: Encodable { var id: UUID; var name: String; var description: String }
        let dto = Out(id: bid, name: board.name, description: board.description)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "board", entityId: bid, action: "update")
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func archive(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let bid = try req.parameters.require("boardId", as: UUID.self)
        guard let board = try await Board.find(bid, on: req.db) else { throw AppError.notFound("Board not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: board.$project.id, permission: PermissionKey.boardEdit, on: req.db)
        else { throw AppError.forbidden }
        board.isArchived = true
        try await board.save(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "board", entityId: bid, action: "archive")
        return try Response.json(envelopeOk(MessageData(message: "Board archived"), meta: nil))
    }

    static func listColumns(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let bid = try req.parameters.require("boardId", as: UUID.self)
        guard let board = try await Board.find(bid, on: req.db) else { throw AppError.notFound("Board not found") }
        guard try await RBACService.canAccessProject(userId: uid, projectId: board.$project.id, on: req.db) else { throw AppError.forbidden }
        try await req.requirePermission(PermissionKey.boardView)
        let cols = try await BoardColumn.query(on: req.db).filter(\.$board.$id == bid).sort(\.$orderIndex, .ascending).all()
        let cdto = cols.map {
            BoardColumnDTO(id: $0.id!, name: $0.name, key: $0.key, orderIndex: $0.orderIndex, wipLimit: $0.wipLimit, isDoneColumn: $0.isDoneColumn)
        }
        return try Response.json(envelopeOk(cdto, meta: nil))
    }

    static func createColumn(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let bid = try req.parameters.require("boardId", as: UUID.self)
        guard let board = try await Board.find(bid, on: req.db) else { throw AppError.notFound("Board not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: board.$project.id, permission: PermissionKey.boardEdit, on: req.db)
        else { throw AppError.forbidden }
        let body = try req.content.decode(BoardColumnCreateRequest.self)
        let col = BoardColumn(
            boardID: bid,
            name: body.name,
            key: body.key,
            orderIndex: body.orderIndex,
            wipLimit: body.wipLimit,
            isDoneColumn: body.isDoneColumn ?? false
        )
        try await col.save(on: req.db)
        struct Out: Encodable {
            var id: UUID
            var boardId: UUID
            var name: String
            var key: String
            var orderIndex: Int
            var wipLimit: Int?
            var isDoneColumn: Bool
        }
        let dto = Out(
            id: col.id!,
            boardId: bid,
            name: col.name,
            key: col.key,
            orderIndex: col.orderIndex,
            wipLimit: col.wipLimit,
            isDoneColumn: col.isDoneColumn
        )
        try await AuditService.log(db: req.db, actorId: uid, entityType: "board_column", entityId: col.id!, action: "create")
        return try Response.json(envelopeOk(dto, meta: nil), status: .created)
    }

    static func updateColumn(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let cid = try req.parameters.require("columnId", as: UUID.self)
        guard let col = try await BoardColumn.find(cid, on: req.db) else { throw AppError.notFound("Column not found") }
        guard let board = try await Board.find(col.$board.id, on: req.db) else { throw AppError.notFound("Board not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: board.$project.id, permission: PermissionKey.boardEdit, on: req.db)
        else { throw AppError.forbidden }
        let body = try req.content.decode(BoardColumnUpdateRequest.self)
        if let n = body.name { col.name = n }
        if let o = body.orderIndex { col.orderIndex = o }
        if let w = body.wipLimit { col.wipLimit = w }
        try await col.save(on: req.db)
        struct Out: Encodable { var id: UUID; var name: String; var orderIndex: Int; var wipLimit: Int? }
        let dto = Out(id: cid, name: col.name, orderIndex: col.orderIndex, wipLimit: col.wipLimit)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "board_column", entityId: cid, action: "update")
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func deleteColumn(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let cid = try req.parameters.require("columnId", as: UUID.self)
        guard let col = try await BoardColumn.find(cid, on: req.db) else { throw AppError.notFound("Column not found") }
        guard let board = try await Board.find(col.$board.id, on: req.db) else { throw AppError.notFound("Board not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: board.$project.id, permission: PermissionKey.boardEdit, on: req.db)
        else { throw AppError.forbidden }
        try await col.delete(on: req.db)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "board_column", entityId: cid, action: "delete")
        return try Response.json(envelopeOk(MessageData(message: "Column deleted"), meta: nil))
    }

    static func moveTask(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let bid = try req.parameters.require("boardId", as: UUID.self)
        let tid = try req.parameters.require("taskId", as: UUID.self)
        let body = try req.content.decode(BoardMoveRequest.self)
        guard let board = try await Board.find(bid, on: req.db) else { throw AppError.notFound("Board not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: board.$project.id, permission: PermissionKey.boardMove, on: req.db)
        else { throw AppError.forbidden }
        guard let task = try await WorkTask.find(tid, on: req.db), task.$project.id == board.$project.id else { throw AppError.validation(["Invalid task"]) }
        guard let col = try await BoardColumn.find(body.boardColumnId, on: req.db), col.$board.id == bid else { throw AppError.validation(["Invalid column"]) }
        if let limit = col.wipLimit, let colId = col.id {
            let destCount = try await BoardTaskState.query(on: req.db).filter(\.$board.$id == bid).filter(\.$column.$id == colId).count()
            let from = try await BoardTaskState.query(on: req.db).filter(\.$board.$id == bid).filter(\.$task.$id == tid).first()
            let fromOther = from?.column.id != colId
            if fromOther, destCount >= limit {
                throw AppError.conflict("WIP limit reached")
            }
        }
        let state =
            try await BoardTaskState.query(on: req.db).filter(\.$board.$id == bid).filter(\.$task.$id == tid).first()
            ?? BoardTaskState(boardID: bid, taskID: tid, boardColumnID: body.boardColumnId, orderIndex: body.orderIndex)
        state.$column.id = body.boardColumnId
        state.orderIndex = body.orderIndex
        try await state.save(on: req.db)
        if col.isDoneColumn, let task = try await WorkTask.find(tid, on: req.db) {
            task.status = "done"
            task.closedAt = Date()
            try await task.save(on: req.db)
            try await PointsService.awardForTaskCompletion(taskId: tid, on: req.db)
        }
        try await normalizeOrder(boardId: bid, columnId: body.boardColumnId, on: req.db)
        struct Out: Encodable {
            var taskId: UUID
            var boardId: UUID
            var boardColumnId: UUID
            var orderIndex: Int
        }
        let dto = Out(taskId: tid, boardId: bid, boardColumnId: body.boardColumnId, orderIndex: body.orderIndex)
        try await AuditService.log(db: req.db, actorId: uid, entityType: "board_task_state", entityId: state.id!, action: "move")
        return try Response.json(envelopeOk(dto, meta: nil))
    }

    static func reorderTask(req: Request) async throws -> Response {
        let uid = try req.requireUserId()
        let bid = try req.parameters.require("boardId", as: UUID.self)
        let tid = try req.parameters.require("taskId", as: UUID.self)
        let body = try req.content.decode(BoardReorderRequest.self)
        guard let board = try await Board.find(bid, on: req.db) else { throw AppError.notFound("Board not found") }
        guard try await RBACService.canManageProjectScoped(userId: uid, projectId: board.$project.id, permission: PermissionKey.boardMove, on: req.db)
        else { throw AppError.forbidden }
        guard let state = try await BoardTaskState.query(on: req.db).filter(\.$board.$id == bid).filter(\.$task.$id == tid).first()
        else { throw AppError.notFound("Task not on board") }
        state.orderIndex = body.orderIndex
        try await state.save(on: req.db)
        try await normalizeOrder(boardId: bid, columnId: state.$column.id, on: req.db)
        struct Out: Encodable { var taskId: UUID; var orderIndex: Int }
        try await AuditService.log(db: req.db, actorId: uid, entityType: "board_task_state", entityId: state.id!, action: "reorder")
        return try Response.json(envelopeOk(Out(taskId: tid, orderIndex: body.orderIndex), meta: nil))
    }

    private static func normalizeOrder(boardId: UUID, columnId: UUID, on db: Database) async throws {
        let items = try await BoardTaskState.query(on: db).filter(\.$board.$id == boardId).filter(\.$column.$id == columnId)
            .sort(\.$orderIndex, .ascending).all()
        for (i, s) in items.enumerated() where s.orderIndex != i + 1 {
            s.orderIndex = i + 1
            try await s.save(on: db)
        }
    }
}
