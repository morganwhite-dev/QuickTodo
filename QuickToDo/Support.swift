// Support.swift
// Notifications, sound effects, and haptics — ported as-is from the previous single-file app.

import Foundation
import SwiftUI
import UserNotifications
import SwiftData
import AVFoundation
import AppKit
import AppIntents

// MARK: - App Intents (Spotlight / Shortcuts)

// Both ride on SwiftDataBridge, the same cross-context bridge the menu bar/hotkey panel
// already use — so they work whether or not the main window is open. Deliberately no
// typed @Parameter input: routing free text through Spotlight/Siri straight into
// QuickDateParser would need its own resolution/disambiguation UI to do well, so this
// opens the existing quick-add panel instead of guessing at a half-typed phrase.
struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add a Task"
    static var description = IntentDescription("Opens QuickToDo's quick-add panel, ready to type a new task.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAddPanelController.shared.show()
        return .result()
    }
}

struct WhatsNextMoveIntent: AppIntent {
    static var title: LocalizedStringResource = "What's My Next Move"
    static var description = IntentDescription("Asks QuickToDo's Decision Engine which task to do next.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let context = SwiftDataBridge.shared.modelContainer?.mainContext else {
            return .result(dialog: "QuickToDo isn't ready yet — open the app and try again.")
        }
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let active = tasks.filter { !$0.isCompleted }
        // Ready is now a real, user-curated stage (manually placed or auto-suggested
        // at creation) — prefer it, and only fall back to ranking unstaged tasks if
        // nothing has been marked Ready yet.
        let candidate = active.first(where: { $0.resolvedStage == .ready })
            ?? NextMoveEngine.suggested(from: active.filter { $0.resolvedStage == .general }, in: active, limit: 1).first
        guard let suggestion = candidate,
              let recommendation = NextMoveEngine.recommend(for: suggestion, in: active) else {
            return .result(dialog: "Nothing urgent right now — your board is clear.")
        }
        return .result(dialog: "\(recommendation.headline): \(suggestion.title). \(recommendation.summary)")
    }
}

