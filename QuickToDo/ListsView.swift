// ListsView.swift
// Category overview with live counts and a focused task list below it.

import SwiftUI
import UniformTypeIdentifiers

struct ListsView: View {
    let tasks: [TaskItem]
    let categories: [CategoryItem]
    @Binding var search: String
    @Binding var selectedTask: TaskItem?
    @Binding var selectedList: String?
    @Binding var draggedCategoryID: UUID?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onReorderCategory: (UUID, UUID) -> Void
    let onNewTask: () -> Void
    let onAddList: () -> Void
    let onManageLists: () -> Void
    let onBulkComplete: (Set<UUID>) -> Void
    let onBulkDelete: (Set<UUID>) -> Void

    // Filters the rows below, separate from `search` (which filters tasks inside the
    // selected list) so typing in one doesn't blank out the other.
    @State private var listFilter: String = ""
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var focusedID: UUID?

    private var orderedCategories: [CategoryItem] {
        categories.sorted {
            let left = $0.sortIndex ?? Int.max
            let right = $1.sortIndex ?? Int.max
            return left == right ? $0.createdAt < $1.createdAt : left < right
        }
    }

    private var filteredCategories: [CategoryItem] {
        guard !listFilter.isEmpty else { return orderedCategories }
        return orderedCategories.filter { $0.name.localizedCaseInsensitiveContains(listFilter) }
    }

    private var visibleTasks: [TaskItem] {
        guard let selectedList else { return [] }
        let slice = tasks.filter { !$0.isCompleted && $0.category.caseInsensitiveCompare(selectedList) == .orderedSame }
        let filtered = search.isEmpty ? slice : slice.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
        return filtered.sortedChronologically()
    }

    private func stats(for category: CategoryItem) -> ListOverviewStats {
        let inCategory = tasks.filter { $0.category.caseInsensitiveCompare(category.name) == .orderedSame }
        let active = inCategory.filter { !$0.isCompleted }
        let soonCutoff = Date().addingTimeInterval(24 * 3600)
        // "Due soon" = due within 24h but not yet past due; overdue is its own count, so the
        // chips never count the same task twice and match the Today tab.
        let dueSoon = active.filter { ($0.dueDate.map { $0 >= Date() && $0 <= soonCutoff }) ?? false }.count
        let dueToday = active.filter { Planner.isDueLaterToday($0) }.count
        let overdue = active.filter { Planner.isOverdue($0) }.count
        let completed = inCategory.count - active.count
        let fraction = inCategory.isEmpty ? 0 : Double(completed) / Double(inCategory.count)
        return ListOverviewStats(active: active.count, dueSoon: dueSoon, dueToday: dueToday, overdue: overdue,
                                 done: completed, total: inCategory.count, completedFraction: fraction)
    }

    private var selectedCategory: CategoryItem? {
        guard let selectedList else { return nil }
        return categories.first { $0.name.caseInsensitiveCompare(selectedList) == .orderedSame }
    }

    // The selected list's open tasks, grouped by when they're due.
    private var overdueTasks: [TaskItem] { visibleTasks.filter { Planner.isOverdue($0) } }
    private var todayTasks: [TaskItem] { visibleTasks.filter { Planner.isDueLaterToday($0) } }
    private var laterTasks: [TaskItem] {
        let endOfToday = Calendar.current.startOfDay(for: .now).addingTimeInterval(24 * 3600)
        return visibleTasks.filter { ($0.dueDate.map { $0 >= endOfToday }) ?? false }
    }
    private var undatedTasks: [TaskItem] { visibleTasks.filter { $0.dueDate == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lists").font(Fonts.black(46)).foregroundStyle(.white)
                    Text("Pick a list to open it.")
                        .font(Fonts.ui(16, .bold)).foregroundStyle(.white)
                }
                Spacer()
                Button(action: onManageLists) { Text("Manage") }
                    .buttonStyle(NeoButtonStyle())
                Button(action: onAddList) { Text("+ Add List") }
                    .buttonStyle(NeoButtonStyle())
            }

