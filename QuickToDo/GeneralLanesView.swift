// GeneralLanesView.swift
// General = the capture inbox / triage. Three side-by-side priority lanes (High, Medium,
// Low) of sticky-note cards tinted with each task's list colour. Dragging a note to another
// lane changes its priority. Same tick / select / edit / delete / keyboard behaviour as before.

import SwiftUI
import UniformTypeIdentifiers

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
    let onSetPriority: (UUID, TaskPriority) -> Void

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var focusedID: UUID?
    @State private var draggedID: UUID?
    @State private var targetedLane: TaskPriority?

    private var generalTasks: [TaskItem] {
        tasks.filter { !$0.isCompleted && $0.resolvedStage == .general && matches($0, search) }.sortedChronologically()
    }
    private func lane(_ p: TaskPriority) -> [TaskItem] { generalTasks.filter { ($0.priority ?? .low) == p } }

    // Counts and time are on the lane headers; the subtitle is just the tone.
    private var subtitle: String {
        switch generalTasks.count {
        case 0: return "Nothing waiting to be sorted."
        case 1: return "One thing to sort. Easy."
        case 2...5: return "A few to sort. Priority first."
        case 6...15: return "Triage mode. Highest priority first."
        default: return "Deep breath. Start at the top."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("General").font(Fonts.black(46)).foregroundStyle(.white)
                    Text(subtitle).font(Fonts.ui(16, .bold)).foregroundStyle(.white)
                        .contentTransition(.opacity).animation(.easeInOut(duration: 0.25), value: subtitle)
                }
                Spacer()
                HStack(spacing: 12) {
                    SelectModeButton(isSelecting: $isSelecting) { isSelecting = false; selectedIDs = [] }
                    NewTaskButton(action: onNewTask)
                }
            }

            if isSelecting {
                BulkActionBar(
                    count: selectedIDs.count,
                    onComplete: { onBulkComplete(selectedIDs); selectedIDs = [] },
                    onDelete: { onBulkDelete(selectedIDs); selectedIDs = [] },
                    onCancel: { isSelecting = false; selectedIDs = [] }
                )
            }

            if generalTasks.isEmpty {
                inboxZero
            } else {
                HStack(alignment: .top, spacing: 20) {
                    laneView(.high)
                    laneView(.medium)
                    laneView(.low)
                }
                .frame(maxHeight: .infinity)
                .modifier(RowKeyboardNav(
                    ids: (lane(.high) + lane(.medium) + lane(.low)).map(\.id), focused: $focusedID,
                    onToggle: { id in if let t = tasks.first(where: { $0.id == id }) { onToggle(t) } }
                ))
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Lanes

    private func laneTitle(_ p: TaskPriority) -> String { p.label.uppercased() }

    // Clear dark -> mid -> light weight so priority reads at a glance (neutral blues only;
    // amber/red/green keep their own meanings elsewhere in the app).
    private func headerFill(_ p: TaskPriority) -> Color {
        switch p {
        case .high: return Color(hex: "#0A0F18") ?? Theme.ink
        case .medium: return Color(hex: "#43607F") ?? Theme.ink
        case .low: return Color(hex: "#FFFFFF") ?? Theme.card
        }
    }

    private func laneFill(_ p: TaskPriority) -> Color {
        switch p {
        case .high: return Color(hex: "#26354C") ?? Theme.ink
        case .medium: return Color(hex: "#8DA5BF") ?? Theme.panel
        case .low: return Theme.panel
        }
    }

    private func headerForeground(_ p: TaskPriority) -> Color { p == .low ? Theme.ink : .white }
    /// Text that sits directly on the lane panel (empty hint).
    private func laneText(_ p: TaskPriority) -> Color { p == .high ? .white : Theme.ink }

    private func laneView(_ p: TaskPriority) -> some View {
        let items = lane(p)
        let minutes = Planner.openMinutes(items)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(laneTitle(p)).font(Fonts.black(16)).tracking(0.6)
                NeoChip(text: "\(items.count)", fill: Theme.card, size: 12)
                Spacer(minLength: 0)
                Text("≈ \(Planner.label(minutes: minutes))").font(Fonts.ui(13, .heavy))
            }
            .foregroundStyle(headerForeground(p))
            .padding(.horizontal, 14).frame(height: 44)
            .background(headerFill(p))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 2) }

            ScrollView {
                VStack(spacing: 12) {
                    if items.isEmpty {
                        Text(targetedLane == p ? "Drop to make \(p.label.lowercased())" : "Nothing here")
                            .font(Fonts.ui(15, .bold)).foregroundStyle(laneText(p))
                            .frame(maxWidth: .infinity, minHeight: 90)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(laneText(p), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    }
                    ForEach(items) { task in
                        TaskCard(
                            task: task, allTasks: tasks, categories: categories,
                            isSelected: selectedTask?.id == task.id,
                            onSelect: { selectedTask = selectedTask?.id == task.id ? nil : task },
                            onToggle: { onToggle(task) }, onEdit: { onEdit(task) }, onDelete: { onDelete(task) },
                            isMultiSelecting: isSelecting,
                            isMultiSelected: selectedIDs.contains(task.id),
                            onToggleMultiSelect: {
                                if selectedIDs.contains(task.id) { selectedIDs.remove(task.id) } else { selectedIDs.insert(task.id) }
                            },
                            hidesPriorityFlag: true,
                            isNoteLayout: true
                        )
                        .id(task.id)
                        .opacity(draggedID == task.id ? 0.4 : 1)
                        .scaleEffect(draggedID == task.id ? 0.97 : 1)
                        .animation(Motion.dragLift, value: draggedID)
                        .onHover { inside in if inside && draggedID == task.id { draggedID = nil } }
                        .onDrag {
                            draggedID = task.id
                            return NSItemProvider(object: task.title as NSString)
                        } preview: {
                            DragCardPreview(title: task.title, tint: Categories.color(for: task.category, in: categories))
                        }
                    }
                }
                .padding(14)
                .animation(Motion.layoutShift, value: items.map(\.id))
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(laneFill(p))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .neoCard(laneFill(p), radius: 5, shadow: 5)
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.ink, lineWidth: 5)
                .opacity(targetedLane == p ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.15), value: targetedLane)
        .padding(.trailing, 5).padding(.bottom, 5)
        .onDrop(of: [UTType.text], delegate: PriorityLaneDrop(
            priority: p, draggedID: $draggedID, targeted: $targetedLane, onSetPriority: onSetPriority
        ))
    }

    // Natural-size empty state (nothing stretched to fill the page).
    private var inboxZero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing to sort").font(Fonts.black(30)).foregroundStyle(Theme.ink)
            Text("Tasks without a due date or plan show up here so you can set their priority. Add one with + New Task or + Capture.")
                .font(Fonts.ui(15, .semibold)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 620, alignment: .leading)
        .neoCard(Theme.mint, radius: 8, shadow: 5)
        .padding(.trailing, 5).padding(.bottom, 5)
    }
}

/// Dropping a note on a lane sets its priority to that lane's.
private struct PriorityLaneDrop: DropDelegate {
    let priority: TaskPriority
    @Binding var draggedID: UUID?
    @Binding var targeted: TaskPriority?
    let onSetPriority: (UUID, TaskPriority) -> Void

    func dropEntered(info: DropInfo) { targeted = priority }
    func dropExited(info: DropInfo) { if targeted == priority { targeted = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        targeted = nil
        guard let id = draggedID else { return false }
        draggedID = nil
        withAnimation(Motion.dropSettle) { onSetPriority(id, priority) }
        return true
    }
}
