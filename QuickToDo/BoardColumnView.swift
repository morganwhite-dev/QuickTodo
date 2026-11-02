// BoardColumnView.swift
// One column of the Decision Board. Drag-and-drop reuses the same shared-state pattern as
// the existing category/task reordering (a @Binding draggedTaskID, not item-provider payload
// decoding) so dropping a card sets its stage and/or swaps its manual sort order.

import SwiftUI
import UniformTypeIdentifiers

struct BoardColumnView: View {
    let title: String
    let detail: String
    let tasks: [TaskItem]
    let allTasks: [TaskItem]
    let categories: [CategoryItem]
    var width: CGFloat = 184
    let targetStage: TaskStage
    let selectedTaskID: UUID?
    @Binding var draggedTaskID: UUID?
    // Shared with the other columns so a card flies from its old column to its new one.
    var namespace: Namespace.ID
    @Binding var finishedIDs: [UUID]
    let onSelect: (TaskItem) -> Void
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onReorder: (UUID, UUID) -> Void
    let onMoveToStage: (UUID, TaskStage) -> Void

    @State private var isColumnTargeted = false
    @State private var isExpanded = false
    // Tasks ticked off from this column this session (owned by the board, so the Next Move
    // card's Done lands here too). Completed tasks leave every lane
    // (their stage becomes Done), so this is what lets the "✓ N done" pill list them and
    // undo one straight back into the lane it came from.
    @State private var showFinished = false

    // At most this many cards show by default; "Show N more" reveals the rest.
    private static let collapsedLimit = 3

    private var visibleTasks: [TaskItem] {
        isExpanded ? tasks : Array(tasks.prefix(Self.collapsedLimit))
    }

    // Only tasks that are still completed — an undo anywhere else (Completed tab, the
    // inspector) drops them from the pill automatically.
    private var finishedTasks: [TaskItem] {
        finishedIDs.compactMap { id in allTasks.first { $0.id == id && $0.isCompleted } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Group {
                Group {
                    VStack(spacing: 10) {
                        ForEach(visibleTasks) { task in
                            TaskCard(
                                task: task,
                                allTasks: allTasks,
                                categories: categories,
                                isSelected: task.id == selectedTaskID,
                                onSelect: { onSelect(task) },
                                onToggle: {
                                    if !task.isCompleted { finishedIDs.append(task.id) }
                                    onToggle(task)
                                },
                                onEdit: { onEdit(task) },
                                onDelete: { onDelete(task) },
                                isBoardLayout: true
                            )
                            .id(task.id)
                            .matchedGeometryEffect(id: task.id, in: namespace)
                            // The card being dragged stays put but dims and shrinks a touch.
                            .opacity(draggedTaskID == task.id ? 0.4 : 1)
                            .scaleEffect(draggedTaskID == task.id ? 0.97 : 1)
                            .animation(Motion.dragLift, value: draggedTaskID)
                            // If a drag ends outside any column, the card would stay dimmed;
                            // moving the pointer back over it restores it.
                            .onHover { inside in if inside && draggedTaskID == task.id { draggedTaskID = nil } }
                            .onDrag {
                                draggedTaskID = task.id
                                // Internal reordering reads draggedTaskID, not this payload's
                                // content — so it can carry the title instead, which makes
                                // dragging a card out to Mail/Notes/Messages drop in something
                                // useful instead of a bare UUID.
                                return NSItemProvider(object: task.title as NSString)
                            } preview: {
                                DragCardPreview(title: task.title, tint: Categories.color(for: task.category, in: categories))
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
                            .transition(.opacity)
                        }

                        if tasks.isEmpty { emptyState }

                        if tasks.count > Self.collapsedLimit {
                            Button {
                                withAnimation(.snappy(duration: Motion.select)) { isExpanded.toggle() }
                            } label: {
                                Text(isExpanded ? "Show less" : "Show \(tasks.count - Self.collapsedLimit) more")
                                    .font(Fonts.ui(13, .heavy)).padding(.horizontal, 16).frame(height: 32)
                            }
                            .buttonStyle(PressableStyle(fill: Theme.card, shadow: 3, capsule: true))
                            .frame(maxWidth: .infinity)
                        }

                        finishedSection
                    }
                    .padding(.leading, 2).padding(.trailing, 6).padding(.top, 2).padding(.bottom, 8)
                    .animation(Motion.layoutShift, value: tasks.map(\.id))
                }
                .onChange(of: selectedTaskID) { _, newID in
                    guard let newID, tasks.contains(where: { $0.id == newID }) else { return }
                    // A card past the collapsed limit isn't rendered yet (no .id() to scroll
                    // to) until the column expands to actually include it.
                    if !visibleTasks.contains(where: { $0.id == newID }) { isExpanded = true }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .neoPanel()
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.ink, lineWidth: 5)
                .opacity(isColumnTargeted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.15), value: isColumnTargeted)
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased()).font(Fonts.black(19)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                NeoChip(text: "\(tasks.count)", size: 13)
            }
            Rectangle().fill(Theme.ink).frame(height: 2)
        }
    }

    // Faint centred "Nothing else due", blurred fade-in.
    private var emptyState: some View {
        VStack(spacing: 6) {
            // "Nothing else due" only after you actually finished something here.
            Text(finishedTasks.isEmpty ? "Nothing here yet" : "Nothing else due")
                .font(Fonts.bricolage(22, .heavy)).foregroundStyle(Theme.ink.opacity(0.6))
            Text(finishedTasks.isEmpty ? emptyDetail : "Great work today. Get some rest.")
                .font(Fonts.ui(13, .semibold)).foregroundStyle(Theme.ink.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .transition(.opacity.combined(with: .modifier(active: BlurFade(radius: 8), identity: BlurFade(radius: 0))))
    }

    @ViewBuilder private var finishedSection: some View {
        if !finishedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(.snappy(duration: 0.2)) { showFinished.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text("✓ \(finishedTasks.count) done")
                        Text(showFinished ? "hide" : "show").font(Fonts.ui(12, .semibold))
                    }
                    .font(Fonts.ui(13, .heavy)).padding(.horizontal, 14).frame(height: 32)
                }
                .buttonStyle(PressableStyle(fill: Theme.done, shadow: 3, capsule: true))
                if showFinished {
                    ForEach(finishedTasks) { task in
                        Button { undo(task) } label: {
                            HStack(spacing: 8) {
                                Text(task.title).strikethrough().lineLimit(1)
                                Spacer(minLength: 4)
                                Text("undo").font(Fonts.ui(12, .bold)).foregroundStyle(Theme.inkMuted)
                            }
                            .font(Fonts.ui(13, .bold)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .neoCard(Theme.card, radius: 4, shadow: 0)
                        }
                        .buttonStyle(HoverPlainStyle())
                        .help("Mark as not done and put it back in \(title)")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Unticking puts the card back in the lane it was finished from, not just in Capture.
    private func undo(_ task: TaskItem) {
        finishedIDs.removeAll { $0 == task.id }
        onToggle(task)
        onMoveToStage(task.id, targetStage)
    }

    private var emptyDetail: String {
        switch title {
        case "Capture": return "Tasks with no due date land here."
        case "Ready": return "Overdue or due within a week lands here."
        case "Scheduled": return "Due more than a week out waits here."
        case "In Progress": return "Start a task and it appears here."
        default: return ""
        }
    }
}

/// Blur + fade used by the empty states.
struct BlurFade: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
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

        withAnimation(Motion.dropSettle) {
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
        withAnimation(Motion.dropSettle) {
            onMoveToStage(draggedTaskID, targetStage)
        }
        self.draggedTaskID = nil
        return true
    }
}
