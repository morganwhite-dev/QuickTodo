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
    // General groups by priority, so repeating "High" on every row there is noise.
    var hidesPriorityFlag: Bool = false
    // Sticky-note card for General's priority lanes: tinted with the list colour, drawn straight.
    var isNoteLayout: Bool = false

    @State private var isHovered = false
    @Environment(\.taskCardActions) private var cardActions
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(\.keyboardFocusedTaskID) private var keyboardFocusedID
    @State private var flashGreen = false
    @State private var confettiTrigger = 0
    // Every list filters completed tasks out immediately, so without this the row
    // would vanish the instant you tap it — no frame ever shows the completed state,
    // let alone animates it. Setting this immediately and only telling RootShellView
    // about the real completion after the animation plays keeps the card on screen
    // long enough to actually see it finish.
    @State private var isOptimisticallyDone = false

    private var listColor: Color { Categories.color(for: task.category, in: categories) }
    private var displayCompleted: Bool { task.isCompleted || isOptimisticallyDone }

    // The card sits on screen this long after the tick so the confetti and green flash
    // are actually seen before the task leaves its column / list.
    static let completionDelay: Double = 0.8

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
        confettiTrigger += 1
        withAnimation(.easeOut(duration: 0.15)) { flashGreen = true }
        Task {
            try? await Task.sleep(for: .seconds(Self.completionDelay))
            onToggle()
        }
    }

    private var isPicked: Bool { isSelected || (isMultiSelecting && isMultiSelected) }

    // A selected board card gets a warm sand fill plus a slightly heavier outline: clear at a
    // glance without being loud. (Solid black was far too heavy.)
    private var isInverted: Bool { false }
    private var isHighlighted: Bool { isPicked && isBoardLayout && !isMultiSelecting }
    private var onCardText: Color { Theme.ink }

    private var cardFill: Color {
        if flashGreen || (displayCompleted && !isBoardLayout) { return flashGreen ? Theme.done : Theme.mint }
        if isHighlighted { return Theme.sand }
        if isNoteLayout { return Categories.tint(listColor) }
        return Theme.card
    }

    private var checkbox: some View {
        Button(action: handleLeadingTap) {
            ZStack {
                Circle().fill(displayCompleted ? Theme.done : Theme.card)
                Circle().strokeBorder(isInverted ? Color.white : Theme.ink, lineWidth: 2)
                if isMultiSelecting {
                    if isMultiSelected { Image(systemName: "checkmark").font(.system(size: 12, weight: .black)) }
                } else if isBlocked {
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold))
                } else if displayCompleted {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .black))
                }
            }
            .foregroundStyle(Theme.ink)
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(HoverPlainStyle(hover: false))
        .help(helpText)
        .overlay { ConfettiBurst(trigger: confettiTrigger).allowsHitTesting(false) }
        .accessibilityLabel(helpText)
    }

    // Right-click menu, drawn by the app's themed menu instead of the system one.
    private var menuItems: [ContextItem] {
        var items: [ContextItem] = [
            .action(task.isCompleted ? "Mark Not Done" : "Mark Done", icon: "checkmark.circle", handleLeadingTap),
            .action("Edit…", icon: "pencil", onEdit)
        ]
        if !task.isCompleted {
            items.append(.divider)
            if !(task.dueDate.map { Calendar.current.isDateInToday($0) } ?? false) {
                items.append(.action("Move to Today", icon: "sun.max") { cardActions.reschedule(task, Calendar.current.startOfDay(for: .now)) })
            }
            if !(task.dueDate.map { Calendar.current.isDateInTomorrow($0) } ?? false) {
                items.append(.action("Move to Tomorrow", icon: "calendar") {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
                    cardActions.reschedule(task, tomorrow)
                })
            }
            items.append(.action("Start Now", icon: "play.fill", enabled: task.resolvedStage != .inProgress) { cardActions.moveToStage(task.id, .inProgress) })
            items.append(.action("File as Someday", icon: "tray") { cardActions.fileSomeday(task) })
            items.append(.group("Move to Column", [TaskStage.general, .ready, .scheduled, .inProgress].map { stage in
                .action(stage.boardTitle, enabled: task.resolvedStage != stage) { cardActions.moveToStage(task.id, stage) }
            }))
        }
        items.append(.divider)
        items.append(.action("Delete", icon: "trash", destructive: true, onDelete))
        return items
    }

    // The whole card is one Button so the press-in comes from the ButtonStyle. (A custom
    // DragGesture used to track presses here, and it swallowed the mouse-down that starts a
    // drag, so cards could not be dragged between columns.)
    var body: some View {
        Button {
            if isMultiSelecting { onToggleMultiSelect?() } else { onSelect() }
        } label: {
            Group {
                if isNoteLayout { noteCard } else if isBoardLayout { boardCard } else { rowCard }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(fill: cardFill, radius: 4, shadow: (isBoardLayout || isNoteLayout) ? 4 : 3))
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
        .padding(.trailing, (isBoardLayout || isNoteLayout) ? 4 : 3).padding(.bottom, (isBoardLayout || isNoteLayout) ? 4 : 3)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.ink, lineWidth: isPicked ? (isHighlighted ? 3 : 4) : (keyboardFocusedID == task.id ? 4 : 0)).padding(.trailing, 3).padding(.bottom, 3))
        .onHover { isHovered = $0 }
        .themedContextMenu { menuItems }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.title)
        .accessibilityValue(voiceOverOn ? accessibilitySummary : "")
        .accessibilityHint("Select to see the recommended next move.")
        // Combining children for one clean VoiceOver stop (above) hides the checkbox/
        // edit/delete buttons as separate elements, so they're restored here as actions
        // — otherwise a VoiceOver user would have no way to complete or delete a task.
        .accessibilityAction(named: Text(helpText), handleLeadingTap)
        .accessibilityAction(named: Text("Edit"), onEdit)
        .accessibilityAction(named: Text("Delete"), onDelete)
    }

    // Board column card: list tag + checkbox, bold title, estimate + time chips.
    private var boardCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                ListTag(name: task.category, color: listColor)
                Spacer(minLength: 6)
                // Shown on hover, in the top row so it never sits on top of the progress bar.
                deleteButton.opacity(isHovered ? 1 : 0)
                checkbox
            }
            // Everything below the tag row is a value-only subview: when only the selection or
            // another card changes, SwiftUI skips rebuilding it.
            BoardCardDetails(
                title: task.title, strike: displayCompleted, textColor: onCardText,
                waitingOn: isBlocked ? dependsOnTask?.title : nil,
                estimateText: estimateText,
                estimateHelp: isHovered ? timerHelpText(task.planningEstimate) : "",
                dueText: task.dueDate.map { Planner.compactDue($0) }, dueOverdue: isOverdue,
                progressLabel: progressText, progressValue: progressFraction
            )
            .equatable()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // General's sticky note: checkbox + estimate on top, title, one line of notes, then tag + due.
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                checkbox
                Spacer(minLength: 6)
                durationChip
            }
            titleText
            if let firstLine = task.notes.split(whereSeparator: \.isNewline).first {
                Text(String(firstLine)).font(Fonts.ui(13, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
            }
            if isBlocked, let dependsOnTask {
                Label("Waiting on \(dependsOnTask.title)", systemImage: "lock.fill")
                    .font(Fonts.ui(13, .bold)).foregroundStyle(Theme.ink).lineLimit(2)
            }
            HStack(spacing: 6) {
                ListTag(name: task.category, color: listColor, fill: .white)
                dueChip
                Spacer(minLength: 0)
            }
            extras
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { deleteButton.padding(8).opacity(isHovered ? 1 : 0).padding(.top, 36) }
    }

    // Every other list: checkbox, title (+ metadata line), list tag, estimate.
    private var rowCard: some View {
        HStack(alignment: .center, spacing: 12) {
            checkbox
            VStack(alignment: .leading, spacing: 4) {
                titleText
                HStack(spacing: 6) {
                    dueChip
                    statusBadges
                }
                extras
            }
            Spacer(minLength: 8)
            ListTag(name: task.category, color: listColor)
            durationChip
            deleteButton.opacity(isHovered ? 1 : 0.8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var extras: some View {
        let progress = task.subtaskProgress
        if task.progressPercent != nil || progress.total > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text(progressLabel(progress))
                    .font(Fonts.ui(12, .bold))
                    .foregroundStyle(isInverted ? Color.white : Theme.inkMuted)
                NeoProgressBar(value: Double(cardProgress(progress)) / 100)
            }
        }
    }

    private var titleText: some View {
        Text(task.title)
            .font(Fonts.ui(isBoardLayout ? 15 : 17, .heavy))
            .foregroundStyle(onCardText)
            .strikethrough(displayCompleted, color: onCardText)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isInverted ? Color.white : Theme.inkMuted)
        }
        .buttonStyle(HoverPlainStyle())
        .help("Delete task")
    }

    // Text for the estimate chip ("≈ 20m", or "Took 12m" / "Started 5m ago" once real time exists).
    private var estimateText: String {
        let label = actualDurationLabel ?? task.planningEstimate.shortLabel.replacingOccurrences(of: "~", with: "≈")
        return label.hasPrefix("≈") ? "≈ " + label.dropFirst() : label
    }

    private var progressText: String? {
        let progress = task.subtaskProgress
        return (task.progressPercent != nil || progress.total > 0) ? progressLabel(progress) : nil
    }

    private var progressFraction: Double {
        Double(cardProgress(task.subtaskProgress)) / 100
    }

    private var durationChip: some View {
        let estimate = task.planningEstimate
        let label = actualDurationLabel ?? estimate.shortLabel.replacingOccurrences(of: "~", with: "≈")
        return NeoChip(text: label.hasPrefix("≈") ? "≈ " + label.dropFirst() : label, size: 12)
            .help(isHovered ? timerHelpText(estimate) : "")
    }

    @ViewBuilder private var dueChip: some View {
        if let due = task.dueDate {
            let hasTime = Calendar.current.component(.hour, from: due) != 0 || Calendar.current.component(.minute, from: due) != 0
            NeoChip(
                text: isBoardLayout ? Planner.compactDue(due) : relativeDate(due),
                fill: Theme.card,
                foreground: isOverdue ? Theme.overdue : Theme.ink,
                size: 12,
                borderColor: isOverdue ? Theme.overdue : Theme.ink
            )
        }
    }

    @ViewBuilder private var statusBadges: some View {
        if (task.priority ?? .low) == .high && !hidesPriorityFlag {
            Label("High", systemImage: "flag.fill")
                .font(Fonts.ui(12, .bold)).foregroundStyle(Theme.ink)
        }
        if !blockedTasks.isEmpty {
            Label("\(blockedTasks.count)", systemImage: "link")
                .font(Fonts.ui(12, .bold)).foregroundStyle(Theme.ink)
                .help("Blocks: " + blockedTasks.map(\.title).joined(separator: ", "))
        }
        if let dependsOnTask {
            Label(dependsOnTask.title, systemImage: "hourglass")
                .font(Fonts.ui(13, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                .help("Waiting on: \(dependsOnTask.title)")
        }
        if let rule = task.recurrenceRule {
            Image(systemName: "repeat").font(.system(size: 11, weight: .bold))
                .help("Repeats \(rule.label.lowercased())")
        }
        if task.rescheduleCount >= 3 {
            Label("\(task.rescheduleCount)x", systemImage: "arrow.uturn.forward.circle")
                .font(Fonts.ui(12, .bold)).foregroundStyle(Theme.ink)
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

/// Black-bordered progress bar (done = green fill).
struct NeoProgressBar: View {
    let value: Double
    var height: CGFloat = 10
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card)
                Capsule().fill(Theme.done)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                Capsule().strokeBorder(Theme.ink, lineWidth: 2)
            }
        }
        .frame(height: height)
    }
}

