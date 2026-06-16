// QuickTodo – a polished macOS SwiftUI to-do app with on-device storage (SwiftData)
// and reliable local notifications using UserNotifications.
//
// ✅ Privacy-first: no networking, all data stays local.
// ✅ Quick-entry parser: "Pay rent tomorrow 9am #Personal" → task + due date + category.
// ✅ Works on macOS 14+ (Sonoma) with Xcode 15+. Uses SwiftData (@Model).
// ✅ Desktop notifications with snooze & mark-done actions.
// ✅ Modern dark UI, grid cards, toolbar, categories, menu bar quick-add.
//
// ─────────────────────────────────────────────────────────────────────────────
// HOW TO RUN
// 1) In Xcode: File → New → Project → App (macOS) → Product Name: QuickTodo →
//    Interface: SwiftUI, Language: Swift. Minimum: macOS 14.0 (or newer).
// 2) Replace the default App & ContentView with this single file.
// 3) Build & Run. Allow notifications on first launch.
//
// ─────────────────────────────────────────────────────────────────────────────
// MARK: Imports

@preconcurrency import SwiftUI
@preconcurrency import AppKit
@preconcurrency import SwiftData
@preconcurrency import UserNotifications
@preconcurrency import AVFoundation
@preconcurrency import UniformTypeIdentifiers
@preconcurrency import Carbon.HIToolbox
@preconcurrency import ServiceManagement

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Theme & Categories

enum Theme {
    static let accent = Color(red: 0.2, green: 0.7, blue: 0.95) // Modern vibrant blue
    static let accentDim = Color(red: 0.15, green: 0.6, blue: 0.85)
    static let bg = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.08, blue: 0.12),
            Color(red: 0.05, green: 0.06, blue: 0.10)
        ], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let cardFill = Color.white.opacity(0.05)
    static let cardBorder = Color.white.opacity(0.08)
    static let critical = Color(red: 0.98, green: 0.3, blue: 0.4) // Overdue / Focus First
    static let dueSoon = Color(red: 1.0, green: 0.6, blue: 0.2) // Coming Up

    // Pressure system colors — intentionally separate from the app's blue brand accent.
    static let onDeck = Color(red: 0.58, green: 0.54, blue: 0.88) // Future, scheduled, manageable
    static let keepInMind = Color(red: 0.72, green: 0.58, blue: 0.70) // Worth remembering, not urgent
    static let lowPressure = Color(red: 0.49, green: 0.72, blue: 0.56) // Calm, no deadline

    // Quiet neutral used everywhere Inbox appears, so the capture bucket stays visually calm.
    static let inbox = Color(red: 0.55, green: 0.57, blue: 0.62)
}

enum Categories {
    // Refined color palette for categories
    private static let colorPalette: [Color] = [
        Color(red: 0.2, green: 0.7, blue: 0.95),   // Vibrant blue
        Color(red: 0.6, green: 0.3, blue: 0.95),   // Vibrant purple
        Color(red: 0.95, green: 0.3, blue: 0.7),   // Vibrant pink
        Color(red: 1.0, green: 0.6, blue: 0.2),    // Vibrant amber
        Color(red: 0.2, green: 0.85, blue: 0.6),   // Vibrant teal
        Color(red: 0.3, green: 0.95, blue: 0.5),   // Vibrant green
        Color(red: 0.95, green: 0.4, blue: 0.3),   // Vibrant orange-red
        Color(red: 0.5, green: 0.7, blue: 0.95),   // Soft blue
    ]

    // Fallback stable color (used when a category has no saved custom color)
    static func fallbackColor(for name: String) -> Color {
        var hash: UInt = 5381
        for char in name.lowercased().utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt(char)
        }
        let index = Int(bitPattern: hash) % colorPalette.count
        return colorPalette[abs(index)]
    }

    // Resolve a color for a CategoryItem (custom if set, otherwise stable fallback)
    static func color(for category: CategoryItem) -> Color {
        // Inbox is always the quiet neutral, regardless of any stored color.
        if category.name.caseInsensitiveCompare("Inbox") == .orderedSame { return Theme.inbox }
        if let hex = category.colorHex, let c = Color(hex: hex) {
            return c
        }
        return fallbackColor(for: category.name)
    }

    // Resolve a color by name, given the categories list (custom if exists, otherwise fallback)
    static func color(for name: String, in categories: [CategoryItem]) -> Color {
        if name.caseInsensitiveCompare("Inbox") == .orderedSame { return Theme.inbox }
        if let cat = categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return color(for: cat)
        }
        return fallbackColor(for: name)
    }
}



// ─────────────────────────────────────────────────────────────────────────────
// MARK: Color <-> Hex Helpers (for user-picked subject colors)

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&value) else { return nil }

        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8) / 255.0
            b = Double(value & 0x0000FF) / 255.0
            a = 1.0
        } else {
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >> 8) / 255.0
            a = Double(value & 0x000000FF) / 255.0
        }

        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    func toHex(includeAlpha: Bool = false) -> String? {
        let ns = NSColor(self).usingColorSpace(.sRGB)
        guard let c = ns else { return nil }

        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        let a = Int(round(c.alphaComponent * 255))

        if includeAlpha {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        } else {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Model (SwiftData)

enum TaskPriority: String, CaseIterable, Codable, Sendable, Comparable {
    case high, medium, low

    var label: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var color: Color {
        switch self {
        case .high:
            return Theme.critical
        case .medium:
            return Theme.dueSoon
        case .low:
            return Theme.accent
        }
    }

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        let order: [TaskPriority] = [.high, .medium, .low]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

enum ReminderSchedule: String, CaseIterable, Codable, Sendable, Comparable {
    case none, fiveMinutes, tenAndFive, thirtyTenFive

    var label: String {
        switch self {
        case .none: return "None"
        case .fiveMinutes: return "5 min before"
        case .tenAndFive: return "10 & 5 min"
        case .thirtyTenFive: return "30, 10 & 5 min"
        }
    }

    var offsets: [TimeInterval] {
        switch self {
        case .none: return []
        case .fiveMinutes: return [-300]
        case .tenAndFive: return [-600, -300]
        case .thirtyTenFive: return [-1800, -600, -300]
        }
    }

    static func < (lhs: ReminderSchedule, rhs: ReminderSchedule) -> Bool {
        let order: [ReminderSchedule] = [.none, .fiveMinutes, .tenAndFive, .thirtyTenFive]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// Lightweight checklist item stored inline on a task. Codable value type so SwiftData
// can persist it as an attribute without a separate model/relationship.
struct Subtask: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

@Model final class TaskItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var category: String // NEW
    var priority: TaskPriority?
    var reminderSchedule: ReminderSchedule?
    var customReminderMinutes: [Int]?
    var sortIndex: Int?
    // Optional checklist of subtasks. Optional so existing stores migrate cleanly (nil == none).
    var subtasks: [Subtask]?

    init(id: UUID = UUID(), title: String, notes: String = "", dueDate: Date? = nil, isCompleted: Bool = false, createdAt: Date = .now, completedAt: Date? = nil, category: String = "Inbox", priority: TaskPriority? = .low, reminderSchedule: ReminderSchedule? = nil, customReminderMinutes: [Int]? = nil, sortIndex: Int? = nil, subtasks: [Subtask]? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.category = category
        self.priority = priority
        self.reminderSchedule = reminderSchedule
        self.customReminderMinutes = customReminderMinutes
        self.sortIndex = sortIndex
        self.subtasks = subtasks
    }
}

@Model final class CategoryItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    // Optional user-picked color. If nil, we fall back to a stable generated color.
    var colorHex: String?
    var sortIndex: Int?

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, colorHex: String? = nil, sortIndex: Int? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}


// Convenience query helpers
extension TaskItem {
    static func upcomingPredicate(includeDone: Bool = false) -> Predicate<TaskItem> {
        if includeDone { return #Predicate<TaskItem> { _ in true } }
        return #Predicate<TaskItem> { !$0.isCompleted }
    }
}

// Subtask convenience accessors. Storage stays optional (nil == empty) but callers
// work with a plain array.
extension TaskItem {
    var subtaskList: [Subtask] {
        get { subtasks ?? [] }
        set { subtasks = newValue.isEmpty ? nil : newValue }
    }

    var subtaskProgress: (done: Int, total: Int) {
        let list = subtasks ?? []
        return (list.filter { $0.isDone }.count, list.count)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Notifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()
    private override init() { super.init() }

    enum CategoryID { static let taskDue = "TASK_DUE_CATEGORY" }
    enum ActionID { static let markDone = "MARK_DONE"; static let snooze5 = "SNOOZE_5" }

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
                self.cancel(for: task)
                try? model.save()
            }
        }
    }

    private func snoozeTask(uuid: UUID, minutes: Int) async {
        await MainActor.run {
            if let model = SwiftDataBridge.shared.modelContainer?.mainContext,
               let task = try? model.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == uuid })).first {
                task.dueDate = Date().addingTimeInterval(Double(minutes) * 60)
                self.schedule(for: task)
                try? model.save()
            }
        }
    }
}

final class SwiftDataBridge: @unchecked Sendable {
    static let shared = SwiftDataBridge()

    var modelContainer: ModelContainer?
    var isUsingTemporaryStore: Bool = false
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: Date Parsing (quick entry with #category)
//
// Drop-in replacement for your existing `QuickDateParser` enum.
// Fix: an explicit month/day ("july 4th") no longer short-circuits before the
// time is parsed. Date phrase, time, and #category are now ALL stripped out of
// the title in every code path, so the title comes out clean.
//
// Examples:
//   "submit rationale quiz july 4th at 10am" -> title "submit rationale quiz", Jul 4 10:00 AM
//   "submit report june 15th at 10pm"        -> title "submit report",        Jun 15 10:00 PM
//   "Pay rent tomorrow 9am #Personal"        -> title "Pay rent",  tomorrow 9:00 AM, cat Personal
//   "call mom friday 5pm"                     -> title "call mom",  next Friday 5:00 PM
//   "review notes december 7th"              -> title "review notes", Dec 7 12:00 PM (noon default)

enum QuickDateParser {
    struct Result { let title: String; let date: Date?; let category: String?; let priority: TaskPriority? }

    static func parse(_ raw: String, now: Date = .now) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(title: "", date: nil, category: nil, priority: nil)
        }

        var working = trimmed
        let cal = Calendar.current

        // 1) Priority/category can appear at the end in either order:
        //    "Essay tomorrow #English !high" OR "Essay tomorrow !high #English".
        let firstPriority = extractPriority(&working)
        let category = extractCategory(&working)
        let priority = firstPriority ?? extractPriority(&working)

        // 3) Date phrase — explicit month/day first, then today / tomorrow / weekday.
        //    Each helper strips the matched phrase out of `working`.
        var baseDate = extractMonthDay(&working, now: now)
        if baseDate == nil { baseDate = extractRelativeDate(&working, now: now) }

        // 3.5) Time offset — "in 10 minutes", "in 2 hours", etc.
        let timeOffset = extractTimeOffset(&working)

        // 3) Time — strips the time phrase (and a leading "at"/"@") out of `working`,
        //    then applies the hour/minute onto whatever date we found.
        var finalDate = baseDate
        if let time = extractTime(&working) {
            let base = baseDate ?? now
            finalDate = cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base)
            // Time given but no explicit date, and it's already past today → roll to tomorrow.
            if baseDate == nil, let d = finalDate, d < now {
                finalDate = cal.date(byAdding: .day, value: 1, to: d)
            }
        }

        // Apply time offset if specified
        if let offset = timeOffset {
            let base = finalDate ?? now
            finalDate = cal.date(byAdding: offset.unit, value: offset.value, to: base)
        }

