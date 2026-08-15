// Models.swift
// Data model: TaskItem, CategoryItem, Subtask, and the enums that describe a task's
// priority, reminder schedule, and (new) its place in the Decision Board workflow.

import Foundation
import SwiftUI
import SwiftData

// MARK: - Color <-> Hex Helpers (for user-picked subject colors)

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

// MARK: - Model (SwiftData)

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
            return Theme.warning
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

// How often a task repeats. Recurrence needs a due date to advance from, so this only
// takes effect on tasks that have one (see TaskItem.spawnNextOccurrence).
enum RecurrenceRule: String, CaseIterable, Codable, Sendable {
    case daily, weekdays, weekly, monthly

    var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
            }
            return next
        }
    }
}

// Where a task sits in the Decision Board workflow. "Suggested" is intentionally not a
// case here — it's a computed top-ranked subset of `.general` tasks (see NextMoveEngine
// and DecisionBoardView), not something a task is ever persisted into directly.
enum TaskStage: String, CaseIterable, Codable, Sendable {
    case general, ready, scheduled, inProgress, done

    // Matches the Decision Board's column titles exactly (In Progress, not "Doing";
    // Completed, not "Done") so the inspector's stage chip never disagrees with the board.
    var label: String {
        switch self {
        case .general: return "General"
        case .ready: return "Ready"
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .done: return "Completed"
        }
    }

    // Smart starting lane for a newly created or imported task — a one-time
    // suggestion only. Stage is fully manual after this: dragging a card or filing
    // it Someday always sticks, nothing ever re-derives or overrides it later.
    static func suggestedInitial(forDueDate due: Date?, now: Date = .now) -> TaskStage {
        guard let due else { return .general }
        let calendar = Calendar.current
        if due < now || calendar.isDateInToday(due) || calendar.isDateInTomorrow(due) {
            return .ready
        }
        return .scheduled
    }
}

// Lightweight checklist item stored inline on a task. Codable value type so SwiftData
// can persist it as an attribute without a separate model/relationship.
struct Subtask: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
}

enum TaskEstimateSource {
    case explicit
    case subtasks
    case wording
    case defaultPlanning
}

struct TaskDurationEstimate {
    let minutes: Int
    let source: TaskEstimateSource
    // Internal diagnostic only (e.g. "20 base + 3×15 steps") — never shown in UI.
    // friendlyReasonText below is what's safe to display.
    let basis: String

    var isInferred: Bool { source != .explicit }

    var shortLabel: String {
        let prefix = isInferred ? "≈" : "~"
        guard minutes >= 60 else { return "\(prefix)\(minutes)m" }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(prefix)\(hours)h" : "\(prefix)\(hours)h \(remaining)m"
    }

    var friendlyReasonText: String {
        source == .explicit
            ? "About \(shortLabel.dropFirst()) set by you"
            : "About \(shortLabel.dropFirst()) based on task details"
    }
}

@Model final class TaskItem: Identifiable {
    @Attribute(.unique) var id: UUID
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
    // nil means "doesn't repeat". See spawnNextOccurrence below for what happens on completion.
    var recurrenceRule: RecurrenceRule?
    var sortIndex: Int?
    // Optional checklist of subtasks. Optional so existing stores migrate cleanly (nil == none).
    var subtasks: [Subtask]?

    // Optional at rest so stores created before Decision Board existed can be read safely.
    // `resolvedStage` supplies an immediate value until RootShellView backfills the row.
    var stage: TaskStage?
    // How long the task is expected to take, in minutes. Drives the Quick Win
    // recommendation and duration chip. This property is only user-entered data;
    // `planningEstimate` provides separately labeled inference when it is nil.
    var estimatedMinutes: Int?
    // The single task this one is waiting on, if any. Intentionally a single pointer
    // (not a multi-edge graph) — "blocks N tasks if delayed" for task T is just
    // `allTasks.filter { $0.dependsOnTaskID == T.id }.count`.
    var dependsOnTaskID: UUID?
    // Optional user-reported completion for work that does not need a checklist.
    var progressPercent: Int?
    // nil = active. Non-nil = sitting in Trash, recoverable until it's purged or
    // permanently deleted. RootShellView's main @Query excludes anything non-nil here,
    // so every existing view's filtering logic needed zero changes for Trash to exist.
    var deletedAt: Date?
    // Counts forward pushes only (moving a due date later) — set for the first time
    // doesn't count, and pulling a date earlier doesn't either. See RootShellView's
    // registerRescheduleIfNeeded.
    var rescheduleCount: Int = 0
    // First time stage becomes .inProgress. Paired with completedAt to estimate how
    // long a task actually took, for self-calibrating estimates — see calibrationNote.
    var startedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        category: String = "General",
        priority: TaskPriority? = .low,
        reminderSchedule: ReminderSchedule? = nil,
        customReminderMinutes: [Int]? = nil,
        recurrenceRule: RecurrenceRule? = nil,
        sortIndex: Int? = nil,
        subtasks: [Subtask]? = nil,
        stage: TaskStage = .general,
        estimatedMinutes: Int? = nil,
        dependsOnTaskID: UUID? = nil,
        progressPercent: Int? = nil,
        deletedAt: Date? = nil,
        rescheduleCount: Int = 0,
        startedAt: Date? = nil
    ) {
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
        self.recurrenceRule = recurrenceRule
        self.sortIndex = sortIndex
        self.subtasks = subtasks
        self.stage = stage
        self.estimatedMinutes = estimatedMinutes
        self.dependsOnTaskID = dependsOnTaskID
        self.progressPercent = progressPercent
        self.deletedAt = deletedAt
        self.rescheduleCount = rescheduleCount
        self.startedAt = startedAt
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

// MARK: - Schema Versioning (SwiftData)

// Names today's model shape as a baseline. Without this, schema identity is implicit —
// the first time a future change needs more than a new optional property (a non-optional
// field, a rename, splitting a model), there's no prior version to migrate from and
// existing users' stores would have no safe upgrade path. A future breaking change adds
// `SchemaV2` plus a corresponding stage in `QuickTodoMigrationPlan.stages`.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [TaskItem.self, CategoryItem.self] }
}

