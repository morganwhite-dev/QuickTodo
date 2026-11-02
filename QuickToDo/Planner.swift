// Planner.swift
// Pure scheduling maths shared by the Decision Board, Upcoming and the free-time blocks.
// No SwiftUI, no SwiftData writes: every number the screens show about "minutes of work",
// "done n/total" and "free time" comes from here, so they can't drift apart.

import Foundation

enum Planner {
    /// Free blocks shorter than this are not worth showing.
    static let minFreeMinutes = 30
    /// Timeline starts at 8 AM unless a task is earlier.
    static let dayStartHour = 8

    struct FreeBlock: Identifiable, Equatable {
        let start: Date
        let end: Date
        var id: TimeInterval { start.timeIntervalSinceReferenceDate }
        var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
    }

    static func minutes(of task: TaskItem) -> Int { task.planningEstimate.minutes }

    // MARK: Overdue / today — the one definition every screen uses
    // (Today tab, its tiles, nav badge, Dock badge, Lists chips, Board counts), so the
    // numbers can never drift apart.

    /// Open and past its due date/time.
    static func isOverdue(_ t: TaskItem, now: Date = .now) -> Bool {
        guard !t.isCompleted, let due = t.dueDate else { return false }
        return due < now
    }

    /// Open, due later today (not yet past due).
    static func isDueLaterToday(_ t: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !t.isCompleted, let due = t.dueDate else { return false }
        return due >= now && calendar.isDate(due, inSameDayAs: now)
    }

    /// What the Today tab shows: overdue plus due-later-today. Tomorrow onward is Upcoming.
    static func isOnTodayTab(_ t: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        isOverdue(t, now: now) || isDueLaterToday(t, now: now, calendar: calendar)
    }

    /// "35m", "2h", "4h 45m".
    static func label(minutes: Int) -> String {
        let m = max(0, minutes)
        guard m >= 60 else { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    /// Short "when is this due" text for chips: "Today · 5:30 PM", "Tomorrow · 9 AM", "Tue · 5:30 PM"
    /// (within the next 6 days), "Nov 12 · 11:59 PM" (further out), "Yesterday" / "Oct 28" for the past.
    /// Date-only tasks drop the time.
    static func compactDue(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let day: String
        if calendar.isDateInToday(date) { day = "Today" }
        else if calendar.isDateInTomorrow(date) { day = "Tomorrow" }
        else if calendar.isDateInYesterday(date) { day = "Yesterday" }
        else {
            let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
            day = (1...6).contains(diff)
                ? date.formatted(.dateTime.weekday(.abbreviated))
                : date.formatted(.dateTime.month(.abbreviated).day())
        }
        guard hasClockTime(date, calendar: calendar) else { return day }
        return day + " · " + date.formatted(date: .omitted, time: .shortened)
    }

    static func hasClockTime(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.hour, from: date) != 0 || calendar.component(.minute, from: date) != 0
    }

    /// Every task (open or done) due on `day`, soonest first.
    static func tasks(on day: Date, in tasks: [TaskItem], calendar: Calendar = .current) -> [TaskItem] {
        tasks.filter { t in
            guard let due = t.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }
        .sorted { ($0.dueDate ?? .distantFuture, $0.createdAt) < ($1.dueDate ?? .distantFuture, $1.createdAt) }
    }

    static func openMinutes(_ tasks: [TaskItem]) -> Int {
        tasks.filter { !$0.isCompleted }.reduce(0) { $0 + minutes(of: $1) }
    }

    /// Free time rule: free time is only the gaps between tasks that already existed.
    ///
    /// The gaps are measured against *every* task due that day, including finished ones.
    /// A finished task therefore keeps anchoring the gaps on either side of it: ticking it
    /// closes its slot up but never merges that time into a neighbouring free block, and
    /// unticking it puts it back exactly where it was. Only untimed (date-only) tasks are
    /// ignored, since they don't occupy a slot. There is deliberately no trailing block
    /// after the last task ("Nothing else due after this").
    static func freeBlocks(forDay dayTasks: [TaskItem], day: Date, calendar: Calendar = .current) -> [FreeBlock] {
        let timed = dayTasks.compactMap { t -> (start: Date, end: Date)? in
            guard let due = t.dueDate, hasClockTime(due, calendar: calendar) else { return nil }
            return (due, due.addingTimeInterval(Double(minutes(of: t)) * 60))
        }
        .sorted { $0.start < $1.start }
        guard let first = timed.first else { return [] }

        let eight = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: day) ?? day
        var cursor = min(eight, first.start)
        var blocks: [FreeBlock] = []
        for slot in timed {
            if slot.start.timeIntervalSince(cursor) >= Double(minFreeMinutes) * 60 {
                blocks.append(FreeBlock(start: cursor, end: slot.start))
            }
            cursor = max(cursor, slot.end)
        }
        return blocks
    }

    // MARK: Week summary (Decision Board "This week" panel)

    struct WeekSummary: Equatable {
        var total = 0
        var done = 0
        var overdue = 0
        var minutesLeft = 0
    }

    /// Tasks due from the start of today through the next 6 days, plus anything still open
    /// and overdue. A task finished today stays in the count even if it was overdue, so
    /// ticking it moves "done" up and "minutes left" down without changing the total.
    static func weekTasks(_ tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> [TaskItem] {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: today) ?? now
        return tasks.filter { t in
            guard let due = t.dueDate else { return false }
            if due >= end { return false }
            if due >= today { return true }
            if !t.isCompleted { return true }
            return (t.completedAt ?? .distantPast) >= today
        }
    }

    static func weekSummary(_ tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> WeekSummary {
        let week = weekTasks(tasks, now: now, calendar: calendar)
        var s = WeekSummary()
        s.total = week.count
        s.done = week.filter(\.isCompleted).count
        s.overdue = week.filter { isOverdue($0, now: now) }.count
        s.minutesLeft = openMinutes(week)
        return s
    }

    /// The Decision Board's Next Move: an overdue task always wins (earliest first), then
    /// the soonest due, undated last. Blocked tasks can't be started so they never qualify.
    static func nextMove(from tasks: [TaskItem], now: Date = .now) -> TaskItem? {
        let candidates = tasks.filter { !$0.isCompleted && !$0.isBlocked(in: tasks) }
        let overdue = candidates.filter { ($0.dueDate ?? .distantFuture) < now }
        let pool = overdue.isEmpty ? candidates : overdue
        return NextMoveEngine.suggested(from: pool, in: tasks, limit: 1, now: now).first
    }
}

/// Remembers which Decision Board lane a task was in when it was completed, so undoing the
/// tick (from the board pill, the Completed tab, the inspector, or the undo toast) always puts
/// it back in that same lane. Kept in UserDefaults rather than on TaskItem so the saved
/// SwiftData model is not touched.
enum StageMemory {
    private static let key = "stageBeforeDoneV1"

    private static var store: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func remember(_ task: TaskItem) {
        let stage = task.resolvedStage
        guard stage != .done else { return }
        store[task.id.uuidString] = stage.rawValue
    }

    /// The remembered lane, removed from memory once used.
    static func recall(_ id: UUID) -> TaskStage? {
        var s = store
        guard let raw = s.removeValue(forKey: id.uuidString) else { return nil }
        store = s
        return TaskStage(rawValue: raw)
    }

    static func forget(_ id: UUID) {
        var s = store
        if s.removeValue(forKey: id.uuidString) != nil { store = s }
    }
}
