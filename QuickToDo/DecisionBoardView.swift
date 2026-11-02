// DecisionBoardView.swift
// The hero view: header, amber Next Move card + week summary, then four workflow lanes.

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

    private enum BoardSortMode: String, CaseIterable, Identifiable {
        case recommended = "Recommended", dueDate = "Due Date", priority = "Priority", manual = "Manual"
        var id: String { rawValue }
    }

    @State private var sortMode: BoardSortMode = .recommended
    @State private var finished: [TaskStage: [UUID]] = [:]
    @Namespace private var cardSpace

    var body: some View {
        // The whole page scrolls (instead of each column clipping its own cards), so no
        // card is ever cut off mid-edge; the four columns grow to the tallest one.
        GeometryReader { geo in
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    HStack(alignment: .top, spacing: 18) {
                        NextMoveCard(
                            task: nextMoveTask, hasOpenTasks: !searchedActiveTasks.isEmpty, allTasks: tasks, categories: categories,
                            onStart: { onMoveToStage($0.id, .inProgress) },
                            onDone: { task in
                                if !task.isCompleted { finished[task.resolvedStage, default: []].append(task.id) }
                                onToggle(task)
                            },
                            onOpen: toggleSelection
                        )
                        .layoutPriority(1)
                        WeekSummaryCard(summary: weekSummary)
                            .frame(width: 380)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 16) {
                        column("Capture", "", tasks: generalColumnTasks, stage: .general, width: 0)
                        column("Ready", "", tasks: readyTasks, stage: .ready, width: 0)
                        column("Scheduled", "", tasks: scheduledTasks, stage: .scheduled, width: 0)
                        column("In Progress", "", tasks: inProgressTasks, stage: .inProgress, width: 0)
                    }
                    // The four columns run down to the bottom of the page (never short of it).
                    .frame(maxHeight: .infinity)
                    .padding(.trailing, 6).padding(.bottom, 4)
                }
                .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 12)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
            }
            .scrollIndicators(.never)
            .onChange(of: selectedTask?.id) { _, id in
                guard let id else { return }
                DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } }
            }
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func column(_ title: String, _ detail: String, tasks columnTasks: [TaskItem], stage: TaskStage, width: CGFloat) -> some View {
        BoardColumnView(
            title: title, detail: detail, tasks: columnTasks, allTasks: tasks,
            categories: categories, width: width, targetStage: stage,
            selectedTaskID: selectedTask?.id, draggedTaskID: $draggedTaskID, namespace: cardSpace,
            finishedIDs: Binding(get: { finished[stage] ?? [] }, set: { finished[stage] = $0 }),
            onSelect: toggleSelection, onToggle: onToggle, onEdit: onEdit, onDelete: onDelete,
            onReorder: reorderByDrag, onMoveToStage: onMoveToStage
        )
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(Fonts.black(36)).foregroundStyle(.white)
                // The week total lives on the "This week" card; only the overdue count is new here.
                if weekSummary.overdue > 0 {
                    Text("\(weekSummary.overdue) overdue")
                        .font(Fonts.ui(16, .bold)).foregroundStyle(.white)
                }
            }
            Spacer()
            NeoDropdown(selection: $sortMode, options: BoardSortMode.allCases.map { ($0, $0.rawValue) }, minWidth: 150)
                .help("Smart Sort: how Capture, Ready, Scheduled, and In Progress are ordered")
        }
    }

    private var weekSummary: Planner.WeekSummary { Planner.weekSummary(tasks) }
    private var nextMoveTask: TaskItem? { Planner.nextMove(from: searchedActiveTasks) }

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
        selectedTask = selectedTask?.id == task.id ? nil : task
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
            // Dependants are counted once for the whole sort (not once per comparison).
            let dependants = Dictionary(grouping: tasks.compactMap(\.dependsOnTaskID), by: { $0 }).mapValues(\.count)
            return list.sorted { a, b in
                let rankA = rankForSort(a, dependants), rankB = rankForSort(b, dependants)
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

    private func rankForSort(_ task: TaskItem, _ dependants: [UUID: Int]) -> Int {
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
        score += (dependants[task.id] ?? 0) * 15
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
