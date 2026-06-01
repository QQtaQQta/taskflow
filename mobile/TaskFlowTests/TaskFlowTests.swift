import XCTest
@testable import TaskFlow

final class TaskFlowTests: XCTestCase {
    func testEndpointPath() {
        let endpoint = Endpoint.task(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
        XCTAssertEqual(endpoint.path, "/tasks/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
    }

    func testEpicEndpointPaths() {
        let epicId = UUID()
        XCTAssertEqual(Endpoint.updateEpic(id: epicId, request: .init(projectId: nil, title: "t", description: nil, status: nil, startDate: nil, dueDate: nil)).path, "/epics/\(epicId.uuidString)")
        XCTAssertEqual(Endpoint.archiveEpic(id: epicId).path, "/epics/\(epicId.uuidString)")
    }

    func testProjectEndpointPaths() {
        let id = UUID()
        XCTAssertEqual(Endpoint.archiveProject(id: id).path, "/projects/\(id.uuidString)")
        XCTAssertEqual(Endpoint.updateProject(id: id, request: .init(name: "n", description: "d")).path, "/projects/\(id.uuidString)")
    }

    // MARK: - JSON contract: request encoding must match backend camelCase
    // Regression guard for "Ошибка обработки ответа сервера" on create/edit.

    private func makeEncoder() -> JSONEncoder {
        APIConfiguration(baseURL: URL(string: "http://localhost")!).encoder
    }

    private func makeDecoder() -> JSONDecoder {
        APIConfiguration(baseURL: URL(string: "http://localhost")!).decoder
    }

    func testCreateTaskRequestEncodesCamelCase() throws {
        let projectId = UUID()
        let reporterId = UUID()
        let req = CreateTaskRequest(
            projectId: projectId,
            epicId: nil,
            parentTaskId: nil,
            title: "T",
            description: "D",
            issueType: "task",
            priority: "high",
            assigneeId: nil,
            reporterId: reporterId,
            estimateMinutes: 60,
            dueDate: nil
        )
        let data = try makeEncoder().encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["projectId"] as? String, projectId.uuidString)
        XCTAssertEqual(json["reporterId"] as? String, reporterId.uuidString)
        XCTAssertEqual(json["issueType"] as? String, "task")
        XCTAssertEqual(json["estimateMinutes"] as? Int, 60)
        XCTAssertNil(json["project_id"]) // regression guard
        XCTAssertNil(json["reporter_id"]) // regression guard
    }

    func testUpdateTaskRequestEncodesDueDateAsCamelCase() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let req = UpdateTaskRequest(title: "T", description: "D", priority: "medium", dueDate: date)
        let data = try makeEncoder().encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // The silent save bug was caused by converting `dueDate` to `due_date`,
        // which backend's TaskUpdateRequest silently discarded. Verify the wire format.
        XCTAssertNotNil(json["dueDate"])
        XCTAssertNil(json["due_date"]) // regression guard
    }

