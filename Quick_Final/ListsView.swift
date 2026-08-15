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
        let dueSoon = active.filter { ($0.dueDate.map { $0 <= soonCutoff }) ?? false }.count
        let dueToday = active.filter { ($0.dueDate.map { Calendar.current.isDateInToday($0) }) ?? false }.count
        let completed = inCategory.count - active.count
        let fraction = inCategory.isEmpty ? 0 : Double(completed) / Double(inCategory.count)
        return ListOverviewStats(active: active.count, dueSoon: dueSoon, dueToday: dueToday, completedFraction: fraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.keepInMind.opacity(0.16))
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.keepInMind)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Lists").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Keep related work together without crowding the sidebar.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onManageLists) { Label("Manage", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.glass)
                    .modifier(HoverButtonModifier())
                Button(action: onAddList) { Label("Add List", systemImage: "plus") }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .modifier(HoverButtonModifier())
            }

            ScrollViewReader { proxy in
                ScrollView {
                    listScrollContent
                }
                .onChange(of: selectedTask?.id) { _, newID in
                    guard let newID, visibleTasks.contains(where: { $0.id == newID }) else { return }
                    withAnimation { proxy.scrollTo(newID, anchor: .center) }
                }
            }
        }
        .padding(18)
        .background(Theme.bg)
        .onAppear {
            if selectedList == nil { selectedList = orderedCategories.first?.name }
        }
    }

    @ViewBuilder
    private var listScrollContent: some View {
        VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search lists", text: $listFilter).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))

                    if filteredCategories.isEmpty {
                        EmptyStateCard(icon: "list.bullet", title: "No Lists", detail: "No lists match your search.")
                    } else {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredCategories) { category in
                                ListOverviewRow(
                                    category: category,
                                    isSelected: selectedList == category.name,
                                    stats: stats(for: category),
                                    onSelect: { selectedList = category.name }
                                )
                                .opacity(draggedCategoryID == category.id ? 0.5 : 1)
                                .animation(.snappy(duration: Motion.dragReorder), value: draggedCategoryID)
                                .onDrag {
                                    draggedCategoryID = category.id
                                    return NSItemProvider(object: category.id.uuidString as NSString)
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
                    }

                    if let selectedList {
                        Divider().background(Theme.divider)

                        HStack {
                            Text(selectedList).font(.system(size: 16, weight: .semibold))
                            Spacer()
                            SelectModeButton(isSelecting: $isSelecting) { isSelecting = false; selectedIDs = [] }
                            Button(action: onNewTask) { Label("New Task", systemImage: "plus") }
                                .buttonStyle(.glass)
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
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("Search \(selectedList)", text: $search).textFieldStyle(.plain)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }

                        if visibleTasks.isEmpty {
                            EmptyStateCard(icon: "list.bullet", title: "No Tasks", detail: "Nothing matches this list yet.")
                        } else {
                            LazyVGrid(columns: twoCardColumns, alignment: .leading, spacing: 10) {
                                ForEach(visibleTasks) { task in
                                    TaskCard(
                                        task: task, allTasks: tasks, categories: categories,
                                        isSelected: selectedTask?.id == task.id,
                                        onSelect: { selectedTask = selectedTask?.id == task.id ? nil : task }, onToggle: { onToggle(task) },
                                        onEdit: { onEdit(task) }, onDelete: { onDelete(task) },
                                        isMultiSelecting: isSelecting,
                                        isMultiSelected: selectedIDs.contains(task.id),
                                        onToggleMultiSelect: {
                                            if selectedIDs.contains(task.id) { selectedIDs.remove(task.id) }
                                            else { selectedIDs.insert(task.id) }
                                        }
                                    )
                                    .id(task.id)
                                    .onDrag { NSItemProvider(object: task.title as NSString) }
                                }
                            }
                        }
                    } else {
                        EmptyStateCard(icon: "list.bullet", title: "Choose a List", detail: "Select a list above to see its tasks.")
                    }
        }
    }
}

struct ListOverviewStats {
    let active: Int
    let dueSoon: Int
    let dueToday: Int
    let completedFraction: Double
}

// A flat, single-line row — colored dot, name, inline counts, thin progress bar. Dense
// on purpose: a card-per-list look ate too much vertical space for what little each
// row says, so this favors fitting more lists on screen over a "card" feel.
private struct ListOverviewRow: View {
    let category: CategoryItem
    let isSelected: Bool
    let stats: ListOverviewStats
    let onSelect: () -> Void

    private var tint: Color { Categories.color(for: category) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Circle().fill(tint).frame(width: 7, height: 7)

                Text(category.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text("\(stats.active)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if stats.dueSoon > 0 {
                    Text("\(stats.dueSoon) due soon")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                }
                if stats.dueToday > 0 {
                    Text("\(stats.dueToday) today")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.critical)
                }

                Spacer(minLength: 8)

                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 56, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(3, 56 * stats.completedFraction), height: 4)
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.14) : Color.white.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
        withAnimation(.snappy(duration: Motion.dragReorder)) {
            if dragged != targetCategoryID {
                onReorder(dragged, targetCategoryID)
            }
        }
        self.draggedCategoryID = nil
        return true
    }
}
