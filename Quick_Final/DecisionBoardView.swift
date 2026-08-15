// DecisionBoardView.swift
// The hero view: a live Decision Brief above four readable workflow lanes.

import SwiftUI

struct DecisionBoardView: View {
    let tasks: [TaskItem]
    let categories: [CategoryItem]
    @Binding var search: String
    @Binding var selectedTask: TaskItem?
    @Binding var draggedTaskID: UUID?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onReorder: (UUID, UUID) -> Void
    let onMoveToStage: (UUID, TaskStage) -> Void
    let onNewTask: () -> Void
    let onQuickCapture: (QuickDateParser.Result) -> Void

    private enum BoardSortMode: String, CaseIterable, Identifiable {
        case recommended = "Recommended", dueDate = "Due Date", priority = "Priority", manual = "Manual"
        var id: String { rawValue }
    }

    @State private var sortMode: BoardSortMode = .recommended
    @State private var showQuickCapture = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            toolbar

            DecisionPulseView(
                activeCount: activeTasks.count,
                readyCount: readyTasks.count,
                riskCount: riskTasks.count,
                completedCount: doneTasks.count
            )

            HStack {
                Text("YOUR TASKS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(Theme.mutedText)
                Text("Move tasks as you work on them.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
                Spacer()
                Text("Finished tasks are in Completed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.mutedText)
            }

            GeometryReader { geometry in
                let columnWidth = (geometry.size.width - 36) / 4

                HStack(alignment: .top, spacing: 12) {
                    BoardColumnView(
                        title: "Capture", icon: "tray", tasks: generalColumnTasks, allTasks: tasks,
                        categories: categories, width: columnWidth, accent: Theme.general, isVirtual: false, targetStage: .general,
                        selectedTaskID: selectedTask?.id, draggedTaskID: $draggedTaskID,
                        onSelect: toggleSelection, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete,
                        onReorder: reorderByDrag, onMoveToStage: onMoveToStage
                    )

                    BoardColumnView(
                        title: "Ready", icon: "sparkles", tasks: readyTasks, allTasks: tasks,
                        categories: categories, width: columnWidth, accent: Theme.warning, isVirtual: false, targetStage: .ready,
                        selectedTaskID: selectedTask?.id, draggedTaskID: $draggedTaskID,
                        onSelect: toggleSelection, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete,
                        onReorder: reorderByDrag, onMoveToStage: onMoveToStage
                    )

                    BoardColumnView(
                        title: "Scheduled", icon: "calendar", tasks: scheduledTasks, allTasks: tasks,
                        categories: categories, width: columnWidth, accent: Theme.accent, isVirtual: false, targetStage: .scheduled,
                        selectedTaskID: selectedTask?.id, draggedTaskID: $draggedTaskID,
                        onSelect: toggleSelection, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete,
                        onReorder: reorderByDrag, onMoveToStage: onMoveToStage
                    )

                    BoardColumnView(
                        title: "In Progress", icon: "waveform.path.ecg", tasks: inProgressTasks, allTasks: tasks,
                        categories: categories, width: columnWidth, accent: Theme.accent, isVirtual: false, targetStage: .inProgress,
                        selectedTaskID: selectedTask?.id, draggedTaskID: $draggedTaskID,
                        onSelect: toggleSelection, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete,
                        onReorder: reorderByDrag, onMoveToStage: onMoveToStage
                    )

                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Decision Board")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("See what matters and choose your next task.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.mutedText)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search tasks", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 210, idealWidth: 270, maxWidth: 320)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))

            Picker("", selection: $sortMode) {
                ForEach(BoardSortMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)
            .help("Smart Sort: how Capture, Scheduled, and In Progress are ordered")
            .accessibilityLabel("Sort order")

            Button(action: { showQuickCapture.toggle() }) {
                Label("Capture", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .modifier(HoverButtonModifier())
            .help("Capture a task quickly")
            .popover(isPresented: $showQuickCapture, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Quick Capture")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button { showQuickCapture = false } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Close Quick Capture")
                        .accessibilityLabel("Close Quick Capture")
                        .modifier(HoverButtonModifier())
                    }
                    QuickCapture { result in
                        onQuickCapture(result)
                        showQuickCapture = false
                    }
                    Button("Open Detailed Task") {
                        showQuickCapture = false
                        onNewTask()
                    }
                    .buttonStyle(.link)
                }
                .padding(14)
                .frame(width: 500)
                .background(Theme.bg)
            }
        }
    }

    // Dragging a card to reorder it only changes anything visible under Manual sort —
    // under Recommended/Due Date/Priority, the column re-sorts itself right past
    // whatever sortIndex swap just happened. Treat the drag itself as "I want manual
    // order now" so reordering always works, the same way moving a card to another
    // column always works regardless of sort mode.
    private func reorderByDrag(_ draggedID: UUID, _ targetID: UUID) {
        sortMode = .manual
        onReorder(draggedID, targetID)
    }

    private func toggleSelection(_ task: TaskItem) {
        withAnimation(.snappy(duration: Motion.select)) {
            selectedTask = selectedTask?.id == task.id ? nil : task
        }
    }

    // MARK: Derived data

    private var activeTasks: [TaskItem] { tasks.filter { !$0.isCompleted } }

    private var searchedActiveTasks: [TaskItem] {
        guard !search.isEmpty else { return activeTasks }
        return activeTasks.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
    }

    // Every lane below is a real, persisted stage — once a card lands somewhere
    // (by smart initial placement at creation, or by being dragged), it stays there
    // until you move it again. Nothing here recomputes or overrides your placement.
    private var generalColumnTasks: [TaskItem] { applySort(searchedActiveTasks.filter { $0.resolvedStage == .general }) }
    private var readyTasks: [TaskItem] { applySort(searchedActiveTasks.filter { $0.resolvedStage == .ready }) }
    private var scheduledTasks: [TaskItem] { applySort(searchedActiveTasks.filter { $0.resolvedStage == .scheduled }) }
    private var inProgressTasks: [TaskItem] { applySort(searchedActiveTasks.filter { $0.resolvedStage == .inProgress }) }

    private var doneTasks: [TaskItem] {
        let completed = tasks.filter(\.isCompleted)
        let filtered = search.isEmpty ? completed : completed.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
        return filtered.sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private func applySort(_ list: [TaskItem]) -> [TaskItem] {
        switch sortMode {
        case .recommended:
            return list.sorted { a, b in
                let rankA = rankForSort(a), rankB = rankForSort(b)
                if rankA != rankB { return rankA > rankB }
                return dueDateThenCreatedAscending(a, b)
            }
        case .dueDate:
            return list.sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (d1?, d2?): if d1 != d2 { return d1 < d2 }
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): break
                }
                return a.createdAt < b.createdAt
            }
        case .priority:
            return list.sorted { a, b in
                let priA = a.priority ?? .low, priB = b.priority ?? .low
                if priA != priB { return priA < priB }
                return dueDateThenCreatedAscending(a, b)
            }
        case .manual:
            return list.sortedForDisplay()
        }
    }

    // Shared tiebreak for sort modes above: when the primary key ties, fall back to
    // soonest due date, then oldest first — never an unspecified/unstable order.
    private func dueDateThenCreatedAscending(_ a: TaskItem, _ b: TaskItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (d1?, d2?): if d1 != d2 { return d1 < d2 }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        return a.createdAt < b.createdAt
    }

    private func rankForSort(_ task: TaskItem) -> Int {
        var score = 0
        if let due = task.dueDate {
            // A due date further out than tomorrow earns nothing here — it
            // shouldn't outrank an equally-prioritized task with no due date just
            // for having a technically-earlier date. (This sort mode, unlike
            // NextMoveEngine's suggestion ranking, still weighs priority/blocking —
            // that engine is now purely due-date ordered, see NextMoveEngine.swift.)
            if due < Date() { score += 100 }
            else if due <= Date().addingTimeInterval(86400) { score += 60 }
        }
        if (task.priority ?? .low) == .high { score += 40 }
        score += task.blockedTaskCount(in: tasks) * 15
        return score
    }

    private var riskTasks: [TaskItem] {
        let soon = Date().addingTimeInterval(24 * 3600)
        return activeTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return due <= soon
        }
    }

}