        let title = cleanup(working)
        return Result(
            title: title.isEmpty ? trimmed : title,
            date: finalDate,
            category: category,
            priority: priority
        )
    }

    private static func extractPriority(_ working: inout String) -> TaskPriority? {
        let patterns: [String: TaskPriority] = [
            #"(?i)\s!high\s*$"#: .high,
            #"(?i)\s!medium\s*$"#: .medium,
            #"(?i)\s!low\s*$"#: .low,
            #"\s!!\s*$"#: .high,
            #"\s!\s*$"#: .low,

            #"(?i)\s(?:high\s+priority|priority\s+high)\s*$"#: .high,
            #"(?i)\s(?:medium\s+priority|priority\s+medium)\s*$"#: .medium,
            #"(?i)\s(?:low\s+priority|priority\s+low)\s*$"#: .low,
            #"(?i)\s(?:urgent|important|asap)\s*$"#: .high
        ]

        let ns = working as NSString
        let full = NSRange(location: 0, length: ns.length)

        for (pattern, priority) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            if let match = regex.firstMatch(in: working, range: full) {
                working = ns.replacingCharacters(in: match.range, with: "")
                return priority
            }
        }

        return nil
    }

    // MARK: - #category

    private static func extractCategory(_ working: inout String) -> String? {
        let tagPatterns: [String] = [
            #"(?i)\s#\[(.+?)\]\s*$"#,      // #[Senior Seminar]
            #"(?i)\s#\"(.+?)\"\s*$"#,    // #"Senior Seminar"
            #"(?i)\s#([a-z0-9_-]+(?:\s+[a-z0-9_-]+)*)\s*$"#  // #Senior Seminar
        ]
        for p in tagPatterns {
            guard let r = try? NSRegularExpression(pattern: p) else { continue }
            let ns = working as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let m = r.firstMatch(in: working, range: full), m.numberOfRanges >= 2 {
                let tag = ns.substring(with: m.range(at: 1))
                working = ns.replacingCharacters(in: m.range, with: "")
                return tag.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    // MARK: - Explicit month/day ("july 4th", "march 3 2027", typo "decemeber")

    private static func extractMonthDay(_ working: inout String, now: Date) -> Date? {
        let pattern = #"(?i)\b(january|february|march|april|may|june|july|august|september|october|november|december|decemeber)\s+(\d{1,2})(st|nd|rd|th)?(,?\s+(\d{4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = working as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: working, range: full) else { return nil }

        let monthName = ns.substring(with: match.range(at: 1)).lowercased()
        let dayString = ns.substring(with: match.range(at: 2))
        let yearString: String? = match.range(at: 5).location != NSNotFound
            ? ns.substring(with: match.range(at: 5)) : nil

        let months: [String: Int] = [
            "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
            "july": 7, "august": 8, "september": 9, "october": 10, "november": 11,
            "december": 12, "decemeber": 12 // typo support
        ]
        guard let month = months[monthName], let day = Int(dayString) else { return nil }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.month = month
        comps.day = day
        comps.hour = 12; comps.minute = 0; comps.second = 0   // default noon; overridden if a time is found
        if let yStr = yearString, let y = Int(yStr) { comps.year = y }

        var date = cal.date(from: comps)
        // No explicit year and the date already passed this year → assume next year.
        if yearString == nil, let d = date, d < now {
            comps.year = (comps.year ?? cal.component(.year, from: now)) + 1
            date = cal.date(from: comps)
        }
        guard let finalDate = date else { return nil }

        working = ns.replacingCharacters(in: match.range, with: " ")
        return finalDate
        
    }

    // MARK: - Relative dates (today / tomorrow / weekday)

    private static func extractRelativeDate(_ working: inout String, now: Date) -> Date? {
        let cal = Calendar.current

        func noon(_ date: Date) -> Date {
            cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        }
        @discardableResult
        func strip(_ pattern: String) -> Bool {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
            let ns = working as NSString
            let full = NSRange(location: 0, length: ns.length)
            guard let m = re.firstMatch(in: working, range: full) else { return false }
            working = ns.replacingCharacters(in: m.range, with: " ")
            return true
        }

        if strip(#"(?i)\btomorrow\b"#) {
            return noon(cal.date(byAdding: .day, value: 1, to: now) ?? now)
        }
        if strip(#"(?i)\btoday\b"#) {
            return noon(now)
        }

        // Full names FIRST so "monday" isn't half-eaten by the "mon" abbreviation.
        let weekdays: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7),
            ("sun", 1), ("mon", 2), ("tues", 3), ("tue", 3), ("wed", 4),
            ("thurs", 5), ("thu", 5), ("fri", 6), ("sat", 7)
        ]
        for (name, index) in weekdays {
            if strip(#"(?i)\b(?:on\s+|next\s+)?"# + name + #"\b"#) {
                guard let d = next(index, now: now) else { return nil }
                return noon(d)
            }
        }
        return nil
    }

    private static func next(_ weekday: Int, now: Date) -> Date? {
        let cal = Calendar.current
        let today = cal.component(.weekday, from: now) // 1=Sun ... 7=Sat
        var offset = weekday - today
        if offset <= 0 { offset += 7 }                 // always the NEXT occurrence
        return cal.date(byAdding: .day, value: offset, to: now)
    }

    // MARK: - Time ("10am", "10:30 pm", "at 9am", "@5pm", "14:30")

    private static func extractTime(_ working: inout String) -> (hour: Int, minute: Int)? {
        // Colon form first so "10:30" isn't half-matched by the bare-hour pattern.
        // A leading "at " or "@" is consumed so it doesn't linger in the title.
        let withMinutes = #"(?i)(?:\bat\s+|@\s*)?\b(\d{1,2}):(\d{2})\s*(am|pm)?\b"#
        let bareHour    = #"(?i)(?:\bat\s+|@\s*)?\b(\d{1,2})\s*(am|pm)\b"#

        let ns = working as NSString
        let full = NSRange(location: 0, length: ns.length)

        if let re = try? NSRegularExpression(pattern: withMinutes),
           let m = re.firstMatch(in: working, range: full), m.numberOfRanges >= 4 {
            let h = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let mn = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let ampm = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : nil
            working = ns.replacingCharacters(in: m.range, with: " ")
            return normalize(hour: h, minute: mn, ampm: ampm)
        }

        if let re = try? NSRegularExpression(pattern: bareHour),
           let m = re.firstMatch(in: working, range: full), m.numberOfRanges >= 3 {
            let h = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let ampm = ns.substring(with: m.range(at: 2))
            working = ns.replacingCharacters(in: m.range, with: " ")
            return normalize(hour: h, minute: 0, ampm: ampm)
        }
        return nil
    }

    private static func normalize(hour: Int, minute: Int, ampm: String?) -> (hour: Int, minute: Int) {
        var h = hour % 24
        let m = minute % 60
        if let ampm = ampm?.lowercased() {
            if ampm == "am" { if h == 12 { h = 0 } }
            else if ampm == "pm" { if h < 12 { h += 12 } }
        }
        return (h, m)
    }

    // MARK: - Time offset ("in 10 minutes", "in two hours", etc.)

    private static func extractTimeOffset(_ working: inout String) -> (unit: Calendar.Component, value: Int)? {
        let numberWords: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
            "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60
        ]
        let wordPattern = numberWords.keys.joined(separator: "|")
        let pattern = #"(?i)\bin\s+(?:(\d+)|("# + wordPattern + #"))\s+(second|minute|hour|day)s?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let ns = working as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: working, range: full), match.numberOfRanges >= 4 else {
            return nil
        }

        var value: Int?
        // Try digit form first
        if match.range(at: 1).location != NSNotFound {
            value = Int(ns.substring(with: match.range(at: 1)))
        }
        // Then try word form
        else if match.range(at: 2).location != NSNotFound {
            let word = ns.substring(with: match.range(at: 2)).lowercased()
            value = numberWords[word]
        }

        guard let finalValue = value else { return nil }
        let unit = ns.substring(with: match.range(at: 3)).lowercased()

        let component: Calendar.Component
        switch unit {
        case "second": component = .second
        case "minute": component = .minute
        case "hour": component = .hour
        case "day": component = .day
        default: return nil
        }

        working = ns.replacingCharacters(in: match.range, with: " ")
        return (component, finalValue)
    }

    // MARK: - Title cleanup

    private static func cleanup(_ s: String) -> String {
        var out = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove a dangling connector left at the end (e.g. "submit report at").
        out = out.replacingOccurrences(of: #"(?i)\s*(?:\bat\b|@)\s*$"#, with: "", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#if DEBUG
enum QuickDateParserSelfTest {
    private struct ExpectedDate {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
    }

    private struct Case {
        let input: String
        let expectedTitle: String
        let expectedCategory: String?
        let expectedPriority: TaskPriority?
        let expectedDate: ExpectedDate?
    }

    static func run() {
        let calendar = Calendar.current

        guard let fixedNow = calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 10,
            hour: 9,
            minute: 0,
            second: 0
        )) else {
            print("[ParserTest] Could not create fixed test date.")
            return
        }

        let cases: [Case] = [
            Case(
                input: "essay friday 11:59pm #English !high",
                expectedTitle: "essay",
                expectedCategory: "English",
                expectedPriority: .high,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 12, hour: 23, minute: 59)
            ),
            Case(
                input: "pay rent tomorrow 9am #Bills !medium",
                expectedTitle: "pay rent",
                expectedCategory: "Bills",
                expectedPriority: .medium,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 11, hour: 9, minute: 0)
            ),
            Case(
                input: "gym #Fitness !low",
                expectedTitle: "gym",
                expectedCategory: "Fitness",
                expectedPriority: .low,
                expectedDate: nil
            ),
            Case(
                input: "call mom in 10 minutes",
                expectedTitle: "call mom",
                expectedCategory: nil,
                expectedPriority: nil,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 10, hour: 9, minute: 10)
            ),
            Case(
                input: "submit report june 15th at 10pm #Work",
                expectedTitle: "submit report",
                expectedCategory: "Work",
                expectedPriority: nil,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 15, hour: 22, minute: 0)
            ),
            Case(
                input: "project next monday #Schoolwork",
                expectedTitle: "project",
                expectedCategory: "Schoolwork",
                expectedPriority: nil,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
            ),
            Case(
                input: #"quiz tomorrow 5pm #"Senior Seminar" !high"#,
                expectedTitle: "quiz",
                expectedCategory: "Senior Seminar",
                expectedPriority: .high,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 11, hour: 17, minute: 0)
            )
        ]

        print("──────── QuickDateParser Self-Test ────────")

        var passed = 0

        for testCase in cases {
            let result = QuickDateParser.parse(testCase.input, now: fixedNow)

            let titleOK = result.title == testCase.expectedTitle
            let categoryOK = result.category == testCase.expectedCategory
            let priorityOK = result.priority == testCase.expectedPriority
            let dateOK = matches(result.date, expected: testCase.expectedDate, calendar: calendar)

            if titleOK && categoryOK && priorityOK && dateOK {
                passed += 1
                print("✅ [ParserTest] \(testCase.input)")
            } else {
                print("❌ [ParserTest] \(testCase.input)")
                print("   title:    expected '\(testCase.expectedTitle)', got '\(result.title)'")
                print("   category: expected '\(testCase.expectedCategory ?? "nil")', got '\(result.category ?? "nil")'")
                print("   priority: expected '\(testCase.expectedPriority?.rawValue ?? "nil")', got '\(result.priority?.rawValue ?? "nil")'")
                print("   date:     expected '\(dateDescription(testCase.expectedDate))', got '\(dateDescription(result.date, calendar: calendar))'")
            }
        }

        print("[ParserTest] \(passed)/\(cases.count) passed")
        print("──────────────────────────────────────────")
    }

    private static func matches(_ date: Date?, expected: ExpectedDate?, calendar: Calendar) -> Bool {
        if date == nil && expected == nil {
            return true
        }

        guard let date, let expected else {
            return false
        }

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        return components.year == expected.year &&
            components.month == expected.month &&
            components.day == expected.day &&
            components.hour == expected.hour &&
            components.minute == expected.minute
    }

    private static func dateDescription(_ expected: ExpectedDate?) -> String {
        guard let expected else { return "nil" }
        return "\(expected.year)-\(expected.month)-\(expected.day) \(expected.hour):\(String(format: "%02d", expected.minute))"
    }

    private static func dateDescription(_ date: Date?, calendar: Calendar) -> String {
        guard let date else { return "nil" }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0) \(components.hour ?? 0):\(String(format: "%02d", components.minute ?? 0))"
    }
}
#endif


// ─────────────────────────────────────────────────────────────────────────────
// MARK: App

@main
struct QuickTodoApp: App {
    var container: ModelContainer = QuickTodoApp.makeModelContainer()

    init() {
        NotificationManager.shared.configure()

        // System-wide capture: ⌃⌥⌘ Space pops up the floating Quick Add panel from anywhere.
        GlobalHotKeyManager.shared.register {
            Task { @MainActor in QuickAddPanelController.shared.toggle() }
        }

        #if DEBUG
        QuickDateParserSelfTest.run()
        #endif
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([TaskItem.self, CategoryItem.self])
        let persistentConfig = ModelConfiguration(isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: persistentConfig)
            SwiftDataBridge.shared.modelContainer = container
            SwiftDataBridge.shared.isUsingTemporaryStore = false
            return container
        } catch {
            print("[SwiftData] Persistent store failed: \(error)")
            print("[SwiftData] Falling back to in-memory storage for this launch.")

            do {
                let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(for: schema, configurations: fallbackConfig)
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
            RootView()
                .modelContainer(container)
        }
        .windowStyle(.titleBar)
        .commands { AppCommands() }

        // Menu bar quick-add
        MenuBarExtra("QuickTodo", systemImage: "checkmark.circle") {
            MenuBarView().modelContainer(container)
        }
        .menuBarExtraStyle(.window)

        // Standard macOS Settings window (⌘,)
        Settings {
            SettingsView()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Helper Functions

func relativeDate(_ date: Date) -> String {
    let now = Date()
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: date)
    let minute = calendar.component(.minute, from: date)
    let hasTime = hour != 0 || minute != 0
    let timeStr = hasTime ? date.formatted(date: .omitted, time: .shortened) : ""

    if calendar.isDateInToday(date) {
        return hasTime ? "Today at \(timeStr)" : "Today"
    }
    if calendar.isDateInTomorrow(date) {
        return hasTime ? "Tomorrow at \(timeStr)" : "Tomorrow"
    }
    if calendar.isDateInYesterday(date) {
        return hasTime ? "Yesterday at \(timeStr)" : "Yesterday"
    }

    let daysUntil = calendar.dateComponents([.day], from: now, to: date).day ?? 0
    if daysUntil > 0 && daysUntil <= 7 {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let dayStr = formatter.string(from: date)
        return hasTime ? "\(dayStr) at \(timeStr)" : dayStr
    }

    if daysUntil < 0 {
        return "Overdue by \(abs(daysUntil))d"
    }

    return date.formatted(date: .abbreviated, time: .shortened)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Help Registry

enum QuickTodoHelpContent {
    static let quickAddTips = [
        "Write naturally: essay friday 11:59pm",
        "Add #English to assign a task, or type #English alone to create the category.",
        "Use !high, !medium, or !low when priority matters.",
        "Press ⌃⌥⌘ Space anywhere to capture a task without opening the app.",
        "Open Detailed Task when you need notes, reminders, or exact settings."
    ]

    static let notificationDeniedTip = "Enable notifications in System Settings to receive reminders."

    static let sections: [HelpGuideSection] = [
        HelpGuideSection(
            title: "Create Tasks",
            icon: "plus.circle.fill",
            color: Theme.accent,
            items: [
                HelpGuideItem(title: "Quick Add", body: "Type a task in plain language, then press Return or Add. Example: essay friday 11:59pm #English !high."),
                HelpGuideItem(title: "Detailed Task", body: "Use Detailed Task when you need notes, a precise due date, custom reminders, or more control before saving."),
                HelpGuideItem(title: "Menu Bar", body: "Use the QuickTodo menu bar icon to capture a task without switching back to the main window."),
                HelpGuideItem(title: "Global Hotkey", body: "Press ⌃⌥⌘ Space from any app to pop up Quick Add. It uses the same plain-language parsing and files uncategorized tasks into Inbox.")
            ]
        ),
        HelpGuideSection(
            title: "Quick Add Language",
            icon: "text.badge.plus",
            color: Theme.accent,
            items: [
                HelpGuideItem(title: "Dates", body: "Use words like today, tomorrow, friday, june 15, 2pm, or in 10 minutes."),
                HelpGuideItem(title: "Categories", body: "Add #Work to put a task in Work. Type #Work by itself to create the category. Category matching is not case-sensitive."),
                HelpGuideItem(title: "Priority", body: "Add !high, !medium, or !low. The toolbar filters those priorities without needing a separate sidebar item.")
            ]
        ),
        HelpGuideSection(
            title: "Organize",
            icon: "sidebar.left",
            color: Theme.dueSoon,
            items: [
                HelpGuideItem(title: "Sidebar Views", body: "My Day shows today and tomorrow. Due Soon shows tasks due in the next 6 hours. Upcoming shows everything scheduled beyond today for planning. All shows every active task. Inbox collects quick-adds that have no category yet."),
                HelpGuideItem(title: "Smart Filters", body: "No Date lists tasks without a deadline. High This Week shows high-priority tasks due this week. Completed This Week shows what you finished, even when completed tasks are hidden."),
                HelpGuideItem(title: "Categories", body: "Use Manage Categories to create, rename, recolor, delete, and reorder categories."),
                HelpGuideItem(title: "Drag Reordering", body: "Drag categories in the sidebar or Manage Categories. Drag task cards to swap their order inside the current section.")
            ]
        ),
        HelpGuideSection(
            title: "Complete And Clean Up",
            icon: "checkmark.circle.fill",
            color: Theme.lowPressure,
            items: [
                HelpGuideItem(title: "Complete Tasks", body: "Click the circle on a task card to mark it complete. Click again to make it active."),
                HelpGuideItem(title: "Completed Toggle", body: "Use the Completed control to show or hide finished tasks."),
                HelpGuideItem(title: "Clear Completed", body: "Right-click Completed and choose Clear Completed. QuickTodo asks for confirmation before deleting finished tasks.")
            ]
        ),
        HelpGuideSection(
            title: "Editing And Safety",
            icon: "pencil.circle.fill",
            color: Theme.onDeck,
            items: [
                HelpGuideItem(title: "Edit Tasks", body: "Use the pencil button on a task card to edit details inline."),
                HelpGuideItem(title: "Subtasks", body: "Open a task with the pencil button to add checklist subtasks. Tick them off right on the card as you go."),
                HelpGuideItem(title: "Delete Tasks", body: "Use the task delete action only when you want the item removed. An Undo prompt appears briefly after deletion."),
                HelpGuideItem(title: "Reminders", body: "Tasks with due dates can schedule local reminders. If reminders do not appear, check macOS notification permission for QuickTodo."),
                HelpGuideItem(title: "Settings", body: "Open QuickTodo ▸ Settings (⌘,) to mute completion sounds, launch at login, see the global hotkey, check notification status, or replay the welcome screen.")
            ]
        )
    ]
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Views

struct ColorPickerView: View {
    @Binding var selectedColor: Color
    @Binding var isPresented: Bool
    let onSelect: (Color) -> Void

    @State private var hue: Double = 0.05
    @State private var saturation: Double = 0.85
    @State private var brightness: Double = 0.95
    @State private var cursorLocation: CGPoint = .zero
    @State private var isHoveringWheel: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geo in
                    ZStack {
                        Canvas { context, size in
                            let center = CGPoint(x: size.width / 2, y: size.height / 2)
                            let radius = min(size.width, size.height) / 2

                            for y in stride(from: 0, to: Int(size.height), by: 1) {
                                for x in stride(from: 0, to: Int(size.width), by: 1) {
                                    let dx = CGFloat(x) - center.x
                                    let dy = CGFloat(y) - center.y
                                    let distance = sqrt(dx * dx + dy * dy)

                                    if distance <= radius {
                                        let angle = atan2(dy, dx)
                                        let normalizedAngle = (angle + .pi) / (2 * .pi)
                                        let sat = distance / radius

                                        let pixelColor = Color(
                                            hue: normalizedAngle,
                                            saturation: sat,
                                            brightness: brightness
                                        )
                                        context.fill(
                                            Path(CGRect(x: x, y: y, width: 1, height: 1)),
                                            with: .color(pixelColor)
                                        )
                                    }
                                }
                            }
                        }

                        if isHoveringWheel {
                            Image(systemName: "eyedropper")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                                .offset(x: cursorLocation.x - geo.size.width / 2, y: cursorLocation.y - geo.size.height / 2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let radius = min(geo.size.width, geo.size.height) / 2

                            let dx = location.x - center.x
                            let dy = location.y - center.y
                            let distance = sqrt(dx * dx + dy * dy)

                            let isOnWheel = distance <= radius

                            if isOnWheel && !isHoveringWheel {
                                NSCursor.hide()
                            } else if !isOnWheel && isHoveringWheel {
                                NSCursor.unhide()
                            }

                            isHoveringWheel = isOnWheel
                            cursorLocation = location

                            if isOnWheel {
                                let angle = atan2(dy, dx)
                                hue = (angle + .pi) / (2 * .pi)
                                saturation = min(distance / radius, 1.0)
                            }
                        case .ended:
                            isHoveringWheel = false
                            NSCursor.unhide()
                            break
                        }
                    }
                }
                .frame(height: 240)

                VStack(spacing: 10) {
                    Text("Brightness")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Slider(value: $brightness, in: 0...1)
                        .tint(Theme.accent)
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Selected Color")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(Color(hue: hue, saturation: saturation, brightness: brightness).toHex() ?? "#FF6B35")
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .help("Close without changing the color")
                        .modifier(HoverButtonModifier())

                    Button("Select") {
                        onSelect(Color(hue: hue, saturation: saturation, brightness: brightness))
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .help("Use this color")
                    .modifier(HoverButtonModifier())
                }
            }
            .padding(16)
            .navigationTitle("Choose Color")
            .frame(minWidth: 380, minHeight: 420)
        }
    }
}

struct AddCategoryModal: View {
    @Binding var isPresented: Bool
    @Binding var newName: String
    let onAdd: (String, Color) -> Void

    @State private var selectedColor = Theme.accent
    @State private var categoryName = ""
    @State private var showColorPicker = false
    @State private var customColor = Theme.accent

    private let presetColors: [Color] = [Theme.accent, Theme.critical, Theme.dueSoon, Color.green, Color.blue, Color.purple]

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // Category Name Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Category Name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("e.g. Work, Personal, Finance", text: $categoryName)
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 32)
                        .font(.system(size: 14))
                        .help("Name the category that will appear in the sidebar")
                }

