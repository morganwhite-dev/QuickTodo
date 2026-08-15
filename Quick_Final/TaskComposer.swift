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
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isFocused ? Theme.accent.opacity(0.75) : Color.white.opacity(0.10),
                        lineWidth: isFocused ? 1.6 : 1
                    )
            )
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
            .opacity(isHovered ? 1.0 : 0.8)
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

    private let presetColors: [Color] = [Theme.accent, Theme.critical, Theme.warning, Color.green, Color.purple, Color.pink]
    private let estimatePresets = [5, 15, 30, 60, 120]

    init(
        isPresented: Binding<Bool>,
        categories: [CategoryItem],
        defaultCategory: String,
        allTasks: [TaskItem] = [],
        existingTask: TaskItem? = nil,
        onSave: @escaping (TaskComposerResult) -> Void
    ) {
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
        } else {
            let initialCategory = SidebarSection.reservedNames.contains(defaultCategory) ? "" : defaultCategory
            _categoryName = State(initialValue: initialCategory)
            _categoryColor = State(initialValue: initialCategory.isEmpty ? Theme.accent : Categories.color(for: initialCategory, in: categories))
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
            dependsOnTaskID: dependsOnTaskID
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: existingTask == nil ? "calendar.badge.plus" : "pencil")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(existingTask == nil ? "New Task" : "Edit Task")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Add details now so the task is ready when it lands.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Title")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextField("What do you need to do?", text: $title.autoCapitalized())
                                .focused($focusedComposerField, equals: .title)
                                .composerFieldStyle(isFocused: focusedComposerField == .title, minHeight: 38)
                                .help("Enter the task title")
                                .onSubmit(saveTask)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextField("Optional details", text: $notes.autoCapitalized(), axis: .vertical)
                                .lineLimit(2...3)
                                .focused($focusedComposerField, equals: .notes)
                                .composerFieldStyle(isFocused: focusedComposerField == .notes, minHeight: 58)
                                .help("Add optional notes or context for this task")
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 10) {
                            Toggle("", isOn: $hasDueDate)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .help(hasDueDate ? "Remove the due date section" : "Add a due date and optional reminders")

                            Text("Due date")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            if hasDueDate {
                                DatePicker("", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                                    .help("Choose the task's due date and time")
                            } else {
                                Text("None")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        if hasDueDate {
                            HStack(alignment: .center, spacing: 10) {
                                Toggle("", isOn: $isRecurring)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .help(isRecurring ? "Stop repeating this task" : "Repeat this task automatically after it's completed")

                                Text("Repeats")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if isRecurring {
                                    Picker("", selection: $recurrenceRule) {
                                        ForEach(RecurrenceRule.allCases, id: \.self) { rule in
                                            Text(rule.label).tag(rule)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .help("Choose how often this task repeats")
                                } else {
                                    Text("Never")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        HStack(alignment: .center, spacing: 10) {
                            Toggle("", isOn: $hasEstimate)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .help(hasEstimate ? "Remove the time estimate" : "Estimate how long this will take")

                            Text("Estimate")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            if hasEstimate {
                                HStack(spacing: 4) {
                                    ForEach(estimatePresets, id: \.self) { minutes in
                                        Button {
                                            estimatedMinutes = minutes
                                        } label: {
                                            Text(minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(estimatedMinutes == minutes ? .white : .secondary)
                                                .padding(.vertical, 5)
                                                .padding(.horizontal, 9)
                                                .background(
                                                    Capsule().fill(estimatedMinutes == minutes ? Theme.accent : Color.white.opacity(0.06))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .help("~\(minutes) minutes")
                                    }
                                }
                            } else {
                                Text("None")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 10) {
                            Text("Priority")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 86, alignment: .leading)

                            HStack(spacing: 4) {
                                ForEach(TaskPriority.allCases, id: \.self) { item in
                                    Button {
                                        withAnimation(.snappy(duration: Motion.prioritySelect)) {
                                            priority = item
                                        }
                                    } label: {
                                        Text(item.label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(priority == item ? Color.white : Color.secondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 7)
                                            .background(
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .fill(priority == item ? item.color : Color.white.opacity(0.06))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help("Set priority to \(item.label)")
                                }
                            }
                            .padding(3)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.white.opacity(0.055))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("List")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Circle()
                                .fill(categoryColor)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))

                            TextField("Class, work, bills, personal...", text: $categoryName.autoCapitalized())
                                .focused($focusedComposerField, equals: .category)
                                .composerFieldStyle(isFocused: focusedComposerField == .category, minHeight: 36)
                                .help("Type a new or existing list name")
                                .onSubmit(saveTask)

                            Button(action: { showColorPicker = true }) {
                                Image(systemName: "eyedropper.full")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .modifier(HoverButtonModifier())
                            .help("Pick list color")
                        }

                        if !visibleCategories.isEmpty {
                            Picker("Choose existing", selection: $categoryName) {
                                Text("New list").tag("")
                                ForEach(visibleCategories) { category in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Categories.color(for: category))
                                            .frame(width: 8, height: 8)
                                        Text(category.name)
                                    }
                                    .tag(category.name)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help("Choose an existing list")
                            .onChange(of: categoryName) { _, newValue in
                                if let selected = visibleCategories.first(where: { $0.name == newValue }) {
                                    categoryColor = Categories.color(for: selected)
                                }
                            }
                        }

                        HStack(spacing: 7) {
                            ForEach(presetColors.indices, id: \.self) { index in
                                let color = presetColors[index]
                                Button(action: { categoryColor = color }) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 18, height: 18)
                                        .overlay(Circle().stroke(Color.white.opacity(categoryColor == color ? 0.9 : 0.16), lineWidth: categoryColor == color ? 2 : 1))
                                }
                                .buttonStyle(.plain)
                                .help("Use this list color")
                                .modifier(HoverButtonModifier())
                            }
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Depends on")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("Only set this if the task you pick must genuinely finish first. This task can't be marked done until it is.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        Picker("", selection: $dependsOnTaskID) {
                            Text("Nothing").tag(UUID?.none)
                            ForEach(dependencyCandidates) { candidate in
                                Text(candidate.title).tag(Optional(candidate.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help("If this task can't start until another one finishes, link it here. It can't be completed until that other task is.")
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("Reminders")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Picker("", selection: $reminderMode) {
                                ForEach(ReminderMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                            .help("Choose preset reminders or custom reminder times")
                        }

                        if !hasDueDate {
                            Text("Choose a due date to enable reminders.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else if reminderMode == .preset {
                            Picker("", selection: $reminderSchedule) {
                                ForEach(ReminderSchedule.allCases, id: \.self) { schedule in
                                    Text(schedule.label).tag(schedule)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help("Choose when QuickTodo should remind you")
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(customReminderMinutes.enumerated()), id: \.offset) { index, _ in
                                    HStack(spacing: 8) {
                                        TextField("", value: Binding(
                                            get: { customReminderMinutes[index] },
                                            set: { customReminderMinutes[index] = max(1, $0) }
                                        ), format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 58)
                                            .help("Minutes before the due time")
                                        Text("minutes before")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button(action: { customReminderMinutes.remove(at: index) }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove this custom reminder")
                                        .modifier(HoverButtonModifier())
                                    }
                                }

                                if customReminderMinutes.count < 3 {
                                    Button(action: { customReminderMinutes.append(15) }) {
                                        Label("Add reminder", systemImage: "plus.circle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Add another custom reminder time")
                                    .modifier(HoverButtonModifier())
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .help("Close without saving")
                        .modifier(HoverButtonModifier())

                        Button(existingTask == nil ? "Create Task" : "Save Changes", action: saveTask)
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .help(trimmedTitle.isEmpty ? "Enter a title before saving" : "Save this task")
                        .modifier(HoverButtonModifier())
                        .disabled(trimmedTitle.isEmpty)
                    }
                }
                .padding(16)
            }
            .frame(minWidth: 440, idealWidth: 460, minHeight: 560, maxHeight: 680)
            .tint(Theme.accent)
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColor: $categoryColor, isPresented: $showColorPicker) { color in
                    categoryColor = color
                }
            }
        }
    }
}
