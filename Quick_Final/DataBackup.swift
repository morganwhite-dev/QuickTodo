// DataBackup.swift
// JSON export/import for a full local backup. QuickTodo has no sync, so this is the
// only way to move data to a new Mac or recover from a lost install. Lives outside
// the main view hierarchy (same reason as SwiftDataBridge/NotificationManager in
// Support.swift) since Settings isn't wired to the SwiftData @Environment.

import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers

private struct TaskBackup: Codable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var category: String
    var priority: TaskPriority?
    var reminderSchedule: ReminderSchedule?
    var customReminderMinutes: [Int]?
    var recurrenceRule: RecurrenceRule?
    var sortIndex: Int?
    var subtasks: [Subtask]?
    var stage: TaskStage?
    var estimatedMinutes: Int?
    var dependsOnTaskID: UUID?
    var progressPercent: Int?
    var deletedAt: Date?
    var rescheduleCount: Int
    var startedAt: Date?

    init(_ task: TaskItem) {
        id = task.id; title = task.title; notes = task.notes; dueDate = task.dueDate
        isCompleted = task.isCompleted; createdAt = task.createdAt; completedAt = task.completedAt
        category = task.category; priority = task.priority; reminderSchedule = task.reminderSchedule
        customReminderMinutes = task.customReminderMinutes; recurrenceRule = task.recurrenceRule
        sortIndex = task.sortIndex; subtasks = task.subtasks; stage = task.stage
        estimatedMinutes = task.estimatedMinutes; dependsOnTaskID = task.dependsOnTaskID
        progressPercent = task.progressPercent; deletedAt = task.deletedAt
        rescheduleCount = task.rescheduleCount; startedAt = task.startedAt
    }

    // Preserves the original id, so dependsOnTaskID cross-references between
    // restored tasks stay valid instead of pointing at IDs that no longer exist.
    func makeTask() -> TaskItem {
        TaskItem(
            id: id, title: title, notes: notes, dueDate: dueDate, isCompleted: isCompleted,
            createdAt: createdAt, completedAt: completedAt, category: category, priority: priority,
            reminderSchedule: reminderSchedule, customReminderMinutes: customReminderMinutes,
            recurrenceRule: recurrenceRule, sortIndex: sortIndex, subtasks: subtasks,
            stage: stage ?? .general, estimatedMinutes: estimatedMinutes,
            dependsOnTaskID: dependsOnTaskID, progressPercent: progressPercent, deletedAt: deletedAt,
            rescheduleCount: rescheduleCount, startedAt: startedAt
        )
    }
}

private struct CategoryBackup: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var colorHex: String?
    var sortIndex: Int?

    init(_ category: CategoryItem) {
        id = category.id; name = category.name; createdAt = category.createdAt
        colorHex = category.colorHex; sortIndex = category.sortIndex
    }

    func makeCategory() -> CategoryItem {
        CategoryItem(id: id, name: name, createdAt: createdAt, colorHex: colorHex, sortIndex: sortIndex)
    }
}

private struct AppBackup: Codable {
    var version = 1
    var exportedAt = Date.now
    var tasks: [TaskBackup]
    var categories: [CategoryBackup]
}

enum BackupManager {
    private static var stagedImport: AppBackup?

    private static var context: ModelContext? { SwiftDataBridge.shared.modelContainer?.mainContext }

    static func exportBackup() {
        guard let context else { return }
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<CategoryItem>())) ?? []
        let backup = AppBackup(tasks: tasks.map(TaskBackup.init), categories: categories.map(CategoryBackup.init))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(backup) else { return }

        let dateLabel = Date.now.formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "QuickToDo Backup \(dateLabel).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    // Stages a chosen file and reports what's in it, so the caller can confirm with
    // the user before commitImport() does anything destructive.
    static func chooseImportFile(completion: @escaping ((tasks: Int, categories: Int)?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else {
                completion(nil)
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let backup = try? decoder.decode(AppBackup.self, from: data) else {
                completion(nil)
                return
            }
            stagedImport = backup
            completion((backup.tasks.count, backup.categories.count))
        }
    }

    // Replaces every task and list with what's in the staged backup. No undo —
    // only call this once the user has confirmed via the staged count above.
    static func commitImport() {
        guard let context, let backup = stagedImport else { return }
        NotificationCenter.default.post(name: .quickToDoDataReplaced, object: nil)
        for task in (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [] {
            NotificationManager.shared.cancel(for: task)
            context.delete(task)
        }
        for category in (try? context.fetch(FetchDescriptor<CategoryItem>())) ?? [] { context.delete(category) }
        for categoryBackup in backup.categories { context.insert(categoryBackup.makeCategory()) }
        for taskBackup in backup.tasks {
            let task = taskBackup.makeTask()
            context.insert(task)
            // The backup only restores data — it doesn't restore the actual system
            // notifications, which live outside SwiftData entirely. Without this, an
            // imported task could say it has a reminder and just never fire one.
            if task.dueDate != nil, !task.isCompleted {
                NotificationManager.shared.schedule(for: task)
            }
        }
        context.saveOrReport()
        stagedImport = nil
    }

    static func cancelImport() {
        stagedImport = nil
    }

    // True wipe, not a soft-delete — bypasses Trash entirely so the warning shown
    // before calling this ("nothing will be retrievable") stays honest. Re-seeds
    // "General" immediately after so the app is usable without restarting.
    static func eraseEverything() {
        guard let context else { return }
        NotificationCenter.default.post(name: .quickToDoDataReplaced, object: nil)
        for task in (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [] {
            // Without this, a reminder scheduled for a task wiped here would still
            // fire on schedule — for a task that, as far as you're concerned, never
            // existed.
            NotificationManager.shared.cancel(for: task)
            context.delete(task)
        }
        for category in (try? context.fetch(FetchDescriptor<CategoryItem>())) ?? [] { context.delete(category) }
        context.insert(CategoryItem(name: "General", sortIndex: 0))
        context.saveOrReport()
    }
}
