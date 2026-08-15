// NextMoveEngine.swift
// The recommendation engine behind the "Next Move" inspector. Pure function over real
// task fields — due date, priority, estimate, dependencies, and (optionally) the user's
// configured focus window. Never persisted, never fabricated: if a signal isn't there,
// the corresponding reason is simply omitted.

import Foundation

enum NextMoveAction: String, Codable, CaseIterable, Sendable, Equatable {
    case startNow, schedule, breakIntoSteps, file, quickWin

    var label: String {
        switch self {
        case .startNow: return "Start Now"
        case .schedule: return "Schedule"
        case .breakIntoSteps: return "Break Into Steps"
        case .file: return "File / Someday"
        case .quickWin: return "Quick Win"
        }
    }

    var icon: String {
        switch self {
        case .startNow: return "play.fill"
        case .schedule: return "calendar"
        case .breakIntoSteps: return "arrow.triangle.branch"
        case .file: return "folder"
        case .quickWin: return "bolt.fill"
        }
    }
}

struct NextMoveReason: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

struct NextMoveRecommendation {
    let action: NextMoveAction
    let headline: String
    let summary: String
    let reasons: [NextMoveReason]
}

// Thin wrapper around the focus-window preference set in Settings. Stored via plain
// UserDefaults keys (not @AppStorage, since this is read from a non-View context) —
// SettingsView's @AppStorage properties use these same key strings.
enum FocusWindowSettings {
    static let enabledKey = "focusWindowEnabled"
    static let startKey = "focusWindowStartMinutes"
    static let endKey = "focusWindowEndMinutes"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var startMinutes: Int { UserDefaults.standard.integer(forKey: startKey) }
    static var endMinutes: Int { UserDefaults.standard.integer(forKey: endKey) }

    static func label(start: Int, end: Int) -> String {
        func format(_ minutes: Int) -> String {
            var comps = DateComponents()
            comps.hour = minutes / 60
            comps.minute = minutes % 60
            let date = Calendar.current.date(from: comps) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        }
        return "\(format(start))\u{2013}\(format(end))"
    }

    // True if today's configured window is currently active or still ahead.
    static func isUpcomingOrActiveToday(_ now: Date = .now) -> Bool {
        guard isEnabled, endMinutes > startMinutes else { return false }
        let calendar = Calendar.current
        let minutesNow = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return minutesNow < endMinutes
    }
}

