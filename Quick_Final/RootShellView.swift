// RootShellView.swift
// The application shell and single owner of SwiftData mutations.

import SwiftUI
import SwiftData
import UserNotifications
import AppKit

struct RootShellView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }) private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt != nil }) private var trashedTasks: [TaskItem]
    @Query(sort: \CategoryItem.name, order: .forward) private var categories: [CategoryItem]

    @State private var selection: SidebarSection = .decisionBoard
    @State private var selectedTask: TaskItem?
    @State private var selectedList: String?
    @State private var search = ""
    @State private var draggedTaskID: UUID?
    @State private var draggedCategoryID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showNewTaskComposer = false
    @State private var editingTask: TaskItem?
    @State private var showAddCategoryModal = false
    @State private var showCategoryManager = false
    @State private var showClearCompletedConfirmation = false
    @State private var newCategoryName = ""
    @State private var deletedTask: TaskItem?
    @State private var showUndoNotification = false
    @State private var undoTimer: Timer?
    @State private var saveErrorMessage: String?
    @State private var saveErrorTimer: Timer?
    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @State private var showWelcome = false
    @State private var showGlobalSearch = false
    @State private var blockedCompletionTask: TaskItem?
    @State private var repeatedlyPushedTask: TaskItem?

    @AppStorage("hasMigratedTaskStage") private var hasMigratedTaskStage = false
    @AppStorage("hasSeenWelcomeV1") private var hasSeenWelcome = false
    @AppStorage("hasSeededDecisionBoardPreviewV1") private var hasSeededDecisionBoardPreview = false
    @AppStorage("hasSeededFeatureShowcaseV3") private var hasSeededFeatureShowcase = false
    @AppStorage("hasRemovedPreviewFocusOverrideV1") private var hasRemovedPreviewFocusOverride = false
    // Last calendar day the Scheduled-to-Ready catch-up sweep ran, e.g. "2026-06-27" —
    // a date (not a Bool) since this needs to fire again every day, not just once ever.
    @AppStorage("lastReadyPromotionDay") private var lastReadyPromotionDay = ""

    // How long the undo/error toasts stay on screen, how far back Trash reaches before
    // purging for good, how long the menu bar/hotkey panel's save needs to propagate to
    // this window's @Query before a just-created task can be looked up, how long to wait
    // before re-checking notification permission after scheduling one, and how many times
    // in a row a due date can get pushed back before it's worth flagging.
    private static let undoWindowSeconds: TimeInterval = 5
    private static let saveErrorBannerSeconds: TimeInterval = 6
    private static let trashRetentionDays: Int = 30
    private static let crossContextSyncDelay: Duration = .seconds(0.15)
    private static let notificationAuthRecheckDelay: TimeInterval = 0.8
    private static let repeatedRescheduleThreshold: Int = 3

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var activeTasks: [TaskItem] { tasks.filter { !$0.isCompleted } }
    private var generalCount: Int { activeTasks.filter { $0.resolvedStage == .general }.count }
    private var todayCount: Int {
        activeTasks.filter {
            guard let due = $0.dueDate else { return false }
            return Calendar.current.isDateInToday(due) || Calendar.current.isDateInTomorrow(due)
        }.count
    }
    private var upcomingCount: Int {
        let now = Date()
        return activeTasks.filter {
            guard let due = $0.dueDate else { return false }
            return due > now && !Calendar.current.isDateInToday(due)
        }.count
    }
    private var completedCount: Int { tasks.filter(\.isCompleted).count }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selection: $selection, generalCount: generalCount,
                todayCount: todayCount, upcomingCount: upcomingCount,
                completedCount: completedCount, trashCount: trashedTasks.count
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } content: {
            content
                .frame(minWidth: 900, maxWidth: .infinity, maxHeight: .infinity)
        } detail: {
            Group {
                if let selectedTask {
                    NextMoveInspector(
                        task: selectedTask, allTasks: tasks, categories: categories,
                        onClose: { self.selectedTask = nil },
                        onEdit: beginEditing,
                        onSetStage: { task, stage in moveToStage(task.id, to: stage) },
                        onScheduleConfirm: schedule,
                        onSetSubtasks: setSubtasks,
                        onSetProgress: setProgress,
                        onFileSomeday: fileSomeday
                    )
                } else {
                    EmptyNextMoveInspector(tasks: tasks, onSelect: { selectedTask = $0 })
                }
            }
            .navigationSplitViewColumnWidth(
                min: 340,
                ideal: 360,
                max: 420
            )
        }
        .animation(reduceMotion ? nil : .snappy(duration: Motion.panelReveal), value: selectedTask?.id)
        .preferredColorScheme(.dark)
        .background(Theme.bg)
        .task {
            ensureDefaultCategories()
            migrateInboxToGeneralIfNeeded()
            migrateStageIfNeeded()
            promoteDueSoonTasksToReadyIfNeeded()
            assignMissingSortIndexesIfNeeded()
            seedDecisionBoardPreviewIfNeeded()
            seedFeatureShowcaseIfNeeded()
            removePreviewFocusOverrideIfNeeded()
            ensurePreviewDependencySignals()
            refreshNotificationAuthorization()
            if !hasSeenWelcome { showWelcome = true }
            updateDockBadge()
            purgeOldTrash()
        }
        .onChange(of: selection) { _, _ in search = "" }
        .onChange(of: hasSeenWelcome) { _, hasSeen in
            if !hasSeen { showWelcome = true }
        }
        .onChange(of: dueBadgeCount) { _, _ in updateDockBadge() }
        .onReceive(NotificationCenter.default.publisher(for: .quickToDoTaskCreated)) { notification in
            guard let id = notification.object as? UUID else { return }
            Task {
                // The menu bar/hotkey panel save into a different ModelContext; give
                // this window's @Query a moment to pick up the new row before looking
                // it up, rather than silently missing it on the very first try.
                try? await Task.sleep(for: Self.crossContextSyncDelay)
                if let task = tasks.first(where: { $0.id == id }) {
                    revealTask(task)
                }
            }
        }
        // Fires synchronously, before BackupManager actually deletes anything — clears
        // every @State reference to a TaskItem so nothing here can touch a property on
        // a model whose backing row is about to disappear out from under it.
        .onReceive(NotificationCenter.default.publisher(for: .quickToDoDataReplaced)) { _ in
            undoTimer?.invalidate()
            undoTimer = nil
            showUndoNotification = false
            selectedTask = nil
            editingTask = nil
            deletedTask = nil
            blockedCompletionTask = nil
            repeatedlyPushedTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickToDoSaveFailed)) { _ in
            saveErrorMessage = "Couldn't save your last change. Check available disk space and try again."
            saveErrorTimer?.invalidate()
            saveErrorTimer = Timer.scheduledTimer(withTimeInterval: Self.saveErrorBannerSeconds, repeats: false) { _ in
                self.saveErrorMessage = nil
            }
        }
        .sheet(isPresented: $showNewTaskComposer) {
            NewTaskComposerView(
                isPresented: $showNewTaskComposer, categories: categories,
                defaultCategory: selectedList ?? "General", allTasks: tasks,
                onSave: addFromComposer
            )
        }
        .sheet(item: $editingTask) { task in
            NewTaskComposerView(
                isPresented: editingPresentationBinding, categories: categories,
                defaultCategory: task.category, allTasks: tasks, existingTask: task,
                onSave: { edit(task, using: $0) }
            )
        }
        .sheet(isPresented: $showAddCategoryModal) {
            AddCategoryModal(isPresented: $showAddCategoryModal, newName: $newCategoryName) { name, color in
                selectedList = ensureCategoryExists(named: name, color: color)
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            ManageCategoriesView(selectedCategory: categoryManagerSelection)
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView {
                hasSeenWelcome = true
                showWelcome = false
            }
        }
        .alert("Clear all completed tasks?", isPresented: $showClearCompletedConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive, action: clearCompleted)
        } message: {
            Text("This permanently deletes every completed task.")
        }
        .alert(
            "Can't Complete Yet",
            isPresented: Binding(
                get: { blockedCompletionTask != nil },
                set: { if !$0 { blockedCompletionTask = nil } }
            ),
            presenting: blockedCompletionTask
        ) { _ in
            Button("OK", role: .cancel) { blockedCompletionTask = nil }
        } message: { task in
            if let blockerID = task.dependsOnTaskID, let blocker = tasks.first(where: { $0.id == blockerID }) {
                Text("\"\(blocker.title)\" must be completed before \"\(task.title)\".")
            } else {
                Text("Something this task depends on must be completed first.")
            }
        }
        .alert(
            "Pushed Back Again",
            isPresented: Binding(
                get: { repeatedlyPushedTask != nil },
                set: { if !$0 { repeatedlyPushedTask = nil } }
            ),
            presenting: repeatedlyPushedTask
        ) { _ in
            Button("OK", role: .cancel) { repeatedlyPushedTask = nil }
        } message: { task in
            Text("\"\(task.title)\" has been pushed back \(task.rescheduleCount) times. Worth asking whether it's really going to happen, needs rescoping, or should just be dropped.")
        }
        .overlay(alignment: .bottom) {
            // Both toasts can be on screen together, so they share one container —
            // Liquid Glass samples what's behind each shape individually otherwise,
            // which looks wrong when two glass capsules sit this close to each other.
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    if let saveErrorMessage {
                        HStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.critical)
                                .accessibilityHidden(true)
                            Text(saveErrorMessage).font(.system(size: 12.5, weight: .medium))
                            Button("Dismiss") { self.saveErrorMessage = nil }.buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .accessibilityElement(children: .combine)
                    }
                    if showUndoNotification {
                        HStack(spacing: 14) {
                            Text("Task deleted").font(.system(size: 12.5, weight: .medium))
                            Button("Undo", action: undoDelete).buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .focusedSceneValue(\.taskActions, TaskActions(
            newTask: { showNewTaskComposer = true },
            focusSearch: { showGlobalSearch = true },
            toggleSelected: { if let task = selectedTask { toggle(task) } },
            editSelected: { if let task = selectedTask { beginEditing(task) } },
            deleteSelected: { if let task = selectedTask { delete(task) } }
        ))
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchView(tasks: tasks, categories: categories, onSelect: revealTask)
        }
    }

    @ViewBuilder private var content: some View {
        switch selection {
        case .general:
            GeneralListView(
                tasks: tasks, categories: categories, search: $search, selectedTask: $selectedTask,
                onToggle: toggle, onEdit: beginEditing, onDelete: delete,
                onNewTask: { showNewTaskComposer = true },
                onBulkComplete: bulkComplete, onBulkDelete: bulkDelete
            )
        case .decisionBoard:
            DecisionBoardView(
                tasks: tasks, categories: categories, search: $search,
                selectedTask: $selectedTask, draggedTaskID: $draggedTaskID,
                onToggle: toggle, onEdit: beginEditing, onDelete: delete,
                onReorder: reorderTask, onMoveToStage: moveToStage,
                onNewTask: { showNewTaskComposer = true },
                onQuickCapture: addFromQuickCapture
            )
        case .today:
            TodayView(
                tasks: tasks, categories: categories, search: $search, selectedTask: $selectedTask,
                onToggle: toggle, onEdit: beginEditing, onDelete: delete,
                onNewTask: { showNewTaskComposer = true },
                onBulkComplete: bulkComplete, onBulkDelete: bulkDelete
            )
        case .upcoming:
            UpcomingView(
                tasks: tasks, categories: categories, search: $search, selectedTask: $selectedTask,
                onToggle: toggle, onEdit: beginEditing, onDelete: delete,
                onNewTask: { showNewTaskComposer = true },
                onBulkComplete: bulkComplete, onBulkDelete: bulkDelete
            )
        case .lists:
            ListsView(
                tasks: tasks, categories: categories, search: $search,
                selectedTask: $selectedTask, selectedList: $selectedList,
                draggedCategoryID: $draggedCategoryID,
                onToggle: toggle, onEdit: beginEditing, onDelete: delete,
                onReorderCategory: reorderCategory,
                onNewTask: { showNewTaskComposer = true },
                onAddList: { showAddCategoryModal = true },
                onManageLists: { showCategoryManager = true },
                onBulkComplete: bulkComplete, onBulkDelete: bulkDelete
            )
        case .completed:
            CompletedView(
                tasks: tasks, categories: categories, search: $search, selectedTask: $selectedTask,
                onToggle: toggle, onEdit: beginEditing, onDelete: delete,
                onClearCompleted: { showClearCompletedConfirmation = true },
                onBulkDelete: bulkDelete
            )
        case .trash:
            TrashView(
                tasks: trashedTasks, categories: categories,
                onRestore: restoreFromTrash, onDeleteForever: permanentlyDelete,
                onEmptyTrash: emptyTrash
            )
        }
    }

    private var editingPresentationBinding: Binding<Bool> {
        Binding(get: { editingTask != nil }, set: { if !$0 { editingTask = nil } })
    }

    private var categoryManagerSelection: Binding<String> {
        Binding(get: { selectedList ?? "General" }, set: { selectedList = $0 })
    }

    // Overdue + due-today, active only — same definition Today's own "Overdue"/"Due
    // today" stats use, so the Dock badge never disagrees with what Today shows.
    private var dueBadgeCount: Int {
        let now = Date()
        let calendar = Calendar.current
        return tasks.filter { task in
            guard !task.isCompleted, let due = task.dueDate else { return false }
            return due < now || calendar.isDateInToday(due)
        }.count
    }

    private func updateDockBadge() {
        NSApplication.shared.dockTile.badgeLabel = dueBadgeCount > 0 ? "\(dueBadgeCount)" : nil
    }

    // Selects the task and scrolls it into view wherever you already are, if it's
    // actually shown there — only jumps to a different tab when the current one
    // genuinely can't show it at all (e.g. you're on Today and the task has no due
    // date). Used after creating a task (composer or Quick Capture) and by global
    // search, which has no "current tab" of its own to prefer.
    private func revealTask(_ task: TaskItem) {
        selectedTask = task
        guard !taskIsVisible(task, on: selection) else { return }
        if task.isCompleted {
            selection = .completed
        } else if let due = task.dueDate {
            let calendar = Calendar.current
            let now = Date()
            if due < now || calendar.isDateInToday(due) || calendar.isDateInTomorrow(due) {
                selection = .today
            } else {
                selection = .upcoming
            }
        } else {
            selection = .general
        }
    }

    // Mirrors each destination view's own membership rule for "is this task actually
    // shown here" — kept in sync with GeneralListView/TodayView/UpcomingView/
    // CompletedView/ListsView's own filters, and DecisionBoardView's four lanes.
    private func taskIsVisible(_ task: TaskItem, on section: SidebarSection) -> Bool {
        switch section {
        case .decisionBoard:
            // The board's four lanes collectively cover every active task.
            return !task.isCompleted
        case .general:
            return !task.isCompleted && task.resolvedStage == .general
        case .today:
            guard !task.isCompleted, let due = task.dueDate else { return false }
            let calendar = Calendar.current
            let now = Date()
            return due < now || calendar.isDateInToday(due) || calendar.isDateInTomorrow(due)
        case .upcoming:
            guard !task.isCompleted, let due = task.dueDate else { return false }
            return due > Date() && !Calendar.current.isDateInToday(due)
        case .completed:
            return task.isCompleted
        case .lists:
            guard !task.isCompleted, let selectedList else { return false }
            return task.category.caseInsensitiveCompare(selectedList) == .orderedSame
        case .trash:
            return false
        }
    }

    private func ensureDefaultCategories() {
        if categories.isEmpty {
            context.insert(CategoryItem(name: "General", sortIndex: 0))
            context.saveOrReport()
        }
    }

    private func migrateInboxToGeneralIfNeeded() {
        var changed = false
        for category in categories where category.name.caseInsensitiveCompare("Inbox") == .orderedSame {
            category.name = "General"
            changed = true
        }
        for task in tasks where task.category.caseInsensitiveCompare("Inbox") == .orderedSame {
            task.category = "General"
            changed = true
        }
        if changed { context.saveOrReport() }
    }

    private func migrateStageIfNeeded() {
        let candidates = hasMigratedTaskStage ? tasks.filter { $0.stage == nil } : tasks
        guard !candidates.isEmpty || !hasMigratedTaskStage else { return }
        for task in candidates {
            task.stage = task.isCompleted ? .done : (task.dueDate == nil ? .general : .scheduled)
        }
        context.saveOrReport()
        hasMigratedTaskStage = true
    }

    // Ready only auto-fills once, at creation/import time — recomputing it live was
    // the original bug (cards snapping back even after being dragged away). This
    // covers the gap that leaves: a task sitting in Scheduled whose due date has
    // since drifted into the urgent window. Runs once per calendar day so it can't
    // fight a choice you made earlier today, and never touches Capture, since
    // landing a due-dated task there (e.g. via File/Someday) is a deliberate "not
    // now" — only Scheduled, the unconsidered default for any future due date, gets
    // graduated automatically.
    private func promoteDueSoonTasksToReadyIfNeeded() {
        let todayKey = Self.dayKeyFormatter.string(from: Date())
        guard lastReadyPromotionDay != todayKey else { return }
        lastReadyPromotionDay = todayKey

        var changed = false
        for task in tasks where !task.isCompleted && task.resolvedStage == .scheduled {
            if let due = task.dueDate, TaskStage.suggestedInitial(forDueDate: due) == .ready {
                task.stage = .ready
                changed = true
            }
        }
        if changed { context.saveOrReport() }
    }

    private func assignMissingSortIndexesIfNeeded() {
        var changed = false
        for (index, category) in categories.sorted(by: { $0.createdAt < $1.createdAt }).enumerated() where category.sortIndex == nil {
            category.sortIndex = index
            changed = true
        }
        for (index, task) in tasks.sorted(by: { $0.createdAt < $1.createdAt }).enumerated() where task.sortIndex == nil {
            task.sortIndex = index
            changed = true
        }
        if changed { context.saveOrReport() }
    }

    private func seedDecisionBoardPreviewIfNeeded() {
        #if DEBUG
        guard !hasSeededDecisionBoardPreview else { return }

        let existingNames = Set(categories.map { $0.name.lowercased() })
        let previewCategories: [(String, String)] = [
            ("School", "#8B67E8"),
            ("Work", "#4C82E8"),
            ("Personal", "#62C781"),
            ("Health", "#4DBFC4"),
            ("Errand", "#D8A64E")
        ]
        var nextCategoryIndex = (categories.compactMap(\.sortIndex).max() ?? categories.count) + 1
        for (name, colorHex) in previewCategories where !existingNames.contains(name.lowercased()) {
            context.insert(CategoryItem(name: name, colorHex: colorHex, sortIndex: nextCategoryIndex))
            nextCategoryIndex += 1
        }

        let calendar = Calendar.current
        let now = Date()
        func date(days: Int, hour: Int, minute: Int = 0) -> Date {
            let shifted = calendar.date(byAdding: .day, value: days, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shifted) ?? shifted
        }

        var nextIndex = nextTaskSortIndex()
        @discardableResult
        func add(
            _ title: String,
            notes: String = "",
            due: Date? = nil,
            category: String,
            priority: TaskPriority = .low,
            stage: TaskStage,
            estimate: Int? = nil,
            completed: Bool = false
        ) -> TaskItem {
            let task = TaskItem(
                title: title,
                notes: notes,
                dueDate: due,
                isCompleted: completed,
                completedAt: completed ? .now : nil,
                category: category,
                priority: priority,
                sortIndex: nextIndex,
                stage: completed ? .done : stage,
                estimatedMinutes: estimate
            )
            nextIndex += 1
            context.insert(task)
            return task
        }

        let midterm = add(
            "Prepare CS301 midterm",
            notes: "Review key concepts, past exams, and problem sets for the CS301 midterm.",
            due: date(days: 2, hour: 18), category: "School", priority: .high,
            stage: .general, estimate: 120
        )
        let lectureNotes = add("Review lecture notes", category: "School", priority: .medium, stage: .general, estimate: 45)
        let professorEmail = add("Email professor about project", due: date(days: 1, hour: 15), category: "School", priority: .medium, stage: .general, estimate: 10)
        let loginBug = add("Fix the login bug on staging", due: date(days: 0, hour: 20), category: "Work", priority: .high, stage: .general, estimate: 60)
        add("Organize desk setup", category: "Personal", stage: .general, estimate: 20)
        add("Plan weekend hike", category: "Personal", priority: .medium, stage: .general, estimate: 30)
        add("Buy printer ink", category: "Errand", stage: .general, estimate: 15)
        add("Submit expense report", due: date(days: 3, hour: 17), category: "Work", priority: .medium, stage: .general, estimate: 25)

        add("CS301 Midterm Study Block", due: date(days: 0, hour: 19), category: "School", priority: .high, stage: .scheduled, estimate: 120)
        add("Team standup", due: date(days: 1, hour: 9), category: "Work", priority: .medium, stage: .scheduled, estimate: 30)
        add("Grocery run", due: date(days: 1, hour: 17), category: "Errand", stage: .scheduled, estimate: 40)

        add("Build landing page components", due: date(days: 2, hour: 16), category: "Work", priority: .high, stage: .inProgress, estimate: 90)
        add("Read: Deep Work (Ch. 4)", due: date(days: 0, hour: 21), category: "Personal", stage: .inProgress, estimate: 35)
        add("Workout", due: date(days: 0, hour: 18), category: "Health", priority: .medium, stage: .inProgress, estimate: 45)

        add("Submit lab report", category: "School", stage: .done, completed: true)
        add("Call mom", category: "Personal", stage: .done, completed: true)
        add("Update resume", category: "Work", stage: .done, completed: true)
        add("Renew library card", category: "Personal", stage: .done, completed: true)

        // Real dependency signals give the inspector meaningful, non-fabricated reasons.
        lectureNotes.dependsOnTaskID = professorEmail.id
        loginBug.dependsOnTaskID = midterm.id

        context.saveOrReport()
        hasSeededDecisionBoardPreview = true
        #endif
    }

    private func seedFeatureShowcaseIfNeeded() {
        #if DEBUG
        guard !hasSeededFeatureShowcase else { return }

        let calendar = Calendar.current
        let now = Date()
        func futureDate(days: Int, hour: Int, minute: Int = 0) -> Date {
            let shifted = calendar.date(byAdding: .day, value: days, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shifted) ?? shifted
        }

        _ = ensureCategoryExists(named: "Home", color: Color(red: 0.78, green: 0.55, blue: 0.68))
        _ = ensureCategoryExists(named: "Finance", color: Color(red: 0.45, green: 0.78, blue: 0.78))

        var nextIndex = nextTaskSortIndex()
        var inserted: [String: TaskItem] = [:]
        @discardableResult
        func add(
            _ title: String,
            notes: String,
            due: Date? = nil,
            category: String,
            priority: TaskPriority = .low,
            stage: TaskStage,
            estimate: Int? = nil,
            subtasks: [Subtask] = [],
            completed: Bool = false
        ) -> TaskItem? {
            guard !tasks.contains(where: { $0.title == title }) else { return nil }
            let item = TaskItem(
                title: title,
                notes: notes,
                dueDate: due,
                isCompleted: completed,
                completedAt: completed ? now : nil,
                category: category,
                priority: priority,
                reminderSchedule: due == nil ? .none : .fiveMinutes,
                sortIndex: nextIndex,
                subtasks: subtasks.isEmpty ? nil : subtasks,
                stage: completed ? .done : stage,
                estimatedMinutes: estimate
            )
            nextIndex += 1
            context.insert(item)
            inserted[title] = item
            return item
        }

        // Capture: intentionally missing urgency signals so these remain unplanned.
        add(
            "Choose living room paint color",
            notes: "Compare the samples already taped beside the window.",
            category: "Home", stage: .general
        )
        add(
            "Sort old downloads folder",
            notes: "Keep anything related to taxes or active projects.",
            category: "Personal", stage: .general
        )

        // Ready: real dates, priorities, wording, and checklists create visible signals.
        add(
            "Research standing desk options",
            notes: "Compare stability, desktop size, warranty, and total delivered price.",
            due: futureDate(days: 3, hour: 17), category: "Home", priority: .high,
            stage: .general
        )
        add(
            "Email landlord about kitchen repair",
            notes: "Include the two photos and ask for an appointment window.",
            due: futureDate(days: 1, hour: 11), category: "Home", priority: .medium,
            stage: .general
        )
        add(
            "Confirm client success metrics",
            notes: "Ask the account lead to confirm retention and activation numbers for the presentation.",
            due: futureDate(days: 1, hour: 13), category: "Work", priority: .medium,
            stage: .general, estimate: 15
        )
        add(
            "Prepare client presentation",
            notes: "Turn the discovery notes into a clear recommendation for Friday's review.",
            due: futureDate(days: 2, hour: 15), category: "Work", priority: .high,
            stage: .general,
            subtasks: [
                Subtask(title: "Choose the three strongest findings", isDone: true),
                Subtask(title: "Build the recommendation slides"),
                Subtask(title: "Rehearse the opening and close")
            ]
        )

        // Scheduled: a mixture of explicit and inferred duration with visible dates.
        add(
            "Dentist appointment",
            notes: "Bring the new insurance card.",
            due: futureDate(days: 4, hour: 10, minute: 30), category: "Health",
            stage: .scheduled, estimate: 60
        )
        add(
            "Pay electricity bill",
            notes: "Confirm the autopay change after submitting payment.",
            due: futureDate(days: 1, hour: 9), category: "Finance", priority: .medium,
            stage: .scheduled
        )
        add(
            "Submit tax documents",
            notes: "Send the W-2, interest statement, and donation receipts to the accountant.",
            due: futureDate(days: 6, hour: 16), category: "Finance", priority: .high,
            stage: .scheduled,
            subtasks: [
                Subtask(title: "Download W-2", isDone: true),
                Subtask(title: "Find donation receipts"),
                Subtask(title: "Upload documents to the portal")
            ]
        )

        // Doing: active work demonstrates the stable in-progress lane.
        add(
            "Redesign portfolio homepage",
            notes: "Finish the case-study grid and test the responsive layout.",
            due: futureDate(days: 2, hour: 18), category: "Work", priority: .high,
            stage: .inProgress, estimate: 120,
            subtasks: [
                Subtask(title: "Create the new hero", isDone: true),
                Subtask(title: "Build the case-study grid"),
                Subtask(title: "Test tablet and mobile layouts")
            ]
        )
        add(
            "Review contract draft",
            notes: "Check termination terms, payment timing, and ownership language.",
            due: now.addingTimeInterval(3 * 3600), category: "Work", priority: .high,
            stage: .inProgress
        )

        // Completed examples keep the active board clean while exercising history.
        add(
            "Book summer travel",
            notes: "Flights and hotel confirmations are saved in the trip folder.",
            category: "Personal", stage: .done, estimate: 30, completed: true
        )

        if let presentation = inserted["Prepare client presentation"],
           let metrics = inserted["Confirm client success metrics"] {
            presentation.dependsOnTaskID = metrics.id
        }

        context.saveOrReport()
        hasSeededFeatureShowcase = true
        #endif
    }

    private func removePreviewFocusOverrideIfNeeded() {
        #if DEBUG
        guard !hasRemovedPreviewFocusOverride else { return }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "hasUpgradedDecisionBoardPreviewV2"),
           defaults.integer(forKey: FocusWindowSettings.startKey) == 19 * 60,
           defaults.integer(forKey: FocusWindowSettings.endKey) == 21 * 60 {
            defaults.set(false, forKey: FocusWindowSettings.enabledKey)
        }
        defaults.removeObject(forKey: "hasUpgradedDecisionBoardPreviewV2")
        hasRemovedPreviewFocusOverride = true
        #endif
    }

    private func ensurePreviewDependencySignals() {
        #if DEBUG
        if let midterm = tasks.first(where: { $0.title == "Prepare CS301 midterm" }),
           let expenseReport = tasks.first(where: { $0.title == "Submit expense report" }) {
            expenseReport.dependsOnTaskID = midterm.id
            context.saveOrReport()
        }
        #endif
    }

    private func ensureCategoryExists(named raw: String, color: Color? = nil) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !SidebarSection.reservedNames.contains(name) else { return "General" }
        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if let color { existing.colorHex = color.toHex() }
            context.saveOrReport()
            return existing.name
        }
        let nextIndex = (categories.compactMap(\.sortIndex).max() ?? categories.count) + 1
        context.insert(CategoryItem(name: name, colorHex: color?.toHex(), sortIndex: nextIndex))
        context.saveOrReport()
        return name
    }

    private func nextTaskSortIndex() -> Int {
        (tasks.compactMap(\.sortIndex).max() ?? tasks.count) + 1
    }

    private func addFromQuickCapture(_ parsed: QuickDateParser.Result) {
        let category = ensureCategoryExists(named: parsed.category ?? "General")
        let item = TaskItem(
            title: parsed.title, dueDate: parsed.date, category: category,
            priority: parsed.priority ?? .low, sortIndex: nextTaskSortIndex(),
            stage: TaskStage.suggestedInitial(forDueDate: parsed.date)
        )
        context.insert(item)
        context.saveOrReport()
        scheduleNotificationsIfNeeded(for: item)
        // Capturing from the Decision Board's own popover stays right there, since
        // every active task shows up in one of its lanes. Capturing from the menu bar
        // or global hotkey has no "current tab" to prefer, so this jumps to wherever
        // the task actually landed.
        revealTask(item)
    }

    private func addFromComposer(_ result: TaskComposerResult) {
        let category = ensureCategoryExists(named: result.categoryName, color: result.categoryColor)
        let item = TaskItem(
            title: result.title, notes: result.notes, dueDate: result.dueDate,
            category: category, priority: result.priority,
            reminderSchedule: result.reminderSchedule,
            customReminderMinutes: result.customReminderMinutes,
            recurrenceRule: result.recurrenceRule,
            sortIndex: nextTaskSortIndex(), stage: TaskStage.suggestedInitial(forDueDate: result.dueDate),
            estimatedMinutes: result.estimatedMinutes,
            dependsOnTaskID: result.dependsOnTaskID
        )
        context.insert(item)
        context.saveOrReport()
        // Stays on whatever tab "+ New Task" was clicked from if it's visible there;
        // only jumps elsewhere if this tab genuinely can't show it.
        revealTask(item)
        scheduleNotificationsIfNeeded(for: item)
    }

    private func reorderTask(_ draggedID: UUID, _ targetID: UUID) {
        guard draggedID != targetID,
              let dragged = tasks.first(where: { $0.id == draggedID }),
              let target = tasks.first(where: { $0.id == targetID }) else { return }
        let oldIndex = dragged.sortIndex ?? 0
        dragged.sortIndex = target.sortIndex ?? oldIndex
        target.sortIndex = oldIndex
        context.saveOrReport()
    }

    private func reorderCategory(_ draggedID: UUID, _ targetID: UUID) {
        guard draggedID != targetID,
              let dragged = categories.first(where: { $0.id == draggedID }),
              let target = categories.first(where: { $0.id == targetID }) else { return }
        let oldIndex = dragged.sortIndex ?? 0
        dragged.sortIndex = target.sortIndex ?? oldIndex
        target.sortIndex = oldIndex
        context.saveOrReport()
    }

    private func moveToStage(_ id: UUID, to stage: TaskStage) {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        if stage == .done {
            if !task.isCompleted { SoundManager.shared.playTaskComplete() }
            task.isCompleted = true
            task.completedAt = task.completedAt ?? .now
            task.progressPercent = 100
            NotificationManager.shared.cancel(for: task)
        } else if task.isCompleted || task.resolvedStage == .done {
            task.isCompleted = false
            task.completedAt = nil
            if task.progressPercent == 100 { task.progressPercent = nil }
            scheduleNotificationsIfNeeded(for: task)
        }
        task.stage = stage
        // No more auto-bumping progress to 10% just for starting — "Started Xm ago"
        // on the card already says that honestly. Progress stays real: 0% until a
        // subtask gets checked off or you move the slider yourself.
        if stage == .inProgress, task.startedAt == nil {
            task.startedAt = .now
        }
        context.saveOrReport()
    }

    private func toggle(_ task: TaskItem) {
        if task.isCompleted {
            task.isCompleted = false
            task.completedAt = nil
            if task.progressPercent == 100 { task.progressPercent = nil }
            if task.resolvedStage == .done { task.stage = .general }
            scheduleNotificationsIfNeeded(for: task)
            context.saveOrReport()
        } else {
            guard !task.isBlocked(in: tasks) else {
                blockedCompletionTask = task
                return
            }
            completeTask(task)
        }
    }

    private func completeTask(_ task: TaskItem) {
        SoundManager.shared.playTaskComplete()
        HapticManager.shared.perform()
        task.isCompleted = true
        task.completedAt = .now
        task.stage = .done
        task.progressPercent = 100
        NotificationManager.shared.cancel(for: task)
        if let next = task.spawnNextOccurrence(in: context) {
            scheduleNotificationsIfNeeded(for: next)
        }
        context.saveOrReport()
    }

    // Bulk versions just loop the same single-task functions below — every task still
    // goes through the normal toggle/delete path (sounds, notifications, Trash), so
    // bulk-deleting 10 tasks is exactly as safe (and as recoverable from Trash) as
    // deleting them one at a time. Blocked tasks are skipped quietly rather than
    // alerting once per task in the loop.
    private func bulkComplete(_ ids: Set<UUID>) {
        for task in tasks where ids.contains(task.id) && !task.isCompleted && !task.isBlocked(in: tasks) {
            completeTask(task)
        }
    }

    private func bulkDelete(_ ids: Set<UUID>) {
        for task in tasks where ids.contains(task.id) {
            delete(task)
        }
    }

    // Soft-delete: the task moves to Trash immediately (and so disappears from every
    // list right away, since the main @Query excludes anything with deletedAt set),
    // but nothing is actually erased. The 5-second toast is just a fast path back —
    // Trash itself is the real undo, good for 30 days.
    private func delete(_ task: TaskItem) {
        NotificationManager.shared.cancel(for: task)
        task.deletedAt = .now
        context.saveOrReport()
        deletedTask = task
        showUndoNotification = true
        if selectedTask?.id == task.id { selectedTask = nil }
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: Self.undoWindowSeconds, repeats: false) { _ in
            self.deletedTask = nil
            self.showUndoNotification = false
        }
    }

    private func undoDelete() {
        undoTimer?.invalidate()
        undoTimer = nil
        if let task = deletedTask {
            task.deletedAt = nil
            context.saveOrReport()
            scheduleNotificationsIfNeeded(for: task)
        }
        deletedTask = nil
        showUndoNotification = false
    }

    private func restoreFromTrash(_ task: TaskItem) {
        task.deletedAt = nil
        context.saveOrReport()
        scheduleNotificationsIfNeeded(for: task)
    }

    private func permanentlyDelete(_ task: TaskItem) {
        context.delete(task)
        context.saveOrReport()
    }

    private func emptyTrash() {
        for task in trashedTasks { context.delete(task) }
        context.saveOrReport()
    }

    // Trash isn't meant to grow forever — anything older than 30 days is gone for
    // good, the same horizon most apps' trash/recently-deleted folders use.
    private func purgeOldTrash() {
        let cutoff = Date().addingTimeInterval(-Double(Self.trashRetentionDays) * 24 * 3600)
        var changed = false
        for task in trashedTasks where (task.deletedAt ?? .now) < cutoff {
            context.delete(task)
            changed = true
        }
        if changed { context.saveOrReport() }
    }

    private func beginEditing(_ task: TaskItem) { editingTask = task }

    private func edit(_ task: TaskItem, using result: TaskComposerResult) {
        NotificationManager.shared.cancel(for: task)
        registerRescheduleIfNeeded(task, newDate: result.dueDate)
        task.title = result.title
        task.notes = result.notes
        task.dueDate = result.dueDate
        task.category = ensureCategoryExists(named: result.categoryName, color: result.categoryColor)
        task.priority = result.priority
        task.reminderSchedule = result.reminderSchedule
        task.customReminderMinutes = result.customReminderMinutes
        task.estimatedMinutes = result.estimatedMinutes
        task.dependsOnTaskID = result.dependsOnTaskID
        task.recurrenceRule = result.recurrenceRule
        context.saveOrReport()
        scheduleNotificationsIfNeeded(for: task)
        editingTask = nil
    }

    private func schedule(_ task: TaskItem, at date: Date) {
        guard date > Date() else { return }
        NotificationManager.shared.cancel(for: task)
        registerRescheduleIfNeeded(task, newDate: date)
        task.dueDate = date
        task.stage = TaskStage.suggestedInitial(forDueDate: date)
        task.isCompleted = false
        task.completedAt = nil
        context.saveOrReport()
        scheduleNotificationsIfNeeded(for: task)
    }

    // Counts only forward pushes (a later date than before) — setting a date for the
    // first time, or pulling one earlier, isn't avoidance. Surfaces an alert the first
    // time a task crosses 3 pushes; the persistent badge on the card after that is
    // the ongoing reminder, not another popup every time.
    private func registerRescheduleIfNeeded(_ task: TaskItem, newDate: Date?) {
        guard let oldDate = task.dueDate, let newDate, newDate > oldDate else { return }
        task.rescheduleCount += 1
        if task.rescheduleCount == Self.repeatedRescheduleThreshold {
            repeatedlyPushedTask = task
        }
    }

    private func setSubtasks(_ task: TaskItem, subtasks: [Subtask]) {
        task.subtaskList = subtasks
        context.saveOrReport()
    }

    private func setProgress(_ task: TaskItem, percent: Int) {
        // The slider can't be dragged past 99% while blocked — same rule as the
        // checkbox, just without an alert interrupting a drag gesture.
        let blocked = task.isBlocked(in: tasks)
        let cappedPercent = (blocked && percent >= 100) ? 99 : percent
        task.progressPercent = min(100, max(0, cappedPercent))
        if cappedPercent > 0, task.resolvedStage == .general { task.stage = .inProgress }
        if cappedPercent > 0, task.startedAt == nil { task.startedAt = .now }
        if cappedPercent >= 100 {
            task.isCompleted = true
            task.completedAt = task.completedAt ?? .now
            task.stage = .done
            NotificationManager.shared.cancel(for: task)
            if let next = task.spawnNextOccurrence(in: context) {
                scheduleNotificationsIfNeeded(for: next)
            }
        }
        context.saveOrReport()
    }

    private func fileSomeday(_ task: TaskItem) {
        NotificationManager.shared.cancel(for: task)
        task.dueDate = nil
        task.reminderSchedule = .none
        task.customReminderMinutes = nil
        task.isCompleted = false
        task.completedAt = nil
        task.stage = .general
        context.saveOrReport()
        selectedTask = nil
    }

    private func clearCompleted() {
        for task in tasks where task.isCompleted {
            NotificationManager.shared.cancel(for: task)
            context.delete(task)
        }
        selectedTask = nil
        context.saveOrReport()
    }

    private func scheduleNotificationsIfNeeded(for task: TaskItem) {
        guard let due = task.dueDate, !task.isCompleted, due > Date() else { return }
        NotificationManager.shared.schedule(for: task)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.notificationAuthRecheckDelay) { refreshNotificationAuthorization() }
    }

    private func refreshNotificationAuthorization() {
        NotificationManager.shared.getAuthorizationStatus { notificationAuthorization = $0 }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}

