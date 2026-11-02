// TaskComposer.swift
// The full task editor — used both to create a new task ("Detailed Task" from Quick
// Capture) and, in edit mode, from the Next Move inspector's "Edit Details" action.

import SwiftUI

struct ComposerFieldStyle: ViewModifier {
    let isFocused: Bool
    var minHeight: CGFloat = 36

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(Fonts.ui(16, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.ink)
                    .offset(x: isFocused ? 4 : 0, y: isFocused ? 4 : 0)
            )
    }
}

/// Themed 0–100% slider in steps of 10: tap or drag along the bar.
struct NeoSlider: View {
    @Binding var value: Int

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = width * CGFloat(value) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.panel)
                Capsule().fill(Theme.done).frame(width: max(0, x))
                Capsule().strokeBorder(Theme.ink, lineWidth: 2)
                Circle().fill(Theme.card).frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                    .offset(x: min(max(0, x - 13), width - 26))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let fraction = max(0, min(1, drag.location.x / max(width, 1)))
                    let stepped = Int((fraction * 10).rounded()) * 10
                    if stepped != value { value = stepped }
                }
            )
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(value) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(100, value + 10)
            case .decrement: value = max(0, value - 10)
            @unknown default: break
            }
        }
    }
}

/// Toggle switch: 48x28 capsule, green when on, white knob with black ring.
struct NeoToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.done : Theme.panel)
                Circle().fill(Theme.card).frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                    .padding(2)
            }
            .frame(width: 48, height: 28)
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
        }
        .buttonStyle(HoverPlainStyle())
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

extension View {
    func composerFieldStyle(isFocused: Bool, minHeight: CGFloat = 36) -> some View {
        modifier(ComposerFieldStyle(isFocused: isFocused, minHeight: minHeight))
    }
}

extension Binding where Value == String {
    // Capitalizes just the first character as you type, leaving the rest of what
    // you typed alone — lighter-touch than full sentence auto-capitalization, and
    // never fights you mid-word since the string's length never changes.
    func autoCapitalized() -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                guard let first = newValue.first else {
                    wrappedValue = newValue
                    return
                }
                wrappedValue = String(first).uppercased() + newValue.dropFirst()
            }
        )
    }
}

struct HoverButtonModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .onHover { hovering in
                withAnimation(.snappy(duration: Motion.hover)) {
                    isHovered = hovering
                }
            }
    }
}

// Bundles everything the composer can produce, so the save closure doesn't grow an
// ever-longer positional tuple as fields get added.
struct TaskComposerResult {
    var title: String
    var notes: String
    var dueDate: Date?
    var categoryName: String
    var categoryColor: Color?
    var priority: TaskPriority
    var reminderSchedule: ReminderSchedule
    var customReminderMinutes: [Int]?
    var recurrenceRule: RecurrenceRule?
    var estimatedMinutes: Int?
    var dependsOnTaskID: UUID?
    var subtasks: [Subtask] = []
    // Set only when the progress slider was moved (edit mode).
    var progressPercent: Int? = nil
}

struct NewTaskComposerView: View {
    @Binding var isPresented: Bool
    let categories: [CategoryItem]
    let defaultCategory: String
    // All other tasks, used for the "Depends on" picker (and its cycle check). Pass an
    // empty array when creating from a context with no task list handy.
    let allTasks: [TaskItem]
    // When editing an existing task, pass it here to prefill every field.
    let existingTask: TaskItem?
    let onSave: (TaskComposerResult) -> Void
    // Edit mode only: footer Delete / Mark done.
    var onDelete: (() -> Void)? = nil
    var onToggleDone: (() -> Void)? = nil

    @State private var steps: [Subtask] = []
    @State private var progressTouched: Int?
    @State private var newStep = ""
    @State private var isSuggesting = false
    @State private var isCreatingList = false
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var categoryName: String
    @State private var categoryColor: Color
    @State private var priority: TaskPriority = .low
    @State private var reminderMode: ReminderMode = .preset
    @State private var reminderSchedule: ReminderSchedule = .none
    @State private var customReminderMinutes: [Int] = []
    @State private var isRecurring = false
    @State private var recurrenceRule: RecurrenceRule = .weekly
    @State private var hasEstimate: Bool
    @State private var estimatedMinutes: Int
    @State private var dependsOnTaskID: UUID?
    @State private var showColorPicker = false
    @FocusState private var focusedComposerField: ComposerField?

