import SwiftUI

@main
struct TaskFlowApp: App {
    @StateObject private var container = AppContainer.bootstrap()
    // Apply theme preferences at the WindowGroup root so that switching
    // them updates the entire app (including TabView and modals) live,
    // without needing to relaunch the app (defect 4).
    @AppStorage("app.theme") private var selectedThemeRaw = AppTheme.system.rawValue
    @AppStorage("app.accentColor") private var selectedAccentRaw = AppAccentColor.blue.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .ignoresSafeArea(.container, edges: .all)
                .preferredColorScheme(AppTheme(rawValue: selectedThemeRaw)?.colorScheme)
                .tint(AppAccentColor(rawValue: selectedAccentRaw)?.color ?? .blue)
                // Keep the iOS home screen icon in sync with the user's
                // chosen accent. Runs once at launch and on every change.
                .task(id: selectedAccentRaw) {
                    if let accent = AppAccentColor(rawValue: selectedAccentRaw) {
                        AppIconSwitcher.apply(accent)
                    }
                }
        }
    }
}