// Searches every active and completed task at once — unlike each view's own search
// field, which only ever looks at what's already in front of you.
private struct GlobalSearchView: View {
    let tasks: [TaskItem]
    let categories: [CategoryItem]
    let onSelect: (TaskItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var results: [TaskItem] {
        guard !query.isEmpty else { return [] }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query)
        }
        .sorted { !$0.isCompleted && $1.isCompleted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search every task", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isFocused)
                    .onSubmit {
                        guard let first = results.first else { return }
                        onSelect(first)
                        dismiss()
                    }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .modifier(HoverButtonModifier())
                }
            }
            .padding(16)

            Divider().overlay(Theme.divider)

            if query.isEmpty {
                emptyState(icon: "magnifyingglass", text: "Search across every list, not just the one you're on.")
            } else if results.isEmpty {
                emptyState(icon: "questionmark.circle", text: "No matches for \"\(query)\".")
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { task in
                            Button {
                                onSelect(task)
                                dismiss()
                            } label: {
                                resultRow(task)
                            }
                            .buttonStyle(.plain)
                            .modifier(HoverButtonModifier())
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(width: 480, height: 360)
        .background(Theme.bg)
        .onAppear { isFocused = true }
    }

    private func resultRow(_ task: TaskItem) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Categories.color(for: task.category, in: categories))
                .frame(width: 7, height: 7)
            Text(task.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                .strikethrough(task.isCompleted, color: .secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(task.category)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.mutedText)
            if let due = task.dueDate {
                Text(relativeDate(due))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.mutedText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.mutedText)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
