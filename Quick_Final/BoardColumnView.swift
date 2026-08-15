// BoardColumnView.swift
// One column of the Decision Board. Drag-and-drop reuses the same shared-state pattern as
// the existing category/task reordering (a @Binding draggedTaskID, not item-provider payload
// decoding) so dropping a card sets its stage and/or swaps its manual sort order.

import SwiftUI
import UniformTypeIdentifiers

struct BoardColumnView: View {
    let title: String
    let icon: String
    let tasks: [TaskItem]
    let allTasks: [TaskItem]
    let categories: [CategoryItem]
    var width: CGFloat = 184
    var accent: Color = Theme.general
    var isVirtual: Bool = false
    // nil for the virtual Suggested column — it's computed, so it isn't a drop target.
    let targetStage: TaskStage?
    let selectedTaskID: UUID?
    @Binding var draggedTaskID: UUID?
    let onSelect: (TaskItem) -> Void
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onReorder: (UUID, UUID) -> Void
    let onMoveToStage: (UUID, TaskStage) -> Void

    @State private var isColumnTargeted = false
    @State private var isExpanded = false

    // Past this many cards, a column just becomes a tall scroll of cards with no
    // sense of "is there more" — capping the default view and surfacing a count
    // keeps every lane scannable at a glance, with the full list one tap away.
    private static let collapsedLimit = 4

    private var visibleTasks: [TaskItem] {
        isExpanded ? tasks : Array(tasks.prefix(Self.collapsedLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if tasks.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Image(systemName: icon)
                                    .font(.system(size: 16, weight: .medium))
                                Text(isVirtual ? "Nothing stands out yet" : "Nothing here")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text(emptyDetail)
                                    .font(.system(size: 10.5))
                            }
                                .font(.system(size: 11.5))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 18)
                        }

                        ForEach(visibleTasks) { task in
                            TaskCard(
                                task: task,
                                allTasks: allTasks,
                                categories: categories,
                                isSelected: task.id == selectedTaskID,
                                onSelect: { onSelect(task) },
                                onToggle: { onToggle(task) },
                                onEdit: { onEdit(task) },
                                onDelete: { onDelete(task) },
                                isBoardLayout: true
                            )
                            .id(task.id)
                            .opacity(draggedTaskID == task.id ? 0.5 : 1)
                            .animation(.snappy(duration: Motion.dragReorder), value: draggedTaskID)
                            .onDrag {
                                draggedTaskID = task.id
                                // Internal reordering reads draggedTaskID, not this payload's
                                // content — so it can carry the title instead, which makes
                                // dragging a card out to Mail/Notes/Messages drop in something
                                // useful instead of a bare UUID.
                                return NSItemProvider(object: task.title as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: BoardCardDropDelegate(
                                    targetTaskID: task.id,
                                    targetStage: targetStage,
                                    draggedTaskID: $draggedTaskID,
                                    onReorder: onReorder,
                                    onMoveToStage: onMoveToStage
                                )
                            )
                        }

                        if tasks.count > Self.collapsedLimit {
                            Button {
                                withAnimation(.snappy(duration: Motion.select)) { isExpanded.toggle() }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(isExpanded ? "Show Less" : "View All (\(tasks.count))")
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                }
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .modifier(HoverButtonModifier())
                        }
                    }
                    .padding(2)
                }
                .onChange(of: selectedTaskID) { _, newID in
                    guard let newID, tasks.contains(where: { $0.id == newID }) else { return }
                    // A card past the collapsed limit isn't rendered yet (no .id() to scroll
                    // to) until the column expands to actually include it.
                    if !visibleTasks.contains(where: { $0.id == newID }) { isExpanded = true }
                    withAnimation { proxy.scrollTo(newID, anchor: .center) }
                }
            }
        }
        .padding(12)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            (isVirtual ? Theme.warning.opacity(0.035) : Color.white.opacity(0.018)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isVirtual ? Theme.warning.opacity(0.22) : Theme.panelBorder, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.accent, lineWidth: isColumnTargeted ? 1.6 : 0)
        )
        .onDrop(
            of: [UTType.text],
            delegate: BoardColumnDropDelegate(
                targetStage: targetStage,
                draggedTaskID: $draggedTaskID,
                onMoveToStage: onMoveToStage,
                isTargeted: $isColumnTargeted
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Text("\(tasks.count)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Theme.mutedText)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.045), in: Capsule())
            }
            Text(laneDetail)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.mutedText)
        }
        .padding(.horizontal, 2)
    }

    private var laneDetail: String {
        switch title {
        case "Capture": return "New tasks"
        case "Ready": return "Good next choices"
        case "Scheduled": return "Planned for later"
        case "In Progress": return "Started"
        default: return ""
        }
    }

    private var emptyDetail: String {
        switch title {
        case "Capture": return "New tasks without a plan appear here."
        case "Ready": return "Helpful next choices will appear here."
        case "Scheduled": return "Tasks with a date appear here."
        case "In Progress": return "Start a task and it will appear here."
        default: return ""
        }
    }
}

private struct BoardCardDropDelegate: DropDelegate {
    let targetTaskID: UUID
    let targetStage: TaskStage?
    @Binding var draggedTaskID: UUID?
    let onReorder: (UUID, UUID) -> Void
    let onMoveToStage: (UUID, TaskStage) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedTaskID else { return false }
        let dragged = draggedTaskID

        withAnimation(.snappy(duration: Motion.dragReorder)) {
            if dragged != targetTaskID {
                onReorder(dragged, targetTaskID)
            }
            if let targetStage {
                onMoveToStage(dragged, targetStage)
            }
        }
        self.draggedTaskID = nil
        return true
    }
}

private struct BoardColumnDropDelegate: DropDelegate {
    let targetStage: TaskStage?
    @Binding var draggedTaskID: UUID?
    let onMoveToStage: (UUID, TaskStage) -> Void
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        if targetStage != nil { isTargeted = true }
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let draggedTaskID, let targetStage else {
            self.draggedTaskID = nil
            return false
        }
        withAnimation(.snappy(duration: Motion.dragReorder)) {
            onMoveToStage(draggedTaskID, targetStage)
        }
        self.draggedTaskID = nil
        return true
    }
}