                // Color Selection Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Color")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(presetColors.indices, id: \.self) { index in
                            let color = presetColors[index]
                            Button(action: { selectedColor = color }) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 2.5 : 0)
                                    )
                                    .scaleEffect(selectedColor == color ? 1.08 : 1.0)
                                    .animation(.snappy(duration: 0.15), value: selectedColor)
                            }
                            .buttonStyle(.plain)
                            .help("Use this preset category color")
                            .modifier(HoverButtonModifier())
                        }

                        Button(action: { showColorPicker = true }) {
                            VStack(spacing: 2) {
                                Image(systemName: "eyedropper.full")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Custom")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .modifier(HoverButtonModifier())
                        .help("Pick custom color")

                        Spacer()
                    }
                }

                // Preview Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 10, height: 10)

                        Text(categoryName.isEmpty ? "Category Name" : categoryName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(categoryName.isEmpty ? .secondary : .primary)

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }

                Spacer()

                // Action Buttons
                VStack(spacing: 6) {
                    Button(action: {
                        guard !categoryName.isEmpty else { return }
                        onAdd(categoryName, selectedColor)
                        isPresented = false
                        categoryName = ""
                    }) {
                        Text("Create Category")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .help("Create this category and add it to the sidebar")
                    .modifier(HoverButtonModifier())
                    .disabled(categoryName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Cancel") { isPresented = false }
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .help("Close without creating a category")
                        .modifier(HoverButtonModifier())
                }
            }
            .padding(14)
            .navigationTitle("New Category")
            .frame(minWidth: 340, minHeight: 320)
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColor: $customColor, isPresented: $showColorPicker) { color in
                    selectedColor = color
                }
            }
        }
    }
}

struct ComposerFieldStyle: ViewModifier {
    let isFocused: Bool
    var minHeight: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isFocused ? Theme.accent.opacity(0.75) : Color.white.opacity(0.10),
                        lineWidth: isFocused ? 1.6 : 1
                    )
            )
    }
}

extension View {
    func composerFieldStyle(isFocused: Bool, minHeight: CGFloat = 36) -> some View {
        modifier(ComposerFieldStyle(isFocused: isFocused, minHeight: minHeight))
    }
}

struct NewTaskComposerView: View {
    @Binding var isPresented: Bool
    let categories: [CategoryItem]
    let defaultCategory: String
    let onCreate: (String, String, Date?, String, Color?, TaskPriority, ReminderSchedule, [Int]?) -> Void

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var categoryName: String
    @State private var categoryColor: Color
    @State private var priority: TaskPriority = .low
    @State private var reminderMode: ReminderMode = .preset
    @State private var reminderSchedule: ReminderSchedule = .none
    @State private var customReminderMinutes: [Int] = []
    @State private var showColorPicker = false
    @FocusState private var focusedComposerField: ComposerField?

    private enum ComposerField: Hashable {
        case title
        case notes
        case category
    }

    private enum ReminderMode: String, CaseIterable {
        case preset = "Preset"
        case custom = "Custom"
    }

    private let presetColors: [Color] = [Theme.accent, Theme.critical, Theme.dueSoon, Color.green, Color.purple, Color.pink]

    init(
        isPresented: Binding<Bool>,
        categories: [CategoryItem],
        defaultCategory: String,
        onCreate: @escaping (String, String, Date?, String, Color?, TaskPriority, ReminderSchedule, [Int]?) -> Void
    ) {
        _isPresented = isPresented
        self.categories = categories
        self.defaultCategory = defaultCategory
        self.onCreate = onCreate

        let systemFilters = RootView.systemViewNames.union(["Inbox"])
        let initialCategory = systemFilters.contains(defaultCategory) ? "" : defaultCategory
        _categoryName = State(initialValue: initialCategory)
        _categoryColor = State(initialValue: initialCategory.isEmpty ? Theme.accent : Categories.color(for: initialCategory, in: categories))
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCategory: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleCategories: [CategoryItem] {
        categories.filter { $0.name != "Inbox" }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("New Task")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Add details now so the task is ready when it lands.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("What do you need to do?", text: $title)
                            .focused($focusedComposerField, equals: .title)
                            .composerFieldStyle(isFocused: focusedComposerField == .title, minHeight: 38)
                            .help("Enter the task title")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                       
                        TextField("Optional details", text: $notes, axis: .vertical)
                            .lineLimit(2...3)
                            .focused($focusedComposerField, equals: .notes)
                            .composerFieldStyle(isFocused: focusedComposerField == .notes, minHeight: 58)
                            .help("Add optional notes or context for this task")
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Toggle("", isOn: $hasDueDate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .help(hasDueDate ? "Remove the due date section" : "Add a due date and optional reminders")

                        Text("Due date")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if hasDueDate {
                            DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .help("Choose the task's due date and time")
                        } else {
                            Text("None")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack(alignment: .center, spacing: 10) {
                        Text("Priority")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 86, alignment: .leading)

                        HStack(spacing: 4) {
                            ForEach(TaskPriority.allCases, id: \.self) { item in
                                Button {
                                    withAnimation(.snappy(duration: 0.16)) {
                                        priority = item
                                    }
                                } label: {
                                    Text(item.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(priority == item ? .white : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(priority == item ? item.color : Color.white.opacity(0.06))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Set priority to \(item.label)")
                            }
                        }
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.055))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Category or Class")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Circle()
                            .fill(categoryColor)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))

                        TextField("Class, work, bills, personal...", text: $categoryName)
                            .focused($focusedComposerField, equals: .category)
                            .composerFieldStyle(isFocused: focusedComposerField == .category, minHeight: 36)
                            .help("Type a new or existing category name")

                        Button(action: { showColorPicker = true }) {
                            Image(systemName: "eyedropper.full")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .modifier(HoverButtonModifier())
                        .help("Pick category color")
                    }

                    if !visibleCategories.isEmpty {
                        Picker("Choose existing", selection: $categoryName) {
                            Text("New category").tag("")
                            ForEach(visibleCategories) { category in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Categories.color(for: category))
                                        .frame(width: 8, height: 8)
                                    Text(category.name)
                                }
                                .tag(category.name)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help("Choose an existing category")
                        .onChange(of: categoryName) { _, newValue in
                            if let selected = visibleCategories.first(where: { $0.name == newValue }) {
                                categoryColor = Categories.color(for: selected)
                            }
                        }
                    }

                    HStack(spacing: 7) {
                        ForEach(presetColors.indices, id: \.self) { index in
                            let color = presetColors[index]
                            Button(action: { categoryColor = color }) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Color.white.opacity(categoryColor == color ? 0.9 : 0.16), lineWidth: categoryColor == color ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                            .help("Use this category color")
                            .modifier(HoverButtonModifier())
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("Reminders")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Picker("", selection: $reminderMode) {
                            ForEach(ReminderMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        .help("Choose preset reminders or custom reminder times")
                    }

                    if !hasDueDate {
                        Text("Choose a due date to enable reminders.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if reminderMode == .preset {
                        Picker("", selection: $reminderSchedule) {
                            ForEach(ReminderSchedule.allCases, id: \.self) { schedule in
                                Text(schedule.label).tag(schedule)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help("Choose when QuickTodo should remind you")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(customReminderMinutes.enumerated()), id: \.offset) { index, _ in
                                HStack(spacing: 8) {
                                    TextField("", value: Binding(
                                        get: { customReminderMinutes[index] },
                                        set: { customReminderMinutes[index] = max(1, $0) }
                                    ), format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 58)
                                        .help("Minutes before the due time")
                                    Text("minutes before")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(action: { customReminderMinutes.remove(at: index) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this custom reminder")
                                    .modifier(HoverButtonModifier())
                                }
                            }

                            if customReminderMinutes.count < 3 {
                                Button(action: { customReminderMinutes.append(15) }) {
                                    Label("Add reminder", systemImage: "plus.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                                .buttonStyle(.plain)
                                .help("Add another custom reminder time")
                                .modifier(HoverButtonModifier())
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .help("Close without creating this task")
                    .modifier(HoverButtonModifier())

                    Button("Create Task") {
                        let finalCustomMinutes = reminderMode == .custom && hasDueDate ? customReminderMinutes : nil
                        let finalSchedule: ReminderSchedule = hasDueDate && reminderMode == .preset ? reminderSchedule : .none
                        onCreate(trimmedTitle, notes, hasDueDate ? dueDate : nil, trimmedCategory, trimmedCategory.isEmpty ? nil : categoryColor, priority, finalSchedule, finalCustomMinutes)
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .help(trimmedTitle.isEmpty ? "Enter a title before creating the task" : "Create this detailed task")
                    .modifier(HoverButtonModifier())
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .padding(16)
            .frame(minWidth: 440, idealWidth: 460, minHeight: 560)
            .tint(Theme.accent)
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColor: $categoryColor, isPresented: $showColorPicker) { color in
                    categoryColor = color
                }
            }
        }
    }
}

struct HoverButtonModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .opacity(isHovered ? 1.0 : 0.8)
            .onHover { hovering in
                withAnimation(.snappy(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

struct PriorityFilterButton: View {
    let priority: TaskPriority?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var title: String {
        priority?.label ?? "All"
    }

    private var iconName: String {
        switch priority {
        case .high:
            return "flame.fill"
        case .medium:
            return "flag.fill"
        case .low:
            return "leaf.fill"
        case nil:
            return "line.3.horizontal.decrease.circle"
        }
    }

    private var tint: Color {
        priority?.color ?? Theme.accent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : tint.opacity(isHovered ? 1 : 0.82))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? tint.opacity(0.88) : Color.white.opacity(isHovered ? 0.10 : 0.045))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.95) : tint.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Show \(title.lowercased()) priority tasks")
        .accessibilityLabel("Priority filter: \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct SidebarBadge: View {
    let count: Int
    var isSelected = false

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .frame(minWidth: 25)
            .background(Color.white.opacity(isSelected ? 0.13 : 0.075), in: Capsule(style: .continuous))
    }
}

struct TaskDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    let onMove: (UUID, UUID) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID, draggedID != targetID else {
            self.draggedID = nil
            return false
        }

        withAnimation(.snappy(duration: 0.18)) {
            onMove(draggedID, targetID)
        }
        self.draggedID = nil
        return true
    }
}

struct SidebarCategoryItem: View {
    let name: String
    let color: Color
    let count: Int
    let isSelected: Bool
    let onEditColor: () -> Void
    let onManage: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isSelected ? Theme.accent : color)
                .frame(width: 5, height: 20)

            Text(name)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(.primary.opacity(isSelected ? 1 : 0.88))
                .lineLimit(1)

            Spacer(minLength: 8)

            if count > 0 {
                SidebarBadge(count: count, isSelected: isSelected)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                    ? Theme.accent.opacity(0.12)
                    : isHovered
                    ? Color.white.opacity(0.045)
                    : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Theme.accent.opacity(0.24) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                onEditColor()
            } label: {
                Label("Edit Color", systemImage: "eyedropper.full")
            }

            Button {
                onManage()
            } label: {
                Label("Manage Categories", systemImage: "slider.horizontal.3")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Category", systemImage: "trash")
            }
        }
        .help(count == 0 ? "\(name): 0 active tasks" : "\(name): \(count) active \(count == 1 ? "task" : "tasks")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(count == 0 ? "0 active tasks" : "\(count) active \(count == 1 ? "task" : "tasks")")
        .accessibilityHint("Selects this category. Right click for color and delete options.")
    }
}

struct SidebarFilterItem: View {
    let icon: String
    let iconColor: Color
    let label: String
    let count: Int
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(iconColor)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)
            SidebarBadge(count: count, isSelected: isSelected)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                    ? Theme.accent.opacity(0.12)
                    : isHovered
                    ? Color.white.opacity(0.045)
                    : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Theme.accent.opacity(0.24) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("\(label): \(count) \(count == 1 ? "task" : "tasks")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(count) \(count == 1 ? "task" : "tasks")")
        .accessibilityHint("Selects this task view.")
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context

    @State private var quickText: String = ""
    @State private var includeCompleted: Bool = false
    @State private var search: String = ""
    @State private var selectedCategory: String = "My Day"
    @State private var selectedPriorityFilter: TaskPriority? = nil
    @AppStorage("categoriesExpanded") private var categoriesExpanded = true
    @AppStorage("smartFiltersExpanded") private var smartFiltersExpanded = false
    @AppStorage("hasSeenWelcomeV1") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    @State private var showNewTaskComposer = false
    @State private var showAddCategoryModal = false
    @State private var showCategoryManager = false
    @State private var newCategoryName = ""
    @State private var showClearCompletedConfirmation = false
    @State private var showHelpBadge = false
    @State private var categoryColorEditorName: String?
    @State private var categoryColorDraft = Theme.accent
    @State private var deletedTask: TaskItem?
    @State private var showUndoNotification: Bool = false
    @State private var undoTimer: Timer?
    @State private var draggedCategoryName: String?
    @State private var draggedTaskID: UUID?

    @FocusState private var quickFieldFocused: Bool
    @State private var today = Date()
    let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .full
        return df
    }()

    @Query private var tasks: [TaskItem]
    @Query(sort: \CategoryItem.name, order: .forward) private var categories: [CategoryItem]

    // Built-in views that are not real categories. New tasks created while one of these
    // is selected fall back to Inbox instead of inventing a category with the view's name.
    static let systemViewNames: Set<String> = [
        "My Day", "All", "Due Soon", "Upcoming", "High Priority",
        "No Date", "High This Week", "Completed This Week"
    ]

    private func ensureDefaultCategories() {
        // Keep one safe default so category pickers never break.
        if categories.isEmpty {
            context.insert(CategoryItem(name: "Inbox", sortIndex: 0))
            try? context.save()
        }
    }

    private func ensureCategoryExists(named raw: String, color: Color? = nil) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Inbox" }

        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if let color, let hex = color.toHex() {
                existing.colorHex = hex
                try? context.save()
            }
            return existing.name
        } else {
            let nextIndex = ((categories.compactMap(\.sortIndex).max() ?? categories.count) + 1)
            context.insert(CategoryItem(name: name, colorHex: color?.toHex(), sortIndex: nextIndex))
            try? context.save()
            return name
        }
    }

    private func createCategoryFromQuickAdd(named name: String) {
        withAnimation(.snappy(duration: 0.22)) {
            selectedCategory = ensureCategoryExists(named: name)
            quickText = ""
            quickFieldFocused = false
        }
    }

    private func addFromCategoryModal(name: String, color: Color) {
        withAnimation(.snappy(duration: 0.22)) {
            selectedCategory = ensureCategoryExists(named: name, color: color)
            newCategoryName = ""
        }
    }

    private func beginEditingCategoryColor(_ name: String) {
        guard let category = categories.first(where: { $0.name == name }) else { return }
        categoryColorDraft = Categories.color(for: category)
        categoryColorEditorName = name
    }

    private func saveCategoryColor(_ color: Color) {
        guard let name = categoryColorEditorName,
              let category = categories.first(where: { $0.name == name }),
              let hex = color.toHex() else { return }
        category.colorHex = hex
        try? context.save()
        categoryColorEditorName = nil
    }

    private var sidebarCategoryItems: [CategoryItem] {
        // Hide Inbox from the sidebar to keep it clean. Still used internally as a safe fallback.
        categories
            .filter { $0.name != "Inbox" }
            .sorted(by: categorySortRule)
    }

    private var sidebarCategoryNames: [String] {
        sidebarCategoryItems.map(\.name)
    }

    private var pendingQuickCategoryName: String? {
        guard let name = standaloneCategoryName(from: quickText.trimmingCharacters(in: .whitespacesAndNewlines)),
              !categories.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        return name
    }

    private var activeTasks: [TaskItem] {
        tasks.filter { !$0.isCompleted }
    }

    private var countsByCategory: [String: Int] {
        var m: [String: Int] = [:]
        for task in activeTasks {
            let canonicalCategory = categories.first {
                $0.name.caseInsensitiveCompare(task.category) == .orderedSame
            }?.name ?? task.category
            m[canonicalCategory, default: 0] += 1
        }
        return m
    }

    private func categorySortRule(_ a: CategoryItem, _ b: CategoryItem) -> Bool {
        let left = a.sortIndex ?? Int.max
        let right = b.sortIndex ?? Int.max
        if left != right { return left < right }
        return a.createdAt < b.createdAt
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

        if changed {
            try? context.save()
        }
    }

    // Reschedules itself each midnight so date-based views stay accurate across day/week boundaries.
    private func scheduleMidnightRefresh() {
        guard let midnight = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        let delay = max(1, midnight.timeIntervalSinceNow)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            today = Date()
            scheduleMidnightRefresh()
        }
    }

    private func selectSidebarView(_ name: String) {
        withAnimation(.snappy(duration: 0.18)) {
            selectedCategory = name
        }
    }

    private func reorderCategory(_ draggedName: String, before targetName: String) {
        guard draggedName != targetName,
              let draggedCategory = sidebarCategoryItems.first(where: { $0.name == draggedName }),
              let targetCategory = sidebarCategoryItems.first(where: { $0.name == targetName }) else { return }

        withAnimation(.snappy(duration: 0.18)) {
            let draggedIndex = draggedCategory.sortIndex ?? 0
            draggedCategory.sortIndex = targetCategory.sortIndex ?? draggedIndex
            targetCategory.sortIndex = draggedIndex
            try? context.save()
        }
    }

    private func reorderTask(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID,
              let draggedTask = tasks.first(where: { $0.id == draggedID }),
              let targetTask = tasks.first(where: { $0.id == targetID }) else { return }

        withAnimation(.snappy(duration: 0.18)) {
            let draggedIndex = draggedTask.sortIndex ?? 0
            draggedTask.sortIndex = targetTask.sortIndex ?? draggedIndex
            targetTask.sortIndex = draggedIndex
            try? context.save()
        }
    }

    private var allTaskCount: Int {
        activeTasks.count
    }

    private var highPriorityCount: Int {
        activeTasks.filter { ($0.priority ?? .low) == .high }.count
    }

    private var myDayCount: Int {
        let calendar = Calendar.current
        return activeTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDateInToday(due) || calendar.isDateInTomorrow(due)
        }.count
    }

    private var helpItems: [String] {
        var items = QuickTodoHelpContent.quickAddTips

        if notificationAuthorization == .denied {
            items.append(QuickTodoHelpContent.notificationDeniedTip)
        }

        return items
    }

    private var dueSoonCount: Int {
        let now = Date()
        let soon = now.addingTimeInterval(60 * 60 * 6) // 6 hours
        return activeTasks.filter {
            guard let due = $0.dueDate else { return false }
            return due >= now && due <= soon
        }.count
    }

    // Planning view: everything with a future due date beyond today.
    private var upcomingCount: Int {
        let now = Date()
        let calendar = Calendar.current
        return activeTasks.filter {
            guard let due = $0.dueDate else { return false }
            return due > now && !calendar.isDateInToday(due)
        }.count
    }

    // Capture safety net: active tasks that were never sorted into a real category.
    private var inboxCount: Int {
        activeTasks.filter { $0.category.caseInsensitiveCompare("Inbox") == .orderedSame }.count
    }

    // The calendar week that contains "today" — shared by the smart filters.
    private var currentWeekInterval: DateInterval? {
        Calendar.current.dateInterval(of: .weekOfYear, for: today)
    }

    // Smart filter: active tasks with no due date at all.
    private var noDateCount: Int {
        activeTasks.filter { $0.dueDate == nil }.count
    }

    // Smart filter: high-priority tasks due within the current week.
    private var highThisWeekCount: Int {
        guard let week = currentWeekInterval else { return 0 }
        return activeTasks.filter {
            guard ($0.priority ?? .low) == .high, let due = $0.dueDate else { return false }
            return week.contains(due)
        }.count
    }

    // Smart filter: tasks completed within the current week.
    private var completedThisWeekCount: Int {
        guard let week = currentWeekInterval else { return 0 }
        return tasks.filter {
            guard $0.isCompleted, let done = $0.completedAt else { return false }
            return week.contains(done)
        }.count
    }

    private var completedCount: Int {
        tasks.filter { $0.isCompleted }.count
    }

    private var hasActiveDatedTasks: Bool {
        activeTasks.contains { $0.dueDate != nil }
    }

    private var shouldShowNotificationWarning: Bool {
        notificationAuthorization == .denied && hasActiveDatedTasks
    }
    
    // "Jun 14 – Jun 20" for the current week, used as a non-redundant subtitle on weekly filters.
    private var weekRangeText: String {
        guard let week = currentWeekInterval else { return "This week" }
        let end = Calendar.current.date(byAdding: .day, value: -1, to: week.end) ?? week.end
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: week.start)) – \(formatter.string(from: end))"
    }