    func testCreateUserRequestEncodesCamelCase() throws {
        let roleId = UUID()
        let req = CreateUserRequest(email: "a@b.com", password: "Password123!", fullName: "User Name", roleId: roleId, isActive: true, projectIds: nil)
        let data = try makeEncoder().encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["fullName"] as? String, "User Name")
        XCTAssertEqual(json["roleId"] as? String, roleId.uuidString)
        XCTAssertEqual(json["isActive"] as? Bool, true)
        XCTAssertNil(json["full_name"]) // regression guard
        XCTAssertNil(json["role_id"]) // regression guard
    }

    func testUpdateUserRequestEncodesCamelCase() throws {
        let roleId = UUID()
        let req = UpdateUserRequest(fullName: "New", avatarUrl: nil, roleId: roleId, isActive: false, projectIds: nil)
        let data = try makeEncoder().encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["fullName"] as? String, "New")
        XCTAssertEqual(json["roleId"] as? String, roleId.uuidString)
        XCTAssertEqual(json["isActive"] as? Bool, false)
        XCTAssertNil(json["full_name"])
        XCTAssertNil(json["role_id"])
    }

    func testUpdateEpicRequestEncodesProjectReassignment() throws {
        let target = UUID()
        let req = UpdateEpicRequest(projectId: target, title: "New", description: "D", status: nil, startDate: nil, dueDate: nil)
        let data = try makeEncoder().encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["projectId"] as? String, target.uuidString)
        XCTAssertEqual(json["title"] as? String, "New")
        XCTAssertNil(json["project_id"]) // regression guard - epic reassignment would not persist
    }

    func testUpdateProjectRequestEncodesWithoutKeyChange() throws {
        let req = UpdateProjectRequest(name: "Name", description: "Desc")
        let data = try makeEncoder().encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "Name")
        XCTAssertEqual(json["description"] as? String, "Desc")
    }

    func testMoveTaskRequestEncodesCamelCase() throws {
        let colId = UUID()
        let req = MoveTaskRequest(boardColumnId: colId, orderIndex: 3)
        let data = try makeEncoder().encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["boardColumnId"] as? String, colId.uuidString)
        XCTAssertEqual(json["orderIndex"] as? Int, 3)
        XCTAssertNil(json["board_column_id"])
    }

    // MARK: - Response decoding parity with backend envelopes

    func testDecodesCamelCaseLoginEnvelope() throws {
        let payload = """
        {"success":true,"data":{"user":{"id":"\(UUID().uuidString)","email":"a@b.com","fullName":"Admin","role":{"id":"\(UUID().uuidString)","name":"admin"}},"accessToken":"a","refreshToken":"r"},"meta":null}
        """.data(using: .utf8)!
        let envelope = try makeDecoder().decode(APIEnvelope<LoginResponse>.self, from: payload)
        XCTAssertTrue(envelope.success)
        XCTAssertEqual(envelope.data?.user.fullName, "Admin")
        XCTAssertEqual(envelope.data?.accessToken, "a")
    }

    func testDecodesCamelCaseProjectList() throws {
        let id = UUID().uuidString
        let payload = """
        {"success":true,"data":[{"id":"\(id)","key":"KEY","name":"P","description":"D","isArchived":false}],"meta":{"page":1,"perPage":20,"total":1}}
        """.data(using: .utf8)!
        let envelope = try makeDecoder().decode(APIEnvelope<[ProjectResponse]>.self, from: payload)
        XCTAssertEqual(envelope.data?.first?.name, "P")
        XCTAssertEqual(envelope.data?.first?.key, "KEY")
        XCTAssertEqual(envelope.data?.first?.isArchived, false)
    }

    func testDecodesTaskPatchResponseCamelCase() throws {
        let id = UUID().uuidString
        let payload = """
        {"success":true,"data":{"id":"\(id)","title":"T","description":"D","priority":"high","dueDate":"2025-04-12T12:00:00Z"},"meta":null}
        """.data(using: .utf8)!
        let envelope = try makeDecoder().decode(APIEnvelope<TaskPatchResponse>.self, from: payload)
        XCTAssertEqual(envelope.data?.title, "T")
        XCTAssertNotNil(envelope.data?.dueDate)
    }

    func testDecodesTaskCreateResponseWithIssueType() throws {
        let id = UUID().uuidString
        let pid = UUID().uuidString
        let payload = """
        {"success":true,"data":{"id":"\(id)","key":"K-1","projectId":"\(pid)","title":"T","description":"D","issueType":"task","priority":"low","status":"todo","estimateMinutes":30,"spentMinutes":0},"meta":null}
        """.data(using: .utf8)!
        let envelope = try makeDecoder().decode(APIEnvelope<TaskMutationResponse>.self, from: payload)
        XCTAssertEqual(envelope.data?.issueType, "task")
        XCTAssertEqual(envelope.data?.projectId.uuidString, pid)
    }

    // MARK: - ViewModel tests

    @MainActor
    func testEditScreenReceivesTaskData() {
        let task = makeTask(title: "Исходный заголовок")
        let vm = TaskEditorViewModel(task: task, taskRepository: MockTaskRepository())

        XCTAssertEqual(vm.title, "Исходный заголовок")
        XCTAssertEqual(vm.description, "Описание")
        XCTAssertEqual(vm.priority, "high")
        XCTAssertEqual(vm.status, "todo")
        XCTAssertEqual(vm.estimateMinutes, "120")
    }

    @MainActor
    func testSaveTaskSuccess() async {
        let repo = MockTaskRepository()
        let task = makeTask(title: "A")
        let vm = TaskEditorViewModel(task: task, taskRepository: repo)
        vm.title = "Новое название"

        let result = await vm.save()

        XCTAssertTrue(result)
        XCTAssertEqual(repo.updatedTaskID, task.id)
        XCTAssertEqual(repo.lastUpdateRequest?.title, "Новое название")
        XCTAssertEqual(repo.changedStatusTaskID, task.id)
        XCTAssertNil(vm.error)
    }

    @MainActor
    func testSaveTaskFailureShowsError() async {
        let repo = MockTaskRepository(shouldFail: true)
        let vm = TaskEditorViewModel(task: makeTask(title: "A"), taskRepository: repo)

        let result = await vm.save()

        XCTAssertFalse(result)
        XCTAssertNotNil(vm.error)
    }

    @MainActor
    func testSaveTaskPropagatesDueDateChange() async throws {
        let repo = MockTaskRepository()
        let task = makeTask(title: "A")
        let vm = TaskEditorViewModel(task: task, taskRepository: repo)
        // Defect: due date is now picked with a calendar DatePicker and
        // serialised through `hasDueDate`/`dueDate`. Verify the VM
        // propagates the chosen date to the outbound update request.
        var components = DateComponents()
        components.year = 2025
        components.month = 5
        components.day = 1
        components.hour = 12
        let picked = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: components))
        vm.hasDueDate = true
        vm.dueDate = picked

        _ = await vm.save()

        let sent = try XCTUnwrap(repo.lastUpdateRequest?.dueDate)
        let got = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: sent)
        XCTAssertEqual(got.year, 2025)
        XCTAssertEqual(got.month, 5)
        XCTAssertEqual(got.day, 1)
    }

    @MainActor
    func testEditorDroppingDueDateClearsItInRequest() async {
        let repo = MockTaskRepository()
        let task = makeTask(title: "A")
        let vm = TaskEditorViewModel(task: task, taskRepository: repo)
        vm.hasDueDate = false
        _ = await vm.save()
        XCTAssertNil(repo.lastUpdateRequest?.dueDate)
    }

    @MainActor
    func testBoardTapOpensTaskAndCloseReturnsToBoard() {
        let state = TaskPresentationState()
        let task = makeTask(title: "Карточка")

        state.openFromBoard(task: task)
        XCTAssertEqual(state.boardOpenedTask?.id, task.id)

        state.closeBoardTask()
        XCTAssertNil(state.boardOpenedTask)
    }

    @MainActor
    func testEditFromBoardCardWorks() {
        let state = TaskPresentationState()
        let task = makeTask(title: "Карточка")

        state.openEditor(task: task)
        XCTAssertEqual(state.editingTask?.id, task.id)
    }

    @MainActor
    func testTimeEntryPrependReflectsInState() {
        let state = TimeTrackingState()
        let first = TimeEntry(id: UUID(), userId: nil, userFullName: nil, spentMinutes: 60, comment: "A", startedAt: nil)
        let second = TimeEntry(id: UUID(), userId: nil, userFullName: nil, spentMinutes: 30, comment: "B", startedAt: nil)

        state.set([first])
        state.prepend(second)

        XCTAssertEqual(state.entries.count, 2)
        XCTAssertEqual(state.entries.first?.id, second.id)
    }

    // MARK: - Projects VM: create, edit, archive reflect in state

    @MainActor
    func testProjectsViewModelCreateInsertsAtTop() async {
        let repo = MockProjectRepository()
        let vm = ProjectsViewModel(repository: repo)
        await vm.createProject(key: "K", name: "N", description: "D")
        XCTAssertEqual(vm.projects.first?.name, "N")
        XCTAssertEqual(repo.createdRequest?.key, "K")
    }

    @MainActor
    func testProjectsViewModelUpdateReplacesProject() async {
        let repo = MockProjectRepository()
        let existing = Project(id: UUID(), key: "K", name: "Old", description: "D", isArchived: false, tasksCount: 0, epicsCount: 0)
        repo.prepopulated = [existing]
        let vm = ProjectsViewModel(repository: repo)
        await vm.reload()
        await vm.updateProject(id: existing.id, name: "New", description: "D2")
        XCTAssertEqual(vm.projects.first(where: { $0.id == existing.id })?.name, "New")
        XCTAssertEqual(repo.updateRequests.last?.request.name, "New")
    }

    @MainActor
    func testProjectsViewModelArchiveRemovesProject() async {
        let repo = MockProjectRepository()
        let existing = Project(id: UUID(), key: "K", name: "To go", description: "D", isArchived: false, tasksCount: 0, epicsCount: 0)
        repo.prepopulated = [existing]
        let vm = ProjectsViewModel(repository: repo)
        await vm.reload()
        await vm.archiveProject(id: existing.id)
        XCTAssertTrue(vm.projects.isEmpty)
        XCTAssertEqual(repo.archivedIds, [existing.id])
    }

    // MARK: - Board list VM: project switcher filters and persists

    @MainActor
    func testBoardListProjectSwitcherChangesFilterAndPersists() async {
        let projectId = UUID()
        let boardRepo = MockBoardRepository()
        boardRepo.boardsByProject[projectId] = [
            Board(id: UUID(), projectId: projectId, name: "Board A", columns: nil)
        ]
        let projectRepo = MockProjectRepository()
        projectRepo.prepopulated = [
            Project(id: projectId, key: "KEY", name: "Project", description: "D", isArchived: false, tasksCount: 0, epicsCount: 0)
        ]
        UserDefaults.standard.removeObject(forKey: "boards.selectedProjectID")
        let vm = BoardListViewModel(repository: boardRepo, projectRepository: projectRepo)
        await vm.loadProjects()
        vm.selectedProjectID = projectId
        await vm.load()
        XCTAssertEqual(vm.boards.map(\.id), boardRepo.boardsByProject[projectId]!.map(\.id))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "boards.selectedProjectID"), projectId.uuidString)
    }

    @MainActor
    func testBoardListFilterRestoredAfterRelaunch() {
        let projectId = UUID()
        UserDefaults.standard.set(projectId.uuidString, forKey: "boards.selectedProjectID")
        let vm = BoardListViewModel(repository: MockBoardRepository(), projectRepository: MockProjectRepository())
        XCTAssertEqual(vm.selectedProjectID, projectId)
    }

    // MARK: - Accent color persistence

    func testAccentColorSettingPersists() {
        let store = UserDefaults.standard
        store.removeObject(forKey: "app.accentColor")
        store.set(AppAccentColor.orange.rawValue, forKey: "app.accentColor")
        let stored = store.string(forKey: "app.accentColor")
        let accent = AppAccentColor(rawValue: stored ?? "")
        XCTAssertEqual(accent, .orange)
    }

    func testAccentColorAllCasesProvideTitles() {
        for accent in AppAccentColor.allCases {
            XCTAssertFalse(accent.title.isEmpty)
        }
    }

    // MARK: - Defect 5: Task detail renders reporter/assignee/epic

    func testDecodesWorkTaskWithNestedEpicAssigneeReporter() throws {
        let tid = UUID().uuidString
        let eid = UUID().uuidString
        let aid = UUID().uuidString
        let rid = UUID().uuidString
        let payload = """
        {"success":true,"data":{"id":"\(tid)","key":"MOB-1","title":"T","description":"D","status":"todo","priority":"high","estimateMinutes":60,"spentMinutes":10,"assignee":{"id":"\(aid)","fullName":"Ann"},"reporter":{"id":"\(rid)","fullName":"Bob"},"epic":{"id":"\(eid)","key":"EP","title":"Auth redesign"}},"meta":null}
        """.data(using: .utf8)!
        let envelope = try makeDecoder().decode(APIEnvelope<WorkTask>.self, from: payload)
        let task = try XCTUnwrap(envelope.data)
        XCTAssertEqual(task.reporter?.fullName, "Bob")
        XCTAssertEqual(task.assignee?.fullName, "Ann")
        XCTAssertEqual(task.epic?.key, "EP")
        XCTAssertEqual(task.epic?.title, "Auth redesign")
        XCTAssertEqual(task.epicId, task.epic?.id)
    }

    @MainActor
    func testTaskDetailViewModelRefreshesFromRepositoryOnReload() async {
        let fresh = WorkTask(
            id: UUID(),
            key: "MOB-9",
            title: "Fresh title",
            description: "Fresh desc",
            status: "in_progress",
            priority: "medium",
            estimateMinutes: 100,
            spentMinutes: 25,
            assignee: Assignee(id: UUID(), fullName: "Исполнитель"),
            reporter: Assignee(id: UUID(), fullName: "Автор"),
            dueDate: nil,
            epic: TaskEpicMini(id: UUID(), key: "EP-1", title: "Auth"),
            parentTaskId: nil
        )
        let repo = MockTaskRepository(detailTask: fresh)
        let stale = WorkTask(
            id: fresh.id,
            key: nil,
            title: "Stale",
            description: nil,
            status: "todo",
            priority: nil,
            estimateMinutes: nil,
            spentMinutes: nil,
            assignee: nil,
            reporter: nil,
            dueDate: nil,
            epic: nil,
            parentTaskId: nil
        )
        let vm = TaskDetailViewModel(task: stale, repository: repo)
        await vm.reload()
        XCTAssertEqual(vm.task.title, "Fresh title")
        XCTAssertEqual(vm.task.reporter?.fullName, "Автор")
        XCTAssertEqual(vm.task.assignee?.fullName, "Исполнитель")
        XCTAssertEqual(vm.task.epic?.title, "Auth")
    }

    // MARK: - Defect 7: Time entry exposes user

    func testDecodesTimeEntryWithUser() throws {
        let eid = UUID().uuidString
        let uid = UUID().uuidString
        let payload = """
        {"success":true,"data":[{"id":"\(eid)","userId":"\(uid)","userFullName":"Demo Admin","spentMinutes":45,"comment":"ok","startedAt":"2025-01-01T00:00:00Z"}],"meta":null}
        """.data(using: .utf8)!
        let envelope = try makeDecoder().decode(APIEnvelope<[TimeEntry]>.self, from: payload)
        let entry = try XCTUnwrap(envelope.data?.first)
        XCTAssertEqual(entry.userFullName, "Demo Admin")
        XCTAssertEqual(entry.spentMinutes, 45)
    }

    // MARK: - Defect 3: Board detail decodes columns with key/isDoneColumn

    func testDecodesBoardDetailWithColumns() throws {
        let bid = UUID().uuidString
        let pid = UUID().uuidString
        let payload = """
        {"success":true,"data":{"id":"\(bid)","projectId":"\(pid)","name":"B","columns":[{"id":"\(UUID().uuidString)","name":"Backlog","key":"backlog","orderIndex":1,"isDoneColumn":false},{"id":"\(UUID().uuidString)","name":"Done","key":"done","orderIndex":5,"isDoneColumn":true}]},"meta":null}
        """.data(using: .utf8)!
        let envelope = try makeDecoder().decode(APIEnvelope<Board>.self, from: payload)
        let columns = try XCTUnwrap(envelope.data?.columns)
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns.first?.key, "backlog")
        XCTAssertEqual(columns.last?.isDoneColumn, true)
    }

    // MARK: - Defect 3: Board creation

    @MainActor
    func testBoardListCreateBoardPersistsAndRefreshes() async {
        let boardRepo = MockBoardRepository()
        let projectRepo = MockProjectRepository()
        let projectId = UUID()
        projectRepo.prepopulated = [
            Project(id: projectId, key: "P", name: "Project", description: nil, isArchived: false, tasksCount: 0, epicsCount: 0)
        ]
        UserDefaults.standard.removeObject(forKey: "boards.selectedProjectID")
        let vm = BoardListViewModel(repository: boardRepo, projectRepository: projectRepo)
        await vm.loadProjects()
        vm.selectedProjectID = projectId
        await vm.load()

        XCTAssertTrue(vm.boards.isEmpty)
        let createdId = await vm.createBoard(projectId: projectId, name: "Kanban", description: "d", isDefault: true)
        XCTAssertNotNil(createdId)
        XCTAssertEqual(vm.boards.count, 1)
        XCTAssertEqual(vm.boards.first?.name, "Kanban")
        XCTAssertEqual(boardRepo.createdBoards.last?.name, "Kanban")
        XCTAssertEqual(boardRepo.createdBoards.last?.isDefault, true)
    }

    @MainActor
    func testBoardListSurfacesErrorOnCreateFailure() async {
        let boardRepo = MockBoardRepository()
        boardRepo.shouldFailCreate = true
        let projectRepo = MockProjectRepository()
        let vm = BoardListViewModel(repository: boardRepo, projectRepository: projectRepo)
        let id = await vm.createBoard(projectId: UUID(), name: "X", description: "", isDefault: false)
        XCTAssertNil(id)
        XCTAssertNotNil(vm.error)
    }

    // MARK: - Defect 1: Project delete from details VM

    @MainActor
    func testProjectDetailsViewModelArchiveDelegatesToRepository() async {
        let pid = UUID()
        let taskRepo = MockTaskRepository()
        let projectRepo = MockProjectRepository()
        projectRepo.prepopulated = [Project(id: pid, key: "P", name: "Delete me", description: nil, isArchived: false, tasksCount: 0, epicsCount: 0)]
        let vm = ProjectDetailsViewModel(project: projectRepo.prepopulated[0], taskRepository: taskRepo)
        let ok = await vm.archiveProject(repository: projectRepo)
        XCTAssertTrue(ok)
        XCTAssertEqual(projectRepo.archivedIds, [pid])
    }

    @MainActor
    func testProjectDetailsViewModelUpdatePersistsLocalProject() async {
        let pid = UUID()
        let taskRepo = MockTaskRepository()
        let projectRepo = MockProjectRepository()
        projectRepo.prepopulated = [Project(id: pid, key: "P", name: "Old", description: "old", isArchived: false, tasksCount: 0, epicsCount: 0)]
        let vm = ProjectDetailsViewModel(project: projectRepo.prepopulated[0], taskRepository: taskRepo)
        await vm.updateProject(repository: projectRepo, name: "New name", description: "new desc")
        XCTAssertEqual(vm.project.name, "New name")
        XCTAssertEqual(projectRepo.updateRequests.last?.request.name, "New name")
    }

    // MARK: - Board management (edit / delete / columns)

    @MainActor
    func testBoardRepositoryMockUpdatesBoard() async throws {
        let repo = MockBoardRepository()
        let id = UUID()
        _ = try await repo.update(id: id, name: "Nn", description: "Dd")
        XCTAssertEqual(repo.updatedBoards.last?.name, "Nn")
        XCTAssertEqual(repo.updatedBoards.last?.description, "Dd")
    }

    @MainActor
    func testBoardRepositoryMockArchivesBoard() async throws {
        let repo = MockBoardRepository()
        let pid = UUID()
        let bid = UUID()
        repo.boardsByProject[pid] = [Board(id: bid, projectId: pid, name: "n", columns: nil)]
        try await repo.archive(id: bid)
        XCTAssertEqual(repo.archivedBoardIds, [bid])
        XCTAssertTrue((repo.boardsByProject[pid] ?? []).isEmpty)
    }

    @MainActor
    func testBoardRepositoryMockCreatesAndDeletesColumns() async throws {
        let repo = MockBoardRepository()
        let bid = UUID()
        try await repo.createColumn(boardId: bid, name: "Ready", key: "ready", orderIndex: 6, wipLimit: nil, isDoneColumn: false)
        XCTAssertEqual(repo.createdColumns.last?.key, "ready")
        let cid = UUID()
        try await repo.deleteColumn(columnId: cid)
        XCTAssertEqual(repo.deletedColumnIds, [cid])
    }

    // MARK: - TaskDetailViewModel.changeStatus

    @MainActor
    func testTaskDetailViewModelChangeStatusCallsRepository() async {
        let fresh = WorkTask(
            id: UUID(), key: "T-1", title: "t", description: nil, status: "done",
            priority: nil, estimateMinutes: nil, spentMinutes: nil,
            assignee: nil, reporter: nil, dueDate: nil, epic: nil, parentTaskId: nil
        )
        let repo = MockTaskRepository(detailTask: fresh)
        let stale = WorkTask(
            id: fresh.id, key: nil, title: "t", description: nil, status: "todo",
            priority: nil, estimateMinutes: nil, spentMinutes: nil,
            assignee: nil, reporter: nil, dueDate: nil, epic: nil, parentTaskId: nil
        )
        let vm = TaskDetailViewModel(task: stale, repository: repo)
        await vm.changeStatus(to: "done")
        XCTAssertEqual(repo.changedStatusTaskID, fresh.id)
        XCTAssertEqual(vm.task.status, "done")
        XCTAssertNil(vm.statusError)
    }

    // MARK: - App icon ↔ accent color mapping

    func testAccentColorMapsToAlternateIconName() {
        XCTAssertEqual(AppAccentColor.blue.alternateIconName, "AppIcon-Blue")
        XCTAssertEqual(AppAccentColor.green.alternateIconName, "AppIcon-Green")
        XCTAssertEqual(AppAccentColor.orange.alternateIconName, "AppIcon-Orange")
        XCTAssertEqual(AppAccentColor.purple.alternateIconName, "AppIcon-Purple")
        XCTAssertEqual(AppAccentColor.pink.alternateIconName, "AppIcon-Pink")
    }

    // MARK: - ProjectDetailsView task/epic segmented control

    func testProjectContentTabAllCasesTranslated() {
        XCTAssertEqual(ProjectContentTab.tasks.title, "Задачи")
        XCTAssertEqual(ProjectContentTab.epics.title, "Эпики")
        XCTAssertEqual(ProjectContentTab.allCases.count, 2)
    }

    // MARK: - Defect 6: Editor no longer exposes parent task

    @MainActor
    func testTaskEditorViewModelDoesNotExposeParentTask() {
        let vm = TaskEditorViewModel(task: makeTask(title: "T"), taskRepository: MockTaskRepository())
        let mirror = Mirror(reflecting: vm)
        for child in mirror.children {
            XCTAssertNotEqual(child.label, "parentTaskId", "Parent task field must be removed from editor (defect 6)")
        }
    }

    private func makeTask(title: String, epic: TaskEpicMini? = nil, assignee: Assignee? = nil, reporter: Assignee? = nil) -> WorkTask {
        WorkTask(
            id: UUID(),
            key: "MOB-1",
            title: title,
            description: "Описание",
            status: "todo",
            priority: "high",
            estimateMinutes: 120,
            spentMinutes: 0,
            assignee: assignee,
            reporter: reporter,
            dueDate: nil,
            epic: epic,
            parentTaskId: nil
        )
    }
}

