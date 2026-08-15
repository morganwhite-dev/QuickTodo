// SimpleListViews.swift
// Focused task lists for the non-board destinations in the sidebar. Tasks are grouped
// into small dated/prioritized sections (Overdue, Today, Tomorrow, etc.) instead of one
// flat list under a row of stat tiles — gives each view real structure without eating
// vertical space on boxes that just restate a number shown right above them.

import SwiftUI

// Matches BoardColumnView's empty-lane styling instead of the generic system look.
struct EmptyStateCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.mutedText)
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GeneralListView: View {
    let tasks: [TaskItem]
    let categories: [CategoryItem]
    @Binding var search: String
    @Binding var selectedTask: TaskItem?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onNewTask: () -> Void
    let onBulkComplete: (Set<UUID>) -> Void
    let onBulkDelete: (Set<UUID>) -> Void

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    private var generalTasks: [TaskItem] {
        let base = tasks.filter { !$0.isCompleted && $0.resolvedStage == .general }
        let filtered = search.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
        return filtered.sortedChronologically()
    }

    private var highPriority: [TaskItem] { generalTasks.filter { ($0.priority ?? .low) == .high } }
    private var mediumPriority: [TaskItem] { generalTasks.filter { ($0.priority ?? .low) == .medium } }
    private var lowPriority: [TaskItem] { generalTasks.filter { ($0.priority ?? .low) == .low } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ListHeaderBar(title: "General", subtitle: "Captured tasks waiting to be clarified.", icon: "tray", accent: Theme.general) {
                SelectModeButton(isSelecting: $isSelecting) { isSelecting = false; selectedIDs = [] }
                Button(action: onNewTask) { Label("New Task", systemImage: "plus") }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .modifier(HoverButtonModifier())
            }

            if isSelecting {
                BulkActionBar(
                    count: selectedIDs.count,
                    onComplete: { onBulkComplete(selectedIDs); selectedIDs = [] },
                    onDelete: { onBulkDelete(selectedIDs); selectedIDs = [] },
                    onCancel: { isSelecting = false; selectedIDs = [] }
                )
            } else {
                ListSearchField(text: $search)
            }

            if generalTasks.isEmpty {
                EmptyStateCard(icon: "tray", title: "No Tasks", detail: "Nothing matches this view yet.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            TaskSection(title: "High Priority", tint: Theme.critical, tasks: highPriority, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                            TaskSection(title: "Medium Priority", tint: Theme.warning, tasks: mediumPriority, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                            TaskSection(title: "Low Priority", tint: Theme.general, tasks: lowPriority, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                        }
                    }
                    .onChange(of: selectedTask?.id) { _, newID in
                        guard let newID, generalTasks.contains(where: { $0.id == newID }) else { return }
                        withAnimation { proxy.scrollTo(newID, anchor: .center) }
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.bg)
    }
}

// Full-width "what to do next" + stats strip, same chrome as DecisionPulseView on the
// board page. The headline comes straight from NextMoveEngine instead of a static
// summary, so the recommended task is visible without selecting anything first —
// putting the Next Move suggestion to work at the top of the page instead of only
// in the side inspector.
private struct TodayPulseView: View {
    let tasks: [TaskItem]
    let allTasks: [TaskItem]
    let onSelect: (TaskItem) -> Void

    private var incomplete: [TaskItem] { tasks.filter { !$0.isCompleted } }
    private var overdueCount: Int { incomplete.filter { $0.dueDate.map { $0 < Date() } ?? false }.count }
    private var todayCount: Int { incomplete.filter { $0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false }.count }
    private var tomorrowCount: Int { incomplete.filter { $0.dueDate.map { Calendar.current.isDateInTomorrow($0) } ?? false }.count }
    private var totalMinutes: Int { incomplete.reduce(0) { $0 + $1.planningEstimate.minutes } }

    private var topPick: TaskItem? {
        let candidates = incomplete.filter { $0.resolvedStage != .inProgress }
        return NextMoveEngine.suggested(from: candidates, in: allTasks, limit: 1).first
    }
    private var recommendation: NextMoveRecommendation? {
        topPick.flatMap { NextMoveEngine.recommend(for: $0, in: allTasks) }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                    Text("NEXT MOVE").tracking(1.2)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.accent)

                if let topPick, let recommendation {
                    Button(action: { onSelect(topPick) }) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recommendation.headline)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(topPick.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.mutedText)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .modifier(HoverButtonModifier())
                } else {
                    Text("All clear")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Nothing in Today needs a decision right now.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.mutedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DecisionStat(label: "Overdue", value: "\(overdueCount)", icon: "exclamationmark.triangle", tint: Theme.critical)
            DecisionStat(label: "Today", value: "\(todayCount)", icon: "sun.max", tint: Theme.accent)
            DecisionStat(label: "Tomorrow", value: "\(tomorrowCount)", icon: "moon", tint: Theme.warning)
            DecisionStat(label: "Est. Time", value: formattedTotal, icon: "timer", tint: Theme.mutedText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.panelBorder, lineWidth: 1)
        )
    }

    private var formattedTotal: String {
        guard totalMinutes > 0 else { return "0m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

struct TodayView: View {
    let tasks: [TaskItem]
    let categories: [CategoryItem]
    @Binding var search: String
    @Binding var selectedTask: TaskItem?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onNewTask: () -> Void
    let onBulkComplete: (Set<UUID>) -> Void
    let onBulkDelete: (Set<UUID>) -> Void

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    private let calendar = Calendar.current
    private let now = Date()

    // Overdue work belongs in Today too — a task due yesterday shouldn't vanish from
    // every simple list just because it's no longer due "today" by the calendar.
    private var slice: [TaskItem] {
        let base = tasks.filter { task in
            guard !task.isCompleted, let due = task.dueDate else { return false }
            return due < now || calendar.isDateInToday(due) || calendar.isDateInTomorrow(due)
        }
        let filtered = search.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
        return filtered.sortedChronologically()
    }

    private var overdue: [TaskItem] { slice.filter { ($0.dueDate.map { $0 < now }) ?? false } }
    private var dueToday: [TaskItem] {
        slice.filter { task in
            guard let due = task.dueDate else { return false }
            return due >= now && calendar.isDateInToday(due)
        }
    }
    private var dueTomorrow: [TaskItem] {
        slice.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDateInTomorrow(due)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ListHeaderBar(title: "Today", subtitle: "Overdue, due today, and due tomorrow.", icon: "sun.max", accent: Theme.accent) {
                SelectModeButton(isSelecting: $isSelecting) { isSelecting = false; selectedIDs = [] }
                Button(action: onNewTask) { Label("New Task", systemImage: "plus") }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .modifier(HoverButtonModifier())
            }

            TodayPulseView(tasks: slice, allTasks: tasks, onSelect: { selectedTask = $0 })

            if isSelecting {
                BulkActionBar(
                    count: selectedIDs.count,
                    onComplete: { onBulkComplete(selectedIDs); selectedIDs = [] },
                    onDelete: { onBulkDelete(selectedIDs); selectedIDs = [] },
                    onCancel: { isSelecting = false; selectedIDs = [] }
                )
            } else {
                ListSearchField(text: $search)
            }

            if slice.isEmpty {
                EmptyStateCard(icon: "sun.max", title: "No Tasks", detail: "Nothing matches this view yet.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            TaskSection(title: "Overdue", tint: Theme.critical, tasks: overdue, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                            TaskSection(title: "Today", tint: Theme.accent, tasks: dueToday, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                            TaskSection(title: "Tomorrow", tint: Theme.warning, tasks: dueTomorrow, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                        }
                    }
                    .onChange(of: selectedTask?.id) { _, newID in
                        guard let newID, slice.contains(where: { $0.id == newID }) else { return }
                        withAnimation { proxy.scrollTo(newID, anchor: .center) }
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.bg)
    }
}

struct UpcomingView: View {
    let tasks: [TaskItem]
    let categories: [CategoryItem]
    @Binding var search: String
    @Binding var selectedTask: TaskItem?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onNewTask: () -> Void
    let onBulkComplete: (Set<UUID>) -> Void
    let onBulkDelete: (Set<UUID>) -> Void

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    private let now = Date()
    private let calendar = Calendar.current

    private var slice: [TaskItem] {
        let base = tasks.filter { task in
            guard !task.isCompleted, let due = task.dueDate else { return false }
            return due > now && !calendar.isDateInToday(due)
        }
        let filtered = search.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
        return filtered.sortedChronologically()
    }

    private var thisWeek: [TaskItem] {
        let weekOut = now.addingTimeInterval(7 * 24 * 3600)
        return slice.filter { ($0.dueDate.map { $0 <= weekOut }) ?? false }
    }
    private var later: [TaskItem] {
        let weekOut = now.addingTimeInterval(7 * 24 * 3600)
        return slice.filter { ($0.dueDate.map { $0 > weekOut }) ?? false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ListHeaderBar(title: "Upcoming", subtitle: "Everything scheduled beyond today.", icon: "calendar", accent: Theme.onDeck) {
                SelectModeButton(isSelecting: $isSelecting) { isSelecting = false; selectedIDs = [] }
                Button(action: onNewTask) { Label("New Task", systemImage: "plus") }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .modifier(HoverButtonModifier())
            }

            if isSelecting {
                BulkActionBar(
                    count: selectedIDs.count,
                    onComplete: { onBulkComplete(selectedIDs); selectedIDs = [] },
                    onDelete: { onBulkDelete(selectedIDs); selectedIDs = [] },
                    onCancel: { isSelecting = false; selectedIDs = [] }
                )
            } else {
                ListSearchField(text: $search)
            }

            if slice.isEmpty {
                EmptyStateCard(icon: "calendar", title: "No Tasks", detail: "Nothing matches this view yet.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            TaskSection(title: "This Week", tint: Theme.accent, tasks: thisWeek, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                            TaskSection(title: "Later", tint: Theme.onDeck, tasks: later, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                        }
                    }
                    .onChange(of: selectedTask?.id) { _, newID in
                        guard let newID, slice.contains(where: { $0.id == newID }) else { return }
                        withAnimation { proxy.scrollTo(newID, anchor: .center) }
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.bg)
    }
}

struct CompletedView: View {
    let tasks: [TaskItem]
    let categories: [CategoryItem]
    @Binding var search: String
    @Binding var selectedTask: TaskItem?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onClearCompleted: () -> Void
    let onBulkDelete: (Set<UUID>) -> Void

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    private var completed: [TaskItem] {
        let base = tasks.filter(\.isCompleted)
        let filtered = search.isEmpty ? base : base.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
        return filtered.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private var today: [TaskItem] { completed.filter { Calendar.current.isDateInToday($0.completedAt ?? $0.createdAt) } }
    private var yesterday: [TaskItem] { completed.filter { Calendar.current.isDateInYesterday($0.completedAt ?? $0.createdAt) } }
    private var thisWeek: [TaskItem] {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        return completed.filter { task in
            let date = task.completedAt ?? task.createdAt
            return date >= weekAgo && !Calendar.current.isDateInToday(date) && !Calendar.current.isDateInYesterday(date)
        }
    }
    private var older: [TaskItem] {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        return completed.filter { ($0.completedAt ?? $0.createdAt) < weekAgo }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ListHeaderBar(title: "Completed", subtitle: "A record of finished work.", icon: "checkmark.circle", accent: Theme.lowPressure) {
                if !completed.isEmpty {
                    SelectModeButton(isSelecting: $isSelecting) { isSelecting = false; selectedIDs = [] }
                    Button("Clear Completed", action: onClearCompleted)
                        .buttonStyle(.glass)
                        .modifier(HoverButtonModifier())
                }
            }

            if isSelecting {
                BulkActionBar(
                    count: selectedIDs.count,
                    onDelete: { onBulkDelete(selectedIDs); selectedIDs = [] },
                    onCancel: { isSelecting = false; selectedIDs = [] }
                )
            } else {
                ListSearchField(text: $search)
            }

            if completed.isEmpty {
                EmptyStateCard(icon: "checkmark.circle", title: "No Tasks", detail: "Nothing matches this view yet.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            TaskSection(title: "Today", tint: Theme.lowPressure, tasks: today, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                            TaskSection(title: "Yesterday", tint: Theme.lowPressure, tasks: yesterday, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                            TaskSection(title: "This Week", tint: Theme.lowPressure, tasks: thisWeek, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                            TaskSection(title: "Older", tint: Theme.mutedText, tasks: older, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                        }
                    }
                    .onChange(of: selectedTask?.id) { _, newID in
                        guard let newID, completed.contains(where: { $0.id == newID }) else { return }
                        withAnimation { proxy.scrollTo(newID, anchor: .center) }
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.bg)
    }
}

struct TrashView: View {
    let tasks: [TaskItem]
    let categories: [CategoryItem]
    let onRestore: (TaskItem) -> Void
    let onDeleteForever: (TaskItem) -> Void
    let onEmptyTrash: () -> Void

    private var sorted: [TaskItem] {
        tasks.sorted { ($0.deletedAt ?? $0.createdAt) > ($1.deletedAt ?? $1.createdAt) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ListHeaderBar(
                title: "Trash", subtitle: "Deleted tasks stay here for 30 days, then they're gone for good.",
                icon: "trash", accent: Theme.critical
            ) {
                if !tasks.isEmpty {
                    Button("Empty Trash", role: .destructive, action: onEmptyTrash)
                        .buttonStyle(.glass)
                        .modifier(HoverButtonModifier())
                }
            }

            if sorted.isEmpty {
                EmptyStateCard(icon: "trash", title: "Trash Is Empty", detail: "Deleted tasks show up here before they're gone for good.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sorted) { task in
                            TrashRow(
                                task: task, categories: categories,
                                onRestore: { onRestore(task) },
                                onDeleteForever: { onDeleteForever(task) }
                            )
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.bg)
    }
}

private struct TrashRow: View {
    let task: TaskItem
    let categories: [CategoryItem]
    let onRestore: () -> Void
    let onDeleteForever: () -> Void

    private var listColor: Color { Categories.color(for: task.category, in: categories) }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(listColor)
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: .secondary)
                    .lineLimit(2)
                Text("Deleted \(relativeDate(task.deletedAt ?? task.createdAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.mutedText)
            }

            Spacer(minLength: 8)

            Button(action: onRestore) {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.plain)
            .help("Restore task")
            .modifier(HoverButtonModifier())

            Button(action: onDeleteForever) {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.critical)
            }
            .buttonStyle(.plain)
            .help("Delete forever")
            .modifier(HoverButtonModifier())
        }
        .padding(10)
        .background(Theme.panelRaised.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelBorder, lineWidth: 1))
    }
}

// Shared icon-badge + title + subtitle header, with a caller-supplied trailing control
// (a New Task button, a Clear Completed button, or nothing).
private struct ListHeaderBar<Trailing: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let trailing: Trailing

    init(title: String, subtitle: String, icon: String, accent: Color, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }

            Spacer()
            trailing
        }
    }
}

private struct ListSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search tasks"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// Small tracked-uppercase label + count + a divider line filling the rest of the row —
// same vocabulary as DecisionPulseView's "AT A GLANCE" label, scaled down for repeated use.
private struct TaskSectionHeader: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(tint)
            Text("\(count)")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Theme.mutedText)
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
    }
}

