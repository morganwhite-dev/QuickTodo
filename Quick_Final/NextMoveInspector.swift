// NextMoveInspector.swift
// The right-side inspector. This is the app's one deliberately loud moment — the
// RecommendationCard is the only saturated, glowing surface anywhere in QuickToDo.
// Everything else in this file stays calm so that card reads as "the answer."

import SwiftUI

struct EmptyNextMoveInspector: View {
    let tasks: [TaskItem]
    let onSelect: (TaskItem) -> Void

    // Suggests from every active task that isn't already being worked on — priority,
    // how many other tasks it's blocking, and whether it's a quick win all count, not
    // just an upcoming due date, so there's still something worth doing on a day
    // with nothing pressing scheduled.
    private var suggestion: TaskItem? {
        let candidates = tasks.filter { !$0.isCompleted && $0.resolvedStage != .inProgress }
        return NextMoveEngine.suggested(from: candidates, in: tasks, limit: 1).first
    }

    private var recommendation: NextMoveRecommendation? {
        guard let suggestion else { return nil }
        return NextMoveEngine.recommend(for: suggestion, in: tasks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Next Move", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                }

                Divider().overlay(Color.white.opacity(0.08))

                if let suggestion, let recommendation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(suggestion.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)

                        RecommendationCard(recommendation: recommendation)

                        Button("Open This Task") { onSelect(suggestion) }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accent)
                            .modifier(HoverButtonModifier())
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("All clear")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Nothing stands out right now. Select a task to see why it matters and what you can do next.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .panelCard()
                }

                Spacer()
            }
            .padding(14)
        }
        .frame(minWidth: 340, idealWidth: 360, maxWidth: 420, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.sidebar)
    }
}

struct NextMoveInspector: View {
    let task: TaskItem
    let allTasks: [TaskItem]
    let categories: [CategoryItem]
    let onClose: () -> Void
    let onEdit: (TaskItem) -> Void
    let onSetStage: (TaskItem, TaskStage) -> Void
    let onScheduleConfirm: (TaskItem, Date) -> Void
    let onSetSubtasks: (TaskItem, [Subtask]) -> Void
    let onSetProgress: (TaskItem, Int) -> Void
    let onFileSomeday: (TaskItem) -> Void

    @State private var showInlineScheduler = false
    @State private var draftScheduleDate = Date().addingTimeInterval(86400)
    @State private var showSubtaskEditor = false

    private var recommendation: NextMoveRecommendation? {
        NextMoveEngine.recommend(for: task, in: allTasks)
    }

    private var blockerTask: TaskItem? {
        guard !task.isCompleted, task.isBlocked(in: allTasks), let id = task.dependsOnTaskID else { return nil }
        return allTasks.first { $0.id == id }
    }

    // Once this task is done it isn't blocking anyone in practice anymore, even
    // though other tasks may still structurally point at it.
    private var tasksWaitingOnThis: [TaskItem] {
        guard !task.isCompleted else { return [] }
        return task.blockedTasks(in: allTasks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                Divider().overlay(Color.white.opacity(0.08))

                if let blockerTask {
                    LockedBanner(blockerTitle: blockerTask.title)
                }

                if !tasksWaitingOnThis.isEmpty {
                    BlockingOthersBanner(blockedTitles: tasksWaitingOnThis.map(\.title))
                }

                TaskSummarySection(task: task, categories: categories)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Details")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(task.notes.isEmpty ? "No details added." : task.notes)
                        .scaledFont(12.5)
                        .foregroundStyle(task.notes.isEmpty ? Color.secondary : Color.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !task.isCompleted {
                    TaskProgressSection(
                        task: task,
                        onProgress: { onSetProgress(task, $0) },
                        onStepsChange: { onSetSubtasks(task, $0) }
                    )
                }

                if task.isCompleted {
                    CompletedBadge()
                } else if let recommendation {
                    RecommendationCard(recommendation: recommendation)

                    Text("Actions")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ActionButtonsStack(
                        recommended: recommendation.action,
                        onStartNow: { onSetStage(task, .inProgress) },
                        onSchedule: {
                            draftScheduleDate = task.dueDate
                                ?? Calendar.current.date(byAdding: .day, value: 1, to: Date())
                                ?? Date()
                            showInlineScheduler = true
                        },
                        onBreakIntoSteps: { showSubtaskEditor = true },
                        onFile: { onFileSomeday(task) }
                    )
                }

            }
            .padding(14)
        }
        .frame(minWidth: 340, idealWidth: 360, maxWidth: 420)
        .background(Theme.sidebar)
        .sheet(isPresented: $showSubtaskEditor) {
            SubtaskEditorView(task: task) { steps in
                onSetSubtasks(task, steps)
                showSubtaskEditor = false
            }
        }
        .sheet(isPresented: $showInlineScheduler) {
            ScheduleTaskView(taskTitle: task.title, date: draftScheduleDate) { date in
                onScheduleConfirm(task, date)
                showInlineScheduler = false
            }
        }
    }