/// Confetti burst around the checkbox: replays whenever `trigger` increments. The particles
/// only exist while it plays — every card used to carry 14 invisible ones all the time.
struct ConfettiBurst: View {
    let trigger: Int
    @State private var progress: CGFloat = 0
    @State private var active = false
    private static let colors: [Color] = [Theme.done, Theme.amber, Color(hex: "#8EB8F2") ?? .blue, Theme.overdue, Theme.ink]

    var body: some View {
        ZStack {
            if active {
                ForEach(0..<14, id: \.self) { i in
                    let angle = Double(i) / 14 * 2 * .pi + Double(i % 3) * 0.2
                    let dist: CGFloat = 26 + CGFloat((i * 7) % 16)
                    RoundedRectangle(cornerRadius: i % 2 == 0 ? 1 : 3)
                        .fill(Self.colors[i % Self.colors.count])
                        .frame(width: 6, height: i % 2 == 0 ? 9 : 6)
                        .rotationEffect(.degrees(Double(i) * 47 + Double(progress) * 220))
                        .offset(x: CGFloat(cos(angle)) * dist * progress, y: CGFloat(sin(angle)) * dist * progress + 10 * progress * progress)
                        .opacity(Double(1 - progress * progress))
                }
            }
        }
        .onChange(of: trigger) { _, _ in
            progress = 0
            active = true
            Task { @MainActor in
                await Task.yield()
                withAnimation(.easeOut(duration: 0.7)) { progress = 1 }
                try? await Task.sleep(for: .seconds(0.8))
                active = false
                progress = 0
            }
        }
    }
}