// Two equal lanes — every list (General/Today/Upcoming/Completed/Lists) shares this,
// so a row of two cards fills the pane's width instead of one card stretching across
// it with nothing alongside.
let twoCardColumns: [GridItem] = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10)
]

// Renders nothing when `tasks` is empty, so a page composed of several of these only
// ever shows the sections that actually have something in them.
private struct TaskSection: View {
    let title: String
    let tint: Color
    let tasks: [TaskItem]
    let allTasks: [TaskItem]
    let categories: [CategoryItem]
    @Binding var selectedTask: TaskItem?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    var isMultiSelecting: Bool = false
    @Binding var multiSelectedIDs: Set<UUID>

    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                TaskSectionHeader(title: title, count: tasks.count, tint: tint)
                LazyVGrid(columns: twoCardColumns, alignment: .leading, spacing: 10) {
                    ForEach(tasks) { task in
                        TaskCard(
                            task: task, allTasks: allTasks, categories: categories,
                            isSelected: selectedTask?.id == task.id,
                            onSelect: { selectedTask = selectedTask?.id == task.id ? nil : task },
                            onToggle: { onToggle(task) }, onEdit: { onEdit(task) }, onDelete: { onDelete(task) },
                            isMultiSelecting: isMultiSelecting,
                            isMultiSelected: multiSelectedIDs.contains(task.id),
                            onToggleMultiSelect: {
                                if multiSelectedIDs.contains(task.id) {
                                    multiSelectedIDs.remove(task.id)
                                } else {
                                    multiSelectedIDs.insert(task.id)
                                }
                            }
                        )
                        .id(task.id)
                        .onDrag { NSItemProvider(object: task.title as NSString) }
                    }
                }
            }
        }
    }
}

// Replaces the search field while selecting, since searching and bulk-selecting
// aren't something you do at the same time.
struct BulkActionBar: View {
    let count: Int
    var onComplete: (() -> Void)? = nil
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(count == 0 ? "Select tasks" : "\(count) selected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let onComplete {
                Button("Mark Done", action: onComplete)
                    .buttonStyle(.glass)
                    .disabled(count == 0)
                    .modifier(HoverButtonModifier())
            }
            Button("Delete", role: .destructive, action: onDelete)
                .buttonStyle(.glass)
                .disabled(count == 0)
                .modifier(HoverButtonModifier())
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .modifier(HoverButtonModifier())
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

// One small icon button that flips a view into/out of multi-select mode. Shared so
// General/Today/Upcoming/Completed all get the identical control, not four slightly
// different ones.
struct SelectModeButton: View {
    @Binding var isSelecting: Bool
    let onCancel: () -> Void

    var body: some View {
        Button {
            if isSelecting { onCancel() } else { isSelecting = true }
        } label: {
            Label(isSelecting ? "Cancel" : "Select", systemImage: isSelecting ? "xmark" : "checkmark.circle")
        }
        .buttonStyle(.glass)
        .modifier(HoverButtonModifier())
    }
}
