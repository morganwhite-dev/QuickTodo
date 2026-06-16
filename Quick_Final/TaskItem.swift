import Foundation
import SwiftData

@Model
final class TaskItem: Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date

    // Extended fields for Calendar-like creation
    var dueDate: Date?
    var isAllDay: Bool
    var repeatRuleRaw: String?
    var alertsRaw: [TimeInterval]?
    var notes: String?
    var category: Category?

    // Completion state
    var isCompleted: Bool
    var completedAt: Date?

    // Checklist relationship
    var checklist: [ChecklistItem]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date,
        dueDate: Date? = nil,
        isAllDay: Bool = false,
        repeatRuleRaw: String? = nil,
        alertsRaw: [TimeInterval]? = nil,
        notes: String? = nil,
        category: Category? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        checklist: [ChecklistItem] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.isAllDay = isAllDay
        self.repeatRuleRaw = repeatRuleRaw
        self.alertsRaw = alertsRaw
        self.notes = notes
        self.category = category
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.checklist = checklist
    }
}

// Convenience computed properties for Alerts
extension TaskItem {
    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRuleRaw ?? RepeatRule.none.rawValue) ?? .none }
        set { repeatRuleRaw = newValue.rawValue }
    }

    var alertOffsets: [TimeInterval] {
        get { alertsRaw ?? [] }
        set { alertsRaw = newValue }
    }
}

// Convenience status helpers
extension TaskItem {
    var isOverdue: Bool {
        guard !isCompleted, let due = dueDate else { return false }
        return due < Date()
    }

    var isDueToday: Bool {
        guard let due = dueDate else { return false }
        return Calendar.current.isDateInToday(due)
    }
}
