import Combine
import SwiftUI

@MainActor
final class TaskPresentationState: ObservableObject {
    @Published var editingTask: WorkTask?
    @Published var boardOpenedTask: WorkTask?

    func openEditor(task: WorkTask) {
        editingTask = task
    }

    func openFromBoard(task: WorkTask) {
        boardOpenedTask = task
    }

    func closeBoardTask() {
        boardOpenedTask = nil
    }
}

@MainActor
final class TimeTrackingState: ObservableObject {
    @Published var entries: [TimeEntry] = []
    @Published var inputError: String?

    func set(_ value: [TimeEntry]) {
        entries = value
    }

    func prepend(_ entry: TimeEntry) {
        entries.insert(entry, at: 0)
    }
}

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = "admin@demo.local"
    @Published var password = "Password123!"
    @Published var isLoading = false
    @Published var error: String?

    private let authRepository: AuthRepository
    private let authManager: AuthManager
    private let onSuccess: () -> Void

    init(authRepository: AuthRepository, authManager: AuthManager, onSuccess: @escaping () -> Void) {
        self.authRepository = authRepository
        self.authManager = authManager
        self.onSuccess = onSuccess
    }

    func login() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await authRepository.login(email: email, password: password)
            authManager.updateTokens(access: result.accessToken, refresh: result.refreshToken)
            onSuccess()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct LoginView: View {
    @StateObject var viewModel: LoginViewModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Вход")
                    .font(.largeTitle.bold())
                Text("Управляйте задачами, эпиками и досками в одном месте.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 14) {
                TextField("Почта", text: $viewModel.email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                SecureField("Пароль", text: $viewModel.password)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }

            if let error = viewModel.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Button {
                Task { await viewModel.login() }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text("Войти")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .disabled(viewModel.isLoading)
        }
        .padding(20)
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
final class TaskEditorViewModel: ObservableObject {
    @Published var title: String
    @Published var description: String
    @Published var priority: String
    @Published var estimateMinutes: String
    @Published var status: String
    @Published var assigneeId: UUID?
    @Published var hasDueDate: Bool
    @Published var dueDate: Date
    @Published var isSaving = false
    @Published var error: String?

    let taskRepository: TaskRepository
    let task: WorkTask

    init(task: WorkTask, taskRepository: TaskRepository) {
        self.task = task
        self.taskRepository = taskRepository
        self.title = task.title
        self.description = task.description ?? ""
        self.priority = task.priority ?? "medium"
        self.estimateMinutes = "\(task.estimateMinutes ?? 0)"
        self.status = task.status
        self.assigneeId = task.assignee?.id
        self.hasDueDate = task.dueDate != nil
        self.dueDate = task.dueDate ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Int(estimateMinutes) != nil
    }

    func save() async -> Bool {
        guard isValid else {
            error = "Проверьте обязательные поля формы."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let _ = try await taskRepository.update(
                id: task.id,
                request: .init(
                    title: title,
                    description: description,
                    priority: priority,
                    dueDate: hasDueDate ? dueDate : nil
                )
            )
            if let estimate = Int(estimateMinutes), estimate != (task.estimateMinutes ?? 0) {
                try await taskRepository.estimate(taskId: task.id, minutes: estimate)
            }
            if let assigneeId, assigneeId != task.assignee?.id {
                try await taskRepository.assign(taskId: task.id, assigneeId: assigneeId)
            }
            try await taskRepository.changeStatus(taskId: task.id, status: status)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

}

struct TaskEditorView: View {
    @StateObject var viewModel: TaskEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer
    @State private var availableAssignees: [UserListItem] = []

    var body: some View {
        Form {
            Section("Основное") {
                TextField("Название", text: $viewModel.title)
                TextField("Описание", text: $viewModel.description, axis: .vertical)
            }
            Section("Планирование") {
                Picker("Приоритет", selection: $viewModel.priority) {
                    Text("Низкий").tag("low")
                    Text("Средний").tag("medium")
                    Text("Высокий").tag("high")
                    Text("Критический").tag("critical")
                }
                .pickerStyle(.menu)
                TextField("Оценка (мин.)", text: $viewModel.estimateMinutes).keyboardType(.numberPad)
                Picker("Статус", selection: $viewModel.status) {
                    Text("К выполнению").tag("todo")
                    Text("В работе").tag("in_progress")
                    Text("Готово").tag("done")
                }
                .pickerStyle(.menu)
                Picker("Исполнитель", selection: $viewModel.assigneeId) {
                    Text("Не назначен").tag(UUID?.none)
                    ForEach(availableAssignees) { user in
                        Text(user.fullName).tag(Optional(user.id))
                    }
                }
                .pickerStyle(.menu)
                // Defect: use a real calendar picker instead of a free-form
                // text field so the user can visually pick a due date.
                Toggle("Указать срок", isOn: $viewModel.hasDueDate)
                if viewModel.hasDueDate {
                    DatePicker(
                        "Срок",
                        selection: $viewModel.dueDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                }
            }
            if let error = viewModel.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .navigationTitle("Редактирование")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сохранить") {
                    Task {
                        if await viewModel.save() {
                            dismiss()
                        }
                    }
                }
                .disabled(!viewModel.isValid || viewModel.isSaving)
            }
        }
        .task {
            availableAssignees = (try? await container.adminRepository.users(search: nil)) ?? []
        }
    }
}

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var searchText = ""
    @Published var selectedProject: Project?
    @Published var showCreateProject = false
    @Published var selectedProjectForEdit: Project?

    private let repository: ProjectRepository
    private var page = 1
    private var canLoadMore = true
    private var cancellables: Set<AnyCancellable> = []

    init(repository: ProjectRepository) {
        self.repository = repository
        $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.reload() }
            }
            .store(in: &cancellables)
    }

    func reload() async {
        page = 1
        canLoadMore = true
        projects = []
        await loadMoreIfNeeded(current: nil)
        await refreshProjectCounts()
    }

    func loadMoreIfNeeded(current: Project?) async {
        guard !isLoading, canLoadMore else { return }
        if let current, projects.suffix(5).contains(current) == false {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await repository.list(page: page, search: searchText.isEmpty ? nil : searchText)
            projects.append(contentsOf: next)
            canLoadMore = !next.isEmpty
            page += 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createProject(key: String, name: String, description: String) async {
        do {
            let created = try await repository.create(.init(key: key, name: name, description: description))
            projects.insert(created, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateProject(id: UUID, name: String, description: String) async {
        do {
            let updated = try await repository.update(id: id, request: .init(name: name, description: description))
            if let idx = projects.firstIndex(where: { $0.id == id }) {
                projects[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func archiveProject(id: UUID) async {
        do {
            try await repository.archive(id: id)
            projects.removeAll { $0.id == id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshProjectCounts() async {
        for (index, project) in projects.enumerated() {
            if let detailed = try? await repository.detail(id: project.id) {
                projects[index] = detailed
            }
        }
    }
}

struct ProjectsView: View {
    @StateObject var viewModel: ProjectsViewModel
    let taskRepository: TaskRepository
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.projects.isEmpty && !viewModel.isLoading {
                    EmptyStateView(title: "Проекты не найдены", subtitle: "Создайте проект на backend или измените фильтры.")
                }

                ForEach(viewModel.projects) { project in
                    NavigationLink(value: project) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(project.key) · \(project.name)")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(project.description ?? "Описание отсутствует")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                Label("Задачи: \(project.tasksCount ?? 0)", systemImage: "checkmark.circle")
                                Spacer()
                                Label("Эпики: \(project.epicsCount ?? 0)", systemImage: "flag")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Удалить") {
                            Task { await viewModel.archiveProject(id: project.id) }
                        }
                        .tint(.red)
                        Button("Изменить") {
                            viewModel.selectedProjectForEdit = project
                        }
                        .tint(.blue)
                    }
                    .task { await viewModel.loadMoreIfNeeded(current: project) }
                }

                if viewModel.isLoading {
                    ProgressView().padding(.top, 12)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .searchable(text: $viewModel.searchText, prompt: "Поиск проекта")
        .navigationDestination(for: Project.self) { project in
            ProjectDetailsView(
                viewModel: .init(project: project, taskRepository: taskRepository),
                epicsModel: EpicsTabModel(projectId: project.id, container: container)
            )
        }
        .refreshable { await viewModel.reload() }
        .task { await viewModel.reload() }
        .navigationTitle("Проекты")
        .toolbar {
            Button("Создать") { viewModel.showCreateProject = true }
        }
        .sheet(isPresented: $viewModel.showCreateProject) {
            ProjectFormSheet(mode: .create) { key, name, description in
                Task { await viewModel.createProject(key: key, name: name, description: description) }
            }
        }
        // Use `.sheet(item:)` so the edited project identity is bound into
        // the presentation instead of reading from mutable state — avoids
        // a race where the sheet pops with `selectedProjectForEdit == nil`
        // and the edit button appears to do nothing (defect 2).
        .sheet(item: $viewModel.selectedProjectForEdit) { selected in
            ProjectFormSheet(mode: .edit(selected)) { _, name, description in
                Task { await viewModel.updateProject(id: selected.id, name: name, description: description) }
            }
        }
        .overlay(alignment: .center) {
            if let error = viewModel.error {
                ErrorBanner(text: error)
            }
        }
    }
}

@MainActor
final class ProjectDetailsViewModel: ObservableObject {
    @Published var tasks: [WorkTask] = []
    @Published var showCreate = false
    @Published var project: Project

    let taskRepository: TaskRepository
    @Published var error: String?

    init(project: Project, taskRepository: TaskRepository) {
        self.project = project
        self.taskRepository = taskRepository
    }

    func load() async {
        do {
            tasks = try await taskRepository.list(projectId: project.id, epicId: nil, page: 1, search: nil)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func applyOptimisticStatus(taskId: UUID, status: String) async {
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            let existing = tasks[idx]
            tasks[idx] = WorkTask(
                id: existing.id,
                key: existing.key,
                title: existing.title,
                description: existing.description,
                status: status,
                priority: existing.priority,
                estimateMinutes: existing.estimateMinutes,
                spentMinutes: existing.spentMinutes,
                assignee: existing.assignee,
                reporter: existing.reporter,
                dueDate: existing.dueDate,
                epic: existing.epic,
                parentTaskId: existing.parentTaskId
            )
        }
        try? await taskRepository.changeStatus(taskId: taskId, status: status)
    }

    func archiveTask(taskId: UUID) async {
        do {
            try await taskRepository.archive(id: taskId)
            tasks.removeAll { $0.id == taskId }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Edit the project currently displayed on screen. The repository is
    /// passed from the view because ProjectDetailsViewModel doesn't own
    /// the project repository (it only tracks tasks).
    func updateProject(repository: ProjectRepository, name: String, description: String) async {
        do {
            let updated = try await repository.update(id: project.id, request: .init(name: name, description: description))
            project = updated
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Archive (hard-delete) the currently displayed project.
    /// Returns true on success so the caller can pop the navigation stack.
    func archiveProject(repository: ProjectRepository) async -> Bool {
        do {
            try await repository.archive(id: project.id)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

enum ProjectContentTab: String, Hashable, CaseIterable, Identifiable {
    case tasks
    case epics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tasks: return "Задачи"
        case .epics: return "Эпики"
        }
    }
}

struct ProjectDetailsView: View {
    @StateObject var viewModel: ProjectDetailsViewModel
    @StateObject private var presentation = TaskPresentationState()
    @StateObject private var epicsModel: EpicsTabModel
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ProjectContentTab = .tasks
    @State private var showDeleteConfirmation = false
    @State private var editingProject: Project?

    init(viewModel: ProjectDetailsViewModel, epicsModel: EpicsTabModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _epicsModel = StateObject(wrappedValue: epicsModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Defect: project-level segmented control to switch between the
            // project's tasks and epics. Replaces the old "Эпики" toolbar link.
            Picker("Раздел", selection: $selectedTab) {
                ForEach(ProjectContentTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch selectedTab {
            case .tasks:
                tasksList
            case .epics:
                EpicsTabContent(model: epicsModel)
            }
        }
        .navigationDestination(for: WorkTask.self) { task in
            TaskDetailsView(task: task, repository: viewModel.taskRepository)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Context-aware create button: create a task on the tasks
                // tab, create an epic on the epics tab.
                Button("Создать") {
                    switch selectedTab {
                    case .tasks: viewModel.showCreate = true
                    case .epics: epicsModel.showCreate = true
                    }
                }
                Menu {
                    Button("Редактировать проект") {
                        editingProject = viewModel.project
                    }
                    Button("Удалить проект", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $viewModel.showCreate) {
            CreateTaskSheet(projectId: viewModel.project.id)
        }
        .onChange(of: viewModel.showCreate) { _, newValue in
            if !newValue {
                Task { await viewModel.load() }
            }
        }
        .sheet(item: $presentation.editingTask) { task in
            NavigationStack {
                TaskEditorView(viewModel: .init(task: task, taskRepository: viewModel.taskRepository))
            }
        }
        .onChange(of: presentation.editingTask) { _, newValue in
            if newValue == nil {
                Task { await viewModel.load() }
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectFormSheet(mode: .edit(project)) { _, name, description in
                Task {
                    await viewModel.updateProject(
                        repository: container.projectRepository,
                        name: name,
                        description: description
                    )
                }
            }
        }
        .confirmationDialog(
            "Удалить проект \"\(viewModel.project.name)\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                Task {
                    let ok = await viewModel.archiveProject(repository: container.projectRepository)
                    if ok { dismiss() }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Эпики и задачи, связанные с проектом, будут удалены.")
        }
        .navigationTitle(viewModel.project.name)
        .task { await viewModel.load() }
        .overlay(alignment: .center) {
            if let error = viewModel.error {
                ErrorBanner(text: error)
            }
        }
    }

    private var tasksList: some View {
        List {
            if viewModel.tasks.isEmpty {
                Text("Задачи не созданы. Нажмите «Создать» в верхнем правом углу, чтобы добавить задачу.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.tasks) { task in
                NavigationLink(value: task) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(.headline)
                            Text(statusTitle(task.status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let assignee = task.assignee {
                                Label(assignee.fullName, systemImage: "person.crop.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        // Explicit status-change menu on the task row so the
                        // user can flip the state without opening the editor.
                        Menu {
                            ForEach(TaskStatusOption.allCases) { option in
                                Button(option.title) {
                                    Task {
                                        await viewModel.applyOptimisticStatus(taskId: task.id, status: option.rawValue)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.headline)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tint)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Удалить") {
                        Task { await viewModel.archiveTask(taskId: task.id) }
                    }
                    .tint(.red)
                    Button("Готово") {
                        Task { await viewModel.applyOptimisticStatus(taskId: task.id, status: "done") }
                    }
                    .tint(.green)
                    Button("Изменить") {
                        presentation.openEditor(task: task)
                    }
                    .tint(.blue)
                }
            }
        }
    }

    private func statusTitle(_ status: String) -> String {
        switch status {
        case "todo": "К выполнению"
        case "in_progress": "В работе"
        case "done": "Готово"
        default: status
        }
    }
}

enum TaskStatusOption: String, CaseIterable, Identifiable {
    case todo, inProgress = "in_progress", done
    var id: String { rawValue }
    var title: String {
        switch self {
        case .todo: return "К выполнению"
        case .inProgress: return "В работе"
        case .done: return "Готово"
        }
    }
}

@MainActor
final class TaskDetailViewModel: ObservableObject {
    @Published var task: WorkTask
    @Published var isLoading = false
    @Published var statusError: String?
    private let repository: TaskRepository

    init(task: WorkTask, repository: TaskRepository) {
        self.task = task
        self.repository = repository
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        // Fetch the full TaskDetailDTO from the backend so that reporter,
        // assignee and epic (which are absent from TaskListRowDTO) are
        // populated. This also makes edits visible immediately after the
        // editor sheet is dismissed (defect 2).
        if let fresh = try? await repository.detail(id: task.id) {
            task = fresh
        }
    }

    /// Change the task's status via the explicit status endpoint. Exposed
    /// to every role; the backend enforces the actual permission.
    func changeStatus(to newStatus: String) async {
        do {
            try await repository.changeStatus(taskId: task.id, status: newStatus)
            await reload()
        } catch {
            self.statusError = error.localizedDescription
        }
    }
}

struct TaskDetailsView: View {
    @StateObject var viewModel: TaskDetailViewModel
    @EnvironmentObject private var container: AppContainer
    @State private var showEdit = false

    init(task: WorkTask, repository: TaskRepository) {
        _viewModel = StateObject(wrappedValue: TaskDetailViewModel(task: task, repository: repository))
    }

    var body: some View {
        List {
            Section("Основное") {
                Text(viewModel.task.title).font(.headline)
                Text(viewModel.task.description ?? "")
            }
            Section("Атрибуты задачи") {
                detailRow("Приоритет", viewModel.task.priority.map(priorityTitle) ?? "-")
                detailRow("Планируемое время", viewModel.task.estimateMinutes.map { "\($0) мин" } ?? "-")
                detailRow("Затрачено", viewModel.task.spentMinutes.map { "\($0) мин" } ?? "-")
                detailRow("Осталось", remainingMinutesLabel(task: viewModel.task))
                detailRow("Статус", statusTitle(viewModel.task.status))
                detailRow("Автор", viewModel.task.reporter?.fullName ?? "-")
                detailRow("Исполнитель", viewModel.task.assignee?.fullName ?? "Не назначен")
                detailRow("Срок", viewModel.task.dueDate.map { DateFormatter.taskDate.string(from: $0) } ?? "-")
                detailRow("Эпик", viewModel.task.epic.map { "\($0.key) · \($0.title)" } ?? "-")
            }
            // Defect: explicit, always-visible status change control that
            // does not require opening the editor. Every role sees it; the
            // backend enforces the actual permission when the request lands.
            Section("Смена статуса") {
                Menu {
                    ForEach(TaskStatusOption.allCases) { option in
                        Button {
                            Task { await viewModel.changeStatus(to: option.rawValue) }
                        } label: {
                            if option.rawValue == viewModel.task.status {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Изменить статус: \(statusTitle(viewModel.task.status))")
                        Spacer()
                    }
                }
                if let err = viewModel.statusError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            NavigationLink("Учет времени") { TimeTrackingView(taskId: viewModel.task.id) }
            Button("Редактировать задачу") { showEdit = true }
        }
        .navigationTitle(viewModel.task.key ?? "Задача")
        .task { await viewModel.reload() }
        .refreshable { await viewModel.reload() }
        .sheet(isPresented: $showEdit, onDismiss: {
            Task { await viewModel.reload() }
        }) {
            NavigationStack {
                TaskEditorView(viewModel: .init(task: viewModel.task, taskRepository: container.taskRepository))
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func remainingMinutesLabel(task: WorkTask) -> String {
        guard let estimate = task.estimateMinutes else { return "-" }
        let spent = task.spentMinutes ?? 0
        return "\(max(estimate - spent, 0)) мин"
    }

    private func statusTitle(_ status: String) -> String {
        switch status {
        case "todo": "К выполнению"
        case "in_progress": "В работе"
        case "done": "Готово"
        default: status
        }
    }

    private func priorityTitle(_ priority: String) -> String {
        switch priority {
        case "low": "Низкий"
        case "medium": "Средний"
        case "high": "Высокий"
        case "critical": "Критический"
        default: priority
        }
    }
}

struct CreateTaskSheet: View {
    let projectId: UUID
    var taskToEdit: WorkTask?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: AppContainer

    @State private var title = ""
    @State private var description = ""
    @State private var priority = "high"
    @State private var estimateMinutes = "60"
    @State private var assigneeId: UUID?
    @State private var availableAssignees: [UserListItem] = []
    @State private var reporterId: UUID?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $title)
                TextField("Описание", text: $description, axis: .vertical)
                Picker("Приоритет", selection: $priority) {
                    Text("Низкий").tag("low")
                    Text("Средний").tag("medium")
                    Text("Высокий").tag("high")
                    Text("Критический").tag("critical")
                }
                .pickerStyle(.menu)
                TextField("Оценка (мин.)", text: $estimateMinutes)
                    .keyboardType(.numberPad)
                Picker("Исполнитель", selection: $assigneeId) {
                    Text("Не назначен").tag(UUID?.none)
                    ForEach(availableAssignees) { user in
                        Text(user.fullName).tag(Optional(user.id))
                    }
                }
                .pickerStyle(.menu)
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .onAppear {
                title = taskToEdit?.title ?? ""
                description = taskToEdit?.description ?? ""
                assigneeId = taskToEdit?.assignee?.id
            }
            .task {
                availableAssignees = (try? await container.adminRepository.users(search: nil)) ?? []
                reporterId = (try? await container.authRepository.me())?.id
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        Task {
                            if let taskToEdit {
                                do {
                                    let _ = try await container.taskRepository.update(
                                        id: taskToEdit.id,
                                        request: .init(title: title, description: description, priority: priority, dueDate: nil)
                                    )
                                } catch {
                                    self.error = error.localizedDescription
                                    return
                                }
                            } else if let estimate = Int(estimateMinutes) {
                                guard let reporterId else {
                                    error = "Не удалось определить автора задачи."
                                    return
                                }
                                do {
                                    try await container.taskRepository.create(
                                        .init(
                                            projectId: projectId,
                                            epicId: nil,
                                            parentTaskId: nil,
                                            title: title,
                                            description: description,
                                            issueType: "task",
                                            priority: priority,
                                            assigneeId: assigneeId,
                                            reporterId: reporterId,
                                            estimateMinutes: estimate,
                                            dueDate: nil
                                        )
                                    )
                                } catch {
                                    self.error = error.localizedDescription
                                    return
                                }
                            } else {
                                error = "Введите корректную оценку в минутах."
                                return
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(taskToEdit == nil ? "Новая задача" : "Редактирование")
        }
    }
}

/// Embeddable epics content. The ViewModel lives in an `@ObservedObject` so
/// the parent (project detail) can trigger a create via its own toolbar.
@MainActor
final class EpicsTabModel: ObservableObject {
    let projectId: UUID
    @Published var epics: [Epic] = []
    @Published var tasksByEpic: [UUID: [WorkTask]] = [:]
    @Published var availableTasks: [WorkTask] = []
    @Published var availableProjects: [Project] = []
    @Published var showCreate = false
    @Published var linkingEpicId: UUID?
    @Published var editingEpic: Epic?
    @Published var error: String?

    private let container: AppContainer

    init(projectId: UUID, container: AppContainer) {
        self.projectId = projectId
        self.container = container
    }

    func reload() async {
        epics = (try? await container.epicRepository.list(projectId: projectId)) ?? []
        availableProjects = (try? await container.projectRepository.list(page: 1, search: nil)) ?? []
        availableTasks = (try? await container.taskRepository.list(projectId: projectId, epicId: nil, page: 1, search: nil)) ?? []
        for epic in epics {
            tasksByEpic[epic.id] = (try? await container.taskRepository.list(projectId: projectId, epicId: epic.id, page: 1, search: nil)) ?? []
        }
    }

    func archive(epicId: UUID) async {
        do {
            try await container.epicRepository.archive(id: epicId)
            epics.removeAll { $0.id == epicId }
            tasksByEpic.removeValue(forKey: epicId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateEpic(id: UUID, request: UpdateEpicRequest) async -> Bool {
        do {
            try await container.epicRepository.update(id: id, request: request)
            await reload()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func linkTask(epicId: UUID, taskId: UUID) async -> Bool {
        do {
            try await container.epicRepository.linkTask(epicId: epicId, taskId: taskId)
            await reload()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct EpicsTabContent: View {
    @ObservedObject var model: EpicsTabModel
    @EnvironmentObject private var container: AppContainer
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var editProjectId: UUID?
    @State private var linkTaskId: UUID?

    var body: some View {
        List {
            if model.epics.isEmpty {
                Section {
                    Text("Эпики не созданы. Нажмите «Создать» в верхнем правом углу, чтобы добавить эпик.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(model.epics) { epic in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(epic.key).font(.caption).foregroundStyle(.secondary)
                        Text(epic.title).font(.headline)
                        if let tasks = model.tasksByEpic[epic.id], !tasks.isEmpty {
                            ForEach(tasks) { task in
                                NavigationLink(task.title) {
                                    TaskDetailsView(task: task, repository: container.taskRepository)
                                }
                                .font(.subheadline)
                            }
                        } else {
                            Text("Задачи эпика отсутствуют").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button("Добавить задачу") {
                                model.linkingEpicId = epic.id
                                linkTaskId = nil
                            }
                            .buttonStyle(.bordered)
                            Button("Изменить эпик") {
                                model.editingEpic = epic
                                editTitle = epic.title
                                editDescription = epic.description ?? ""
                                editProjectId = epic.projectId
                            }
                            .buttonStyle(.bordered)
                            Button("Удалить эпик", role: .destructive) {
                                Task { await model.archive(epicId: epic.id) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Эпик")
                }
            }
            if let error = model.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .task { await model.reload() }
        .sheet(isPresented: $model.showCreate) {
            EpicFormSheet(projectId: model.projectId)
        }
        .onChange(of: model.showCreate) { _, newValue in
            if !newValue { Task { await model.reload() } }
        }
        .sheet(item: $model.editingEpic) { epic in
            NavigationStack {
                Form {
                    TextField("Название", text: $editTitle)
                    TextField("Описание", text: $editDescription, axis: .vertical)
                    Picker("Проект", selection: $editProjectId) {
                        ForEach(model.availableProjects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    .pickerStyle(.menu)
                    if let error = model.error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Отмена") { model.editingEpic = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Сохранить") {
                            Task {
                                let ok = await model.updateEpic(
                                    id: epic.id,
                                    request: .init(projectId: editProjectId, title: editTitle, description: editDescription, status: nil, startDate: nil, dueDate: nil)
                                )
                                if ok { model.editingEpic = nil }
                            }
                        }
                        .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle("Редактирование эпика")
            }
        }
        .sheet(item: Binding(
            get: { model.linkingEpicId.map { LinkEpicTarget(epicId: $0) } },
            set: { model.linkingEpicId = $0?.epicId }
        )) { target in
            NavigationStack {
                Form {
                    Picker("Задача", selection: $linkTaskId) {
                        Text("Выберите задачу").tag(UUID?.none)
                        ForEach(model.availableTasks.filter { $0.epicId == nil }) { task in
                            Text(task.title).tag(Optional(task.id))
                        }
                    }
                    .pickerStyle(.menu)
                    if let error = model.error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Отмена") { model.linkingEpicId = nil }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Добавить") {
                            Task {
                                guard let linkTaskId else { return }
                                let ok = await model.linkTask(epicId: target.epicId, taskId: linkTaskId)
                                if ok { model.linkingEpicId = nil }
                            }
                        }
                        .disabled(linkTaskId == nil)
                    }
                }
                .navigationTitle("Добавить в эпик")
            }
        }
    }
}

private struct LinkEpicTarget: Identifiable {
    let epicId: UUID
    var id: UUID { epicId }
}

@MainActor
final class BoardListViewModel: ObservableObject {
    @Published var boards: [Board] = []
    @Published var selectedBoard: Board?
    @Published var selectedProjectID: UUID? {
        didSet {
            UserDefaults.standard.set(selectedProjectID?.uuidString, forKey: "boards.selectedProjectID")
        }
    }
    @Published var projects: [Project] = []
    @Published var error: String?
    private let repository: BoardRepository
    private let projectRepository: ProjectRepository

    init(repository: BoardRepository, projectRepository: ProjectRepository) {
        self.repository = repository
        self.projectRepository = projectRepository
        if let raw = UserDefaults.standard.string(forKey: "boards.selectedProjectID") {
            self.selectedProjectID = UUID(uuidString: raw)
        }
    }

    func load() async {
        boards = (try? await repository.list(projectId: selectedProjectID)) ?? []
    }

    func loadProjects() async {
        projects = (try? await projectRepository.list(page: 1, search: nil)) ?? []
    }

    /// Create a new board scoped to the given project. Returns the created
    /// id on success so the caller can optimistically select it.
    func createBoard(projectId: UUID, name: String, description: String, isDefault: Bool) async -> UUID? {
        do {
            let created = try await repository.create(
                projectId: projectId,
                name: name,
                description: description,
                isDefault: isDefault
            )
            await load()
            return created.id
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}

struct BoardListView: View {
    @StateObject var viewModel: BoardListViewModel
    @State private var showCreateBoard = false

    var body: some View {
        List {
            Section("Проект") {
                Picker("Фильтр проекта", selection: $viewModel.selectedProjectID) {
                    Text("Все проекты").tag(UUID?.none)
                    ForEach(viewModel.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Доски") {
                if viewModel.boards.isEmpty {
                    Text("Нет досок для выбранного проекта.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.boards) { board in
                    NavigationLink(value: board) {
                        Text(board.name)
                    }
                }
            }
        }
        .navigationDestination(for: Board.self) { board in
            KanbanBoardView(boardId: board.id)
        }
        .toolbar {
            // Defect 3: add a visible "Создать доску" button. Disabled
            // while no project is selected since the backend requires a
            // projectId for board creation.
            Button("Создать доску") { showCreateBoard = true }
                .disabled(viewModel.selectedProjectID == nil)
        }
        .sheet(isPresented: $showCreateBoard) {
            if let pid = viewModel.selectedProjectID {
                BoardFormSheet(projectId: pid) { name, description, isDefault in
                    Task { _ = await viewModel.createBoard(projectId: pid, name: name, description: description, isDefault: isDefault) }
                }
            }
        }
        .task {
            await viewModel.loadProjects()
            await viewModel.load()
        }
        .onChange(of: viewModel.selectedProjectID) { _, _ in
            Task { await viewModel.load() }
        }
        .refreshable {
            await viewModel.loadProjects()
            await viewModel.load()
        }
        .overlay(alignment: .center) {
            if let error = viewModel.error {
                ErrorBanner(text: error)
            }
        }
        .navigationTitle("Доски")
    }
}

struct BoardFormSheet: View {
    let projectId: UUID
    let onSave: (_ name: String, _ description: String, _ isDefault: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isDefault = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название доски", text: $name)
                TextField("Описание", text: $description, axis: .vertical)
                Toggle("Доска по умолчанию", isOn: $isDefault)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Создать") {
                        onSave(name, description, isDefault)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Новая доска")
        }
    }
}

struct BoardEditSheet: View {
    let initialName: String
    let initialDescription: String
    let onSave: (_ name: String, _ description: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String

    init(initialName: String, initialDescription: String, onSave: @escaping (String, String) -> Void) {
        self.initialName = initialName
        self.initialDescription = initialDescription
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _description = State(initialValue: initialDescription)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название доски", text: $name)
                TextField("Описание", text: $description, axis: .vertical)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        onSave(name, description)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Редактирование доски")
        }
    }
}

struct BoardColumnsSheet: View {
    let boardId: UUID
    @State var columns: [BoardColumn]
    let repository: BoardRepository
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var newKey = ""
    @State private var isDoneColumn = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Колонки доски") {
                    if columns.isEmpty {
                        Text("Колонки отсутствуют. Добавьте колонку ниже.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(columns) { column in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(column.name).font(.headline)
                                Text(column.key ?? "—")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if column.isDoneColumn == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task {
                                    do {
                                        try await repository.deleteColumn(columnId: column.id)
                                        columns.removeAll { $0.id == column.id }
                                    } catch {
                                        self.error = error.localizedDescription
                                    }
                                }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
                Section("Добавить колонку") {
                    TextField("Название (например, Ready)", text: $newName)
                    TextField("Ключ (например, ready)", text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Колонка «Готово»", isOn: $isDoneColumn)
                    Button("Добавить") {
                        Task {
                            let nextOrder = (columns.map(\.orderIndex).max() ?? 0) + 1
                            do {
                                try await repository.createColumn(
                                    boardId: boardId,
                                    name: newName,
                                    key: newKey.isEmpty ? newName.lowercased().replacingOccurrences(of: " ", with: "_") : newKey,
                                    orderIndex: nextOrder,
                                    wipLimit: nil,
                                    isDoneColumn: isDoneColumn
                                )
                                columns.append(BoardColumn(
                                    id: UUID(),
                                    name: newName,
                                    key: newKey.isEmpty ? nil : newKey,
                                    orderIndex: nextOrder,
                                    isDoneColumn: isDoneColumn
                                ))
                                newName = ""
                                newKey = ""
                                isDoneColumn = false
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Готово") { dismiss() } }
            }
            .navigationTitle("Колонки")
        }
    }
}

struct KanbanBoardView: View {
    let boardId: UUID
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var board: Board?
    @State private var tasks: [WorkTask] = []
    @State private var draggedTask: WorkTask?
    @State private var showEditBoard = false
    @State private var showDeleteConfirmation = false
    @State private var showManageColumns = false
    @State private var errorMessage: String?
    @StateObject private var presentation = TaskPresentationState()

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .center, spacing: 16) {
                ForEach(board?.columns ?? []) { column in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(column.name).font(.headline)
                        let tasksInColumn = tasks.filter { $0.status == mapColumn(column) }
                        if tasksInColumn.isEmpty {
                            Text("Нет задач в этой колонке")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(tasksInColumn) { task in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(task.title).font(.subheadline).bold()
                                if let epic = task.epic {
                                    Text("Эпик: \(epic.key) · \(epic.title)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text("Приоритет: \(priorityTitle(task.priority))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    // Defect 3c: surface the current assignee so the
                                    // board shows who each task is parked on.
                                    Label(
                                        task.assignee?.fullName ?? "Не назначен",
                                        systemImage: "person.crop.circle"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(task.assignee == nil ? .secondary : .primary)
                                }
                            }
                                .padding(8)
                                .frame(maxWidth: 320, alignment: .leading)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    presentation.openFromBoard(task: task)
                                }
                                .draggable(task.id.uuidString)
                                .dropDestination(for: String.self) { _, _ in
                                    guard let draggedTask else { return false }
                                    Task {
                                        try? await container.boardRepository.moveTask(
                                            boardId: boardId,
                                            taskId: draggedTask.id,
                                            columnId: column.id,
                                            orderIndex: 1
                                        )
                                        await reloadBoard()
                                    }
                                    return true
                                }
                                .onLongPressGesture {
                                    draggedTask = task
                                }
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await reloadBoard() }
        .refreshable { await reloadBoard() }
        .sheet(item: $presentation.boardOpenedTask, onDismiss: {
            presentation.closeBoardTask()
            Task { await reloadBoard() }
        }) { task in
            NavigationStack {
                TaskDetailsView(task: task, repository: container.taskRepository)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Редактировать доску") { showEditBoard = true }
                    Button("Управление колонками") { showManageColumns = true }
                    Button("Удалить доску", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditBoard, onDismiss: {
            Task { await reloadBoard() }
        }) {
            if let current = board {
                BoardEditSheet(
                    initialName: current.name,
                    initialDescription: "",
                    onSave: { newName, newDesc in
                        Task {
                            do {
                                _ = try await container.boardRepository.update(id: boardId, name: newName, description: newDesc)
                                await reloadBoard()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showManageColumns, onDismiss: {
            Task { await reloadBoard() }
        }) {
            if let current = board {
                BoardColumnsSheet(
                    boardId: boardId,
                    columns: current.columns ?? [],
                    repository: container.boardRepository
                )
            }
        }
        .confirmationDialog(
            "Удалить доску \"\(board?.name ?? "")\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                Task {
                    do {
                        try await container.boardRepository.archive(id: boardId)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .overlay(alignment: .center) {
            if let errorMessage {
                ErrorBanner(text: errorMessage)
            }
        }
        .navigationTitle(board?.name ?? "Доска")
    }

    private func reloadBoard() async {
        board = try? await container.boardRepository.detail(id: boardId)
        guard let projectId = board?.projectId else {
            tasks = []
            return
        }
        // Pull the project's tasks so the Kanban surface reflects the
        // actual backlog (defect 3b — "наполнение досок задачами").
        tasks = (try? await container.taskRepository.list(projectId: projectId, epicId: nil, page: 1, search: nil)) ?? []
    }

    private func mapColumn(_ column: BoardColumn) -> String {
        if let key = column.key, !key.isEmpty {
            switch key {
            case "backlog", "todo": return "todo"
            case "in_progress": return "in_progress"
            case "review", "done": return "done"
            default: return key
            }
        }
        switch column.name.lowercased() {
        case "to do", "todo", "backlog": return "todo"
        case "in progress", "in_progress": return "in_progress"
        case "done", "review": return "done"
        default: return "todo"
        }
    }

    private func statusTitle(_ status: String) -> String {
        switch status {
        case "todo":
            return "К выполнению"
        case "in_progress":
            return "В работе"
        case "done":
            return "Готово"
        default:
            return status
        }
    }

    private func priorityTitle(_ priority: String?) -> String {
        guard let priority else { return "-" }
        switch priority {
        case "low":
            return "Низкий"
        case "medium":
            return "Средний"
        case "high":
            return "Высокий"
        case "critical":
            return "Критический"
        default:
            return priority
        }
    }
}

struct TimeTrackingView: View {
    let taskId: UUID
    @EnvironmentObject private var container: AppContainer
    @StateObject private var state = TimeTrackingState()
    @State private var spent = ""
    @State private var comment = ""
    @State private var isSaving = false

    var body: some View {
        List {
            Section("Добавить запись") {
                TextField("Минуты", text: $spent).keyboardType(.numberPad)
                TextField("Комментарий", text: $comment)
                Button("Сохранить") {
                    Task {
                        guard let minutes = Int(spent), minutes > 0 else {
                            state.inputError = "Введите корректное количество минут."
                            return
                        }
                        isSaving = true
                        defer { isSaving = false }
                        do {
                            let newEntry = try await container.timeRepository.create(taskId: taskId, spentMinutes: minutes, comment: comment)
                            state.prepend(newEntry)
                            spent = ""
                            comment = ""
                            state.inputError = nil
                        } catch {
                            state.inputError = error.localizedDescription
                        }
                    }
                }
                .disabled(isSaving)
                if let inputError = state.inputError {
                    Text(inputError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("История") {
                ForEach(state.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(entry.spentMinutes) мин").font(.headline)
                            Spacer()
                            if let user = entry.userFullName, !user.isEmpty {
                                Text(user)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !entry.comment.isEmpty {
                            Text(entry.comment).foregroundStyle(.secondary)
                        }
                        if let started = entry.startedAt {
                            Text(DateFormatter.taskDate.string(from: started))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .task {
            state.set((try? await container.timeRepository.list(taskId: taskId)) ?? [])
        }
        .navigationTitle("Учет времени")
    }
}

enum ProjectFormMode {
    case create
    case edit(Project)
}

struct ProjectFormSheet: View {
    let mode: ProjectFormMode
    let onSave: (_ key: String, _ name: String, _ description: String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var name = ""
    @State private var description = ""

    var body: some View {
        NavigationStack {
            Form {
                if case .create = mode {
                    TextField("Ключ проекта", text: $key)
                }
                TextField("Название проекта", text: $name)
                TextField("Описание", text: $description, axis: .vertical)
            }
            .onAppear {
                if case let .edit(project) = mode {
                    key = project.key
                    name = project.name
                    description = project.description ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        onSave(key, name, description)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (isCreate && key.isEmpty))
                }
            }
            .navigationTitle(isCreate ? "Новый проект" : "Редактирование проекта")
        }
    }

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }
}

struct EpicFormSheet: View {
    let projectId: UUID
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var title = ""
    @State private var description = ""
    @State private var availableTasks: [WorkTask] = []
    @State private var selectedTaskID: UUID?
    @State private var createdEpic: Epic?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Эпик") {
                    TextField("Ключ эпика", text: $key)
                    TextField("Название", text: $title)
                    TextField("Описание", text: $description, axis: .vertical)
                }
                if let createdEpic {
                    Section("Добавить задачу в эпик") {
                        Picker("Задача", selection: $selectedTaskID) {
                            Text("Выберите задачу").tag(UUID?.none)
                            ForEach(availableTasks) { task in
                                Text(task.title).tag(Optional(task.id))
                            }
                        }
                        .pickerStyle(.menu)
                        Button("Добавить в эпик") {
                            Task {
                                guard let selectedTaskID else { return }
                                do {
                                    try await container.epicRepository.linkTask(epicId: createdEpic.id, taskId: selectedTaskID)
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        }
                        .disabled(selectedTaskID == nil)
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .task {
                availableTasks = (try? await container.taskRepository.list(projectId: projectId, epicId: nil, page: 1, search: nil)) ?? []
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Создать") {
                        Task {
                            do {
                                try await container.epicRepository.create(
                                    projectId: projectId,
                                    request: .init(key: key, title: title, description: description)
                                )
                                let epics = (try? await container.epicRepository.list(projectId: projectId)) ?? []
                                createdEpic = epics.first(where: { $0.key == key })
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(key.isEmpty || title.isEmpty)
                }
            }
            .navigationTitle("Новый эпик")
        }
    }
}

private extension DateFormatter {
    static let taskDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var user: User?
    private let authRepository: AuthRepository
    private let authManager: AuthManager
    private let logoutAction: () -> Void

    init(authRepository: AuthRepository, authManager: AuthManager, logout: @escaping () -> Void) {
        self.authRepository = authRepository
        self.authManager = authManager
        self.logoutAction = logout
    }

    func load() async {
        user = try? await authRepository.me()
    }

    func logout() async {
        authManager.clearTokens()
        logoutAction()
    }
}

struct ProfileView: View {
    @StateObject var viewModel: ProfileViewModel
    let adminRepository: AdminRepository
    @AppStorage("app.theme") private var selectedThemeRaw = AppTheme.system.rawValue
    @AppStorage("app.accentColor") private var selectedAccentRaw = AppAccentColor.blue.rawValue

    var body: some View {
        List {
            if let user = viewModel.user {
                Text(user.fullName).font(.headline)
                Text(user.email).foregroundStyle(.secondary)
                Text("Роль: \(user.role.localizedName)")
                if let permissions = user.permissions {
                    Text("Права: \(permissions.joined(separator: ", "))")
                }
                if let points = user.pointsBalance {
                    Text("Баллы: \(points)")
                        .font(.subheadline)
                }
                if user.role.name.lowercased() == "admin" {
                    NavigationLink("Управление ролями и правами") {
                        AdminAccessView(viewModel: .init(repository: adminRepository, currentUserId: user.id))
                    }
                }
            } else {
                ProgressView()
            }
            // Defect 4: `.menu`-style Pickers render their selected value via
            // a UIKit menu button which captures its tint color at creation
            // time and does NOT repaint when SwiftUI's tint environment
            // changes later. Binding `.id(selectedAccentRaw)` to the stored
            // accent forces SwiftUI to rebuild the Picker every time the user
            // switches accents, so the selection text on THIS screen picks up
            // the new colour together with the rest of the app. `.tint(...)`
            // supplies the colour explicitly for good measure.
            Section("Оформление") {
                Picker("Тема", selection: $selectedThemeRaw) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }
                .tint(currentAccent)
                .id("theme-picker-\(selectedAccentRaw)")
                Picker("Акцентный цвет", selection: $selectedAccentRaw) {
                    ForEach(AppAccentColor.allCases) { accent in
                        Text(accent.title).tag(accent.rawValue)
                    }
                }
                .tint(currentAccent)
                .id("accent-picker-\(selectedAccentRaw)")
            }
            Button(role: .destructive) {
                Task { await viewModel.logout() }
            } label: {
                Text("Выйти")
            }
        }
        .task { await viewModel.load() }
        .navigationTitle("Профиль")
    }

    private var currentAccent: Color {
        AppAccentColor(rawValue: selectedAccentRaw)?.color ?? .blue
    }
}

@MainActor
final class AdminAccessViewModel: ObservableObject {
    @Published var users: [UserListItem] = []
    @Published var roles: [Role] = []
    @Published var selectedRoles: [UUID: UUID] = [:]
    @Published var rolePermissions: [UUID: String] = [:]
    @Published var error: String?
    @Published var showCreateUser = false
    @Published var editingUser: UserListItem?
    @Published var assignableProjects: [ProjectRef] = []
    let repository: AdminRepository
    let currentUserId: UUID

    init(repository: AdminRepository, currentUserId: UUID) {
        self.repository = repository
        self.currentUserId = currentUserId
    }

    func load() async {
        do {
            async let fetchedUsers = repository.users(search: nil)
            async let fetchedRoles = repository.roles(search: nil)
            async let fetchedProjects = repository.assignableProjects()
            users = try await fetchedUsers
            roles = try await fetchedRoles
            assignableProjects = try await fetchedProjects
            selectedRoles = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0.role.id) })
        } catch {
            self.error = error.localizedDescription
        }
    }

    func applyRole(for user: UserListItem) async {
        guard user.id != currentUserId else {
            self.error = "Нельзя изменить роль текущего администратора."
            return
        }
        guard let roleID = selectedRoles[user.id] else { return }
        do {
            try await repository.updateUserRole(userId: user.id, roleId: roleID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func applyPermissions(for role: Role) async {
        let raw = rolePermissions[role.id] ?? ""
        let permissions = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !permissions.isEmpty else {
            self.error = "Введите хотя бы одно право."
            return
        }
        do {
            try await repository.updateRolePermissions(roleId: role.id, permissions: permissions)
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createUser(email: String, password: String, fullName: String, roleId: UUID, projectIds: [UUID]) async {
        do {
            try await repository.createUser(
                .init(
                    email: email,
                    password: password,
                    fullName: fullName,
                    roleId: roleId,
                    isActive: true,
                    projectIds: projectIds.isEmpty ? nil : projectIds
                )
            )
            users = try await repository.users(search: nil)
            showCreateUser = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveUserProjects(userId: UUID, projectIds: [UUID]) async {
        do {
            try await repository.replaceUserProjects(userId: userId, projectIds: projectIds)
            editingUser = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AdminAccessView: View {
    @StateObject var viewModel: AdminAccessViewModel

    var body: some View {
        List {
            Section("Пользователи и роли") {
                ForEach(viewModel.users) { user in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(user.fullName).font(.headline)
                                Text(user.email).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Проекты") {
                                viewModel.editingUser = user
                            }
                            .buttonStyle(.bordered)
                        }
                        Picker("Роль", selection: Binding(
                            get: { viewModel.selectedRoles[user.id] ?? user.role.id },
                            set: { viewModel.selectedRoles[user.id] = $0 }
                        )) {
                            ForEach(viewModel.roles) { role in
                                Text(role.localizedName).tag(role.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(user.id == viewModel.currentUserId)
                        Button("Применить роль") {
                            Task { await viewModel.applyRole(for: user) }
                        }
                        .disabled(user.id == viewModel.currentUserId)
                    }
                }
            }

            Section("Права ролей") {
                ForEach(viewModel.roles) { role in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(role.localizedName).font(.headline)
                        TextField(
                            "Права через запятую (task.create, task.assign)",
                            text: Binding(
                                get: { viewModel.rolePermissions[role.id] ?? "" },
                                set: { viewModel.rolePermissions[role.id] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        Button("Применить права") {
                            Task { await viewModel.applyPermissions(for: role) }
                        }
                    }
                }
            }
            if let error = viewModel.error {
                Text(error).foregroundStyle(.red)
            }
        }
        .task { await viewModel.load() }
        .toolbar {
            Button("Новый пользователь") {
                viewModel.showCreateUser = true
            }
        }
        .sheet(isPresented: $viewModel.showCreateUser) {
            AdminCreateUserSheet(roles: viewModel.roles, projects: viewModel.assignableProjects) { email, password, fullName, roleId, projectIds in
                Task { await viewModel.createUser(email: email, password: password, fullName: fullName, roleId: roleId, projectIds: projectIds) }
            }
        }
        .sheet(item: $viewModel.editingUser) { user in
            AdminEditUserProjectsSheet(
                user: user,
                repository: viewModel.repository,
                allProjects: viewModel.assignableProjects
            ) { projectIds in
                Task { await viewModel.saveUserProjects(userId: user.id, projectIds: projectIds) }
            }
        }
        .navigationTitle("Доступы")
    }
}

struct AdminProjectSelectionSection: View {
    let projects: [ProjectRef]
    @Binding var selectedProjectIds: Set<UUID>

    var body: some View {
        Section {
            if projects.isEmpty {
                Text("Нет доступных проектов")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projects) { project in
                    Toggle(isOn: Binding(
                        get: { selectedProjectIds.contains(project.id) },
                        set: { isOn in
                            if isOn {
                                selectedProjectIds.insert(project.id)
                            } else {
                                selectedProjectIds.remove(project.id)
                            }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(project.name)
                            Text(project.key).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Проекты")
        } footer: {
            if selectedProjectIds.isEmpty {
                Text("Пользователь не привязан ни к одному проекту.")
            }
        }
    }
}

struct AdminCreateUserSheet: View {
    let roles: [Role]
    let projects: [ProjectRef]
    let onSave: (_ email: String, _ password: String, _ fullName: String, _ roleId: UUID, _ projectIds: [UUID]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var selectedRoleId: UUID?
    @State private var selectedProjectIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Пароль", text: $password)
                TextField("ФИО", text: $fullName)
                Picker("Роль", selection: $selectedRoleId) {
                    Text("Выберите роль").tag(UUID?.none)
                    ForEach(roles) { role in
                        Text(role.localizedName).tag(Optional(role.id))
                    }
                }
                AdminProjectSelectionSection(projects: projects, selectedProjectIds: $selectedProjectIds)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        guard let selectedRoleId else { return }
                        onSave(email, password, fullName, selectedRoleId, Array(selectedProjectIds))
                        dismiss()
                    }
                    .disabled(email.isEmpty || password.count < 8 || fullName.isEmpty || selectedRoleId == nil)
                }
            }
            .navigationTitle("Новый пользователь")
        }
    }
}

struct AdminEditUserProjectsSheet: View {
    let user: UserListItem
    let repository: AdminRepository
    let allProjects: [ProjectRef]
    let onSave: (_ projectIds: [UUID]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProjectIds: Set<UUID> = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Загрузка проектов…")
                } else {
                    Form {
                        Section {
                            Text(user.fullName).font(.headline)
                            Text(user.email).foregroundStyle(.secondary)
                        }
                        AdminProjectSelectionSection(projects: allProjects, selectedProjectIds: $selectedProjectIds)
                        if let loadError {
                            Text(loadError).foregroundStyle(.red)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        onSave(Array(selectedProjectIds))
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
            .navigationTitle("Проекты пользователя")
            .task {
                do {
                    let detail = try await repository.userDetail(userId: user.id)
                    selectedProjectIds = Set(detail.projects.map(\.id))
                    isLoading = false
                } catch {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Shop

enum ShopContentTab: String, Hashable, Identifiable {
    case catalog
    case myOrders
    case allOrders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catalog: return "Магазин"
        case .myOrders: return "Мои заказы"
        case .allOrders: return "Заказы"
        }
    }
}

@MainActor
final class ShopViewModel: ObservableObject {
    @Published var selectedTab: ShopContentTab = .catalog
    @Published var items: [ShopItem] = []
    @Published var myOrders: [ShopOrder] = []
    @Published var allOrders: [ShopOrder] = []
    @Published var pointsBalance: Int = 0
    @Published var error: String?
    @Published var showCreateItem = false
    @Published var editingItem: ShopItem?
    @Published var orderingItem: ShopItem?
    @Published var deleteConfirmationItem: ShopItem?
    @Published var isAdmin = false

    private let shopRepository: ShopRepository
    private let authRepository: AuthRepository
    @Published var currentUserId: UUID?

    init(shopRepository: ShopRepository, authRepository: AuthRepository) {
        self.shopRepository = shopRepository
        self.authRepository = authRepository
    }

    var visibleTabs: [ShopContentTab] {
        isAdmin ? [.catalog, .myOrders, .allOrders] : [.catalog, .myOrders]
    }

    func load() async {
        do {
            let me = try await authRepository.me()
            currentUserId = me.id
            isAdmin = me.role.name.lowercased() == "admin"
            if !visibleTabs.contains(selectedTab) {
                selectedTab = .catalog
            }
            async let fetchedItems = shopRepository.items()
            async let fetchedMyOrders = shopRepository.myOrders()
            async let fetchedBalance = shopRepository.balance()
            items = try await fetchedItems
            myOrders = try await fetchedMyOrders
            pointsBalance = try await fetchedBalance
            if isAdmin {
                allOrders = try await shopRepository.allOrders()
            } else {
                allOrders = []
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createItem(name: String, description: String, pricePoints: Int, isObsolete: Bool) async {
        do {
            _ = try await shopRepository.createItem(
                .init(name: name, description: description, pricePoints: pricePoints, isObsolete: isObsolete)
            )
            showCreateItem = false
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateItem(_ item: ShopItem, name: String, description: String, pricePoints: Int, isObsolete: Bool) async {
        do {
            _ = try await shopRepository.updateItem(
                id: item.id,
                request: .init(
                    name: name,
                    description: description,
                    pricePoints: pricePoints,
                    isObsolete: isObsolete,
                    isActive: true
                )
            )
            editingItem = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func requestDelete(_ item: ShopItem) {
        deleteConfirmationItem = item
    }

    func deleteItem(_ item: ShopItem) async {
        do {
            try await shopRepository.deleteItem(id: item.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func placeOrder(item: ShopItem, address: String) async {
        do {
            _ = try await shopRepository.createOrder(.init(itemId: item.id, deliveryAddress: address))
            orderingItem = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateOrderStatus(order: ShopOrder, to status: String) async {
        do {
            _ = try await shopRepository.updateOrderStatus(orderId: order.id, status: status)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func canMarkShipped(order: ShopOrder) -> Bool {
        isAdmin && order.status == "assembling"
    }

    func canMarkReceived(order: ShopOrder, currentUserId: UUID) -> Bool {
        order.status == "shipped" && order.userId == currentUserId
    }
}

struct ShopView: View {
    @StateObject var viewModel: ShopViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Баланс: \(viewModel.pointsBalance) баллов")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Picker("Раздел", selection: $viewModel.selectedTab) {
                ForEach(viewModel.visibleTabs) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if let error = viewModel.error {
                Text(error).foregroundStyle(.red).padding(.horizontal)
            }

            switch viewModel.selectedTab {
            case .catalog:
                shopCatalog
            case .myOrders:
                ShopOrdersList(
                    orders: viewModel.myOrders,
                    showAdminColumns: false,
                    viewModel: viewModel
                )
            case .allOrders:
                ShopOrdersList(
                    orders: viewModel.allOrders,
                    showAdminColumns: true,
                    viewModel: viewModel
                )
            }
        }
        .navigationTitle("Магазин")
        .toolbar {
            if viewModel.isAdmin, viewModel.selectedTab == .catalog {
                Button("Добавить товар") {
                    viewModel.showCreateItem = true
                }
            }
        }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .sheet(isPresented: $viewModel.showCreateItem) {
            ShopItemFormSheet(title: "Новый товар", isObsolete: false) { name, description, price, obsolete in
                await viewModel.createItem(name: name, description: description, pricePoints: price, isObsolete: obsolete)
            }
        }
        .sheet(item: $viewModel.editingItem) { item in
            ShopItemFormSheet(title: "Изменить товар", item: item) { name, description, price, isObsolete in
                await viewModel.updateItem(item, name: name, description: description, pricePoints: price, isObsolete: isObsolete)
            }
        }
        .sheet(item: $viewModel.orderingItem) { item in
            ShopOrderSheet(
                item: item,
                balance: viewModel.pointsBalance,
                onOrder: { address in
                    Task { await viewModel.placeOrder(item: item, address: address) }
                },
                onInsufficientPoints: {
                    viewModel.error = "Недостаточно баллов для покупки этого товара."
                    viewModel.orderingItem = nil
                }
            )
        }
        .alert(item: $viewModel.deleteConfirmationItem) { item in
            Alert(
                title: Text("Удалить «\(item.name)»?"),
                message: Text("Если по товару уже есть заказы, товар будет скрыт из каталога."),
                primaryButton: .destructive(Text("Удалить")) {
                    Task { await viewModel.deleteItem(item) }
                },
                secondaryButton: .cancel(Text("Отмена"))
            )
        }
    }

    @ViewBuilder
    private var shopCatalog: some View {
        if viewModel.items.isEmpty {
            ContentUnavailableView("Магазин пуст", systemImage: "bag")
        } else {
            List(viewModel.items) { item in
                ShopCatalogRow(item: item, viewModel: viewModel)
            }
        }
    }
}

struct ShopCatalogRow: View {
    let item: ShopItem
    @ObservedObject var viewModel: ShopViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.name).font(.headline)
                if item.isObsolete {
                    Text("Не актуально")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .clipShape(Capsule())
                }
                if item.isActive == false {
                    Text("Снят с продажи")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(item.description).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Text("\(item.pricePoints) баллов")
                    .font(.subheadline.bold())
                Spacer()
                if item.isOrderable {
                    Button("Потратить баллы") {
                        if viewModel.pointsBalance < item.pricePoints {
                            viewModel.error = "Недостаточно баллов для покупки этого товара."
                        } else {
                            viewModel.orderingItem = item
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Недоступно для заказа")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if viewModel.isAdmin {
                HStack(spacing: 12) {
                    ShopIconActionButton(
                        systemImage: "pencil",
                        accessibilityLabel: "Изменить",
                        tint: .accentColor
                    ) {
                        viewModel.editingItem = item
                    }
                    ShopIconActionButton(
                        systemImage: "trash",
                        accessibilityLabel: "Удалить",
                        tint: .red
                    ) {
                        viewModel.requestDelete(item)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Compact bordered icon button (~4× smaller than the previous 44 pt control).
private struct ShopIconActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 11, height: 11)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 6))
        .controlSize(.mini)
        .tint(tint)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ShopOrdersList: View {
    let orders: [ShopOrder]
    let showAdminColumns: Bool
    @ObservedObject var viewModel: ShopViewModel

    var body: some View {
        if orders.isEmpty {
            ContentUnavailableView("Заказов пока нет", systemImage: "shippingbox")
        } else {
            List(orders) { order in
                VStack(alignment: .leading, spacing: 6) {
                    if showAdminColumns {
                        Text("\(order.itemName) / \(order.userFullName)")
                            .font(.headline)
                        Text(order.deliveryAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(order.itemName).font(.headline)
                        Text(order.deliveryAddress).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Статус: \(order.localizedStatus)")
                        .font(.subheadline)
                    if let userId = viewModel.currentUserId {
                        if viewModel.canMarkShipped(order: order) {
                            Button("Отметить отправленным") {
                                Task { await viewModel.updateOrderStatus(order: order, to: "shipped") }
                            }
                        }
                        if viewModel.canMarkReceived(order: order, currentUserId: userId) {
                            Button("Подтвердить получение") {
                                Task { await viewModel.updateOrderStatus(order: order, to: "received") }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct ShopItemFormSheet: View {
    let title: String
    let initialIsObsolete: Bool
    let onSave: (String, String, Int, Bool) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var name: String
    @State private var description: String
    @State private var priceText: String
    @State private var isObsolete: Bool

    init(title: String, isObsolete: Bool, onSave: @escaping (String, String, Int, Bool) async -> Void) {
        self.title = title
        self.initialIsObsolete = isObsolete
        self.onSave = onSave
        _name = State(initialValue: "")
        _description = State(initialValue: "")
        _priceText = State(initialValue: "")
        _isObsolete = State(initialValue: isObsolete)
    }

    init(title: String, item: ShopItem, onSave: @escaping (String, String, Int, Bool) async -> Void) {
        self.title = title
        self.initialIsObsolete = item.isObsolete
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _description = State(initialValue: item.description)
        _priceText = State(initialValue: "\(item.pricePoints)")
        _isObsolete = State(initialValue: item.isObsolete)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                TextField("Описание", text: $description)
                TextField("Стоимость в баллах", text: $priceText)
                    .keyboardType(.numberPad)
                Toggle("Не актуально", isOn: $isObsolete)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        guard let price = Int(priceText), price > 0 else { return }
                        isSaving = true
                        Task {
                            await onSave(name, description, price, isObsolete)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving || name.isEmpty || description.isEmpty || Int(priceText) == nil)
                }
            }
            .navigationTitle(title)
        }
    }
}

struct ShopOrderSheet: View {
    let item: ShopItem
    let balance: Int
    let onOrder: (String) -> Void
    let onInsufficientPoints: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""

    var body: some View {
        NavigationStack {
            Form {
                Text(item.name).font(.headline)
                Text("Стоимость: \(item.pricePoints) баллов")
                Text("Ваш баланс: \(balance)")
                    .foregroundStyle(balance >= item.pricePoints ? Color.secondary : Color.red)
                TextField("Адрес доставки", text: $address, axis: .vertical)
                    .lineLimit(3...6)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Заказать") {
                        if balance < item.pricePoints {
                            onInsufficientPoints()
                        } else {
                            onOrder(address)
                            dismiss()
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
                }
            }
            .navigationTitle("Оформление заказа")
        }
    }
}
