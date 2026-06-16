import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Repeat and Alert Options

enum RepeatRule: String, CaseIterable, Codable, Identifiable {
    case none, daily, weekly, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "None"
        case .daily: "Every Day"
        case .weekly: "Every Week"
        case .monthly: "Every Month"
        case .yearly: "Every Year"
        }
    }
}

let defaultAlertOffsets: [TimeInterval] = [3600, 1800, 900, 600, 300]

enum CustomUnit: String, CaseIterable, Identifiable {
    case minutes, hours, days, weeks
    var id: String { rawValue }
    var label: String {
        switch self {
        case .minutes: "Minutes"
        case .hours: "Hours"
        case .days: "Days"
        case .weeks: "Weeks"
        }
    }
    var secondsPerUnit: TimeInterval {
        switch self {
        case .minutes: 60
        case .hours: 3600
        case .days: 86400
        case .weeks: 604800
        }
    }
}

func alertLabel(for offset: TimeInterval) -> String {
    if offset == 0 { return "At time of task" }
    let minutes = Int(offset / 60)
    let week = 7 * 24 * 60
    if minutes % week == 0 {
        let weeks = minutes / week
        return weeks == 1 ? "1 week before" : "\(weeks) weeks before"
    }
    let day = 24 * 60
    if minutes % day == 0 {
        let days = minutes / day
        return days == 1 ? "1 day before" : "\(days) days before"
    }
    if minutes % 60 == 0 {
        let hours = minutes / 60
        return hours == 1 ? "1 hour before" : "\(hours) hours before"
    }
    return minutes == 1 ? "1 minute before" : "\(minutes) minutes before"
}

// MARK: - Category Model

@Model
final class Category: Identifiable {
    var id: UUID
    var name: String
    var color: CodableColor

    init(id: UUID = UUID(), name: String, color: CodableColor) {
        self.id = id
        self.name = name
        self.color = color
    }
}

struct CodableColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ color: Color) {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, &g, &b, &a)
        self.r = Double(r)
        self.g = Double(g)
        self.b = Double(b)
        self.a = Double(a)
        #elseif canImport(AppKit)
        let ns = NSColor(color)
        let rgb = ns.usingColorSpace(.deviceRGB) ?? ns
        self.r = Double(rgb.redComponent)
        self.g = Double(rgb.greenComponent)
        self.b = Double(rgb.blueComponent)
        self.a = Double(rgb.alphaComponent)
        #else
        self.r = 0; self.g = 0; self.b = 1; self.a = 1
        #endif
    }

    var swiftUIColor: Color {
        Color(red: r, green: g, blue: b).opacity(a)
    }
}

// MARK: - Notification Scheduler

final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private init() {}

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus != .authorized else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    func scheduleNotifications(for task: TaskItem) {
        guard let due = task.dueDate else { return }
        let center = UNUserNotificationCenter.current()

        for (idx, offset) in task.alertOffsets.enumerated() {
            let fireDate = due.addingTimeInterval(-offset)
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.title
            if let notes = task.notes, !notes.isEmpty { content.body = notes }
            content.sound = .default

            let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

            let id = "\(task.id.uuidString)-alert-\(idx)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request)
        }
    }
}

