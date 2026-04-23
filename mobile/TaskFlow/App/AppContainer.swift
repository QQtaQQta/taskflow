import Combine
import Foundation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppAccentColor: String, CaseIterable, Identifiable {
    case blue
    case green
    case orange
    case purple
    case pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "Синий"
        case .green: return "Зелёный"
        case .orange: return "Оранжевый"
        case .purple: return "Фиолетовый"
        case .pink: return "Розовый"
        }
    }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        }
    }

    /// Name of the alternate app icon bundle entry registered in Info.plist.
    /// Matches the `CFBundleAlternateIcons` keys (AppIcon-Blue … AppIcon-Pink)
    /// so `UIApplication.setAlternateIconName` can switch the home-screen
    /// icon to the accent the user just picked.
    var alternateIconName: String {
        switch self {
        case .blue: return "AppIcon-Blue"
        case .green: return "AppIcon-Green"
        case .orange: return "AppIcon-Orange"
        case .purple: return "AppIcon-Purple"
        case .pink: return "AppIcon-Pink"
        }
    }
}

#if canImport(UIKit)
import UIKit

enum AppIconSwitcher {
    /// Asynchronously align the iOS alternate app icon with the current
    /// accent preference. iOS 16+ accepts this call at any time and shows
    /// its own confirmation UI. Silently no-ops if the app is not allowed
    /// to change icons (e.g. previews, tests) or if the target is already
    /// selected.
    @MainActor static func apply(_ accent: AppAccentColor) {
        let desired = accent.alternateIconName
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        if app.alternateIconName == desired { return }
        // Primary icon's equivalent name is the same as Blue; iOS treats
        // the primary icon as "nil" alternate. To support setting Blue
        // explicitly we map it to nil so iOS reverts to the primary asset.
        let target: String? = (accent == .blue) ? nil : desired
        app.setAlternateIconName(target) { _ in }
    }
}
#endif

@MainActor
final class AppContainer: ObservableObject {
    let configuration: APIConfiguration
    let tokenStore: TokenStore
    let authManager: AuthManager
    let apiClient: APIClient

    let authRepository: AuthRepository
    let projectRepository: ProjectRepository
    let taskRepository: TaskRepository
    let epicRepository: EpicRepository
    let boardRepository: BoardRepository
    let timeRepository: TimeTrackingRepository
    let adminRepository: AdminRepository

    @Published var authState: AuthState = .loggedOut

    private init(
        configuration: APIConfiguration,
        tokenStore: TokenStore,
        authManager: AuthManager,
        apiClient: APIClient
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.authManager = authManager
        self.apiClient = apiClient
        self.authRepository = AuthRepositoryImpl(client: apiClient)
        self.projectRepository = ProjectRepositoryImpl(client: apiClient)
        self.taskRepository = TaskRepositoryImpl(client: apiClient)
        self.epicRepository = EpicRepositoryImpl(client: apiClient)
        self.boardRepository = BoardRepositoryImpl(client: apiClient)
        self.timeRepository = TimeTrackingRepositoryImpl(client: apiClient)
        self.adminRepository = AdminRepositoryImpl(client: apiClient)
    }

    static func bootstrap() -> AppContainer {
        let configuration = APIConfiguration(baseURL: URL(string: "http://127.0.0.1:8080/api/v1")!)
        let tokenStore = KeychainTokenStore(service: "com.taskflow.mobile")
        let authManager = AuthManager(tokenStore: tokenStore)
        let apiClient = APIClient(configuration: configuration, authManager: authManager)
        let container = AppContainer(
            configuration: configuration,
            tokenStore: tokenStore,
            authManager: authManager,
            apiClient: apiClient
        )
        Task {
            let isLoggedIn = authManager.hasValidTokens()
            await MainActor.run {
                container.authState = isLoggedIn ? .loggedIn : .loggedOut
            }
        }
        return container
    }
}

enum AuthState {
    case loggedOut
    case loggedIn
}

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Group {
                switch container.authState {
                case .loggedOut:
                    LoginView(viewModel: .init(authRepository: container.authRepository, authManager: container.authManager) {
                        container.authState = .loggedIn
                    })
                case .loggedIn:
                    MainTabView()
                }
            }
        }
        .dynamicTypeSize(.large ... .accessibility2)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        TabView {
            NavigationStack {
                ProjectsView(
                    viewModel: .init(repository: container.projectRepository),
                    taskRepository: container.taskRepository
                )
            }
            .tabItem {
                Label("Проекты", systemImage: "folder")
            }

            NavigationStack {
                BoardListView(viewModel: .init(repository: container.boardRepository, projectRepository: container.projectRepository))
            }
            .tabItem {
                Label("Доски", systemImage: "rectangle.3.group")
            }

            NavigationStack {
                ProfileView(viewModel: .init(authRepository: container.authRepository, authManager: container.authManager) {
                    container.authManager.clearTokens()
                    container.authState = .loggedOut
                }, adminRepository: container.adminRepository)
            }
            .tabItem {
                Label("Профиль", systemImage: "person.crop.circle")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