    private var header: some View {
        HStack {
            Label("Next Move", systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Spacer()

            Button { onEdit(task) } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit task details")
            .modifier(HoverButtonModifier())

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close inspector")
            .modifier(HoverButtonModifier())
        }
    }

}

private struct TaskProgressSection: View {
    let task: TaskItem
    let onProgress: (Int) -> Void
    let onStepsChange: ([Subtask]) -> Void

    private var progress: (done: Int, total: Int) { task.subtaskProgress }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Progress")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text("\(displayedPercent)% done")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.mutedText)
            }

            Slider(
                value: Binding(
                    get: { Double(displayedPercent) },
                    set: { onProgress(Int($0)) }
                ),
                in: 0...100,
                step: 10
            )
            .tint(Theme.lowPressure)

            if !task.subtaskList.isEmpty {
                Divider().overlay(Theme.divider)
                Text("Steps")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.mutedText)
                VStack(spacing: 6) {
                    ForEach(task.subtaskList) { step in
                    Button {
                        var updated = task.subtaskList
                        guard let index = updated.firstIndex(where: { $0.id == step.id }) else { return }
                        updated[index].isDone.toggle()
                        onStepsChange(updated)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.isDone ? Theme.lowPressure : Color.secondary)
                            Text(step.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .strikethrough(step.isDone, color: .secondary)
                                .foregroundStyle(step.isDone ? Color.secondary : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                }
            }
        }
        .padding(12)
        .panelCard()
    }

    private var displayedPercent: Int {
        if let percent = task.progressPercent { return percent }
        guard progress.total > 0 else { return 0 }
        return Int((Double(progress.done) / Double(progress.total) * 100).rounded())
    }
}

private struct TaskSummarySection: View {
    let task: TaskItem
    let categories: [CategoryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Categories.color(for: task.category, in: categories))
                    .frame(width: 9, height: 9)
                    .padding(.top, 6)

                Text(task.title)
                    .scaledFont(16, weight: .semibold)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)

            }

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Categories.color(for: task.category, in: categories))
                        .frame(width: 7, height: 7)
                    Text(task.category)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05), in: Capsule())

                if let due = task.dueDate {
                    Text(relativeDate(due))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05), in: Capsule())
                }

                Text(task.resolvedStage.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05), in: Capsule())
            }

            Label(task.planningEstimate.friendlyReasonText, systemImage: "timer")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.mutedText)
                .help(task.planningEstimate.friendlyReasonText)
        }
    }
}

private struct RecommendationCard: View {
    let recommendation: NextMoveRecommendation

    private let tint = Theme.accent

