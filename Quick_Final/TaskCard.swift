// TaskCard.swift
// The one task row/card used everywhere: board columns, General/Today/Upcoming/Completed
// lists. Calm by design — color only for the checkbox ring, overdue text, and a high-priority flag.

import SwiftUI

struct TaskCard: View {
    let task: TaskItem
    let allTasks: [TaskItem]
    let categories: [CategoryItem]
    var isSelected: Bool = false
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    // Bulk-select mode (General/Today/Upcoming/Lists/Completed only — the Decision
    // Board never sets these, so it renders exactly as before).
    var isMultiSelecting: Bool = false
    var isMultiSelected: Bool = false
    var onToggleMultiSelect: (() -> Void)? = nil
    // The Decision Board's columns are narrow, single-lane, and fixed-width, so its
    // cards keep the original stacked metadata (category+timer / date / flags, each on
    // its own line). Every other list lays tasks out in a two-column grid, where each
    // lane is wide enough for category + date + flags + duration to share one packed
    // line — both layouts fill their assigned column; only the metadata density differs.
    var isBoardLayout: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var showStrikeSweep = false
    @State private var sweepExpanded = false
    // Every list filters completed tasks out immediately, so without this the row
    // would vanish the instant you tap it — no frame ever shows the completed state,
    // let alone animates it. Setting this immediately and only telling RootShellView
    // about the real completion after the animation plays keeps the card on screen
    // long enough to actually see it finish.
    @State private var isOptimisticallyDone = false

    private var listColor: Color { Categories.color(for: task.category, in: categories) }
    private var displayCompleted: Bool { task.isCompleted || isOptimisticallyDone }

    private var isOverdue: Bool {
        guard let due = task.dueDate, !displayCompleted else { return false }
        return due < Date()
    }

    private var blockedTasks: [TaskItem] { task.blockedTasks(in: allTasks) }

    private var dependsOnTask: TaskItem? {
        guard let id = task.dependsOnTaskID else { return nil }
        return allTasks.first { $0.id == id }
    }

    private var isBlocked: Bool { !isMultiSelecting && !displayCompleted && task.isBlocked(in: allTasks) }

    private var leadingIcon: String {
        if isMultiSelecting { return isMultiSelected ? "checkmark.circle.fill" : "circle" }
        if isBlocked { return "lock.circle" }
        return displayCompleted ? "checkmark.circle.fill" : "circle"
    }

    private var leadingTint: Color {
        if isMultiSelecting { return isMultiSelected ? Theme.accent : listColor.opacity(0.85) }
        if isBlocked { return Theme.mutedText }
        return displayCompleted ? Theme.lowPressure : listColor.opacity(0.85)
    }

    private var helpText: String {
        if isMultiSelecting { return isMultiSelected ? "Deselect" : "Select" }
        if isBlocked, let dependsOnTask { return "\"\(dependsOnTask.title)\" must be completed before this" }
        return displayCompleted ? "Mark as not done" : "Mark as done"
    }