            HStack(alignment: .top, spacing: 22) {
                listRail.frame(width: 290).frame(maxHeight: .infinity)
                detailPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 32).padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if selectedList == nil {
                // Open on the first list that actually has something in it.
                selectedList = orderedCategories.first { stats(for: $0).active > 0 }?.name ?? orderedCategories.first?.name
            }
        }
    }

    // MARK: Left rail: search + one colourful pill per list (drag to reorder)

    private var listRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted)
                TextField("Search lists", text: $listFilter).textFieldStyle(.plain).font(Fonts.ui(15, .semibold)).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 16).frame(height: 44)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
            .padding(.trailing, 4)

            if filteredCategories.isEmpty {
                Text(orderedCategories.isEmpty ? "No lists yet. Every tidy mind starts with one shelf." : "No lists match “\(listFilter)”.")
                    .font(Fonts.ui(15, .bold)).foregroundStyle(.white)
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filteredCategories) { category in
                        ListRailPill(
                            category: category,
                            isSelected: selectedList == category.name,
                            stats: stats(for: category),
                            onSelect: { withAnimation(.snappy(duration: 0.2)) { selectedList = category.name } }
                        )
                        .opacity(draggedCategoryID == category.id ? 0.4 : 1)
                        .scaleEffect(draggedCategoryID == category.id ? 0.97 : 1)
                        .animation(Motion.dragLift, value: draggedCategoryID)
                        .onHover { inside in if inside && draggedCategoryID == category.id { draggedCategoryID = nil } }
                        .onDrag {
                            draggedCategoryID = category.id
                            return NSItemProvider(object: category.id.uuidString as NSString)
                        } preview: {
                            DragCardPreview(title: category.name, tint: Categories.color(for: category))
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: CategoryRowDropDelegate(
                                targetCategoryID: category.id,
                                draggedCategoryID: $draggedCategoryID,
                                onReorder: onReorderCategory
                            )
                        )
                    }
                }
                .padding(.trailing, 6).padding(.bottom, 6)
                .animation(Motion.layoutShift, value: filteredCategories.map(\.id))
            }
            .scrollClipDisabled()
            .scrollIndicators(.never)
        }
    }

    // MARK: Detail: tinted header with the list's numbers, then tasks grouped by due date

    private var detailPanel: some View {
        let category = selectedCategory
        let color = category.map { Categories.color(for: $0) } ?? Theme.general
        let st = category.map { stats(for: $0) }
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(selectedList ?? "Choose a list").font(Fonts.black(32)).foregroundStyle(Theme.ink).lineLimit(1)
                    if let st {
                        if st.overdue > 0 { NeoChip(text: "\(st.overdue) overdue", foreground: Theme.overdue, size: 13, borderColor: Theme.overdue) }
                    }
                    Spacer(minLength: 8)
                    if selectedList != nil {
                        SelectModeButton(isSelecting: $isSelecting) { isSelecting = false; selectedIDs = [] }
                        NewTaskButton(action: onNewTask)
                    }
                }
                if let st, st.total > 0 {
                    HStack(spacing: 14) {
                        NeoProgressBar(value: st.completedFraction, height: 14).frame(maxWidth: 360)
                        Text("\(st.done) of \(st.total) done").font(Fonts.ui(14, .heavy)).foregroundStyle(Theme.ink)
                    }
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Categories.tint(color))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 2) }

            if isSelecting {
                BulkActionBar(
                    count: selectedIDs.count,
                    onComplete: { onBulkComplete(selectedIDs); selectedIDs = [] },
                    onDelete: { onBulkDelete(selectedIDs); selectedIDs = [] },
                    onCancel: { isSelecting = false; selectedIDs = [] }
                )
                .padding(.horizontal, 22).padding(.top, 16)
            }

            Group {
                if selectedList == nil {
                    detailEmpty("Choose a list", "Pick one from the left to see its tasks.")
                } else if visibleTasks.isEmpty {
                    if let st, st.total > 0 && st.active == 0 {
                        detailEmpty("\(selectedList ?? ""): all shelved ✓", "Nothing else open here. Great work.")
                    } else {
                        detailEmpty("Nothing in \(selectedList ?? "this list") yet.", "Plenty of room. Add the first one with + New Task.")
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                group("Overdue", overdueTasks)
                                group("Later today", todayTasks)
                                group("Coming up", laterTasks)
                                group("No date", undatedTasks)
                            }
                            .padding(22)
                        }
                        .scrollIndicators(.never)
                        .modifier(RowKeyboardNav(
                            ids: (overdueTasks + todayTasks + laterTasks + undatedTasks).map(\.id), focused: $focusedID,
                            onToggle: { id in if let t = tasks.first(where: { $0.id == id }) { onToggle(t) } }
                        ))
                        .onChange(of: selectedTask?.id) { _, newID in
                            guard let newID, visibleTasks.contains(where: { $0.id == newID }) else { return }
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newID) }
                        }
                    }
                }
            }
            .id(selectedList ?? "")
            .transition(.opacity)
            .animation(.easeOut(duration: 0.15), value: selectedList)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .neoCard(Theme.card, radius: 5, shadow: 5)
        .padding(.trailing, 5).padding(.bottom, 5)
    }

    private func group(_ title: String, _ items: [TaskItem]) -> some View {
        TaskSection(
            title: title, tasks: items, allTasks: tasks, categories: categories,
            selectedTask: $selectedTask,
            onToggle: onToggle, onEdit: onEdit, onDelete: onDelete,
            isMultiSelecting: isSelecting, multiSelectedIDs: $selectedIDs
        )
    }

    private func detailEmpty(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(Fonts.black(30)).foregroundStyle(Theme.ink)
            Text(detail).font(Fonts.ui(15, .semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ListOverviewStats {
    let active: Int
    let dueSoon: Int
    let dueToday: Int
    let overdue: Int
    let done: Int
    let total: Int
    let completedFraction: Double
}

/// One pill per list in the left rail: list colour, mini progress ring, name, open count.
/// Selected = black with white text, like the nav pills.
private struct ListRailPill: View {
    let category: CategoryItem
    let isSelected: Bool
    let stats: ListOverviewStats
    let onSelect: () -> Void

    private var color: Color { Categories.color(for: category) }
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ProgressRing(value: stats.completedFraction, label: "", size: 36, lineWidth: 7)
                    .background(Circle().fill(Categories.tint(color)).padding(3))
                Text(category.name).font(Fonts.ui(17, .heavy)).lineLimit(1)
                Spacer(minLength: 4)
                if stats.overdue > 0 {
                    Circle().fill(Theme.overdue).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(isSelected ? Color.white : Theme.ink, lineWidth: 2))
                        .help("\(stats.overdue) overdue")
                }
                NeoChip(text: "\(stats.active)", size: 13)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PressableStyle(
            fill: isSelected ? color : Categories.tint(color),
            foreground: Theme.ink,
            radius: 10, shadow: 4))
        // Glow follows the card's rounded shape: a blurred copy of the same rounded rect in the list's
        // color. Hover shows half strength; the selected list stays fully lit after the click.
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .blur(radius: 10)
                .opacity(isSelected ? 0.6 : (hovering ? 0.25 : 0))
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .padding(.trailing, 6).padding(.bottom, 4)
        .accessibilityLabel("\(category.name), \(stats.active) open")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// Same shared-state drag pattern as the Decision Board's BoardCardDropDelegate — drop
// a list onto another to swap their manual sort order, right here, no Manage sheet needed.
private struct CategoryRowDropDelegate: DropDelegate {
    let targetCategoryID: UUID
    @Binding var draggedCategoryID: UUID?
    let onReorder: (UUID, UUID) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedCategoryID else { return false }
        let dragged = draggedCategoryID
        withAnimation(Motion.dropSettle) {
            if dragged != targetCategoryID {
                onReorder(dragged, targetCategoryID)
            }
        }
        self.draggedCategoryID = nil
        return true
    }
}