/// Lays children out left to right and wraps to a new line when the row is full. Cheaper and
/// more predictable than measuring several alternative layouts with ViewThatFits.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    /// Centers each row inside the width it is given (used by the list picker).
    var centered = false

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [[(LayoutSubview, CGSize)]] {
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { rows.append([]); x = 0 }
            rows[rows.count - 1].append((view, size))
            x += size.width + spacing
        }
        return rows
    }

    private func rowWidth(_ row: [(LayoutSubview, CGSize)]) -> CGFloat {
        row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let laid = rows(subviews, maxWidth: maxWidth)
        var height: CGFloat = 0
        for (i, row) in laid.enumerated() {
            height += (row.map { $0.1.height }.max() ?? 0) + (i > 0 ? spacing : 0)
        }
        let widest = laid.map(rowWidth).max() ?? 0
        let width = centered && maxWidth.isFinite ? maxWidth : widest
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, maxWidth: bounds.width) {
            let offset = centered ? max(0, (bounds.width - rowWidth(row)) / 2) : 0
            var x = bounds.minX + offset
            let rowHeight = row.map { $0.1.height }.max() ?? 0
            for (view, size) in row {
                view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
}

// MARK: - Environment plumbing for context-menu actions and keyboard row focus

/// Actions the card's context menu needs from RootShellView, injected once at the root so
/// every list/board that shows TaskCards gets them without extra parameters.
struct TaskCardActions {
    var reschedule: (TaskItem, Date) -> Void = { _, _ in }
    var moveToStage: (UUID, TaskStage) -> Void = { _, _ in }
    var fileSomeday: (TaskItem) -> Void = { _ in }
}

private struct TaskCardActionsKey: EnvironmentKey { static let defaultValue = TaskCardActions() }
private struct KeyboardFocusedTaskKey: EnvironmentKey { static let defaultValue: UUID? = nil }

extension EnvironmentValues {
    var taskCardActions: TaskCardActions {
        get { self[TaskCardActionsKey.self] }
        set { self[TaskCardActionsKey.self] = newValue }
    }
    var keyboardFocusedTaskID: UUID? {
        get { self[KeyboardFocusedTaskKey.self] }
        set { self[KeyboardFocusedTaskKey.self] = newValue }
    }
}

extension TaskStage {
    /// Column names as the Decision Board shows them.
    var boardTitle: String {
        switch self {
        case .general: return "Capture"
        case .ready: return "Ready"
        case .scheduled: return "Scheduled"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}

/// Up/Down move a black focus ring between task rows; Space or Return ticks the focused one.
struct RowKeyboardNav: ViewModifier {
    let ids: [UUID]
    @Binding var focused: UUID?
    let onToggle: (UUID) -> Void
    @FocusState private var hasFocus: Bool

    func body(content: Content) -> some View {
        content
            .environment(\.keyboardFocusedTaskID, focused)
            .focusable()
            .focused($hasFocus)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.space) { toggle() }
            .onKeyPress(.return) { toggle() }
            .onAppear { hasFocus = true }
    }

    private func move(_ by: Int) {
        guard !ids.isEmpty else { return }
        guard let current = focused, let i = ids.firstIndex(of: current) else {
            focused = by > 0 ? ids.first : ids.last
            return
        }
        focused = ids[max(0, min(ids.count - 1, i + by))]
    }

    private func toggle() -> KeyPress.Result {
        guard let id = focused, ids.contains(id) else { return .ignored }
        onToggle(id)
        return .handled
    }
}

/// The body of a board card (title, "waiting on", chips, progress) as plain values. It is
/// Equatable, so SwiftUI only rebuilds it when one of these values actually changes.
struct BoardCardDetails: View, Equatable {
    let title: String
    let strike: Bool
    let textColor: Color
    let waitingOn: String?
    let estimateText: String
    let estimateHelp: String
    let dueText: String?
    let dueOverdue: Bool
    let progressLabel: String?
    let progressValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Fonts.ui(15, .heavy))
                .foregroundStyle(textColor)
                .strikethrough(strike, color: textColor)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let waitingOn {
                Label("Waiting on \(waitingOn)", systemImage: "lock.fill")
                    .font(Fonts.ui(13, .bold)).foregroundStyle(textColor).lineLimit(2)
            }
            // Side by side when they fit; wraps to a second line in a narrow column.
            WrapLayout(spacing: 6) {
                NeoChip(text: estimateText, size: 12).help(estimateHelp)
                if let dueText {
                    NeoChip(
                        text: dueText, fill: Theme.card,
                        foreground: dueOverdue ? Theme.overdue : Theme.ink, size: 12,
                        borderColor: dueOverdue ? Theme.overdue : Theme.ink
                    )
                }
            }
            if let progressLabel {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progressLabel).font(Fonts.ui(12, .bold)).foregroundStyle(Theme.inkMuted)
                    NeoProgressBar(value: progressValue)
                }
            }
        }
    }
}