    private var currentViewTitle: String {
        switch selectedCategory {
        case "My Day":
            return "My Day"
        case "All":
            return "All Tasks"
        case "Due Soon":
            return "Due Soon"
        case "Upcoming":
            return "Upcoming"
        case "High Priority":
            return "High Priority"
        case "Inbox":
            return "Inbox"
        case "No Date":
            return "No Date"
        case "High This Week":
            return "High This Week"
        case "Completed This Week":
            return "Completed This Week"
        default:
            return selectedCategory
        }
    }

    private var currentViewSubtitle: String {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search results"
        }

        switch selectedCategory {
        case "My Day":
            return dateFormatter.string(from: today)
        case "All":
            return "Everything you need to remember"
        case "Due Soon":
            return "Tasks due in the next 6 hours"
        case "Upcoming":
            return "Everything scheduled beyond today"
        case "High Priority":
            return "Important tasks only"
        case "Inbox":
            return "Unsorted tasks waiting to be organized"
        case "No Date":
            return "Tasks without a deadline"
        case "High This Week":
            return weekRangeText
        case "Completed This Week":
            return weekRangeText
        default:
            return "Category"
        }
    }

    private var currentViewColor: Color {
        switch selectedCategory {
        case "My Day":
            return Theme.accent
        case "All":
            return Categories.fallbackColor(for: "All")
        case "Due Soon":
            return Theme.dueSoon
        case "Upcoming":
            return Theme.onDeck
        case "High Priority":
            return Theme.critical
        case "Inbox":
            return Theme.inbox
        case "No Date":
            return Theme.inbox
        case "High This Week":
            return Theme.critical
        case "Completed This Week":
            return Theme.lowPressure
        default:
            return Categories.color(for: selectedCategory, in: categories)
        }
    }

    private var currentViewCount: Int {
        filtered(tasks).count
    }

    private var currentViewCountLabel: String {
        switch selectedCategory {
        case "My Day":
            return "My Day"
        case "All":
            return "All"
        case "Due Soon":
            return "Soon"
        case "Upcoming":
            return "Ahead"
        case "High Priority":
            return "Focus"
        case "Inbox":
            return "Inbox"
        case "No Date":
            return "Undated"
        case "High This Week":
            return "This wk"
        case "Completed This Week":
            return "Done"
        default:
            return "Tasks"
        }
    }

    private var taskAnimationToken: [UUID] {
        tasks.map { $0.id }
    }

    @ViewBuilder
    private var notificationWarningBanner: some View {
        if shouldShowNotificationWarning {
            HStack(spacing: 12) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.dueSoon)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Theme.dueSoon.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are off")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Due-date reminders will not appear until notifications are enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Button("Open Settings") {
                    openNotificationSettings()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open macOS notification settings for QuickTodo")

                Button("Check Again") {
                    refreshNotificationAuthorization()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help("Recheck whether notifications are enabled")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.dueSoon.opacity(0.22), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    @ViewBuilder
    private var storageWarningBanner: some View {
        if SwiftDataBridge.shared.isUsingTemporaryStore {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.critical)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Theme.critical.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Temporary storage mode")
                        .font(.system(size: 13, weight: .semibold))

                    Text("QuickTodo had trouble opening saved data. New changes may not be saved after quitting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.critical.opacity(0.22), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emptyStateTitle: String {
        if !trimmedSearch.isEmpty {
            return "No matches found"
        }

        if let selectedPriorityFilter {
            return "No \(selectedPriorityFilter.label.lowercased()) priority tasks here"
        }

        switch selectedCategory {
        case "My Day":
            return "Nothing pressing today"
        case "All":
            return "Start with one task"
        case "Due Soon":
            return "Nothing due soon"
        case "Upcoming":
            return "Nothing scheduled ahead"
        case "High Priority":
            return "Nothing needs Focus First"
        case "Inbox":
            return "Inbox is clear"
        case "No Date":
            return "Everything has a date"
        case "High This Week":
            return "No high-priority tasks this week"
        case "Completed This Week":
            return "Nothing completed yet this week"
        default:
            return "No active tasks in \(selectedCategory)"
        }
    }

    private var emptyStateSubtitle: String {
        if !trimmedSearch.isEmpty {
            return "Try a different search or check another category."
        }

        if let selectedPriorityFilter {
            return "Click All in Priority or add a task with !\(selectedPriorityFilter.rawValue)."
        }

        switch selectedCategory {
        case "My Day":
            return "Tasks due today or tomorrow will land here automatically."
        case "All":
            return "Use Quick Add above — try “essay friday 11:59pm #English !high”."
        case "Due Soon":
            return "Tasks due in the next 6 hours will show here."
        case "Upcoming":
            return "Tasks scheduled for a future day will appear here for planning."
        case "High Priority":
            return "Use !high when something should become Focus First."
        case "Inbox":
            return "Quick-added tasks without a category land here so nothing slips through."
        case "No Date":
            return "Tasks you add without a due date will collect here."
        case "High This Week":
            return "High-priority tasks due in the current week will appear here."
        case "Completed This Week":
            return "Tasks you finish this week will be listed here."
        default:
            return "Add a task to \(selectedCategory), or use Quick Add with #\(selectedCategory)."
        }
    }

    private var emptyStateIcon: String {
        if !trimmedSearch.isEmpty {
            return "magnifyingglass"
        }

        if selectedPriorityFilter != nil {
            return "line.3.horizontal.decrease.circle"
        }

        switch selectedCategory {
        case "My Day":
            return "sun.max.fill"
        case "All":
            return "sparkles"
        case "Due Soon":
            return "clock.fill"
        case "Upcoming":
            return "calendar"
        case "High Priority":
            return "flame.fill"
        case "Inbox":
            return "tray"
        case "No Date":
            return "calendar.badge.minus"
        case "High This Week":
            return "flame"
        case "Completed This Week":
            return "checkmark.seal.fill"
        default:
            return "folder.fill"
        }
    }

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(spacing: 0) {
                List {
                    Section {
                        TextField("Search", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .help("Search tasks by title, notes, or category")
                    }

                    Section {
                        SidebarFilterItem(icon: "circle.fill", iconColor: Theme.accent, label: "My Day", count: myDayCount, isSelected: selectedCategory == "My Day")
                            .onTapGesture { selectSidebarView("My Day") }

                        SidebarFilterItem(icon: "circle.fill", iconColor: Theme.dueSoon, label: "Due Soon", count: dueSoonCount, isSelected: selectedCategory == "Due Soon")
                            .onTapGesture { selectSidebarView("Due Soon") }

                        SidebarFilterItem(icon: "circle.fill", iconColor: Theme.onDeck, label: "Upcoming", count: upcomingCount, isSelected: selectedCategory == "Upcoming")
                            .onTapGesture { selectSidebarView("Upcoming") }

                        SidebarFilterItem(icon: "circle.fill", iconColor: Categories.fallbackColor(for: "All"), label: "All", count: allTaskCount, isSelected: selectedCategory == "All")
                            .onTapGesture { selectSidebarView("All") }

                        // Quiet capture safety net — uncategorized quick-adds collect here.
                        SidebarFilterItem(icon: "tray", iconColor: Theme.inbox, label: "Inbox", count: inboxCount, isSelected: selectedCategory == "Inbox")
                            .onTapGesture { selectSidebarView("Inbox") }
                    }

                    Section {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                smartFiltersExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 8)
                                    .rotationEffect(.degrees(smartFiltersExpanded ? 90 : 0))

                                Text("Smart Filters")
                                    .font(.system(size: 13.5, weight: .bold))

                                Spacer(minLength: 8)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(smartFiltersExpanded ? "Collapse smart filters" : "Expand smart filters")

                        if smartFiltersExpanded {
                            SidebarFilterItem(icon: "circle.fill", iconColor: Theme.inbox, label: "No Date", count: noDateCount, isSelected: selectedCategory == "No Date")
                                .onTapGesture { selectSidebarView("No Date") }

                            SidebarFilterItem(icon: "circle.fill", iconColor: Theme.critical, label: "High This Week", count: highThisWeekCount, isSelected: selectedCategory == "High This Week")
                                .onTapGesture { selectSidebarView("High This Week") }

                            SidebarFilterItem(icon: "circle.fill", iconColor: Theme.lowPressure, label: "Done This Week", count: completedThisWeekCount, isSelected: selectedCategory == "Completed This Week")
                                .onTapGesture { selectSidebarView("Completed This Week") }
                        }
                        
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                categoriesExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 8)
                                    .rotationEffect(.degrees(categoriesExpanded ? 90 : 0))

                                Text("Categories")
                                    .font(.system(size: 13.5, weight: .bold))

                                Spacer(minLength: 8)

                                SidebarBadge(count: sidebarCategoryNames.count)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 0)
                            .padding(.bottom, 2)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                        .help(categoriesExpanded ? "Collapse categories. Right-click to add or manage categories." : "Expand categories. Right-click to add or manage categories.")
                        .contextMenu {
                            Button {
                                showAddCategoryModal = true
                            } label: {
                                Label("New Category", systemImage: "tag.badge.plus")
                            }

                            Button {
                                showCategoryManager = true
                            } label: {
                                Label("Manage Categories", systemImage: "slider.horizontal.3")
                            }
                        }

                        if categoriesExpanded {
                            ForEach(sidebarCategoryItems) { category in
                                let name = category.name
                                SidebarCategoryItem(
                                    name: name,
                                    color: Categories.color(for: category),
                                    count: countsByCategory[name] ?? 0,
                                    isSelected: selectedCategory == name,
                                    onEditColor: { beginEditingCategoryColor(name) },
                                    onManage: { showCategoryManager = true },
                                    onDelete: { deleteCategory(name) }
                                )
                                .onTapGesture { selectSidebarView(name) }
                                .opacity(draggedCategoryName == name ? 0.55 : 1)
                                .animation(.snappy(duration: 0.18), value: draggedCategoryName)
                                .draggable(name) {
                                    SidebarCategoryItem(
                                        name: name,
                                        color: Categories.color(for: category),
                                        count: countsByCategory[name] ?? 0,
                                        isSelected: selectedCategory == name,
                                        onEditColor: {},
                                        onManage: {},
                                        onDelete: {}
                                    )
                                    .frame(width: 190)
                                }
                                .onDrag {
                                    draggedCategoryName = name
                                    return NSItemProvider(object: name as NSString)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let draggedName = items.first else { return false }
                                    reorderCategory(draggedName, before: name)
                                    draggedCategoryName = nil
                                    return true
                                }
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .contextMenu {
                    Button {
                        showAddCategoryModal = true
                    } label: {
                        Label("New Category", systemImage: "tag.badge.plus")
                    }

                    Button {
                        showCategoryManager = true
                    } label: {
                        Label("Manage Categories", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("QuickTodo")
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 16) {

                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(currentViewColor)
                        .frame(width: 6, height: 44)
                        .shadow(color: currentViewColor.opacity(0.35), radius: 8, x: 0, y: 0)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(currentViewTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(currentViewSubtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(spacing: currentViewCountLabel.isEmpty ? 0 : 1) {
                        Text("\(currentViewCount)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .center)

                        if !currentViewCountLabel.isEmpty {
                            Text(currentViewCountLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .frame(width: 72, height: 64)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)


                HStack(spacing: 8) {
                    PriorityFilterButton(priority: nil, isSelected: selectedPriorityFilter == nil) {
                        withAnimation(.snappy(duration: 0.18)) {
                            selectedPriorityFilter = nil
                        }
                    }

                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        PriorityFilterButton(priority: priority, isSelected: selectedPriorityFilter == priority) {
                            withAnimation(.snappy(duration: 0.18)) {
                                selectedPriorityFilter = priority
                            }
                        }
                    }

                    Spacer(minLength: 12)

                    Button {
                        includeCompleted.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: includeCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 12, weight: .semibold))

                            Text("Completed")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            if completedCount > 0 {
                                Text("\(completedCount)")
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 6)
                                    .background(Color.white.opacity(0.12), in: Capsule(style: .continuous))
                            }
                        }
                        .foregroundStyle(includeCompleted ? .white : .secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(includeCompleted ? 0.14 : 0.055), in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(includeCompleted ? 0.20 : 0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(completedCount == 0 && !includeCompleted)
                    .help(completedCount > 0 ? "Click to show or hide completed tasks. Right-click to clear completed tasks." : "No completed tasks yet")
                    .accessibilityLabel("Completed tasks")
                    .accessibilityHint("Shows or hides completed tasks. Right click for clear completed.")
                    .modifier(HoverButtonModifier())
                    .contextMenu {
                        Button {
                            includeCompleted.toggle()
                        } label: {
                            Label(includeCompleted ? "Hide Completed" : "Show Completed", systemImage: includeCompleted ? "eye.slash" : "eye")
                        }

                        if completedCount > 0 {
                            Divider()

                            Button(role: .destructive) {
                                showClearCompletedConfirmation = true
                            } label: {
                                Label("Clear Completed", systemImage: "trash")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 4)
                .padding(.horizontal, 12)

                // Quick Add command bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label("Quick Add", systemImage: "bolt.fill")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Button(action: { withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { showHelpBadge.toggle() } }) {
                            Label(showHelpBadge ? "Hide Tips" : "Tips", systemImage: showHelpBadge ? "info.circle.fill" : "info.circle")
                                .labelStyle(.iconOnly)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(showHelpBadge ? "Hide Tips" : "Show Tips")
                        .modifier(HoverButtonModifier())

                        Spacer()

                        Button(action: { showNewTaskComposer = true }) {
                            Label("Detailed Task", systemImage: "slider.horizontal.3")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.045), in: Capsule(style: .continuous))
                        .help("Open the full task editor")
                        .modifier(HoverButtonModifier())
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)

                        TextField("Add task, or create a category with #Work", text: $quickText)
                            .textFieldStyle(.plain)
                            .onSubmit(addFromQuickEntry)
                            .submitLabel(.done)
                            .focused($quickFieldFocused)
                            .font(.system(size: 15))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .help("Type #Category to create a category, or add it to a task like essay friday 11:59pm #English !high.")
                            .accessibilityLabel("Quick Add input")
                            .accessibilityHint("Type a hashtag by itself to create a category, or type a task with a date, category, and priority.")

                        Button(action: addFromQuickEntry) {
                            Label("Add", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(minWidth: 70)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(Theme.accent)
                        .help("Quick add this task")
                        .accessibilityLabel("Quick add task")
                        .accessibilityHint("Adds the task from the Quick Add field.")
                        .modifier(HoverButtonModifier())
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.055), lineWidth: 1)
                    }

                    if let pendingQuickCategoryName {
                        Button {
                            createCategoryFromQuickAdd(named: pendingQuickCategoryName)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "tag.badge.plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.accent)

                                Text("Create category \"\(pendingQuickCategoryName)\"")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "return")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(Theme.accent.opacity(0.20), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Create category \"\(pendingQuickCategoryName)\"")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "command")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.75))

                        Text("Try: #English, or essay friday 11:59pm #English !high")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.82))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Quick Add example: essay Friday eleven fifty nine PM, hashtag English, exclamation high.")
                    
                }
                .padding(9)
                .background(Color.white.opacity(0.026), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 0)

                if showHelpBadge {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text("Helpful Tips")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(helpItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("•")
                                        .font(.body.weight(.bold))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 12, alignment: .center)
                                    Text(item)
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(nil)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
                
                notificationWarningBanner
                storageWarningBanner

                // Task grid / empty state
                TaskListView(
                    tasks: filtered(tasks),
                    categoryColor: { name in Categories.color(for: name, in: categories) },
                    emptyTitle: emptyStateTitle,
                    emptySubtitle: emptyStateSubtitle,
                    emptyIcon: emptyStateIcon,
                    emptyAccent: currentViewColor,
                    draggedTaskID: $draggedTaskID,
                    onToggle: toggle,
                    onDelete: delete,
                    onEdit: edit,
                    onReorder: reorderTask
                )
                    .animation(.snappy(duration: 0.25), value: taskAnimationToken)
                    .animation(.spring(response: 0.34, dampingFraction: 0.88), value: showHelpBadge)

                if showUndoNotification, let task = deletedTask {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Task deleted")
                                .font(.subheadline.weight(.semibold))
                            Text(task.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(action: undoDelete) {
                            Text("Undo")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .controlSize(.small)
                        .help("Restore the deleted task")
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .bottom).combined(with: .opacity)))
                    .padding(.horizontal, 8)
                }
            }
            .onAppear {
                ensureDefaultCategories()
                assignMissingSortIndexesIfNeeded()

                if !hasSeenWelcome { showWelcome = true }

                // Keep "today" current so My Day and the weekly filters roll over automatically.
                scheduleMidnightRefresh()
            }
            .onChange(of: hasSeenWelcome) { _, seen in
                // Lets "Show Welcome Screen Again" in Settings re-open it live.
                if !seen { showWelcome = true }
            }
            .sheet(isPresented: $showWelcome) {
                WelcomeView {
                    hasSeenWelcome = true
                    showWelcome = false
                }
            }
            .onDisappear {
                undoTimer?.invalidate()
                undoTimer = nil
            }
            .alert("Delete Completed Tasks?", isPresented: $showClearCompletedConfirmation) {
                Button("Delete", role: .destructive) { clearCompleted() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all completed tasks permanently.")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(Theme.bg)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showNewTaskComposer) {
                NewTaskComposerView(
                    isPresented: $showNewTaskComposer,
                    categories: categories,
                    defaultCategory: selectedCategory,
                    onCreate: addFromComposer
                )
            }
            .sheet(isPresented: $showAddCategoryModal) {
                AddCategoryModal(
                    isPresented: $showAddCategoryModal,
                    newName: $newCategoryName,
                    onAdd: addFromCategoryModal
                )
            }
            .sheet(isPresented: $showCategoryManager) {
                ManageCategoriesView(selectedCategory: $selectedCategory)
            }
            .sheet(
                isPresented: Binding(
                    get: { categoryColorEditorName != nil },
                    set: { if !$0 { categoryColorEditorName = nil } }
                )
            ) {
                ColorPickerView(selectedColor: $categoryColorDraft, isPresented: Binding(
                    get: { categoryColorEditorName != nil },
                    set: { if !$0 { categoryColorEditorName = nil } }
                )) { color in
                    saveCategoryColor(color)
                }
            }
        }
        .task {
            refreshNotificationAuthorization()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
        .focusedSceneValue(\.taskActions, TaskActions(
            newTask: { showNewTaskComposer = true }
        ))
    }

private func filtered(_ input: [TaskItem]) -> [TaskItem] {
        // Smart filter: completed-this-week shows finished tasks regardless of the Completed toggle.
        if selectedCategory == "Completed This Week" {
            let result = input.filter { task in
                guard task.isCompleted, let done = task.completedAt, let week = currentWeekInterval else { return false }
                return week.contains(done)
            }
            let byPriority = selectedPriorityFilter == nil ? result : result.filter { $0.priority == selectedPriorityFilter }
            return searchedAndSorted(byPriority)
        }

        let base = includeCompleted ? input : input.filter { !$0.isCompleted }
        let byPriority = selectedPriorityFilter == nil ? base : base.filter { $0.priority == selectedPriorityFilter }

        let byCategory: [TaskItem]
        if selectedCategory == "My Day" {
            let calendar = Calendar.current
            byCategory = byPriority.filter { task in
                guard let due = task.dueDate else { return false }
                return calendar.isDateInToday(due) || calendar.isDateInTomorrow(due)
            }
        } else if selectedCategory == "All" {
            byCategory = byPriority
        } else if selectedCategory == "High Priority" {
            byCategory = byPriority.filter { ($0.priority ?? .low) == .high }
        } else if selectedCategory == "Due Soon" {
            let now = Date()
            let soon = now.addingTimeInterval(60 * 60 * 6)
            byCategory = byPriority.filter { task in
                if let due = task.dueDate {
                    return due >= now && due <= soon
                }
                return false
            }
        } else if selectedCategory == "Upcoming" {
            let now = Date()
            let calendar = Calendar.current
            byCategory = byPriority.filter { task in
                guard let due = task.dueDate else { return false }
                return due > now && !calendar.isDateInToday(due)
            }
        } else if selectedCategory == "No Date" {
            byCategory = byPriority.filter { $0.dueDate == nil }
        } else if selectedCategory == "High This Week" {
            byCategory = byPriority.filter { task in
                guard (task.priority ?? .low) == .high, let due = task.dueDate, let week = currentWeekInterval else { return false }
                return week.contains(due)
            }
        } else {
            byCategory = byPriority.filter { $0.category.caseInsensitiveCompare(selectedCategory) == .orderedSame }
        }

        return searchedAndSorted(byCategory)
    }

    private func searchedAndSorted(_ tasks: [TaskItem]) -> [TaskItem] {
        let filteredTasks = search.isEmpty ? tasks : tasks.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
        return filteredTasks.sorted(by: sortRule)
    }
    private func addFromQuickEntry() {
        let trimmedInput = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        if let categoryName = standaloneCategoryName(from: trimmedInput) {
            withAnimation(.snappy(duration: 0.22)) {
                selectedCategory = ensureCategoryExists(named: categoryName)
                quickText = ""
                quickFieldFocused = false
            }
            return
        }

        let parsed = QuickDateParser.parse(trimmedInput)
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        withAnimation(.snappy(duration: 0.25)) {

            let rawCategory = parsed.category ?? (RootView.systemViewNames.contains(selectedCategory) ? "Inbox" : selectedCategory)
            let finalCategory = ensureCategoryExists(named: rawCategory)

            let item = TaskItem(
                title: parsed.title,
                notes: "",
                dueDate: parsed.date,
                category: finalCategory,
                priority: parsed.priority ?? .low,
                sortIndex: nextTaskSortIndex()
            )
            context.insert(item)
            try? context.save()
            if parsed.date != nil { NotificationManager.shared.schedule(for: item) }
            quickText = ""
            quickFieldFocused = false
        }
    }

    private func standaloneCategoryName(from input: String) -> String? {
        let patterns = [
            #"^#\[(.+?)\]$"#,
            #"^#\"(.+?)\"$"#,
            #"^#(.+)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(input.startIndex..<input.endIndex, in: input)
            guard let match = regex.firstMatch(in: input, range: range),
                  let captureRange = Range(match.range(at: 1), in: input) else { continue }

            let name = String(input[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }

        return nil
    }

    private func nextTaskSortIndex() -> Int {
        (tasks.compactMap(\.sortIndex).max() ?? tasks.count) + 1
    }

    private func addFromComposer(title: String, notes: String, dueDate: Date?, categoryName: String, categoryColor: Color?, priority: TaskPriority, reminderSchedule: ReminderSchedule, customReminderMinutes: [Int]?) {
        let finalCategory = ensureCategoryExists(named: categoryName, color: categoryColor)
        let item = TaskItem(
            title: title,
            notes: notes,
            dueDate: dueDate,
            category: finalCategory,
            priority: priority,
            reminderSchedule: reminderSchedule,
            customReminderMinutes: customReminderMinutes,
            sortIndex: nextTaskSortIndex()
        )

        withAnimation(.snappy(duration: 0.25)) {
            context.insert(item)
            try? context.save()
            scheduleNotificationsIfNeeded(for: item)
        }
    }

    private func sortRule(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.isCompleted, b.isCompleted) {
        case (true, false): return false
        case (false, true): return true
        default:
            let orderA = a.sortIndex ?? Int.max
            let orderB = b.sortIndex ?? Int.max
            if orderA != orderB { return orderA < orderB }

            let priA = a.priority ?? .low
            let priB = b.priority ?? .low
            if priA != priB { return priA < priB }
            switch (a.dueDate, b.dueDate) {
            case let (d1?, d2?): return d1 < d2
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }
    
    private func refreshNotificationAuthorization() {
        NotificationManager.shared.getAuthorizationStatus { status in
            notificationAuthorization = status
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func scheduleNotificationsIfNeeded(for task: TaskItem) {
        guard let due = task.dueDate, !task.isCompleted, due > Date() else { return }

        NotificationManager.shared.schedule(for: task)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            refreshNotificationAuthorization()
        }
    }

    private func toggle(_ task: TaskItem) {
        let willComplete = !task.isCompleted
        let visibleActiveBefore = filtered(tasks).filter { !$0.isCompleted }
        let willClearVisibleView = willComplete &&
            visibleActiveBefore.count == 1 &&
            visibleActiveBefore.first?.id == task.id

        if willComplete {
            SoundManager.shared.playTaskComplete()
            HapticManager.shared.perform()
        }

        withAnimation(.snappy(duration: 0.60)) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? .now : nil

            if task.isCompleted {
                NotificationManager.shared.cancel(for: task)
            } else {
                scheduleNotificationsIfNeeded(for: task)
            }

            try? context.save()
        }

        if willClearVisibleView {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                SoundManager.shared.playAllComplete()
            }
        }
    }

    private func delete(_ task: TaskItem) {
        withAnimation(.snappy(duration: 0.25)) {
            NotificationManager.shared.cancel(for: task)
            deletedTask = task
            showUndoNotification = true

            undoTimer?.invalidate()
            undoTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                confirmDelete()
            }
        }
    }

    private func confirmDelete() {
        guard let task = deletedTask else { return }
        withAnimation(.snappy(duration: 0.25)) {
            context.delete(task)
            try? context.save()
            deletedTask = nil
            showUndoNotification = false
        }
    }

    private func undoDelete() {
        undoTimer?.invalidate()
        undoTimer = nil
        withAnimation(.snappy(duration: 0.25)) {
            deletedTask = nil
            showUndoNotification = false
        }
    }

    private func edit(_ task: TaskItem, title: String, notes: String, due: Date?, category: String, priority: TaskPriority, reminderSchedule: ReminderSchedule, customReminderMinutes: [Int]?) {
        task.title = title
        task.notes = notes
        task.dueDate = due
        task.category = category
        task.priority = priority
        task.reminderSchedule = reminderSchedule
        task.customReminderMinutes = customReminderMinutes
        NotificationManager.shared.cancel(for: task)
        scheduleNotificationsIfNeeded(for: task)
        try? context.save()
    }

    private func clearCompleted() {
        withAnimation(.snappy(duration: 0.25)) {
            for task in tasks where task.isCompleted {
                NotificationManager.shared.cancel(for: task)
                context.delete(task)
            }
            try? context.save()
        }
    }

    private func deleteCategory(_ categoryName: String) {
        guard let cat = categories.first(where: { $0.name == categoryName }) else { return }

        withAnimation(.snappy(duration: 0.25)) {
            for task in tasks where task.category == categoryName {
                task.category = "Inbox"
                NotificationManager.shared.cancel(for: task)
                scheduleNotificationsIfNeeded(for: task)
            }
            context.delete(cat)
            try? context.save()

            if selectedCategory == categoryName {
                selectedCategory = "My Day"
            }
        }
    }
}

struct TaskListView: View {
    let tasks: [TaskItem]
    let categoryColor: (String) -> Color
    let emptyTitle: String
    let emptySubtitle: String
    let emptyIcon: String
    let emptyAccent: Color
    @Binding var draggedTaskID: UUID?
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onEdit: (TaskItem, String, String, Date?, String, TaskPriority, ReminderSchedule, [Int]?) -> Void
    let onReorder: (UUID, UUID) -> Void

    var body: some View {
        ScrollView {
            if tasks.isEmpty {
                VStack {
                    Spacer(minLength: 22)
                    EmptyState(
                        title: emptyTitle,
                        subtitle: emptySubtitle,
                        icon: emptyIcon,
                        accent: emptyAccent
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                
                let calendar = Calendar.current
                let now = Date()

                let completedTasks = tasks.filter { $0.isCompleted }
                let activeTasks = tasks.filter { !$0.isCompleted }

                let overdue = activeTasks.filter { task in
                    if let due = task.dueDate { return due < now && !calendar.isDateInToday(due) }
                    return false
                }
                let todayTasks = activeTasks.filter { task in
                    if let due = task.dueDate { return calendar.isDateInToday(due) }
                    return false
                }
                let upcoming = activeTasks.filter { task in
                    if let due = task.dueDate { return due > now && !calendar.isDateInToday(due) }
                    return false
                }
                let noDate = activeTasks.filter { $0.dueDate == nil }

                VStack(spacing: 20) {
                    if !overdue.isEmpty {
                        VStack(spacing: 10) {
                            SectionHeader(title: "Overdue", count: overdue.count, accent: Theme.critical)
                            taskGrid(items: overdue)
                        }
                    }
                    if !todayTasks.isEmpty {
                        VStack(spacing: 10) {
                            SectionHeader(title: "Today", count: todayTasks.count, accent: Theme.dueSoon)
                            taskGrid(items: todayTasks)
                        }
                    }
                    if !upcoming.isEmpty {
                        VStack(spacing: 10) {
                            SectionHeader(title: "Upcoming", count: upcoming.count, accent: Theme.accent)
                            taskGrid(items: upcoming)
                        }
                    }
                    if !noDate.isEmpty {
                        VStack(spacing: 10) {
                            SectionHeader(title: "No Due Date", count: noDate.count, accent: .secondary)
                            taskGrid(items: noDate)
                        }
                    }
                    if !completedTasks.isEmpty {
                        VStack(spacing: 10) {
                            SectionHeader(title: "Completed", count: completedTasks.count, accent: .gray)
                            taskGrid(items: completedTasks)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 8)
            }
        }
        .background(Theme.bg)
    }

 
    @ViewBuilder
    private func taskGrid(items: [TaskItem]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                LazyVStack(spacing: 18) {
                    ForEach(columnItems(items, column: 0)) { task in
                        taskCard(task)
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .top)

                LazyVStack(spacing: 18) {
                    ForEach(columnItems(items, column: 1)) { task in
                        taskCard(task)
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .top)
            }

            LazyVStack(spacing: 18) {
                ForEach(items) { task in
                    taskCard(task)
                }
            }
        }
        .padding(.bottom, 18)
    }

    private func columnItems(_ items: [TaskItem], column: Int) -> [TaskItem] {
        items.enumerated().compactMap { index, task in
            index % 2 == column ? task : nil
        }
    }

    @ViewBuilder
    private func taskCard(_ task: TaskItem) -> some View {
        TaskRow(
            task: task,
            categoryColor: categoryColor,
            onToggle: onToggle,
            onDelete: onDelete
        ) { item, title, notes, due, category, priority, reminderSchedule, customReminderMinutes in
            onEdit(item, title, notes, due, category, priority, reminderSchedule, customReminderMinutes)
        }
        .id(task.id)
        .opacity(draggedTaskID == task.id ? 0.55 : 1)
        .animation(.snappy(duration: 0.18), value: draggedTaskID)
        .onDrag {
            draggedTaskID = task.id
            return NSItemProvider(object: task.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: TaskDropDelegate(
                targetID: task.id,
                draggedID: $draggedTaskID,
                onMove: onReorder
            )
        )
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 6) {
                    Text("\(count)")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(accent)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(accent.opacity(0.18), in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.horizontal, 10)
        }
    }
}

// Simple sound manager: plays a bundled whoosh.wav if present, else falls back.
// Simple sound manager: separates small task completion from bigger all-complete feedback.
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

struct TaskRow: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var didAppear = false
    @State private var isHovered = false
    @State private var subtasksExpanded = true

    let task: TaskItem
    let categoryColor: (String) -> Color
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onEdit: (TaskItem, String, String, Date?, String, TaskPriority, ReminderSchedule, [Int]?) -> Void

    private func toggleSubtask(_ subtask: Subtask) {
        var list = task.subtaskList
        guard let index = list.firstIndex(where: { $0.id == subtask.id }) else { return }
        list[index].isDone.toggle()
        withAnimation(.snappy(duration: 0.18)) {
            task.subtaskList = list
            try? modelContext.save()
        }
    }

    private var priority: TaskPriority {
        task.priority ?? .low
    }

    private var categoryTint: Color {
        categoryColor(task.category)
    }

    private var cardChromeTint: Color {
        if task.isCompleted { return Color.white.opacity(0.7) }
        if isOverdue || priority == .high { return Theme.critical }
        if isDueSoon { return Theme.dueSoon }
        return Color.white.opacity(0.75)
    }

    private var isOverdue: Bool {
        guard let due = task.dueDate, !task.isCompleted else { return false }
        return due < Date()
    }

    private var isDueSoon: Bool {
        guard let due = task.dueDate, !task.isCompleted else { return false }

        let calendar = Calendar.current
        return !isOverdue && (calendar.isDateInToday(due) || calendar.isDateInTomorrow(due))
    }

    private var pressureTitle: String {
        if task.isCompleted {
            return "Done"
        }

        if isOverdue {
            return "Overdue"
        }

        if priority == .high {
            return "Focus First"
        }

        if isDueSoon {
            return "Coming Up"
        }

        if task.dueDate != nil {
            return "On Deck"
        }

        switch priority {
        case .high:
            return "Focus First"
        case .medium:
            return "Keep in Mind"
        case .low:
            return "Low Pressure"
        }
    }

    private var pressureColor: Color {
        if task.isCompleted {
            return .secondary
        }

        if isOverdue {
            return Theme.critical
        }

        if priority == .high {
            return Theme.critical
        }

        if isDueSoon {
            return Theme.dueSoon
        }

        if task.dueDate != nil {
            return Theme.onDeck
        }

        switch priority {
        case .high:
            return Theme.critical
        case .medium:
            return Theme.keepInMind
        case .low:
            return Theme.lowPressure
        }
    }

    private var pressureIcon: String {
        if task.isCompleted {
            return "checkmark.circle.fill"
        }

        if isOverdue {
            return "exclamationmark.triangle.fill"
        }

        if priority == .high {
            return "flame.fill"
        }

        if isDueSoon {
            return "clock.fill"
        }

        if task.dueDate != nil {
            return "calendar"
        }

        switch priority {
        case .high:
            return "flame.fill"
        case .medium:
            return "bookmark.fill"
        case .low:
            return "leaf.fill"
        }
    }

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)

        if date < Date() {
            return "Overdue"
        }

        if calendar.isDateInToday(date) {
            return "Today \(time)"
        }

        if calendar.isDateInTomorrow(date) {
            return "Tomorrow \(time)"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func contextLine() -> String {
        var parts: [String] = []

        parts.append(task.category)

        if let due = task.dueDate {
            parts.append(dueText(due))
        } else {
            parts.append("No deadline")
        }

        return parts.joined(separator: " • ")
    }

    private func contextIcon() -> String {
        if isOverdue {
            return "exclamationmark.triangle.fill"
        }

        if task.dueDate != nil {
            return "calendar"
        }

        return "tray"
    }

    private func chip(text: String, systemImage: String, color: Color, filled: Bool = false) -> some View {
        Label {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            Capsule()
                .fill(filled ? color.opacity(0.18) : Color.white.opacity(0.055))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(filled ? 0.28 : 0.14), lineWidth: 1)
        )
    }

    private func pressureChip() -> some View {
        Label {
            Text(pressureTitle)
                .lineLimit(1)
        } icon: {
            Image(systemName: pressureIcon)
                .font(.system(size: 9, weight: .bold))
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(task.isCompleted ? .secondary : pressureColor)
        .padding(.vertical, 3.5)
        .padding(.horizontal, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(task.isCompleted ? 0.035 : 0.055))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(pressureColor.opacity(task.isCompleted ? 0.08 : 0.24), lineWidth: 1)
        )
    }

    private func subtaskProgressChip() -> some View {
        let progress = task.subtaskProgress
        let complete = progress.total > 0 && progress.done == progress.total
        let color = complete ? Theme.lowPressure : Theme.accent
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                subtasksExpanded.toggle()
            }
        } label: {
            Label {
                HStack(spacing: 4) {
                    Text("\(progress.done)/\(progress.total)")
                    Image(systemName: subtasksExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            } icon: {
                Image(systemName: complete ? "checklist.checked" : "checklist")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Capsule().fill(color.opacity(0.18)))
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(subtasksExpanded ? "Hide subtasks" : "Show subtasks")
        .accessibilityLabel("Subtasks \(progress.done) of \(progress.total)")
        .accessibilityHint(subtasksExpanded ? "Collapses the subtask checklist." : "Expands the subtask checklist.")
    }

    @ViewBuilder
    private func subtaskChecklist() -> some View {
        let list = task.subtaskList
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(list) { subtask in
                    Button(action: { toggleSubtask(subtask) }) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(subtask.isDone ? Theme.lowPressure : .secondary)

                            Text(subtask.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(subtask.isDone ? Color.secondary : Color.primary.opacity(0.9))
                                .strikethrough(subtask.isDone)
                                .lineLimit(1)

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(subtask.isDone ? "Mark subtask not done" : "Mark subtask done")
                    .accessibilityLabel("Subtask: \(subtask.title)")
                    .accessibilityValue(subtask.isDone ? "Done" : "Not done")
                }
            }
            .padding(.top, 4)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(categoryTint)
                .frame(width: 5)
                .opacity(task.isCompleted ? 0.45 : 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Button(action: { onToggle(task) }) {
                        ZStack {
                            Circle()
                                .fill(
                                    task.isCompleted
                                    ? Color.white.opacity(0.075)
                                    : categoryTint.opacity(isHovered ? 0.14 : 0.06)
                                )

                            Circle()
                                .stroke(
                                    task.isCompleted
                                    ? Color.secondary.opacity(0.45)
                                    : categoryTint.opacity(isHovered ? 0.95 : 0.82),
                                    lineWidth: 2.0
                                )

                            if task.isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 21, height: 21)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(task.isCompleted ? "Mark task active" : "Mark task done")
                    .accessibilityLabel(task.isCompleted ? "Mark task active" : "Mark task done")
                    .accessibilityHint(task.isCompleted ? "Moves this task back to your active task list." : "Completes this task and cancels future reminders.")
                    .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(task.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(task.isCompleted ? .secondary : .primary)
                            .strikethrough(task.isCompleted)
                            .opacity(task.isCompleted ? 0.62 : 1)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onTapGesture(count: 2) {
                                withAnimation(.snappy(duration: 0.18)) {
                                    isEditing = true
                                }
                            }

                        HStack(spacing: 6) {
                            Image(systemName: contextIcon())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(task.isCompleted ? 0.55 : 0.82))

                            Text(contextLine())
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(task.notes)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .opacity(task.isCompleted ? 0.55 : 0.86)
                        }

                        HStack(spacing: 6) {
                            pressureChip()

                            if task.subtaskProgress.total > 0 {
                                subtaskProgressChip()
                            }
                        }
                        .padding(.top, 2)

                        if subtasksExpanded {
                            subtaskChecklist()
                        }
                    }

                    VStack(spacing: 6) {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                isEditing.toggle()
                            }
                        } label: {
                            Image(systemName: isEditing ? "xmark" : "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(isHovered || isEditing ? 1.0 : 0.68))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(isHovered || isEditing ? 0.085 : 0.035))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(isHovered || isEditing ? 0.11 : 0.045), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(isEditing ? "Close editing" : "Edit task")
                        .accessibilityLabel(isEditing ? "Close editing" : "Edit task")
                        .accessibilityHint(isEditing ? "Closes the task editing controls." : "Opens editable fields for this task.")

                        Button(action: { onDelete(task) }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(isHovered ? 0.085 : 0.0))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(isHovered ? 0.10 : 0.0), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Delete task")
                        .accessibilityLabel("Delete task")
                        .accessibilityHint("Deletes this task and shows an undo option.")
                        .opacity(isHovered ? 1 : 0)
                        .accessibilityHidden(!isHovered)
                    }
                    .frame(width: 34, alignment: .top)
                }
                .padding(14)

                if isEditing {
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                        .padding(.horizontal, 14)
                        .transition(.opacity)

                    EditableFields(task: task, isEditing: isEditing) { title, notes, dueDate, category, priority, reminderSchedule, customMinutes in
                        onEdit(task, title, notes, dueDate, category, priority, reminderSchedule, customMinutes)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: cardChromeTint, completed: task.isCompleted)
        .scaleEffect(isHovered ? 1.006 : 1.0)
        .shadow(
            color: isHovered ? cardChromeTint.opacity(0.14) : Color.clear,
            radius: isHovered ? 10 : 0,
            x: 0,
            y: isHovered ? 4 : 0
        )
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isEditing.toggle()
                }
            } label: {
                Label(isEditing ? "Close Details" : "Edit Details", systemImage: isEditing ? "xmark" : "pencil")
            }

            Button(role: .destructive) {
                onDelete(task)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
        .scaleEffect(didAppear ? 1.0 : 0.98)
        .opacity(didAppear ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.45), value: didAppear)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(0.05)) {
                didAppear = true
            }
        }
        .onDisappear {
            didAppear = false
        }
       
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task: \(task.title). \(pressureTitle). Category \(task.category).")
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isEditing)
        .animation(.snappy(duration: 0.45), value: task.isCompleted)
        .animation(.snappy(duration: 0.22), value: subtasksExpanded)
    }
}

struct EditableFields: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryItem.name, order: .forward) private var categories: [CategoryItem]
    @State private var title: String
    @State private var notes: String
    @State private var dueDate: Date?
    @State private var category: String
    @State private var priority: TaskPriority
    @State private var reminderSchedule: ReminderSchedule
    @State private var reminderMode: ReminderMode = .preset
    @State private var customReminderMinutes: [Int] = []
    @State private var subtasks: [Subtask]

    let task: TaskItem
    let onCommit: (String, String, Date?, String, TaskPriority, ReminderSchedule, [Int]?) -> Void
    let isEditing: Bool

    enum ReminderMode { case preset, custom }

    // Subtasks persist straight to the model (independent of the text-field commit path),
    // so they survive even if the editor closes without re-committing the other fields.
    private func persistSubtasks() {
        task.subtaskList = subtasks.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        try? modelContext.save()
    }

    private var availableCategories: [CategoryItem] {
        categories
    }

    init(task: TaskItem, isEditing: Bool, onCommit: @escaping (String, String, Date?, String, TaskPriority, ReminderSchedule, [Int]?) -> Void) {
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _dueDate = State(initialValue: task.dueDate)
        _category = State(initialValue: task.category)
        _priority = State(initialValue: task.priority ?? .low)
        _subtasks = State(initialValue: task.subtaskList)

        if let customMinutes = task.customReminderMinutes, !customMinutes.isEmpty {
            _reminderMode = State(initialValue: .custom)
            _customReminderMinutes = State(initialValue: customMinutes.sorted(by: >))
            _reminderSchedule = State(initialValue: .none)
        } else {
            _reminderMode = State(initialValue: .preset)
            _reminderSchedule = State(initialValue: task.reminderSchedule ?? .none)
            _customReminderMinutes = State(initialValue: [])
        }

        self.isEditing = isEditing
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Task Details")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Edit the saved task without leaving the list.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                DetailFieldLabel("Title", systemImage: "text.cursor")
                TextField("Task title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .medium))
                    .help("Edit the task title")

                DetailFieldLabel("Notes", systemImage: "note.text")
                TextField("Add details...", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
                    .help("Edit notes for this task")
            }
            .padding(12)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DetailFieldLabel("Subtasks", systemImage: "checklist")
                    Spacer()
                    if !subtasks.isEmpty {
                        Text("\(subtasks.filter { $0.isDone }.count)/\(subtasks.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                }

                if subtasks.isEmpty {
                    Text("Break this task into smaller steps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subtasks.indices, id: \.self) { index in
                        HStack(spacing: 8) {
                            Button {
                                subtasks[index].isDone.toggle()
                                persistSubtasks()
                            } label: {
                                Image(systemName: subtasks[index].isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(subtasks[index].isDone ? Theme.lowPressure : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help(subtasks[index].isDone ? "Mark subtask not done" : "Mark subtask done")

                            TextField("Subtask", text: $subtasks[index].title)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .onSubmit { persistSubtasks() }
                                .help("Edit this subtask")

                            Button {
                                subtasks.remove(at: index)
                                persistSubtasks()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove this subtask")
                            .modifier(HoverButtonModifier())
                        }
                    }
                }

                Button {
                    subtasks.append(Subtask(title: ""))
                } label: {
                    Label("Add Subtask", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Add a checklist item to this task")
                .modifier(HoverButtonModifier())
            }
            .padding(12)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    DetailFieldLabel("Category", systemImage: "tag")

                    Picker("Category", selection: $category) {
                        if !category.isEmpty && !availableCategories.contains(where: { $0.name == category }) {
                            Text(category).tag(category)
                        }

                        ForEach(availableCategories) { cat in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Categories.color(for: cat))
                                    .frame(width: 8, height: 8)
                                Text(cat.name)
                            }
                            .tag(cat.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Move this task to another category")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    DetailFieldLabel("Priority", systemImage: "flag")
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Change this task's priority")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(priority.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(priority.color.opacity(0.18), lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DetailFieldLabel("Reminders", systemImage: "bell")
                    Spacer()
                    Text(reminderMode == .custom ? "Custom" : reminderSchedule.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }

                Picker("Reminder Mode", selection: $reminderMode) {
                    Text("Preset").tag(ReminderMode.preset)
                    Text("Custom").tag(ReminderMode.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Choose preset reminders or custom reminder times")

                if reminderMode == .preset {
                    Picker("Reminder Schedule", selection: $reminderSchedule) {
                        ForEach(ReminderSchedule.allCases, id: \.self) { schedule in
                            Text(schedule.label).tag(schedule)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Choose when QuickTodo should remind you")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if customReminderMinutes.isEmpty {
                            Text("No custom reminders")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(customReminderMinutes.enumerated()), id: \.offset) { index, _ in
                                HStack(spacing: 8) {
                                    TextField("Minutes", value: Binding(
                                        get: { customReminderMinutes[index] },
                                        set: { customReminderMinutes[index] = max(1, $0) }
                                    ), format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 72)
                                    .help("Minutes before the due time")

                                    Text("minutes before")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Button(action: { customReminderMinutes.remove(at: index) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this custom reminder")
                                    .modifier(HoverButtonModifier())
                                }
                            }
                        }

                        if customReminderMinutes.count < 3 {
                            Button(action: { customReminderMinutes.append(15) }) {
                                Label("Add Reminder", systemImage: "plus.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                            .help("Add another custom reminder time")
                            .modifier(HoverButtonModifier())
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DetailFieldLabel("Due", systemImage: "calendar.badge.clock")
                    Spacer()
                    Button {
                        dueDate = nil
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(dueDate == nil ? 0.45 : 1)
                    .disabled(dueDate == nil)
                    .help(dueDate == nil ? "No due date is set" : "Remove this task's due date")
                    .modifier(HoverButtonModifier())
                }

                DatePicker("Due", selection: Binding($dueDate, default: Date()), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .help("Set this task's due date and time")
            }
            .padding(12)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .padding(13)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .onAppear {
            if category.isEmpty, let replacement = availableCategories.first?.name {
                category = replacement
            }
        }
        .onChange(of: isEditing, initial: false) { oldValue, newValue in
            if oldValue && !newValue {
                commitChanges()
            }
        }
        .onDisappear {
            commitChanges()
        }
    }

    private func commitChanges() {
        persistSubtasks()
        let finalCustomMinutes = reminderMode == .custom ? customReminderMinutes : nil
        onCommit(title, notes, dueDate, category, priority, reminderSchedule, finalCustomMinutes)
    }

}

private struct DetailFieldLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }
}

// Helper to bind optional Date in DatePicker
extension Binding where Value == Date {
    init(_ source: Binding<Date?>, default defaultValue: Date) {
        self.init(get: { source.wrappedValue ?? defaultValue }, set: { newValue in source.wrappedValue = newValue })
    }
}
struct ManageCategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Binding var selectedCategory: String

    @State private var pendingDelete: CategoryItem? = nil
    @State private var showConfirmDelete = false
    @State private var categories: [CategoryItem] = []
    @State private var hoveredColorPicker: String? = nil
    @State private var showAddCategoryModal = false
    @State private var newCategoryName = ""

    private var visibleCategories: [CategoryItem] {
        categories
            .filter { $0.name != "Inbox" }
            .sorted { lhs, rhs in
                let left = lhs.sortIndex ?? Int.max
                let right = rhs.sortIndex ?? Int.max
                if left != right { return left < right }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if visibleCategories.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Theme.accent)

                        Text("No categories yet")
                            .font(.headline)

                        Text("Create one here, or type #Category in Quick Add.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(visibleCategories) { cat in
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)

                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Categories.color(for: cat))
                                    .frame(width: 5, height: 22)

                                Text(cat.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 12)

                                ColorPicker(
                                    "",
                                    selection: Binding(
                                        get: { Categories.color(for: cat) },
                                        set: { newColor in
                                            cat.colorHex = newColor.toHex()
                                            try? context.save()
                                        }
                                    )
                                )
                                .labelsHidden()
                                .frame(width: 30, height: 22)
                                .clipShape(Circle())
                                .contentShape(Circle())
                                .help("Change the color for \(cat.name)")
                                .scaleEffect(hoveredColorPicker == cat.name ? 1.12 : 1.0)
                                .onHover { hovering in
                                    withAnimation(.snappy(duration: 0.2)) {
                                        hoveredColorPicker = hovering ? cat.name : nil
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDelete = cat
                                    showConfirmDelete = true
                                } label: {
                                    Label("Delete Category", systemImage: "trash")
                                }
                            }
                        }
                        .onMove(perform: moveCategories)
                        .onDelete(perform: handleDelete)
                    } header: {
                        Text("Drag to reorder")
                    }
                }
            }
            .navigationTitle("Manage Categories")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? context.save()
                        dismiss()
                    }
                    .help("Save category changes and close")
                    .modifier(HoverButtonModifier())
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddCategoryModal = true
                    } label: {
                        Label("New Category", systemImage: "plus")
                    }
                    .help("Create a new category")
                    .modifier(HoverButtonModifier())
                }
            }
        }
        .frame(minWidth: 520, minHeight: 380)
        .task { reload() }
        .sheet(isPresented: $showAddCategoryModal) {
            AddCategoryModal(
                isPresented: $showAddCategoryModal,
                newName: $newCategoryName,
                onAdd: addCategory
            )
        }
        .alert("Delete Category?", isPresented: $showConfirmDelete, presenting: pendingDelete) { cat in
            Button("Delete", role: .destructive) { delete(cat) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { cat in
            Text("This will move any tasks in \(cat.name) to Inbox.")
        }
    }

    private func handleDelete(_ indexSet: IndexSet) {
        for idx in indexSet {
            guard visibleCategories.indices.contains(idx) else { continue }
            pendingDelete = visibleCategories[idx]
            showConfirmDelete = true
            break
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var ordered = visibleCategories
        ordered.move(fromOffsets: source, toOffset: destination)

        for (index, category) in ordered.enumerated() {
            category.sortIndex = index
        }
        try? context.save()
        reload()
    }

    private func reload() {
        let fd = FetchDescriptor<CategoryItem>()
        categories = (try? context.fetch(fd)) ?? []
        ensureDefaultsIfNeeded()
        categories = (try? context.fetch(fd)) ?? []
        assignMissingSortIndexesIfNeeded()
    }

    private func ensureDefaultsIfNeeded() {
        if categories.first(where: { $0.name == "Inbox" }) == nil {
            context.insert(CategoryItem(name: "Inbox", sortIndex: 0))
            try? context.save()
        }
    }

    private func assignMissingSortIndexesIfNeeded() {
        var changed = false
        for (index, category) in categories.sorted(by: { $0.createdAt < $1.createdAt }).enumerated() where category.sortIndex == nil {
            category.sortIndex = index
            changed = true
        }
        if changed { try? context.save() }
    }

    private func addCategory(name: String, color: Color) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            existing.colorHex = color.toHex()
            selectedCategory = existing.name
        } else {
            let nextIndex = ((categories.compactMap(\.sortIndex).max() ?? categories.count) + 1)
            let category = CategoryItem(name: trimmed, colorHex: color.toHex(), sortIndex: nextIndex)
            context.insert(category)
            selectedCategory = category.name
        }

        newCategoryName = ""
        try? context.save()
        reload()
    }

    private func delete(_ cat: CategoryItem) {
        guard cat.name != "Inbox" else { return }

        let fetch = FetchDescriptor<TaskItem>()
        if let allTasks = try? context.fetch(fetch) {
            for task in allTasks where task.category.caseInsensitiveCompare(cat.name) == .orderedSame {
                task.category = "Inbox"
            }
        }

        context.delete(cat)
        try? context.save()

        if selectedCategory.caseInsensitiveCompare(cat.name) == .orderedSame { selectedCategory = "All" }
        pendingDelete = nil
        reload()
    }
}

struct EmptyState: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color

    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accent.opacity(0.095))
                    .frame(width: 58, height: 58)

                Image(systemName: icon)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 58, height: 58)

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 26)
        .frame(maxWidth: 460)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 8)
        .onAppear {
            withAnimation(.snappy(duration: 0.22)) {
                isVisible = true
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Help

@MainActor
final class QuickTodoHelpWindowController {
    static let shared = QuickTodoHelpWindowController()

    private var window: NSWindow?
    private var windowDelegate: HelpWindowDelegate?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: QuickTodoHelpView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickTodo Help"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        let delegate = HelpWindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        window.delegate = delegate

        self.windowDelegate = delegate
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class HelpWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

struct QuickTodoHelpView: View {
    private let sections = QuickTodoHelpContent.sections

    private let twoColumns = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    private let oneColumn = [
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    var body: some View {
        GeometryReader { geo in
            let useTwoColumns = geo.size.width >= 700

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    LazyVGrid(
                        columns: useTwoColumns ? twoColumns : oneColumn,
                        alignment: .center,
                        spacing: 16
                    ) {
                        ForEach(sections) { section in
                            HelpGuideCard(section: section)
                        }
                    }
                }
                .padding(28)
            }
            .background(Theme.bg)
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(
                    Theme.accent.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("QuickTodo Help")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Quick capture, clean organization, reminders, shortcuts, and safe task cleanup.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct HelpGuideSection: Identifiable, @unchecked Sendable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let items: [HelpGuideItem]
}

struct HelpGuideItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let body: String
}

struct HelpGuideCard: View {
    let section: HelpGuideSection

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(section.color)
                    .frame(width: 30, height: 30)
                    .background(section.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(section.items.count) \(section.items.count == 1 ? "topic" : "topics")")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    HelpGuideItemRow(item: item)

                    if index < section.items.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.065))
                            .frame(height: 1)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.043), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        }
    }
}

private struct HelpGuideItemRow: View {
    let item: HelpGuideItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 12.8, weight: .semibold))
                .foregroundStyle(.primary)

            Text(item.body)
                .font(.system(size: 12.4))
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: First-Run Onboarding

private struct TrackpadSwipeMonitor: NSViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.start()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        weak var view: NSView?

        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void

        private var monitor: Any?
        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private var didTrigger = false

        init(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard let window = view?.window, event.window === window else { return }

            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                accumulatedX = 0
                accumulatedY = 0
                didTrigger = false
            }

            accumulatedX += event.scrollingDeltaX
            accumulatedY += event.scrollingDeltaY

            let isHorizontalSwipe =
                abs(accumulatedX) > 60 &&
                abs(accumulatedX) > abs(accumulatedY) * 1.35

            if isHorizontalSwipe && !didTrigger {
                didTrigger = true

                if accumulatedX > 0 {
                    onSwipeRight()
                } else {
                    onSwipeLeft()
                }
            }

            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                accumulatedX = 0
                accumulatedY = 0
                didTrigger = false
            }
        }
    }
}