// MARK: - Mocks

private final class MockTaskRepository: TaskRepository, @unchecked Sendable {
    let shouldFail: Bool
    let detailTask: WorkTask?
    var updatedTaskID: UUID?
    var lastUpdateRequest: UpdateTaskRequest?
    var changedStatusTaskID: UUID?

    init(shouldFail: Bool = false, detailTask: WorkTask? = nil) {
        self.shouldFail = shouldFail
        self.detailTask = detailTask
    }

    func list(projectId: UUID?, epicId: UUID?, page: Int, search: String?) async throws -> [WorkTask] { [] }
    func detail(id: UUID) async throws -> WorkTask {
        if let detailTask { return detailTask }
        throw APIError.unknown
    }
    func create(_ request: CreateTaskRequest) async throws {}

    func update(id: UUID, request: UpdateTaskRequest) async throws -> WorkTask {
        if shouldFail { throw APIError.server(code: "save_failed", message: "Ошибка сохранения") }
        updatedTaskID = id
        lastUpdateRequest = request
        return WorkTask(
            id: id,
            key: "MOB-1",
            title: request.title ?? "Задача",
            description: request.description,
            status: "todo",
            priority: request.priority,
            estimateMinutes: 120,
            spentMinutes: 0,
            assignee: nil,
            reporter: nil,
            dueDate: request.dueDate,
            epic: nil,
            parentTaskId: nil
        )
    }