struct QuickTodoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickAddIntent(),
            phrases: [
                "Quick add a task in \(.applicationName)",
                "Add a task to \(.applicationName)"
            ],
            shortTitle: "Quick Add",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: WhatsNextMoveIntent(),
            phrases: [
                "What's my next move in \(.applicationName)",
                "Ask \(.applicationName) what to do next"
            ],
            shortTitle: "Next Move",
            systemImageName: "sparkles"
        )
    }
}

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()
    private override init() { super.init() }

    enum CategoryID { static let taskDue = "TASK_DUE_CATEGORY" }
    enum ActionID { static let markDone = "MARK_DONE"; static let snooze5 = "SNOOZE_5" }

    // Default "still not done" escalation, independent of whatever per-task
    // reminderSchedule/customReminderMinutes is set. Every task with a due date gets
    // nudged at each of these checkpoints inside the last 24 hours, stopping at the
    // 1-hour mark — closer than that is the main due-time notification's job, plus
    // whatever close-in reminders the task itself is configured with above.
    private static let dueSoonOffsets: [TimeInterval] = [-86400, -43200, -21600, -10800, -3600]

    private static func dueSoonBody(forOffsetSeconds offset: TimeInterval) -> String {
        let hours = Int(-offset / 3600)
        return hours == 1 ? "Due in 1 hour and still not marked complete." : "Due in \(hours) hours and still not marked complete."
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let mark = UNNotificationAction(identifier: ActionID.markDone, title: "Mark Done", options: [.authenticationRequired])
        let snooze = UNNotificationAction(identifier: ActionID.snooze5, title: "Snooze 5 min", options: [])
        let category = UNNotificationCategory(identifier: CategoryID.taskDue, actions: [mark, snooze], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    private struct TaskNotificationSnapshot: Sendable {
        let id: UUID
        let title: String
        let notes: String
        let dueDate: Date?
        let isCompleted: Bool
        let reminderSchedule: ReminderSchedule?
        let customReminderMinutes: [Int]?

        init(task: TaskItem) {
            self.id = task.id
            self.title = task.title
            self.notes = task.notes
            self.dueDate = task.dueDate
            self.isCompleted = task.isCompleted
            self.reminderSchedule = task.reminderSchedule
            self.customReminderMinutes = task.customReminderMinutes
        }
    }

    func requestAuthorization(completion: (@MainActor (Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { print("[Notif] auth error: \(error)") }
            print("[Notif] granted=\(granted)")
            Task { @MainActor in
                completion?(granted)
            }
        }
    }

    func getAuthorizationStatus(completion: @MainActor @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                completion(status)
            }
        }
    }

    func schedule(for task: TaskItem) {
        schedule(snapshot: TaskNotificationSnapshot(task: task))
    }

    private func schedule(snapshot task: TaskNotificationSnapshot) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.scheduleAuthorized(for: task)
            case .notDetermined:
                self.requestAuthorization { granted in
                    guard granted else { return }
                    self.scheduleAuthorized(for: task)
                }
            default:
                print("[Notif] not authorized; skipped scheduling for \(task.title)")
            }
        }
    }

    private func scheduleAuthorized(for task: TaskNotificationSnapshot) {
        guard let due = task.dueDate, !task.isCompleted else { return }
        let now = Date()
        guard due > now.addingTimeInterval(2) else { return }

        cancel(snapshot: task)

        let mainID = task.id.uuidString
        let mainContent = UNMutableNotificationContent()
        mainContent.title = task.title
        if !task.notes.isEmpty { mainContent.body = task.notes }
        mainContent.sound = .default
        mainContent.interruptionLevel = .timeSensitive
        mainContent.categoryIdentifier = CategoryID.taskDue
        mainContent.userInfo = ["taskID": task.id.uuidString]

        let mainTrig = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due),
            repeats: false
        )
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: mainID, content: mainContent, trigger: mainTrig)
        )

        // Determine offsets: custom takes precedence over preset schedule.
        let offsets: [TimeInterval]
        if let customMinutes = task.customReminderMinutes, !customMinutes.isEmpty {
            offsets = customMinutes.map { TimeInterval(-$0 * 60) }
        } else {
            offsets = (task.reminderSchedule ?? .none).offsets
        }

        let reminders = offsets.map { offset -> (offset: TimeInterval, body: String) in
            let minutes = Int(-offset / 60)
            switch minutes {
            case 5: return (offset: offset, body: "Due in 5 minutes.")
            case 10: return (offset: offset, body: "Due in 10 minutes.")
            case 30: return (offset: offset, body: "Due in 30 minutes.")
            default: return (offset: offset, body: "Due in \(minutes) minutes.")
            }
        }

        for reminder in reminders {
            let reminderDate = due.addingTimeInterval(reminder.offset)
            guard reminderDate > now.addingTimeInterval(2) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Upcoming: \(task.title)"
            content.body = reminder.body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = CategoryID.taskDue
            content.userInfo = ["taskID": task.id.uuidString]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
                repeats: false
            )
            let requestID = mainID + "-pre-\(Int(-reminder.offset))"
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
            ) { error in
                if let error {
                    print("[Notif] failed to schedule pre-reminder for \(task.title): \(error)")
                } else {
                    print("[Notif] scheduled pre-reminder for \(task.title) at \(reminderDate)")
                }
            }
        }

        for offset in Self.dueSoonOffsets {
            let reminderDate = due.addingTimeInterval(offset)
            guard reminderDate > now.addingTimeInterval(2) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Still not done: \(task.title)"
            content.body = Self.dueSoonBody(forOffsetSeconds: offset)
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = CategoryID.taskDue
            content.userInfo = ["taskID": task.id.uuidString]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
                repeats: false
            )
            let requestID = mainID + "-duesoon-\(Int(-offset))"
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
            )
        }
    }

    func cancel(for task: TaskItem) {
        cancel(snapshot: TaskNotificationSnapshot(task: task))
    }

    private func cancel(snapshot task: TaskNotificationSnapshot) {
        var ids = [task.id.uuidString]

        let reminderMinutes: [Int]
        if let customMinutes = task.customReminderMinutes, !customMinutes.isEmpty {
            reminderMinutes = customMinutes
        } else {
            let schedule = task.reminderSchedule ?? .none
            reminderMinutes = schedule.offsets.map { Int(-$0 / 60) }
        }

        for minutes in reminderMinutes {
            ids.append(task.id.uuidString + "-pre-\(minutes * 60)")
        }
        for offset in Self.dueSoonOffsets {
            ids.append(task.id.uuidString + "-duesoon-\(Int(-offset))")
        }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }


    // Actions
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let idStr = response.notification.request.content.userInfo["taskID"] as? String, let uuid = UUID(uuidString: idStr) else { return }
        switch response.actionIdentifier {
        case ActionID.markDone: await markTaskDone(uuid: uuid)
        case ActionID.snooze5:  await snoozeTask(uuid: uuid, minutes: 5)
        default: break
        }
    }

    private func markTaskDone(uuid: UUID) async {
        await MainActor.run {
            if let model = SwiftDataBridge.shared.modelContainer?.mainContext,
               let task = try? model.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == uuid })).first {
                task.isCompleted = true
                task.completedAt = .now
                task.stage = .done
                self.cancel(for: task)
                if let next = task.spawnNextOccurrence(in: model) {
                    self.schedule(for: next)
                }
                model.saveOrReport()
            }
        }
    }

    private func snoozeTask(uuid: UUID, minutes: Int) async {
        await MainActor.run {
            if let model = SwiftDataBridge.shared.modelContainer?.mainContext,
               let task = try? model.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == uuid })).first {
                task.dueDate = Date().addingTimeInterval(Double(minutes) * 60)
                self.schedule(for: task)
                model.saveOrReport()
            }
        }
    }
}

