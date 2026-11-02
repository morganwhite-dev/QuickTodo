// SimpleListViews.swift
// Focused task lists for the non-board destinations in the top bar (General, Today,
// Completed, Trash). Same look as the rest of the app: big white title on the
// gradient, one panel, white rows. Upcoming lives in UpcomingPlannerView.swift.

import SwiftUI

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(Fonts.bricolage(26, .heavy))
                .foregroundStyle(Theme.ink.opacity(0.6))
            Text(detail)
                .font(Fonts.ui(14, .semibold))
                .foregroundStyle(Theme.ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }
}

/// The shared page: header, optional stats / bulk bar, then one panel holding `content`.
private struct ListPage<Trailing: View, Extra: View, Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let extra: Extra
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Fonts.black(46)).foregroundStyle(.white)
                    Text(subtitle).font(Fonts.ui(16, .bold)).foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 12) { trailing }
            }
            extra
            content
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .neoPanel()
        }
        .padding(.horizontal, 32).padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

func matches(_ task: TaskItem, _ search: String) -> Bool {
    search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.notes.localizedCaseInsensitiveContains(search)
}

struct NewTaskButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("+ New Task").font(Fonts.ui(14, .heavy)).padding(.horizontal, 18).frame(height: 40)
        }
        .buttonStyle(PressableStyle(fill: Theme.card, shadow: 3, capsule: true))
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
    let onBulkRestore: (Set<UUID>) -> Void

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var focusedID: UUID?

    private var completed: [TaskItem] {
        tasks.filter { $0.isCompleted && matches($0, search) }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
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
        ListPage(
            title: "Completed",
            subtitle: "Tick a task to undo it.",
            trailing: {
                if !completed.isEmpty {
                    SelectModeButton(isSelecting: $isSelecting) { isSelecting = false; selectedIDs = [] }
                    Button(action: onClearCompleted) {
                        Text("Clear Completed").font(Fonts.ui(14, .heavy)).padding(.horizontal, 18).frame(height: 40)
                    }
                    .buttonStyle(PressableStyle(fill: Theme.card, shadow: 3, capsule: true))
                }
            },
            extra: {
                if isSelecting {
                    BulkActionBar(
                        count: selectedIDs.count,
                        onRestore: { onBulkRestore(selectedIDs); selectedIDs = [] },
                        onDelete: { onBulkDelete(selectedIDs); selectedIDs = [] },
                        onCancel: { isSelecting = false; selectedIDs = [] }
                    )
                }
            },
            content: {
                if completed.isEmpty {
                    EmptyStateCard(icon: "checkmark.circle", title: "Nothing finished yet", detail: "Completed tasks collect here.")
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                TaskSection(title: "Today", tasks: today, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                                TaskSection(title: "Yesterday", tasks: yesterday, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                                TaskSection(title: "This Week", tasks: thisWeek, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                                TaskSection(title: "Older", tasks: older, allTasks: tasks, categories: categories, selectedTask: $selectedTask, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete, isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs)
                            }
                            .padding(.trailing, 6).padding(.bottom, 6)
                        }
                        .scrollIndicators(.never)
                        .modifier(RowKeyboardNav(
                            ids: (today + yesterday + thisWeek + older).map(\.id), focused: $focusedID,
                            onToggle: { id in if let t = tasks.first(where: { $0.id == id }) { onToggle(t) } }
                        ))
                        .onChange(of: selectedTask?.id) { _, newID in
                            guard let newID, completed.contains(where: { $0.id == newID }) else { return }
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newID) }
                        }
                    }
                }
            }
        )
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
        ListPage(
            title: "Trash",
            subtitle: "Deleted tasks stay here for 30 days, then they're gone for good.",
            trailing: {
                Button(action: onEmptyTrash) {
                    Text("Empty Trash").font(Fonts.ui(14, .heavy))
                        .padding(.horizontal, 18).frame(height: 40)
                }
                .buttonStyle(PressableStyle(fill: Theme.overdue, foreground: .white, shadow: 3, capsule: true))
                .disabled(tasks.isEmpty)
            },
            extra: { EmptyView() },
            content: {
                if sorted.isEmpty {
                    EmptyStateCard(icon: "trash", title: "Trash is empty", detail: "Deleted tasks show up here before they're gone for good.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(sorted) { task in
                                TrashRow(
                                    task: task, categories: categories,
                                    onRestore: { onRestore(task) },
                                    onDeleteForever: { onDeleteForever(task) }
                                )
                            }
                        }
                        .padding(.trailing, 6).padding(.bottom, 6)
                    }
                    .scrollIndicators(.never)
                }
            }
        )
    }
}

/// "Empty Trash": white capsule with a red outline and red flat shadow.
private struct RedOutlineStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let p = configuration.isPressed
        return configuration.label
            .background { Capsule().fill(Theme.card) }
            .background { Capsule().fill(Theme.overdue).offset(x: p ? 0 : 3, y: p ? 0 : 3) }
            .overlay { Capsule().strokeBorder(Theme.overdue, lineWidth: 2) }
            .offset(x: p ? 3 : 0, y: p ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: p)
    }
}