    private enum ComposerField: Hashable {
        case title
        case notes
        case category
    }

    private enum ReminderMode: String, CaseIterable {
        case preset = "Preset"
        case custom = "Custom"
    }

    private let presetColors: [Color] = [Color(hex: "#9FE2A8") ?? .green, Color(hex: "#8EB8F2") ?? .blue, Color(hex: "#F5E6C8") ?? .yellow, Color(hex: "#F4A9B8") ?? .pink, Color(hex: "#C7B3F0") ?? .purple, Color(hex: "#F5C28F") ?? .orange]
    private let estimatePresets = [5, 15, 30, 60, 120]

    init(
        isPresented: Binding<Bool>,
        categories: [CategoryItem],
        defaultCategory: String,
        allTasks: [TaskItem] = [],
        existingTask: TaskItem? = nil,
        onSave: @escaping (TaskComposerResult) -> Void,
        onDelete: (() -> Void)? = nil,
        onToggleDone: (() -> Void)? = nil
    ) {
        self.onDelete = onDelete
        self.onToggleDone = onToggleDone
        _isPresented = isPresented
        self.categories = categories
        self.defaultCategory = defaultCategory
        self.allTasks = allTasks
        self.existingTask = existingTask
        self.onSave = onSave

        if let task = existingTask {
            _title = State(initialValue: task.title)
            _notes = State(initialValue: task.notes)
            _hasDueDate = State(initialValue: task.dueDate != nil)
            _dueDate = State(initialValue: task.dueDate ?? Date())
            _categoryName = State(initialValue: task.category)
            _categoryColor = State(initialValue: Categories.color(for: task.category, in: categories))
            _priority = State(initialValue: task.priority ?? .low)
            _reminderSchedule = State(initialValue: task.reminderSchedule ?? .none)
            _reminderMode = State(initialValue: (task.customReminderMinutes?.isEmpty ?? true) ? .preset : .custom)
            _customReminderMinutes = State(initialValue: task.customReminderMinutes ?? [])
            _isRecurring = State(initialValue: task.recurrenceRule != nil)
            _recurrenceRule = State(initialValue: task.recurrenceRule ?? .weekly)
            _hasEstimate = State(initialValue: task.estimatedMinutes != nil)
            _estimatedMinutes = State(initialValue: task.estimatedMinutes ?? 15)
            _dependsOnTaskID = State(initialValue: task.dependsOnTaskID)
            _steps = State(initialValue: task.subtaskList)
        } else {
            let initialCategory = SidebarSection.reservedNames.contains(defaultCategory) ? "" : defaultCategory
            _categoryName = State(initialValue: initialCategory)
            _categoryColor = State(initialValue: initialCategory.isEmpty ? (Color(hex: "#9FE2A8") ?? .green) : Categories.color(for: initialCategory, in: categories))
            _hasEstimate = State(initialValue: false)
            _estimatedMinutes = State(initialValue: 15)
            _dependsOnTaskID = State(initialValue: nil)
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCategory: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveTask() {
        guard !trimmedTitle.isEmpty else { return }
        let finalCustomMinutes = reminderMode == .custom && hasDueDate ? customReminderMinutes : nil
        let finalSchedule: ReminderSchedule = hasDueDate && reminderMode == .preset ? reminderSchedule : .none
        onSave(TaskComposerResult(
            title: trimmedTitle,
            notes: notes,
            dueDate: hasDueDate ? dueDate : nil,
            categoryName: trimmedCategory,
            categoryColor: trimmedCategory.isEmpty ? nil : categoryColor,
            priority: priority,
            reminderSchedule: finalSchedule,
            customReminderMinutes: finalCustomMinutes,
            recurrenceRule: hasDueDate && isRecurring ? recurrenceRule : nil,
            estimatedMinutes: hasEstimate ? estimatedMinutes : nil,
            dependsOnTaskID: dependsOnTaskID,
            subtasks: steps.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            progressPercent: progressTouched
        ))
        isPresented = false
    }

    private var visibleCategories: [CategoryItem] {
        categories.filter { $0.name != "General" }
    }

    // Other open tasks, minus this one, minus anything that would create a dependency cycle.
    private var dependencyCandidates: [TaskItem] {
        allTasks.filter { candidate in
            guard !candidate.isCompleted, candidate.id != existingTask?.id else { return false }
            guard let existingTask else { return true }
            return !existingTask.wouldCreateCycle(dependingOn: candidate.id, in: allTasks)
        }
    }

    private var stepsDone: Int { steps.filter(\.isDone).count }
    private var isDone: Bool { existingTask?.isCompleted ?? false }

    private func label(_ text: String) -> some View {
        Text(text).font(Fonts.ui(13, .heavy)).tracking(1.2).foregroundStyle(Theme.ink)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            NeoToggle(isOn: isOn)
            Text(title).font(Fonts.ui(16, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
            trailing().font(Fonts.ui(15, .bold)).foregroundStyle(Theme.ink)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    leftColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                    rightColumn.frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(24)
            }
            .scrollIndicators(.never)
            footer
        }
        .frame(width: 1100, height: 720)
        .background(Theme.navBar)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
        .preferredColorScheme(.light)
        .dropdownHost()
        .sheet(isPresented: $showColorPicker) {
            ColorPickerView(selectedColor: $categoryColor, isPresented: $showColorPicker) { color in
                categoryColor = color
            }
        }
        .onAppear { focusedComposerField = .title }
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            Text(existingTask == nil ? "New Task" : "Edit Task")
                .font(Fonts.black(24)).foregroundStyle(.white)
            if !trimmedCategory.isEmpty { ListTag(name: trimmedCategory, color: categoryColor) }
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .black)).frame(width: 38, height: 38)
            }
            .buttonStyle(PressableStyle(fill: Theme.card, shadow: 0))
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(Color(hex: "#0B1E3A") ?? .black)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 2) }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                label("TITLE")
                TextField("What do you need to do?", text: $title.autoCapitalized())
                    .focused($focusedComposerField, equals: .title)
                    .composerFieldStyle(isFocused: focusedComposerField == .title, minHeight: 54)
                    .font(Fonts.ui(20, .heavy))
                    .onSubmit(saveTask)
            }
            VStack(alignment: .leading, spacing: 8) {
                label("NOTES")
                TextField("Optional details", text: $notes.autoCapitalized(), axis: .vertical)
                    .lineLimit(3...5)
                    .focused($focusedComposerField, equals: .notes)
                    .composerFieldStyle(isFocused: focusedComposerField == .notes, minHeight: 88)
            }
            stepsCard
            if existingTask != nil && !isDone { progressCard }
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                label("STEPS · \(stepsDone) OF \(steps.count)")
                Spacer()
                if TaskAI.isAvailable {
                    Button(action: suggestSteps) {
                        Text(isSuggesting ? "Thinking…" : "✦ Suggest steps")
                            .font(Fonts.ui(13, .heavy)).padding(.horizontal, 12).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.panel))
                            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
                    }
                    .buttonStyle(HoverPlainStyle()).disabled(isSuggesting || trimmedTitle.isEmpty)
                }
            }
            NeoProgressBar(value: steps.isEmpty ? 0 : Double(stepsDone) / Double(steps.count), height: 12)
            ForEach($steps) { $step in
                HStack(spacing: 12) {
                    Button { step.isDone.toggle() } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(step.isDone ? Theme.done : Theme.card)
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink, lineWidth: 2)
                            if step.isDone { Image(systemName: "checkmark").font(.system(size: 13, weight: .black)) }
                        }
                        .frame(width: 24, height: 24).foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(HoverPlainStyle())
                    TextField("Step", text: $step.title.autoCapitalized())
                        .textFieldStyle(.plain).font(Fonts.ui(16, .semibold)).foregroundStyle(Theme.ink)
                        .strikethrough(step.isDone)
                    Button { steps.removeAll { $0.id == step.id } } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(HoverPlainStyle()).help("Delete step")
                }
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: "#9CA3AF") ?? .gray, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 24, height: 24)
                TextField("Add a step…", text: $newStep.autoCapitalized())
                    .textFieldStyle(.plain).font(Fonts.ui(16, .semibold)).foregroundStyle(Theme.ink)
                    .onSubmit(addStep)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard(Theme.card, radius: 14, shadow: 4)
        .padding(.trailing, 4).padding(.bottom, 4)
    }

    // Progress for work you can't finish in one sitting (a lab, a paper). Defaults to the share of
    // steps ticked off until you set it yourself.
    private var shownProgress: Int {
        if let progressTouched { return progressTouched }
        if let saved = existingTask?.progressPercent { return saved }
        guard !steps.isEmpty else { return 0 }
        return Int((Double(stepsDone) / Double(steps.count) * 100).rounded())
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                label("PROGRESS")
                Spacer()
                Text("\(shownProgress)% done").font(Fonts.ui(14, .heavy)).foregroundStyle(Theme.ink)
            }
            NeoSlider(value: Binding(get: { shownProgress }, set: { progressTouched = $0 }))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard(Theme.card, radius: 14, shadow: 4)
        .padding(.trailing, 4).padding(.bottom, 4)
    }

    private func addStep() {
        let t = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        steps.append(Subtask(title: t))
        newStep = ""
    }

    private func suggestSteps() {
        isSuggesting = true
        Task {
            defer { isSuggesting = false }
            if let suggestions = try? await TaskAI.suggestSteps(title: trimmedTitle, notes: notes) {
                steps.append(contentsOf: suggestions.map { Subtask(title: $0) })
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                toggleRow("Due date", isOn: $hasDueDate) {
                    if hasDueDate {
                        NeoDatePicker(date: $dueDate)
                    } else { Text("None") }
                }
                toggleRow("Repeats", isOn: $isRecurring) {
                    if isRecurring && hasDueDate {
                        NeoDropdown(selection: $recurrenceRule, options: RecurrenceRule.allCases.map { ($0, $0.label) })
                    } else { Text("Never") }
                }
                .opacity(hasDueDate ? 1 : 0.5).disabled(!hasDueDate)
                toggleRow("Estimate", isOn: $hasEstimate) {
                    if hasEstimate {
                        HStack(spacing: 6) {
                            ForEach(estimatePresets, id: \.self) { m in
                                Button { estimatedMinutes = m } label: {
                                    Text(m < 60 ? "\(m)m" : "\(m / 60)h").font(Fonts.ui(13, .heavy))
                                        .foregroundStyle(estimatedMinutes == m ? .white : Theme.ink)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill(estimatedMinutes == m ? Theme.ink : Theme.card))
                                        .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
                                }.buttonStyle(HoverPlainStyle())
                            }
                        }
                    } else { Text("None") }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .neoCard(Theme.card, radius: 14, shadow: 0)

            VStack(alignment: .leading, spacing: 8) {
                label("PRIORITY")
                HStack(spacing: 10) {
                    ForEach(TaskPriority.allCases.reversed(), id: \.self) { item in
                        Button { priority = item } label: {
                            Text(item.label).font(Fonts.ui(15, .heavy))
                                .foregroundStyle(priority == item ? .white : Theme.ink)
                                .frame(maxWidth: .infinity).frame(height: 40)
                        }
                        .buttonStyle(PressableStyle(fill: priority == item ? Theme.ink : Theme.card, foreground: priority == item ? .white : Theme.ink, radius: 10, shadow: 3))
                    }
                }
                .padding(.trailing, 3).padding(.bottom, 3)
            }

            VStack(alignment: .leading, spacing: 8) {
                label("LIST")
                WrapLayout(spacing: 10, centered: true) {
                    ForEach(visibleCategories) { category in
                        let chosen = trimmedCategory.caseInsensitiveCompare(category.name) == .orderedSame
                        Button {
                            categoryName = category.name
                            categoryColor = Categories.color(for: category)
                            isCreatingList = false
                        } label: {
                            Text((chosen ? "✓ " : "") + category.name).font(Fonts.ui(14, .heavy)).foregroundStyle(Theme.ink)
                                .lineLimit(1).padding(.horizontal, 16).frame(height: 38)
                        }
                        .buttonStyle(PressableStyle(fill: Categories.tint(Categories.color(for: category)), radius: 10, shadow: chosen ? 4 : 2))
                    }
                    Button { isCreatingList = true; categoryName = ""; focusedComposerField = .category } label: {
                        Text("+ New list").font(Fonts.ui(14, .heavy)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 16).frame(height: 38)
                    }
                    .buttonStyle(PressableStyle(fill: Theme.card, radius: 10, shadow: 2))
                }
                .padding(.bottom, 4)
                if isCreatingList || visibleCategories.isEmpty {
                    HStack(spacing: 10) {
                        Button { showColorPicker = true } label: {
                            Circle().fill(categoryColor).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                        }.buttonStyle(HoverPlainStyle()).help("Pick list color")
                        TextField("Class, work, bills, personal...", text: $categoryName.autoCapitalized())
                            .focused($focusedComposerField, equals: .category)
                            .composerFieldStyle(isFocused: focusedComposerField == .category, minHeight: 36)
                            .onSubmit(saveTask)
                    }
                    HStack(spacing: 8) {
                        ForEach(presetColors.indices, id: \.self) { i in
                            Button { categoryColor = presetColors[i] } label: {
                                Circle().fill(presetColors[i]).frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: categoryColor == presetColors[i] ? 3 : 1.5))
                            }.buttonStyle(HoverPlainStyle())
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    label("DEPENDS ON")
                    NeoDropdown(
                        selection: $dependsOnTaskID,
                        options: [(UUID?.none, "Nothing")] + dependencyCandidates.map { (Optional($0.id), $0.title) },
                        fillsWidth: true
                    )
                    .help("This task can't be marked done until the one you pick is.")
                }
                VStack(alignment: .leading, spacing: 6) {
                    label("REMINDER")
                    if !hasDueDate {
                        Text("Set a due date first").font(Fonts.ui(14, .semibold)).foregroundStyle(Theme.inkMuted).frame(height: 28)
                    } else {
                        NeoDropdown(
                            selection: $reminderSchedule,
                            options: ReminderSchedule.allCases.map { ($0, $0.label) },
                            fillsWidth: true
                        )
                        .onChange(of: reminderSchedule) { _, _ in reminderMode = .preset }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if existingTask != nil, let onDelete {
                Button("Delete") { isPresented = false; onDelete() }
                    .buttonStyle(HoverPlainStyle()).font(Fonts.ui(15, .heavy)).underline().foregroundStyle(Theme.ink)
            }
            Spacer()
            if existingTask != nil, let onToggleDone {
                Button { onToggleDone(); isPresented = false } label: {
                    Text(isDone ? "✓ Done · mark not done" : "Mark done")
                        .font(Fonts.ui(15, .heavy)).padding(.horizontal, 20).frame(height: 44)
                }
                .buttonStyle(PressableStyle(hover: false, fill: isDone ? Theme.done : Theme.card, radius: 10, shadow: 3))
            }
            Button { isPresented = false } label: {
                Text("Cancel").font(Fonts.ui(15, .heavy)).padding(.horizontal, 22).frame(height: 44)
            }
            .buttonStyle(PressableStyle(fill: Theme.card, radius: 10, shadow: 3))
            Button(action: saveTask) {
                Text(existingTask == nil ? "Create Task" : "Save").font(Fonts.ui(15, .heavy)).padding(.horizontal, 26).frame(height: 44)
            }
            .buttonStyle(PressableStyle(fill: Theme.amber, radius: 10, shadow: 3))
            .disabled(trimmedTitle.isEmpty).opacity(trimmedTitle.isEmpty ? 0.5 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(Theme.navBar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 2) }
    }
}