struct WelcomeView: View {
    let onDismiss: () -> Void

    @State private var step = 0

    // MARK: Content model (keep in sync with features — see help/tips)

    fileprivate struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let detail: String
    }

    fileprivate struct Page: Identifiable {
        let id = UUID()
        let badge: String
        let accent: Color
        let title: String
        let subtitle: String
        let features: [Feature]
        var showQuickAddPreview: Bool = false
        var footnote: String? = nil
    }

    private let pages: [Page] = [
        Page(
            badge: "checkmark.circle.fill",
            accent: Theme.accent,
            title: "Welcome to QuickTodo",
            subtitle: "Capture what matters, organize it fast, and keep every task private on your Mac.",
            features: [
                Feature(icon: "lock.fill", color: Theme.lowPressure, title: "Private by design",
                        detail: "Everything stays on this device. No account, no sync, no tracking."),
                Feature(icon: "bolt.fill", color: Theme.accent, title: "Built for speed",
                        detail: "Add a task in seconds from the app, the menu bar, or the global shortcut."),
                Feature(icon: "tray.full.fill", color: Theme.inbox, title: "A calm capture bucket",
                        detail: "Unsorted tasks land in Inbox first, so quick capture never forces you to organize too early.")
            ],
            showQuickAddPreview: true
        ),
        Page(
            badge: "text.badge.plus",
            accent: Theme.accent,
            title: "Capture in plain language",
            subtitle: "Type the way you think — QuickTodo fills in the details for you.",
            features: [
                Feature(icon: "calendar", color: Theme.dueSoon, title: "Dates & times",
                        detail: "“essay friday 11:59pm” sets the due date and time automatically."),
                Feature(icon: "tag.fill", color: Theme.onDeck, title: "Categories & priority",
                        detail: "Add #English and !high. Type #Work on its own to create a category."),
                Feature(icon: "command", color: Theme.keepInMind, title: "From anywhere",
                        detail: "Press ⌃⌥⌘ Space in any app to open Quick Add without switching windows.")
            ]
        ),
        Page(
            badge: "sidebar.left",
            accent: Theme.dueSoon,
            title: "Organized your way",
            subtitle: "Views for right now, and for the long game.",
            features: [
                Feature(icon: "sun.max.fill", color: Theme.accent, title: "My Day & Due Soon",
                        detail: "Stay focused on what's due today and in the next few hours."),
                Feature(icon: "calendar", color: Theme.onDeck, title: "Upcoming",
                        detail: "Plan ahead with everything scheduled beyond today."),
                Feature(icon: "tray.fill", color: Theme.inbox, title: "Inbox",
                        detail: "Anything captured without a category lands here, so nothing gets lost."),
                Feature(icon: "line.3.horizontal.decrease.circle.fill", color: Theme.critical, title: "Smart Filters",
                        detail: "Saved views like No Date and High This Week, tucked in the sidebar.")
            ]
        ),
        Page(
            badge: "checklist",
            accent: Theme.lowPressure,
            title: "Get things done",
            subtitle: "Break work down and let QuickTodo keep you on track.",
            features: [
                Feature(icon: "checklist", color: Theme.accent, title: "Subtasks",
                        detail: "Add a checklist to any task and tick items off right on the card."),
                Feature(icon: "bell.fill", color: Theme.dueSoon, title: "Reminders",
                        detail: "Tasks with a due date can send local notifications before they're due."),
                Feature(icon: "checkmark.seal.fill", color: Theme.lowPressure, title: "Done stays visible when you need it",
                        detail: "Review completed work this week without cluttering your active task list.")
            ],
            footnote: "Need a hand later? Tap the ⓘ beside Quick Add for tips, open Help ▸ QuickTodo Help, or visit Settings (⌘,)."
        )
    ]

    private var isLastStep: Bool { step == pages.count - 1 }

    var body: some View {
        let page = pages[step]

        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? page.accent : Color.white.opacity(0.18))
                        .frame(width: index == step ? 22 : 7, height: 7)
                        .animation(.snappy(duration: 0.25), value: step)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 6)

            // Page content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(page.accent.opacity(0.16))
                            Image(systemName: page.badge)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(page.accent)
                        }
                        .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(page.title)
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(page.subtitle)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if page.showQuickAddPreview {
                        quickAddPreview(accent: page.accent)
                    }

                    VStack(spacing: 10) {
                        ForEach(page.features) { item in
                            featureRow(item)
                        }
                    }

                    if let footnote = page.footnote {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(page.accent)
                                .padding(.top, 1)

                            Text(footnote)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(page.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(page.accent.opacity(0.20), lineWidth: 1)
                        )
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Swipe left or right to move between pages")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 30)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: step)

            Divider().overlay(Color.white.opacity(0.08))

            // Navigation bar
            HStack(spacing: 10) {
                if !isLastStep {
                    Button("Skip", action: onDismiss)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Skip the introduction")
                }

                Spacer()

                if step > 0 {
                    Button(action: goBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button(action: {
                    if isLastStep {
                        onDismiss()
                    } else {
                        goForward()
                    }
                }) {
                    Text(isLastStep ? "Get Started" : "Next")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minWidth: isLastStep ? 120 : 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(page.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 640)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 36, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > 72, abs(horizontal) > abs(vertical) * 1.25 else { return }
                    if horizontal < 0 {
                        goForward()
                    } else {
                        goBack()
                    }
                }
        )
        
        .gesture(
            DragGesture(minimumDistance: 36, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > 72, abs(horizontal) > abs(vertical) * 1.25 else { return }
                    if horizontal < 0 {
                        goForward()
                    } else {
                        goBack()
                    }
                }
        )
        .background(
                TrackpadSwipeMonitor(
                    onSwipeLeft: goForward,
                    onSwipeRight: goBack
                )
            )
        .onMoveCommand { direction in
            switch direction {
            case .left: goBack()
            case .right: goForward()
            default: break
            }
        }
    }
    

    @ViewBuilder
    private func featureRow(_ item: Feature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.color)
                .frame(width: 36, height: 36)
                .background(item.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14.5, weight: .semibold))
                Text(item.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func quickAddPreview(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Example quick capture")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 10) {
                Text("essay friday 11:59pm #English !high")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("essay")
                        .font(.system(size: 13.5, weight: .semibold))
                    HStack(spacing: 6) {
                        Label("Fri 11:59 PM", systemImage: "calendar")
                        Text("English")
                        Text("High")
                            .foregroundStyle(Theme.critical)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: 180, alignment: .leading)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func goForward() {
        guard !isLastStep else { return }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            step += 1
        }
    }

    private func goBack() {
        guard step > 0 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { step -= 1 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Settings

struct SettingsView: View {
    @AppStorage("muteSounds") private var muteSounds = false
    @AppStorage("hasSeenWelcomeV1") private var hasSeenWelcome = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .provisional: return "Enabled"
        case .denied: return "Off"
        case .notDetermined: return "Not requested"
        default: return "Unknown"
        }
    }

    private var notificationDetailText: String {
        switch notificationStatus {
        case .authorized, .provisional: return "Due-date reminders are ready."
        case .denied: return "Turn notifications on in System Settings to receive task reminders."
        case .notDetermined: return "QuickTodo will ask when a reminder is first scheduled."
        default: return "Open System Settings if reminders are not appearing."
        }
    }

    private var notificationAccent: Color {
        switch notificationStatus {
        case .authorized, .provisional: return Theme.lowPressure
        case .denied: return Theme.dueSoon
        case .notDetermined: return Theme.onDeck
        default: return Theme.keepInMind
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader

            ScrollView {
                VStack(spacing: 12) {
                    SettingsCard(title: "General", icon: "gearshape.fill", accent: Theme.accent) {
                        SettingsToggleRow(
                            title: "Completion sound",
                            detail: "Play a subtle sound when you finish a task.",
                            isOn: Binding(
                                get: { !muteSounds },
                                set: { muteSounds = !$0 }
                            )
                        )
                        

                        SettingsDivider()

                        SettingsToggleRow(
                            title: "Launch at login",
                            detail: "Start QuickTodo automatically when you sign in.",
                            isOn: $launchAtLogin
                        )
                        .onChange(of: launchAtLogin) { _, enable in
                            do {
                                if enable {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                // Revert the toggle to the real system state if the change failed.
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                    }

                    SettingsCard(title: "Quick Capture", icon: "bolt.fill", accent: Theme.accent) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Global hotkey")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Open Quick Add from any app. Use #category to file it instantly, or leave it in Inbox.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)

                            Text(GlobalHotKeyManager.shortcutLabel)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                        }
                    }

                    SettingsCard(title: "Notifications", icon: "bell.badge.fill", accent: notificationAccent) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Reminder status")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(notificationDetailText)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)

                            SettingsStatusPill(text: notificationStatusText, color: notificationAccent)
                        }

                        SettingsDivider()

                        HStack(spacing: 8) {
                            SettingsActionButton(title: "System Settings", icon: "arrow.up.right.square", accent: notificationAccent) {
                                openNotificationSettings()
                            }

                            SettingsActionButton(title: "Check Again", icon: "arrow.clockwise", accent: Theme.accent) {
                                refreshStatus()
                            }
                        }
                    }

                    SettingsCard(title: "Help", icon: "questionmark.circle.fill", accent: Theme.onDeck) {
                        HStack(spacing: 8) {
                            SettingsActionButton(title: "Open Help", icon: "book.pages.fill", accent: Theme.onDeck) {
                                Task { @MainActor in
                                    QuickTodoHelpWindowController.shared.show()
                                }
                            }

                            SettingsActionButton(title: "Replay Welcome", icon: "sparkles.rectangle.stack.fill", accent: Theme.accent) {
                                hasSeenWelcome = false
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 520)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .task { refreshStatus() }
    }

    @ViewBuilder
    private var settingsHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.accent.opacity(0.15))
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Keep the controls tight, clear, and easy to scan.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private func refreshStatus() {
        NotificationManager.shared.getAuthorizationStatus { status in
            notificationStatus = status
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let accent: Color
    let content: Content

    init(title: String, icon: String, accent: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        )
    }
}

private struct QuickTodoSwitchStyle: ToggleStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                configuration.isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(configuration.isOn ? accent.opacity(0.92) : Color.white.opacity(0.13))
                .frame(width: 58, height: 30)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.96))
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                        .padding(3),
                    alignment: configuration.isOn ? .trailing : .leading
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            configuration.isOn ? accent.opacity(0.38) : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}


private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .toggleStyle(
                    QuickTodoSwitchStyle(
                        accent: Color(red: 0.2, green: 0.7, blue: 0.95)
                    )
                )
                .labelsHidden()
        }
    }
}