final class SwiftDataBridge: @unchecked Sendable {
    static let shared = SwiftDataBridge()

    var modelContainer: ModelContainer?
    var isUsingTemporaryStore: Bool = false
}

// The menu bar extra and the global-hotkey panel are separate Scenes with their own
// ModelContext — they can't reach into RootShellView's @State directly. Posting here
// lets the main window (if open) select and scroll to a task created from either one.
extension Notification.Name {
    static let quickToDoTaskCreated = Notification.Name("QuickToDoTaskCreated")
    static let quickToDoSaveFailed = Notification.Name("QuickToDoSaveFailed")
    // Posted right before every TaskItem in the store gets deleted (erase, or backup
    // restore). RootShellView holds direct TaskItem references in @State (selectedTask,
    // editingTask, etc.) — without this, touching one of those after its backing row
    // is gone crashes (SwiftData can't resolve a property on a deleted model).
    static let quickToDoDataReplaced = Notification.Name("QuickToDoDataReplaced")
}

extension ModelContext {
    // Every call site used to be a bare `try? context.save()` — if the store rejected
    // the write (disk full, corruption), the UI still showed the edit as if it had
    // persisted. This posts on failure so whichever window is frontmost (main window
    // or the menu bar bridge) can tell the user instead of silently losing the change.
    @discardableResult
    func saveOrReport() -> Bool {
        do {
            try save()
            return true
        } catch {
            print("[SwiftData] Save failed: \(error)")
            NotificationCenter.default.post(name: .quickToDoSaveFailed, object: error)
            return false
        }
    }
}

final class SoundManager: @unchecked Sendable {
    static let shared = SoundManager()

    private var taskPlayer: AVAudioPlayer?
    private var allCompletePlayer: AVAudioPlayer?
    private var activeSystemSounds: [NSSound] = []

    // Small sound for completing one task.
    func playTaskComplete() {
        guard !UserDefaults.standard.bool(forKey: "muteSounds") else { return }
        playBundledSound(
            named: "task-complete",
            fallbackNames: ["Pop", "Tink", "Ping"],
            volume: 0.76,
            player: &taskPlayer
        )
    }

    // Bigger sound for clearing a view/category.
    func playAllComplete() {
        guard !UserDefaults.standard.bool(forKey: "muteSounds") else { return }
        playBundledSound(
            named: "all-complete",
            fallbackNames: ["Glass", "Hero", "Funk", "Ping"],
            volume: 0.90,
            player: &allCompletePlayer
        )
    }

    // Keep the old name so older calls do not break.
    func playWhoosh() {
        playAllComplete()
    }

    private func playBundledSound(
        named resourceName: String,
        fallbackNames: [String],
        volume: Float,
        player: inout AVAudioPlayer?
    ) {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "wav") {
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.volume = volume
                player?.prepareToPlay()
                player?.play()
                return
            } catch {
                // Fall through to macOS system sounds.
            }
        }

        playFallbackSound(named: fallbackNames, volume: volume)
    }

    private func playFallbackSound(named fallbackNames: [String], volume: Float) {
        for fallbackName in fallbackNames {
            if let sound = NSSound(named: NSSound.Name(fallbackName)) {
                sound.stop()
                sound.currentTime = 0
                sound.volume = volume

                activeSystemSounds.append(sound)
                sound.play()

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self, weak sound] in
                    guard let sound else { return }
                    self?.activeSystemSounds.removeAll { $0 === sound }
                }

                return
            }
        }

        NSSound.beep()
    }
}

// Simple haptic helper (macOS trackpad haptics)
final class HapticManager: @unchecked Sendable {
    static let shared = HapticManager()
    func perform() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}

