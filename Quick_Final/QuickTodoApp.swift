// QuickTodoApp.swift
// Slim application entry point; feature code lives in focused files.

import SwiftUI
import SwiftData

@main
struct QuickTodoApp: App {
    var container: ModelContainer = QuickTodoApp.makeModelContainer()

    init() {
        NotificationManager.shared.configure()
        GlobalHotKeyManager.shared.register {
            Task { @MainActor in QuickAddPanelController.shared.toggle() }
        }
        #if DEBUG
        QuickDateParserSelfTest.run()
        NextMoveEngineSelfTest.run()
        #endif
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: QuickTodoMigrationPlan.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
            SwiftDataBridge.shared.modelContainer = container
            SwiftDataBridge.shared.isUsingTemporaryStore = false
            return container
        } catch {
            print("[SwiftData] Persistent store failed: \(error)")
            print("[SwiftData] Falling back to in-memory storage for this launch.")
            do {
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: QuickTodoMigrationPlan.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
                SwiftDataBridge.shared.modelContainer = container
                SwiftDataBridge.shared.isUsingTemporaryStore = true
                return container
            } catch {
                fatalError("SwiftData failed to initialize persistent and fallback stores: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .modelContainer(container)
                .onOpenURL { url in
                    QuickTodoApp.handleDeepLink(url)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1540, height: 900)
        .commands { AppCommands() }

        MenuBarExtra("QuickTodo", systemImage: "checkmark.circle") {
            MenuBarView().modelContainer(container)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView() }
    }

    // MARK: - Deep Link Handler

    // Handles quicktodo://complete?title=POLS%204110%3A%20Read%20Chapters%205-6
    // Matches tasks by their stored title (which includes the "COURSE: " prefix added
    // at import time). Case-insensitive so minor capitalisation differences don't matter.
    @MainActor
    static func handleDeepLink(_ url: URL) {
        guard
            url.scheme?.lowercased() == "quicktodo",
            url.host?.lowercased() == "complete",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let titleParam = components.queryItems?.first(where: { $0.name == "title" })?.value,
            !titleParam.isEmpty
        else { return }

        guard let context = SwiftDataBridge.shared.modelContainer?.mainContext else { return }
        let allTasks = (try? context.fetch(
            FetchDescriptor<TaskItem>(predicate: #Predicate { !$0.isCompleted && $0.deletedAt == nil })
        )) ?? []

        // Optional course param disambiguates tasks that share a title across courses
        // (e.g. "Study for Final Exam" in both Political Psychology & Civil Liberties).
        let courseParam = components.queryItems?.first(where: { $0.name == "course" })?.value

        guard let task = allTasks.first(where: {
            guard $0.title.caseInsensitiveCompare(titleParam) == .orderedSame else { return false }
            if let course = courseParam {
                return $0.category.caseInsensitiveCompare(course) == .orderedSame
            }
            return true
        }) else {
            print("[DeepLink] No matching task found for title: \(titleParam)")
            return
        }

        task.isCompleted = true
        task.completedAt = .now
        task.stage = .done
        NotificationManager.shared.cancel(for: task)
        task.spawnNextOccurrence(in: context)
        context.saveOrReport()
        print("[DeepLink] Marked complete: \(task.title)")
    }
}