enum NextMoveEngine {
    // nil for completed tasks — the inspector shows a "Completed" state instead.
    static func recommend(for task: TaskItem, in allTasks: [TaskItem], now: Date = .now) -> NextMoveRecommendation? {
        guard !task.isCompleted else { return nil }

        let calendar = Calendar.current
        let priority = task.priority ?? .low
        let duration = task.planningEstimate
        let blockedCount = task.blockedTaskCount(in: allTasks)
        let isOverdue = task.dueDate.map { $0 < now } ?? false
        let dueWithin4h = task.dueDate.map { $0 >= now && $0 <= now.addingTimeInterval(4 * 3600) } ?? false
        let dueWithinWeek = task.dueDate.map { $0 >= now && $0 <= now.addingTimeInterval(7 * 24 * 3600) } ?? false
        let focusActive = FocusWindowSettings.isUpcomingOrActiveToday(now)

        func dueReason() -> NextMoveReason? {
            guard let due = task.dueDate else { return nil }
            if due < now {
                let elapsed = now.timeIntervalSince(due)
                if elapsed < 3600 {
                    let minutes = max(1, Int(elapsed / 60))
                    return NextMoveReason(icon: "calendar", text: "Overdue by \(minutes) minute\(minutes == 1 ? "" : "s")")
                }
                if elapsed < 24 * 3600 {
                    let hours = max(1, Int(elapsed / 3600))
                    return NextMoveReason(icon: "calendar", text: "Overdue by \(hours) hour\(hours == 1 ? "" : "s")")
                }
                let days = max(1, Int(elapsed / (24 * 3600)))
                return NextMoveReason(icon: "calendar", text: "Overdue by \(days) day\(days == 1 ? "" : "s")")
            }
            if calendar.isDateInToday(due) {
                return NextMoveReason(icon: "calendar", text: "Due today")
            }
            let days = max(1, calendar.dateComponents([.day], from: now, to: due).day ?? 1)
            return NextMoveReason(icon: "calendar", text: "Due in \(days) day\(days == 1 ? "" : "s")")
        }

        func impactReason() -> NextMoveReason? {
            guard priority == .high else { return nil }
            return NextMoveReason(icon: "flag.fill", text: "High priority")
        }

        func focusReason() -> NextMoveReason? {
            guard focusActive else { return nil }
            return NextMoveReason(
                icon: "clock",
                text: "Preferred focus window: Today, \(FocusWindowSettings.label(start: FocusWindowSettings.startMinutes, end: FocusWindowSettings.endMinutes))"
            )
        }

        func blockReason() -> NextMoveReason? {
            guard blockedCount > 0 else { return nil }
            return NextMoveReason(icon: "link", text: "Blocks \(blockedCount) task\(blockedCount == 1 ? "" : "s") if delayed")
        }

        func estimateReason() -> NextMoveReason? {
            NextMoveReason(icon: "timer", text: duration.friendlyReasonText)
        }

        // 1. Once a deadline has passed, acting is always the first recommendation.
        if isOverdue {
            let reasons = [dueReason(), impactReason(), focusReason(), estimateReason(), blockReason()].compactMap { $0 }
            return NextMoveRecommendation(
                action: .startNow,
                headline: "Start this overdue task now",
                summary: "The deadline has passed. Starting now is the clearest way to reduce the delay and move this task toward completion.",
                reasons: reasons
            )
        }

        // 2. A deadline within four hours is concrete pressure, not a scheduling case.
        if dueWithin4h {
            let reasons = [dueReason(), impactReason(), focusReason(), estimateReason(), blockReason()].compactMap { $0 }
            return NextMoveRecommendation(
                action: .startNow,
                headline: "Start now \u{2014} it's due soon",
                summary: "This task is due within four hours. Starting now gives you the remaining time to finish before its deadline.",
                reasons: reasons
            )
        }

        // High-impact work with a real focus window deserves an intentional start even
        // when its deadline is more than a few hours away.
        if priority == .high, focusActive, dueWithinWeek, duration.minutes >= 60 {
            let reasons = [dueReason(), impactReason(), focusReason(), estimateReason(), blockReason()].compactMap { $0 }
            let length = max(1, (FocusWindowSettings.endMinutes - FocusWindowSettings.startMinutes) / 60)
            return NextMoveRecommendation(
                action: .startNow,
                headline: "Use your focus window",
                summary: "You configured a \(length)-hour focus window today, this task is high priority, and its planned duration is about \(duration.minutes) minutes. Use that window for focused progress.",
                reasons: reasons
            )
        }

        // 2. Short and uncomplicated — clear it now.
        if task.isQuickWin {
            let reasons = [estimateReason(), dueReason()].compactMap { $0 }
            return NextMoveRecommendation(
                action: .quickWin,
                headline: "Knock this out now",
                summary: duration.isInferred
                    ? "QuickToDo estimates this at about \(duration.minutes) minutes from its wording, and it has no subtasks. It is a reasonable quick win."
                    : "You estimated this at \(duration.minutes) minutes and it has no subtasks. It is a reasonable quick win.",
                reasons: reasons
            )
        }

        // 3. Substantial and high priority but no plan yet — decompose before starting.
        // The duration floor matters: with no estimate, a plain title like "Take
        // Chapter 5 Quiz" still infers ~25-30 minutes from wording alone, which isn't
        // "substantial" — there's nothing to break into steps. Only wording that
        // actually signals real complexity (research, build, write, etc. — see
        // planningEstimate) pushes the inferred minutes past this floor.
        if priority == .high, task.subtaskList.isEmpty, task.estimatedMinutes == nil, duration.minutes >= 45 {
            let reasons = [impactReason(), dueReason()].compactMap { $0 }
            return NextMoveRecommendation(
                action: .breakIntoSteps,
                headline: "Break this into steps first",
                summary: "You marked this high priority, but it has no explicit estimate or subtasks. Add concrete steps before committing to the work.",
                reasons: reasons
            )
        }

        // 4. Nothing pulling on it — file for later.
        if task.dueDate == nil, priority != .high {
            return NextMoveRecommendation(
                action: .file,
                headline: "File for later",
                summary: "This task has no due date and is not high priority. Filing it in General keeps it available without treating it as scheduled work.",
                reasons: [
                    NextMoveReason(icon: "calendar.badge.minus", text: "No due date"),
                    NextMoveReason(icon: "flag", text: "\(priority.label) priority")
                ]
            )
        }

        // 5. Has a date, just further out — leave it scheduled.
        if task.dueDate != nil {
            let reasons = [dueReason(), impactReason(), blockReason()].compactMap { $0 }
            return NextMoveRecommendation(
                action: .schedule,
                headline: "Keep it scheduled",
                summary: "Its due date is in the future and outside the immediate four-hour window. Keep it scheduled and revisit it before the deadline.",
                reasons: reasons
            )
        }

        // 6. A high-priority task without a date needs a real schedule.
        return NextMoveRecommendation(
            action: .schedule,
            headline: "Choose a deadline",
            summary: "You marked this task high priority, but it has no due date. Schedule it so the priority is tied to a concrete plan.",
            reasons: [
                NextMoveReason(icon: "flag.fill", text: "High priority"),
                NextMoveReason(icon: "calendar.badge.minus", text: "No due date")
            ]
        )
    }