    // Plays the animation locally first, then tells RootShellView to actually
    // complete the task once it's done — see isOptimisticallyDone above for why.
    private func handleLeadingTap() {
        if isMultiSelecting {
            onToggleMultiSelect?()
            return
        }
        guard !task.isCompleted else {
            onToggle()
            return
        }
        guard !isOptimisticallyDone else { return }
        guard !isBlocked else {
            onToggle()
            return
        }
        isOptimisticallyDone = true
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            onToggle()
        }
    }

    private var isPicked: Bool { isSelected || (isMultiSelecting && isMultiSelected) }

    private var highlightFill: Color {
        if isPicked { return Theme.accent.opacity(0.13) }
        return Theme.panelRaised.opacity(isHovered ? 0.92 : 0.72)
    }

    private var highlightStroke: Color {
        if isPicked { return Theme.accent.opacity(0.62) }
        return isHovered ? Color.white.opacity(0.16) : Theme.panelBorder
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Leading, like every familiar to-do app — not tucked in the corner next to
            // delete, where it was easy to miss and easy to fat-finger into a delete.
            Button(action: handleLeadingTap) {
                Image(systemName: leadingIcon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(leadingTint)
                    .symbolEffect(.bounce, value: isMultiSelecting ? isMultiSelected : displayCompleted)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .help(helpText)
            .modifier(HoverButtonModifier())

            // Board keeps delete inline, pinned to the row's right edge by a spacer.
            // Everywhere else it lives in a corner overlay on the whole card instead
            // (below), so a wrapped 3-line title never collides with it mid-row.
            VStack(alignment: .leading, spacing: isBoardLayout ? 7 : 5) {
                if isBoardLayout {
                    HStack(alignment: .top, spacing: 7) {
                        titleText
                        Spacer(minLength: 4)
                        deleteButton
                    }
                } else {
                    titleText
                }

                if isBoardLayout {
                    stackedMetadata
                } else {
                    packedMetadata
                }

                let progress = task.subtaskProgress
                if task.progressPercent != nil || progress.total > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(progressLabel(progress))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Theme.mutedText)
                        ProgressView(value: Double(cardProgress(progress)), total: 100)
                            .tint(Theme.lowPressure)
                    }
                }
            }
            .padding(.trailing, isBoardLayout ? 0 : 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if isMultiSelecting { onToggleMultiSelect?() } else { onSelect() }
        }
        .onHover { hovering in
            withAnimation(.snappy(duration: Motion.hover)) { isHovered = hovering }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(highlightFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(highlightStroke, lineWidth: isPicked ? 1.3 : 1)
        )
        // Delete pinned to the corner instead of inline (see the note above the title
        // row) — drawn after sizing is resolved, so it never affects how wide the card is.
        .overlay(alignment: .topTrailing) {
            if !isBoardLayout {
                deleteButton
                    .padding(.top, 9)
                    .padding(.trailing, 10)
            }
        }
        .contextMenu {
            Button(task.isCompleted ? "Mark Not Done" : "Mark Done", action: handleLeadingTap)
            Button("Edit…", action: onEdit)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.title)
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Select to see the recommended next move.")
        // Combining children for one clean VoiceOver stop (above) hides the checkbox/
        // edit/delete buttons as separate elements, so they're restored here as actions
        // — otherwise a VoiceOver user would have no way to complete or delete a task.
        .accessibilityAction(named: Text(helpText), handleLeadingTap)
        .accessibilityAction(named: Text("Edit"), onEdit)
        .accessibilityAction(named: Text("Delete"), onDelete)
    }

    private var titleText: some View {
        Text(task.title)
            .scaledFont(13, weight: .semibold, design: .rounded)
            .foregroundStyle(displayCompleted ? Color.secondary : Color.primary)
            .strikethrough(displayCompleted, color: .secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            // The strikethrough line itself can't animate — it's binary, not a
            // continuous value — so this draws a second line on top that sweeps
            // across once on completion, then leaves the real strikethrough in
            // place as the resting state.
            .overlay(alignment: .leading) {
                if showStrikeSweep {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.lowPressure)
                            .frame(width: sweepExpanded ? geo.size.width : 0, height: 1.4)
                            .offset(y: geo.size.height / 2 - 0.7)
                    }
                    .allowsHitTesting(false)
                    // Setting sweepExpanded = true in the same transaction that
                    // first shows this view means SwiftUI never commits a "width
                    // 0" frame to animate from — it just renders the end state
                    // immediately. onAppear fires after that initial frame is
                    // actually on screen, so the animation has something to
                    // start from.
                    .onAppear {
                        if reduceMotion {
                            sweepExpanded = true
                        } else {
                            withAnimation(.easeOut(duration: Motion.completionSweep)) { sweepExpanded = true }
                        }
                    }
                }
            }
            .onChange(of: displayCompleted) { _, completed in
                guard completed else { return }
                sweepExpanded = false
                showStrikeSweep = true
                Task {
                    try? await Task.sleep(for: .seconds(0.45))
                    showStrikeSweep = false
                }
            }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .buttonStyle(.plain)
        .help("Delete task")
        .modifier(HoverButtonModifier())
    }

    // Board columns are narrow and fixed-width — category+duration share a line with a
    // due-date line and a flags line beneath, exactly as before. This is the only
    // layout the Decision Board ever sees.
    private var stackedMetadata: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                categoryBadge
                Spacer(minLength: 0)
                durationBadge
            }

            dueDateBadge
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                statusBadges
                Spacer(minLength: 0)
            }
        }
    }

    // Every other list: each card fills one lane of a two-column grid, so category +
    // date + flags + duration all comfortably share one packed line instead of three
    // stacked ones.
    private var packedMetadata: some View {
        HStack(spacing: 8) {
            categoryBadge
            dueDateBadge.lineLimit(1)
            statusBadges
            durationBadge
        }
    }

    private var categoryBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(listColor).frame(width: 5, height: 5)
            Text(task.category)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.62))
    }

    @ViewBuilder private var dueDateBadge: some View {
        if let due = task.dueDate {
            HStack(spacing: 4) {
                Label(relativeDate(due), systemImage: "calendar")
                if let rule = task.recurrenceRule {
                    Image(systemName: "repeat")
                        .help("Repeats \(rule.label.lowercased())")
                }
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(isOverdue ? Theme.critical : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                (isOverdue ? Theme.critical : Theme.general).opacity(0.10),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
    }

    private var durationBadge: some View {
        let estimate = task.planningEstimate
        return Label(actualDurationLabel ?? estimate.shortLabel, systemImage: actualDurationLabel == nil ? "timer" : "checkmark.circle")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .help(timerHelpText(estimate))
    }

    @ViewBuilder private var statusBadges: some View {
        if (task.priority ?? .low) == .high {
            Label("High", systemImage: "flag.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.critical)
        }

        if !blockedTasks.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "link")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(blockedTasks.count)")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.warning)
            .help("Blocks: " + blockedTasks.map(\.title).joined(separator: ", "))
        }

        if let dependsOnTask {
            HStack(spacing: 3) {
                Image(systemName: "hourglass")
                    .font(.system(size: 9, weight: .semibold))
                Text(dependsOnTask.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.mutedText)
            .help("Waiting on: \(dependsOnTask.title)")
        }

        if task.rescheduleCount >= 3 {
            HStack(spacing: 3) {
                Image(systemName: "arrow.uturn.forward.circle")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(task.rescheduleCount)x")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.warning)
            .help("Pushed back \(task.rescheduleCount) times — worth asking if this is really happening")
        }
    }

    // Everything sighted users get from color and icons (overdue, priority, blocked,
    // progress) restated as text, since the combined element above only speaks the title.
    private var accessibilitySummary: String {
        var parts: [String] = []
        if displayCompleted { parts.append("Completed") }
        if isBlocked { parts.append("Blocked") }
        if (task.priority ?? .low) == .high { parts.append("High priority") }
        if let due = task.dueDate {
            parts.append(isOverdue ? "Overdue, due \(relativeDate(due))" : "Due \(relativeDate(due))")
        }
        parts.append(task.category)
        let progress = task.subtaskProgress
        if task.progressPercent != nil || progress.total > 0 {
            parts.append(progressLabel(progress))
        }
        return parts.joined(separator: ". ")
    }

    // Appends a calibration note when there's enough of your own history in this
    // category to say something real — silent otherwise, no placeholder text.
    private func timerHelpText(_ estimate: TaskDurationEstimate) -> String {
        let base: String
        if actualDurationLabel != nil {
            // The visible label is already the real time, not the estimate — the
            // tooltip's job here is just to say what this app had predicted.
            base = "Estimated \(estimate.shortLabel.dropFirst())."
        } else {
            base = estimate.friendlyReasonText
        }
        guard let note = task.calibrationNote(in: allTasks) else { return base }
        return "\(base) \(note)"
    }

    // Visible proof that Start Now/completion is actually being recorded — shows
    // real elapsed time in place of the estimate once there's something real to show,
    // instead of making you wait for the 3-task calibration threshold to see anything.
    private var actualDurationLabel: String? {
        if task.isCompleted, let started = task.startedAt, let completed = task.completedAt {
            let minutes = Int(completed.timeIntervalSince(started) / 60)
            return "Took \(Self.formatDuration(minutes))"
        }
        if !task.isCompleted, let started = task.startedAt {
            let minutes = Int(Date().timeIntervalSince(started) / 60)
            return "Started \(Self.formatDuration(minutes)) ago"
        }
        return nil
    }

    private static func formatDuration(_ minutes: Int) -> String {
        let clamped = max(0, minutes)
        guard clamped >= 60 else { return "\(clamped)m" }
        let hours = clamped / 60
        let remaining = clamped % 60
        return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
    }

    private func cardProgress(_ progress: (done: Int, total: Int)) -> Int {
        if let percent = task.progressPercent { return percent }
        guard progress.total > 0 else { return 0 }
        return Int((Double(progress.done) / Double(progress.total) * 100).rounded())
    }

    private func progressLabel(_ progress: (done: Int, total: Int)) -> String {
        if task.progressPercent != nil { return "\(cardProgress(progress))% complete" }
        return "\(progress.done) of \(progress.total) steps done"
    }
}