    func assign(taskId: UUID, assigneeId: UUID) async throws {}
    func estimate(taskId: UUID, minutes: Int) async throws {}
    func archive(id: UUID) async throws {}
    func changeStatus(taskId: UUID, status: String) async throws {
        changedStatusTaskID = taskId
    }
}

private final class MockProjectRepository: ProjectRepository, @unchecked Sendable {
    var prepopulated: [Project] = []
    var createdRequest: CreateProjectRequest?
    var updateRequests: [(id: UUID, request: UpdateProjectRequest)] = []
    var archivedIds: [UUID] = []

    func list(page: Int, search: String?) async throws -> [Project] { prepopulated }
    func detail(id: UUID) async throws -> Project {
        prepopulated.first(where: { $0.id == id }) ?? Project(id: id, key: "K", name: "?", description: nil, isArchived: false, tasksCount: 0, epicsCount: 0)
    }

    func create(_ request: CreateProjectRequest) async throws -> Project {
        createdRequest = request
        let new = Project(id: UUID(), key: request.key, name: request.name, description: request.description, isArchived: false, tasksCount: 0, epicsCount: 0)
        prepopulated.insert(new, at: 0)
        return new
    }

    func update(id: UUID, request: UpdateProjectRequest) async throws -> Project {
        updateRequests.append((id, request))
        let updated = Project(id: id, key: "K", name: request.name ?? "", description: request.description, isArchived: false, tasksCount: 0, epicsCount: 0)
        if let idx = prepopulated.firstIndex(where: { $0.id == id }) {
            prepopulated[idx] = updated
        }
        return updated
    }