    private var glowIntensity: Double {
        switch recommendation.action {
        case .startNow: return 0.5
        case .quickWin: return 0.42
        case .breakIntoSteps: return 0.38
        case .schedule: return 0.3
        case .file: return 0.16
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "scope")
                .font(.system(size: 62, weight: .light))
                .foregroundStyle(tint.opacity(0.34))
                .padding(.top, 36)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                    Text("Recommended Next Move")
                        .font(.system(size: 11, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(tint)

                Text(recommendation.headline)
                    .scaledFont(19, weight: .bold, design: .rounded)
                    .frame(maxWidth: 230, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(recommendation.summary)
                    .scaledFont(12.5)
                    .foregroundStyle(.primary.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                if !recommendation.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider().overlay(Color.white.opacity(0.12))
                        Text("Why this?")
                            .font(.system(size: 11.5, weight: .semibold))
                        ForEach(recommendation.reasons) { reason in
                            HStack(spacing: 6) {
                                Image(systemName: reason.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(tint)
                                    .frame(width: 14)
                                Text(reason.text)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.primary.opacity(0.85))
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.5), lineWidth: 1.2)
        )
        .glow(tint, radius: 18, intensity: glowIntensity)
    }
}

private struct ActionButtonsStack: View {
    let recommended: NextMoveAction
    let onStartNow: () -> Void
    let onSchedule: () -> Void
    let onBreakIntoSteps: () -> Void
    let onFile: () -> Void

    private var primaryAction: NextMoveAction {
        switch recommended {
        case .startNow, .quickWin: return .startNow
        case .breakIntoSteps: return .breakIntoSteps
        case .schedule: return .schedule
        case .file: return .file
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            actionButton(.startNow, perform: onStartNow)
            actionButton(.schedule, perform: onSchedule)
            actionButton(.breakIntoSteps, perform: onBreakIntoSteps)
            actionButton(.file, perform: onFile)
        }
    }

    @ViewBuilder
    private func actionButton(_ action: NextMoveAction, perform: @escaping () -> Void) -> some View {
        let isPrimary = action == primaryAction
        Button(action: perform) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Image(systemName: action.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(action.label)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                isPrimary ? Theme.accent : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isPrimary ? Color.clear : Color.white.opacity(0.09), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .modifier(HoverButtonModifier())
        .help(action == .file ? "Move to General and remove its due date" : action.label)
    }
}

private struct SubtaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    let onSave: ([Subtask]) -> Void

    @State private var steps: [Subtask]
    @State private var newStep = ""
    @State private var isSuggestingSteps = false
    @FocusState private var newStepFocused: Bool

    init(task: TaskItem, onSave: @escaping ([Subtask]) -> Void) {
        self.task = task
        self.onSave = onSave
        _steps = State(initialValue: task.subtaskList)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Break Into Steps")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(task.title)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if TaskAI.isAvailable {
                    Button(action: suggestSteps) {
                        if isSuggestingSteps {
                            ProgressView().controlSize(.small).frame(width: 16)
                        } else {
                            Label("Suggest Steps", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.glass)
                    .tint(Theme.accent)
                    .disabled(isSuggestingSteps)
                    .modifier(HoverButtonModifier())
                    .help("Suggest a few steps using on-device AI — nothing leaves your Mac")
                }
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close without saving")
                    .modifier(HoverButtonModifier())
            }
            .padding(18)

            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                LazyVStack(spacing: 8) {
                    if steps.isEmpty {
                        Text(TaskAI.isAvailable ? "Add the first concrete step below, or let AI suggest a few." : "Add the first concrete step below.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    }

                    ForEach($steps) { $step in
                        HStack(spacing: 9) {
                            Button { step.isDone.toggle() } label: {
                                Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(step.isDone ? Theme.lowPressure : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .modifier(HoverButtonModifier())
                            TextField("Step", text: $step.title.autoCapitalized()).textFieldStyle(.plain)
                            Button { steps.removeAll { $0.id == step.id } } label: {
                                Image(systemName: "trash").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain).help("Delete step")
                            .modifier(HoverButtonModifier())
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                .padding(18)
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 8) {
                TextField("Add a step", text: $newStep.autoCapitalized())
                    .textFieldStyle(.plain).focused($newStepFocused).onSubmit(addStep)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                Button(action: addStep) { Image(systemName: "plus") }
                    .buttonStyle(.glass).disabled(trimmedNewStep.isEmpty)
                    .modifier(HoverButtonModifier())
            }
            .padding(.horizontal, 18).padding(.top, 14)

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Spacer()
                Button("Save Steps") {
                    onSave(steps.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
                .buttonStyle(.glassProminent).tint(Theme.accent)
            }
            .padding(18)
        }
        .frame(width: 460, height: 480)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear { newStepFocused = true }
    }

    private var trimmedNewStep: String {
        newStep.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addStep() {
        guard !trimmedNewStep.isEmpty else { return }
        steps.append(Subtask(title: trimmedNewStep))
        newStep = ""
        newStepFocused = true
    }

    private func suggestSteps() {
        isSuggestingSteps = true
        Task {
            defer { isSuggestingSteps = false }
            if let suggestions = try? await TaskAI.suggestSteps(title: task.title, notes: task.notes) {
                for title in suggestions {
                    steps.append(Subtask(title: title))
                }
            }
        }
    }
}

private struct ScheduleTaskView: View {
    @Environment(\.dismiss) private var dismiss
    let taskTitle: String
    let onSchedule: (Date) -> Void
    @State private var date: Date

    init(taskTitle: String, date: Date, onSchedule: @escaping (Date) -> Void) {
        self.taskTitle = taskTitle
        self.onSchedule = onSchedule
        _date = State(initialValue: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("When should this happen?")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(taskTitle).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close without scheduling")
                    .modifier(HoverButtonModifier())
            }
            .padding(20)

            Divider().overlay(Theme.divider)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("QUICK CHOICES")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.mutedText)

                    quickChoice("Later today", icon: "sun.max", date: laterToday)
                    quickChoice("Tomorrow morning", icon: "sunrise", date: tomorrowMorning)
                    quickChoice("This evening", icon: "moon.stars", date: thisEvening)
                    quickChoice("Next Monday", icon: "calendar", date: nextMonday)

                    Divider().overlay(Theme.divider).padding(.vertical, 4)

                    Text("TIME")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.mutedText)

                    DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .controlSize(.large)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scheduled for")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.mutedText)
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                }
                .frame(width: 170)

                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .controlSize(.large)
                    .scaleEffect(1.12)
                    .frame(width: 430, height: 340)
                    .padding(16)
                    .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)

            if date <= Date() {
                Text("Choose a future date and time.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.critical)
                    .padding(.horizontal, 20)
            }

            Divider().overlay(Theme.divider).padding(.top, 14)

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Spacer()
                Button("Schedule Task") { onSchedule(date) }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .disabled(date <= Date())
            }
            .padding(20)
        }
        .frame(width: 720)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func quickChoice(_ title: String, icon: String, date choice: Date) -> some View {
        Button {
            date = choice
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
                if abs(date.timeIntervalSince(choice)) < 60 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var laterToday: Date {
        let calendar = Calendar.current
        return calendar.nextDate(
            after: Date(),
            matching: DateComponents(minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
    }

    private var tomorrowMorning: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var thisEvening: Date {
        let calendar = Calendar.current
        let todayAtSix = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        if todayAtSix > Date() { return todayAtSix }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86400)
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var nextMonday: Date {
        let calendar = Calendar.current
        let monday = calendar.nextDate(
            after: Date(),
            matching: DateComponents(weekday: 2),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(7 * 86400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: monday) ?? monday
    }
}

// Spelled out as text instead of relying on the card's hover-only badges — this is
// the one place that should never require hovering over a small icon to understand
// why a task can't be finished yet.
private struct LockedBanner: View {
    let blockerTitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text("Locked")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("\"\(blockerTitle)\" must be completed before this can be marked done.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .panelCard(tint: Theme.warning.opacity(0.3))
    }
}

// The mirror image of LockedBanner — shown on the task being waited on, not the one
// waiting. Same reasoning: spelled out as text, not left to the card's hover-only badge.
private struct BlockingOthersBanner: View {
    let blockedTitles: [String]

    private var headline: String {
        blockedTitles.count == 1 ? "Blocking 1 Task" : "Blocking \(blockedTitles.count) Tasks"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 13.5, weight: .semibold))
                Text("\(blockedTitles.joined(separator: ", ")) can't be completed until this one is done.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .panelCard(tint: Theme.warning.opacity(0.3))
    }
}

private struct CompletedBadge: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.lowPressure)

            VStack(alignment: .leading, spacing: 2) {
                Text("Completed")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Nothing left to decide here.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .panelCard(tint: Theme.lowPressure.opacity(0.3))
    }
}