    // Ranked candidates for the Suggested column and focus-area card: earliest due
    // date first (overdue counts as earliest of all), undated tasks last, capped by
    // the caller. Purely date-driven by design — priority/blocking/quick-win are
    // still explained in recommend()'s reasons, but they no longer affect ordering.
    static func suggested(from generalTasks: [TaskItem], in allTasks: [TaskItem], limit: Int, now: Date = .now) -> [TaskItem] {
        Array(
            generalTasks
                .filter { !$0.isCompleted }
                .sorted(by: earliestDueDateFirst)
                .prefix(limit)
        )
    }

    private static func earliestDueDateFirst(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (d1?, d2?): if d1 != d2 { return d1 < d2 }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        return a.createdAt < b.createdAt
    }
}

extension TaskItem {
    // Walks the dependsOnTaskID chain to make sure picking `candidateID` as this task's
    // dependency wouldn't create a cycle (candidate already depends on this task,
    // directly or transitively).
    func wouldCreateCycle(dependingOn candidateID: UUID, in allTasks: [TaskItem]) -> Bool {
        var current: UUID? = candidateID
        var hops = 0
        while let currentID = current, hops < allTasks.count {
            if currentID == id { return true }
            current = allTasks.first(where: { $0.id == currentID })?.dependsOnTaskID
            hops += 1
        }
        return false
    }
}

#if DEBUG
enum NextMoveEngineSelfTest {
    static func run() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let overdue = TaskItem(
            title: "Overdue", dueDate: now.addingTimeInterval(-3600),
            category: "General", priority: .medium, stage: .scheduled
        )
        let overdueResult = NextMoveEngine.recommend(for: overdue, in: [overdue], now: now)
        assert(overdueResult?.action == .startNow)
        assert(overdueResult?.headline.localizedCaseInsensitiveContains("overdue") == true)

        let future = TaskItem(
            title: "Future", dueDate: now.addingTimeInterval(2 * 24 * 3600),
            category: "General", priority: .medium, stage: .scheduled
        )
        assert(NextMoveEngine.recommend(for: future, in: [future], now: now)?.action == .schedule)

        let quickWin = TaskItem(
            title: "Quick", category: "General", priority: .low,
            stage: .general, estimatedMinutes: 15
        )
        assert(NextMoveEngine.recommend(for: quickWin, in: [quickWin], now: now)?.action == .quickWin)

        let undated = TaskItem(title: "Undated", category: "General", priority: .low, stage: .general)
        assert(NextMoveEngine.recommend(for: undated, in: [undated], now: now)?.action == .file)
    }
}
#endif