    func archive(id: UUID) async throws {
        archivedIds.append(id)
        prepopulated.removeAll { $0.id == id }
    }
}

private final class MockBoardRepository: BoardRepository, @unchecked Sendable {
    var boardsByProject: [UUID: [Board]] = [:]
    var createdBoards: [(projectId: UUID, name: String, isDefault: Bool)] = []
    var updatedBoards: [(id: UUID, name: String, description: String)] = []
    var archivedBoardIds: [UUID] = []
    var createdColumns: [(boardId: UUID, name: String, key: String, order: Int, isDone: Bool)] = []
    var deletedColumnIds: [UUID] = []
    var shouldFailCreate = false

    func list(projectId: UUID?) async throws -> [Board] {
        guard let pid = projectId else { return boardsByProject.values.flatMap { $0 } }
        return boardsByProject[pid] ?? []
    }
    func detail(id: UUID) async throws -> Board {
        Board(id: id, projectId: nil, name: "B", columns: [])
    }
    func create(projectId: UUID, name: String, description: String, isDefault: Bool) async throws -> BoardCreatedResponse {
        if shouldFailCreate { throw APIError.server(code: "BOARD_ERR", message: "fail") }
        let created = BoardCreatedResponse(id: UUID(), projectId: projectId, name: name, description: description, isDefault: isDefault)
        createdBoards.append((projectId, name, isDefault))
        var list = boardsByProject[projectId] ?? []
        list.append(Board(id: created.id, projectId: projectId, name: name, columns: nil))
        boardsByProject[projectId] = list
        return created
    }
    func update(id: UUID, name: String, description: String) async throws -> BoardUpdatedResponse {
        updatedBoards.append((id, name, description))
        return BoardUpdatedResponse(id: id, name: name, description: description)
    }
    func archive(id: UUID) async throws {
        archivedBoardIds.append(id)
        for key in boardsByProject.keys {
            boardsByProject[key]?.removeAll { $0.id == id }
        }
    }
    func createColumn(boardId: UUID, name: String, key: String, orderIndex: Int, wipLimit: Int?, isDoneColumn: Bool) async throws {
        createdColumns.append((boardId, name, key, orderIndex, isDoneColumn))
    }
    func deleteColumn(columnId: UUID) async throws {
        deletedColumnIds.append(columnId)
    }
    func moveTask(boardId: UUID, taskId: UUID, columnId: UUID, orderIndex: Int) async throws {}
}