private struct TrashRow: View {
    let task: TaskItem
    let categories: [CategoryItem]
    let onRestore: () -> Void
    let onDeleteForever: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(Fonts.ui(16, .heavy)).foregroundStyle(Theme.ink)
                    .strikethrough(true, color: Theme.ink).lineLimit(2)
                Text("Deleted \(relativeDate(task.deletedAt ?? task.createdAt))")
                    .font(Fonts.ui(13, .semibold)).foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 8)
            ListTag(name: task.category, color: Categories.color(for: task.category, in: categories))
            Button(action: onRestore) {
                Text("Restore").font(Fonts.ui(13, .heavy)).padding(.horizontal, 14).frame(height: 32)
            }
            .buttonStyle(PressableStyle(fill: Theme.card, shadow: 3, capsule: true))
            .help("Restore task")
            Button(action: onDeleteForever) {
                Image(systemName: "trash").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.overdue)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(RedOutlineStyle())
            .help("Delete forever")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .neoCard(Theme.card, radius: 4, shadow: 3)
    }
}

// Section label + count + a black rule filling the rest of the row.
private struct TaskSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(Fonts.ui(13, .heavy)).tracking(1.2).foregroundStyle(Theme.ink)
            Text("\(count)")
                .font(Fonts.ui(13, .heavy)).foregroundStyle(Theme.inkMuted)
            Rectangle().fill(Theme.ink).frame(height: 1.5)
        }
    }
}

// Kept for ListsView, which lays its selected list out in two lanes.
let twoCardColumns: [GridItem] = [
    GridItem(.flexible(), spacing: 14),
    GridItem(.flexible(), spacing: 14)
]

// Renders nothing when `tasks` is empty, so a page composed of several of these only
// ever shows the sections that actually have something in them.
struct TaskSection: View {
    let title: String
    let tasks: [TaskItem]
    let allTasks: [TaskItem]
    let categories: [CategoryItem]
    @Binding var selectedTask: TaskItem?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    var isMultiSelecting: Bool = false
    var hidesPriorityFlag: Bool = false
    @Binding var multiSelectedIDs: Set<UUID>

    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                TaskSectionHeader(title: title, count: tasks.count)
                // Two lanes so a title is never a full window-width away from its tag and estimate.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 560), spacing: 14, alignment: .top)], alignment: .leading, spacing: 10) {
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
                            },
                            hidesPriorityFlag: hidesPriorityFlag
                        )
                        .id(task.id)
                        .onDrag { NSItemProvider(object: task.title as NSString) }
                    }
                }
            }
        }
    }
}

// Replaces nothing — appears under the header while selecting.
struct BulkActionBar: View {
    let count: Int
    var onComplete: (() -> Void)? = nil
    var onRestore: (() -> Void)? = nil
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(count == 0 ? "Select tasks" : "\(count) selected")
                .font(Fonts.ui(15, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
            if let onComplete {
                Button(action: onComplete) {
                    Text("Mark Done").font(Fonts.ui(14, .heavy)).padding(.horizontal, 16).frame(height: 36)
                }
                .buttonStyle(PressableStyle(hover: false, fill: Theme.done, shadow: 3, capsule: true))
                .disabled(count == 0)
            }
            if let onRestore {
                Button(action: onRestore) {
                    Text("Restore").font(Fonts.ui(14, .heavy)).padding(.horizontal, 16).frame(height: 36)
                }
                .buttonStyle(PressableStyle(fill: Theme.card, shadow: 3, capsule: true))
                .disabled(count == 0)
            }
            Button(action: onDelete) {
                Text("Delete").font(Fonts.ui(14, .heavy)).foregroundStyle(Theme.overdue).padding(.horizontal, 16).frame(height: 36)
            }
            .buttonStyle(RedOutlineStyle())
            .disabled(count == 0)
            Button("Cancel", action: onCancel)
                .buttonStyle(HoverPlainStyle()).font(Fonts.ui(14, .heavy)).underline().foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .neoCard(Theme.card, radius: 4, shadow: 3)
        .padding(.trailing, 3).padding(.bottom, 3)
    }
}

// One button that flips a view into/out of multi-select mode. Shared so
// General/Today/Completed/Lists all get the identical control.
struct SelectModeButton: View {
    @Binding var isSelecting: Bool
    let onCancel: () -> Void

    var body: some View {
        Button {
            if isSelecting { onCancel() } else { isSelecting = true }
        } label: {
            Text(isSelecting ? "Cancel" : "Select").font(Fonts.ui(14, .heavy)).padding(.horizontal, 18).frame(height: 40)
        }
        .buttonStyle(PressableStyle(fill: isSelecting ? Theme.ink : Theme.card, foreground: isSelecting ? .white : Theme.ink, shadow: 3, capsule: true))
    }
}