private struct SettingsActionButton: View {
    let title: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .modifier(HoverButtonModifier())
    }
}

private struct SettingsStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.10), in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(color.opacity(0.18), lineWidth: 1))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Menu & Shortcuts

struct AppCommands: Commands {
    @FocusedValue(\.taskActions) var actions

    var body: some Commands {
        CommandMenu("Tasks") {
            Button("New Task", action: { actions?.newTask() }).keyboardShortcut("n", modifiers: [.command])
            Button("Quick Capture (\(GlobalHotKeyManager.shortcutLabel))") {
                Task { @MainActor in
                    QuickAddPanelController.shared.show()
                }
            }
        }

        CommandGroup(replacing: .help) {
            Button("QuickTodo Help") {
                Task { @MainActor in
                    QuickTodoHelpWindowController.shared.show()
                }
            }
        }
    }
}

struct TaskActionsKey: FocusedValueKey { typealias Value = TaskActions }
extension FocusedValues { var taskActions: TaskActions? { get { self[TaskActionsKey.self] } set { self[TaskActionsKey.self] = newValue } } }
struct TaskActions { let newTask: () -> Void }

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Global Quick Add Hotkey

/// Registers a process-wide hotkey using Carbon's RegisterEventHotKey. It fires even when
/// QuickTodo is in the background and does not require Accessibility permission, so it is
/// safe for the Mac App Store.
final class GlobalHotKeyManager: @unchecked Sendable {
    static let shared = GlobalHotKeyManager()
    private init() {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    // ⌃⌥⌘ Space
    static let keyCode = UInt32(kVK_Space)
    static let modifierFlags = UInt32(controlKey | optionKey | cmdKey)
    static let shortcutLabel = "⌃⌥⌘ Space"

    func register(onTrigger: @escaping () -> Void) {
        guard hotKeyRef == nil else { return }
        self.onTrigger = onTrigger

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onTrigger?()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x51544B59), id: 1) // 'QTKY'
        RegisterEventHotKey(Self.keyCode, Self.modifierFlags, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

/// A floating HUD panel that pops up anywhere (via the global hotkey or the Tasks menu) for
/// frictionless capture into the shared SwiftData store.
@MainActor
final class QuickAddPanelController {
    static let shared = QuickAddPanelController()
    private init() {}

    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let container = SwiftDataBridge.shared.modelContainer else { return }

        if panel == nil {
            let hosting = NSHostingView(
                rootView: QuickAddPanelView(onClose: { [weak self] in self?.panel?.orderOut(nil) })
                    .modelContainer(container)
            )
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
                styleMask: [.titled, .closable, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Quick Add"
            panel.contentView = hosting
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }

        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}

struct QuickAddPanelView: View {
    @Environment(\.modelContext) private var context
    @State private var text: String = ""
    @FocusState private var focused: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Theme.accent)
                Text("Quick Add")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(GlobalHotKeyManager.shortcutLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("essay friday 11:59pm #English !high", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit(save)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
                )

            HStack {
                Text("Return to add • Esc to close")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
        }
        .onExitCommand(perform: onClose)
    }

    private func save() {
        let parsed = QuickDateParser.parse(text)
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let category = ensureCategoryExists(named: parsed.category ?? "Inbox")
        let item = TaskItem(
            title: parsed.title,
            notes: "",
            dueDate: parsed.date,
            category: category,
            priority: parsed.priority ?? .low,
            sortIndex: nextTaskSortIndex()
        )
        context.insert(item)
        try? context.save()
        if parsed.date != nil { NotificationManager.shared.schedule(for: item) }
        text = ""
        onClose()
    }

    private func nextTaskSortIndex() -> Int {
        let descriptor = FetchDescriptor<TaskItem>()
        let existingTasks = (try? context.fetch(descriptor)) ?? []
        return (existingTasks.compactMap(\.sortIndex).max() ?? existingTasks.count) + 1
    }

    private func ensureCategoryExists(named raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Inbox" }

        let descriptor = FetchDescriptor<CategoryItem>()
        if let existing = try? context.fetch(descriptor).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.name
        }

        let existingCategories = (try? context.fetch(descriptor)) ?? []
        let nextIndex = ((existingCategories.compactMap(\.sortIndex).max() ?? existingCategories.count) + 1)
        context.insert(CategoryItem(name: name, sortIndex: nextIndex))
        try? context.save()
        return name
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Menu Bar Quick Add View

struct MenuBarView: View {
    @Environment(\.modelContext) private var context
    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                TextField("Quick add… (#tag optional)", text: $text)
                    .textFieldStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                    .help("Quick add a task from the menu bar. Example: email Sam tomorrow #Work !medium")

            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button { save() } label: { Label("Add Task", systemImage: "plus.circle.fill") }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .help("Save this menu bar task")
        }
        .padding(12)
        .frame(width: 320)
    }

    private func save() {
        let parsed = QuickDateParser.parse(text)
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let category = ensureCategoryExists(named: parsed.category ?? "Inbox")
        let item = TaskItem(
            title: parsed.title,
            notes: "",
            dueDate: parsed.date,
            category: category,
            priority: parsed.priority ?? .low,
            sortIndex: nextTaskSortIndex()
        )
        context.insert(item)
        try? context.save()
        if parsed.date != nil { NotificationManager.shared.schedule(for: item) }
        text = ""
    }

    private func nextTaskSortIndex() -> Int {
        let descriptor = FetchDescriptor<TaskItem>()
        let existingTasks = (try? context.fetch(descriptor)) ?? []
        return (existingTasks.compactMap(\.sortIndex).max() ?? existingTasks.count) + 1
    }

    private func ensureCategoryExists(named raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Inbox" }

        let descriptor = FetchDescriptor<CategoryItem>()
        if let existing = try? context.fetch(descriptor).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.name
        }

        let existingCategories = (try? context.fetch(descriptor)) ?? []
        let nextIndex = ((existingCategories.compactMap(\.sortIndex).max() ?? existingCategories.count) + 1)
        context.insert(CategoryItem(name: name, sortIndex: nextIndex))
        try? context.save()
        return name
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Shared Card Style (Glassmorphism)

struct GlassCard: ViewModifier {
    let tint: Color
    let isCompleted: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isCompleted ? 0.03 : 0.055),
                                Color.white.opacity(isCompleted ? 0.01 : 0.018)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(isCompleted ? 0.08 : 0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(
                color: tint.opacity(isCompleted ? 0.05 : 0.12),
                radius: 12,
                x: 0,
                y: 2
            )
    }
}

extension View {
    func glassCard(tint: Color, completed: Bool) -> some View {
        self.modifier(GlassCard(tint: tint, isCompleted: completed))
    }
}