// MARK: - Task Editor View

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Category.name) private var categories: [Category]

    // Fields
    @State private var title = ""
    @State private var isAllDay = false
    @State private var dueDate = Date()
    @State private var repeatRule: RepeatRule = .none
    @State private var alerts: [TimeInterval] = []
    @State private var isPresentingCustomAlert = false
    @State private var customAmount = 10
    @State private var customUnit: CustomUnit = .minutes
    @State private var selectedCategory: Category?
    @State private var categoryColor = Color.blue
    @State private var notes = ""

    private let task: TaskItem?

    init(task: TaskItem? = nil) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _isAllDay = State(initialValue: task?.isAllDay ?? false)
        _dueDate = State(initialValue: task?.dueDate ?? Date())
        _repeatRule = State(initialValue: task?.repeatRule ?? .none)
        _alerts = State(initialValue: task?.alertOffsets ?? [])
        _selectedCategory = State(initialValue: task?.category)
        _categoryColor = State(initialValue: task?.category?.color.swiftUIColor ?? .blue)
        _notes = State(initialValue: task?.notes ?? "")
    }

    private var isEditing: Bool { task != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                }

                Section("Time") {
                    Toggle("All-day", isOn: $isAllDay)
                    DatePicker("Due", selection: $dueDate,
                               displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    Picker("Repeat", selection: $repeatRule) {
                        ForEach(RepeatRule.allCases) { rule in
                            Text(rule.label).tag(rule)
                        }
                    }
                }

                Section("Alerts") {
                    if alerts.isEmpty {
                        Text("No alerts")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(alerts.indices, id: \.self) { i in
                            HStack {
                                Text(alertLabel(for: alerts[i]))
                                Spacer()
                                Button {
                                    alerts.remove(at: i)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                                .help("Remove alert")
                            }
                        }
                    }

                    Menu("Add Alert") {
                        ForEach(defaultAlertOffsets, id: \.self) { offset in
                            Button(alertLabel(for: offset)) {
                                if !alerts.contains(offset) && alerts.count < 5 {
                                    alerts.append(offset)
                                }
                            }
                        }
                        Button("Custom…") { isPresentingCustomAlert = true }
                    }
                    .disabled(alerts.count >= 5)
                }
                .sheet(isPresented: $isPresentingCustomAlert) {
                    NavigationStack {
                        Form {
                            Picker("Units", selection: $customUnit) {
                                ForEach(CustomUnit.allCases) { unit in
                                    Text(unit.label).tag(unit)
                                }
                            }
                            Stepper(value: $customAmount, in: 1...99) {
                                Text("Amount: \(customAmount)")
                            }
                            Text("Will alert \(customAmount) \(customUnit.label.lowercased()) before")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .navigationTitle("Custom Alert")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { isPresentingCustomAlert = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") {
                                    let offset = Double(customAmount) * customUnit.secondsPerUnit
                                    if !alerts.contains(offset) && alerts.count < 5 {
                                        alerts.append(offset)
                                    }
                                    isPresentingCustomAlert = false
                                }
                            }
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(Optional<Category>.none)
                        ForEach(categories) { cat in
                            HStack {
                                Circle().fill(cat.color.swiftUIColor).frame(width: 10, height: 10)
                                Text(cat.name)
                            }
                            .tag(Optional(cat))
                        }
                    }

                    ColorPicker("Color", selection: $categoryColor, supportsOpacity: false)
                        .onChange(of: categoryColor) { _, newValue in
                            // Update selected category color live
                            if let cat = selectedCategory {
                                cat.color = CodableColor(newValue)
                            }
                        }

                    Button("New Category with Color") {
                        let new = Category(name: "New Category", color: CodableColor(categoryColor))
                        modelContext.insert(new)
                        selectedCategory = new
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { saveTask() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveTask() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedTask: TaskItem

        if let task {
            task.title = trimmedTitle
            task.dueDate = dueDate
            task.isAllDay = isAllDay
            task.repeatRule = repeatRule
            task.alertOffsets = alerts
            task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
            task.category = selectedCategory
            savedTask = task
        } else {
            let task = TaskItem(
                title: trimmedTitle,
                createdAt: Date(),
                dueDate: dueDate,
                isAllDay: isAllDay,
                repeatRuleRaw: repeatRule.rawValue,
                alertsRaw: alerts,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
                category: selectedCategory
            )
            modelContext.insert(task)
            savedTask = task
        }

        NotificationScheduler.shared.requestAuthorizationIfNeeded()
        NotificationScheduler.shared.scheduleNotifications(for: savedTask)

        dismiss()
    }
}

#Preview {
    TaskEditorView()
        .modelContainer(for: [TaskItem.self, Category.self], inMemory: true)
}