enum QuickTodoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// Convenience query helpers
extension TaskItem {
    var resolvedStage: TaskStage {
        if let stage { return stage }
        if isCompleted { return .done }
        return dueDate == nil ? .general : .scheduled
    }

    static func upcomingPredicate(includeDone: Bool = false) -> Predicate<TaskItem> {
        if includeDone { return #Predicate<TaskItem> { _ in true } }
        return #Predicate<TaskItem> { !$0.isCompleted }
    }
}

extension TaskItem {
    // Called wherever a task gets marked done (checkbox, progress hitting 100%, the
    // "Mark Done" notification action). No-op unless the task repeats and has a due
    // date to advance from. Inserts a fresh, not-yet-completed copy rather than
    // resetting this one, so the just-finished instance still shows up in Completed.
    @discardableResult
    func spawnNextOccurrence(in context: ModelContext) -> TaskItem? {
        guard let rule = recurrenceRule, let due = dueDate else { return nil }
        let siblingSortIndexes = (try? context.fetch(FetchDescriptor<TaskItem>()))?.compactMap(\.sortIndex) ?? []
        let nextSortIndex = (siblingSortIndexes.max() ?? siblingSortIndexes.count) + 1
        let next = TaskItem(
            title: title, notes: notes, dueDate: rule.nextDate(after: due),
            category: category, priority: priority,
            reminderSchedule: reminderSchedule, customReminderMinutes: customReminderMinutes,
            recurrenceRule: rule, sortIndex: nextSortIndex, stage: .scheduled,
            estimatedMinutes: estimatedMinutes
        )
        context.insert(next)
        return next
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

    // Planning duration: explicit input wins; otherwise use visible task structure and
    // wording. The inference is never persisted as user-entered data and is labeled in UI.
    var planningEstimate: TaskDurationEstimate {
        if let estimatedMinutes {
            return TaskDurationEstimate(minutes: estimatedMinutes, source: .explicit, basis: "User estimate")
        }

        let noteWords = notes.split(whereSeparator: { $0.isWhitespace }).count
        let detailMinutes = min(30, (noteWords / 10) * 5)

        if !subtaskList.isEmpty {
            let raw = 20 + subtaskList.count * 15 + detailMinutes
            let rounded = Self.roundPlanningMinutes(raw)
            let detail = detailMinutes > 0 ? " + \(detailMinutes) detail" : ""
            return TaskDurationEstimate(
                minutes: rounded,
                source: .subtasks,
                basis: "20 base + \(subtaskList.count)×15 steps\(detail)"
            )
        }

        let text = "\(title) \(notes)".lowercased()
        let words = Set(
            text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        func matches(_ term: String) -> Bool {
            term.contains(" ") ? text.contains(term) : words.contains(term)
        }
        let rules: [(terms: [String], minutes: Int, label: String)] = [
            (["research", "researching"], 50, "research +50"),
            (["prepare", "preparing", "study", "studying"], 40, "prepare/study +40"),
            (["build", "building", "develop", "developing", "design", "designing"], 45, "build/design +45"),
            (["write", "writing", "report", "proposal", "presentation"], 35, "writing +35"),
            (["debug", "debugging", "fix", "fixing"], 30, "debug/fix +30"),
            (["review", "reviewing", "analyze", "analyzing"], 25, "review/analyze +25"),
            (["plan", "planning"], 20, "planning +20"),
            (["workout", "deep work"], 30, "focused session +30")
        ]

        var rawMinutes = 25
        var components = ["25 base"]
        var matchedSignal = false
        for rule in rules where rule.terms.contains(where: matches) {
            rawMinutes += rule.minutes
            components.append(rule.label)
            matchedSignal = true
        }

        let shortSignals = [
            "email", "call", "reply", "text", "buy", "pick up", "schedule", "book",
            "submit", "pay", "renew", "confirm", "send", "quiz", "test", "exam"
        ]
        if shortSignals.contains(where: matches) {
            rawMinutes -= 10
            components.append("quick action -10")
            matchedSignal = true
        }

        let titleWords = title.split(whereSeparator: { $0.isWhitespace }).count
        let titleComplexity = min(10, max(0, titleWords - 4) * 2)
        if titleComplexity > 0 {
            rawMinutes += titleComplexity
            components.append("title detail +\(titleComplexity)")
        }
        if detailMinutes > 0 {
            rawMinutes += detailMinutes
            components.append("description +\(detailMinutes)")
        }

        let rounded = Self.roundPlanningMinutes(rawMinutes)
        return TaskDurationEstimate(
            minutes: rounded,
            source: matchedSignal || detailMinutes > 0 || titleComplexity > 0 ? .wording : .defaultPlanning,
            basis: components.joined(separator: " + ")
        )
    }

    private static func roundPlanningMinutes(_ minutes: Int) -> Int {
        let clamped = min(240, max(10, minutes))
        return Int((Double(clamped) / 5).rounded()) * 5
    }

    var isQuickWin: Bool {
        guard !isCompleted, subtaskList.isEmpty else { return false }
        return planningEstimate.minutes <= 20
    }

    // Real, derived — never guessed. Which other tasks are waiting on this one.
    func blockedTasks(in allTasks: [TaskItem]) -> [TaskItem] {
        allTasks.filter { $0.dependsOnTaskID == id }
    }

    func blockedTaskCount(in allTasks: [TaskItem]) -> Int {
        blockedTasks(in: allTasks).count
    }

    // True only while the task this one depends on still exists and isn't done yet.
    // If the dependency was deleted (or is itself done), nothing is blocking anymore.
    func isBlocked(in allTasks: [TaskItem]) -> Bool {
        guard let dependsOnTaskID else { return false }
        guard let blocker = allTasks.first(where: { $0.id == dependsOnTaskID }) else { return false }
        return !blocker.isCompleted
    }

    // Looks at your own history of completed tasks in the same category that had
    // both an explicit estimate and were actually timed (started -> completed), and
    // returns the average actual/estimated ratio. Needs a few data points before it
    // means anything — nil rather than guessing from too little history.
    // Compares against planningEstimate, not the raw estimatedMinutes field — every
    // task already gets an automatic estimate (explicit if you typed one, inferred
    // from subtasks/wording otherwise), so calibration shouldn't require you to have
    // typed in a number. "Start Now" already sets startedAt; this just compares that
    // against whatever this app would have predicted, however it got predicted.
    static func calibrationRatio(forCategory category: String, in allTasks: [TaskItem]) -> Double? {
        let ratios = allTasks.compactMap { task -> Double? in
            guard task.category.caseInsensitiveCompare(category) == .orderedSame,
                  task.isCompleted,
                  let started = task.startedAt,
                  let completed = task.completedAt
            else { return nil }
            let actualMinutes = completed.timeIntervalSince(started) / 60
            let predictedMinutes = Double(task.planningEstimate.minutes)
            guard actualMinutes > 0, predictedMinutes > 0 else { return nil }
            return actualMinutes / predictedMinutes
        }
        guard ratios.count >= 3 else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    // A plain-language add-on for the duration chip's tooltip. Only appears once
    // there's enough of your own history in this category to say something real.
    func calibrationNote(in allTasks: [TaskItem]) -> String? {
        guard let ratio = TaskItem.calibrationRatio(forCategory: category, in: allTasks) else { return nil }
        let percent = Int(((ratio - 1) * 100).rounded())
        if abs(percent) < 10 { return "Your \(category) tasks usually match their estimate." }
        if percent > 0 {
            return "Your \(category) tasks usually run about \(percent)% longer than estimated."
        }
        return "Your \(category) tasks usually finish about \(abs(percent))% faster than estimated."
    }
}

// Shared ordering for every task list/column in the app: active before done, then manual
// sort order, then priority, then soonest due date, then creation order.
extension Array where Element == TaskItem {
    func sortedForDisplay() -> [TaskItem] {
        sorted { a, b in
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
    }

    // For views with no manual drag order (General, Today, Upcoming, Lists): due date
    // and time lead, since that's what those views are organized around, so a task
    // due soon doesn't get buried under older tasks. Tasks with no due date fall back
    // to newest-first — without a date or a drag order, "what did I just add" is the
    // only sensible default, instead of leaving a fresh task to sink to the bottom.
    func sortedChronologically() -> [TaskItem] {
        sorted { a, b in
            switch (a.isCompleted, b.isCompleted) {
            case (true, false): return false
            case (false, true): return true
            default:
                switch (a.dueDate, b.dueDate) {
                case let (d1?, d2?):
                    if d1 != d2 { return d1 < d2 }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
                let priA = a.priority ?? .low
                let priB = b.priority ?? .low
                if priA != priB { return priA < priB }
                return a.createdAt > b.createdAt
            }
        }
    }
}

// Friendly relative-date label shared by task cards and the inspector.
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
