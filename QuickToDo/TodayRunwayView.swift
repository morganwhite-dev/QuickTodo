// TodayRunwayView.swift
// Today = "what do I do right now". A progress hero (ring + up-next), a pinned stats column,
// and a time-ordered runway of tasks on a rail. Overdue sits on a red rail, later-today on
// black. All counts come from `Planner`, so they match the nav badge and Dock badge.

import SwiftUI

struct TodayView: View {
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

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var focusedID: UUID?

    private let calendar = Calendar.current

    // MARK: Data (same rule as the nav badge: overdue + due later today)

    private var slice: [TaskItem] {
        tasks.filter { Planner.isOnTodayTab($0) && matches($0, search) }.sortedChronologically()
    }
    private var overdueEarlierDays: [TaskItem] {
        slice.filter { Planner.isOverdue($0) && !($0.dueDate.map { calendar.isDateInToday($0) } ?? false) }
    }
    private var overdueEarlierToday: [TaskItem] {
        slice.filter { Planner.isOverdue($0) && ($0.dueDate.map { calendar.isDateInToday($0) } ?? false) }
    }
    private var laterToday: [TaskItem] { slice.filter { Planner.isDueLaterToday($0) } }

    private var doneToday: Int {
        tasks.filter { $0.isCompleted && ($0.completedAt.map { calendar.isDateInToday($0) } ?? false) }.count
    }
    private var totalToday: Int { doneToday + slice.count }
    private var upNext: TaskItem? { slice.first { !$0.isBlocked(in: tasks) } }
    private var overdueCount: Int { slice.filter { Planner.isOverdue($0) }.count }

    // MARK: Copy

    private var greeting: String {
        switch calendar.component(.hour, from: .now) {
        case 0..<5: return "Burning the midnight oil"
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<22: return "Evening"
        default: return "Late one"
        }
    }

    // Numbers live in the chips below; the subtitle is just the tone of the day.
    private var subtitle: String {
        let n = slice.count
        if n == 0 { return "\(greeting). Nothing due." }
        if n == 1 { return "\(greeting). One left. Finish line is right there." }
        if overdueCount > 0 { return "\(greeting). Overdue first, then the day is yours." }
        return "\(greeting). None of it is on fire."
    }

    private var allClearLine: String {
        switch calendar.component(.hour, from: .now) {
        case 5..<12: return "Nothing due. Suspiciously free morning."
        case 12..<17: return "Cleared. Go outside, it's still there."
        default: return "Done for today ✓ Rest is a feature."
        }
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today").font(Fonts.black(46)).foregroundStyle(.white)
                    Text(subtitle).font(Fonts.ui(16, .bold)).foregroundStyle(.white)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: subtitle)
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

            runway.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 32).padding(.vertical, 26)
        .frame(maxWidth: 1080 + 64, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Runway (hero + sections)

    private var runway: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            statChips
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if slice.isEmpty {
                            allClear
                        } else {
                            section("Overdue · earlier days", overdueEarlierDays, overdue: true)
                            section("Overdue · earlier today", overdueEarlierToday, overdue: true)
                            section("Later today", laterToday, overdue: false)
                            endOfRunway
                        }
                    }
                    .padding(.trailing, 6).padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .modifier(RowKeyboardNav(
                    ids: (overdueEarlierDays + overdueEarlierToday + laterToday).map(\.id), focused: $focusedID,
                    onToggle: { id in if let t = tasks.first(where: { $0.id == id }) { onToggle(t) } }
                ))
                .onChange(of: selectedTask?.id) { _, newID in
                    guard let newID, slice.contains(where: { $0.id == newID }) else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newID) }
                }
            }
        }
    }

    // Closing note at natural size (nothing stretched to fill the page).
    private var endOfRunway: some View {
        VStack(spacing: 4) {
            Text("✦ Nothing else due after this").font(Fonts.bricolage(17, .heavy)).foregroundStyle(.white)
            if doneToday > 0 {
                Text("\(doneToday) finished today").font(Fonts.ui(14, .bold)).foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var hero: some View {
        HStack(spacing: 22) {
            VStack(spacing: 6) {
                ProgressRing(value: totalToday == 0 ? 1 : Double(doneToday) / Double(totalToday), label: "\(doneToday)/\(totalToday)", size: 84, lineWidth: 11)
                Text("done today").font(Fonts.ui(13, .heavy)).foregroundStyle(Theme.ink)
            }
            if let next = upNext {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        tag("UP NEXT", fill: Theme.ink, fg: .white)
                        if Planner.isOverdue(next) { tag("OVERDUE", fill: Theme.overdue, fg: .white) }
                    }
                    Text(next.title).font(Fonts.black(26)).foregroundStyle(Theme.ink).lineLimit(1)
                    HStack(spacing: 8) {
                        ListTag(name: next.category, color: Categories.color(for: next.category, in: categories))
                        NeoChip(text: "≈ \(Planner.label(minutes: Planner.minutes(of: next)))", size: 13)
                        if let due = next.dueDate {
                            NeoChip(text: Planner.hasClockTime(due) ? due.formatted(date: .omitted, time: .shortened) : due.formatted(.dateTime.weekday(.abbreviated)), size: 13)
                        }
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: 12) {
                    Button { onToggle(next) } label: {
                        Label("Done", systemImage: "checkmark").font(Fonts.ui(16, .heavy)).padding(.horizontal, 20).frame(height: 48)
                    }
                    .buttonStyle(PressableStyle(hover: false, fill: Theme.done, radius: 8, shadow: 4))
                    Button { selectedTask = next } label: {
                        Text("Open").font(Fonts.ui(16, .heavy)).padding(.horizontal, 20).frame(height: 48)
                    }
                    .buttonStyle(PressableStyle(fill: Theme.card, radius: 8, shadow: 4))
                }
                .padding(.trailing, 4).padding(.bottom, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("All clear").font(Fonts.black(36)).foregroundStyle(Theme.ink)
                    Text(doneToday > 0 ? "\(doneToday) finished today. Not bad at all." : "Nothing is waiting on you.")
                        .font(Fonts.ui(15, .semibold)).foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard(slice.isEmpty ? Theme.mint : Theme.card, radius: 6, shadow: 6)
        .padding(.trailing, 6).padding(.bottom, 6)
    }

    private var allClear: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing else due").font(Fonts.bricolage(30, .heavy)).foregroundStyle(.white)
            Text(allClearLine).font(Fonts.ui(16, .semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func tag(_ text: String, fill: Color, fg: Color) -> some View {
        Text(text).font(Fonts.ui(12, .heavy)).tracking(1.2).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 3).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink, lineWidth: 2))
    }

    // MARK: Sections on a rail

    @ViewBuilder
    private func section(_ title: String, _ items: [TaskItem], overdue: Bool) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    if overdue {
                        Circle().fill(Theme.overdue).frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                    }
                    Text(title.uppercased()).font(Fonts.black(15)).tracking(0.6).foregroundStyle(.white)
                    NeoChip(text: "\(items.count)", size: 12)
                    Rectangle().fill(Color.white).frame(height: 2)
                }
                VStack(spacing: 10) {
                    ForEach(items) { task in
                        TimelineTaskRow(
                            task: task, allTasks: tasks, categories: categories,
                            showDay: overdue,
                            isMultiSelecting: isSelecting,
                            isMultiSelected: selectedIDs.contains(task.id),
                            onToggleMultiSelect: {
                                if selectedIDs.contains(task.id) { selectedIDs.remove(task.id) } else { selectedIDs.insert(task.id) }
                            },
                            onSelect: { selectedTask = selectedTask?.id == task.id ? nil : task },
                            onToggle: { onToggle(task) }, onEdit: { onEdit(task) }, onDelete: { onDelete(task) }
                        )
                        .id(task.id)
                        .overlay(alignment: .leading) {
                            Circle().fill(Theme.card).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(overdue ? Theme.overdue : Theme.ink, lineWidth: 3))
                                .offset(x: -40 + 15.5 - 8)
                        }
                        .padding(.trailing, 3).padding(.bottom, 3)
                    }
                }
                .padding(.leading, 40)
                .background(alignment: .topLeading) {
                    // The rail (drawn behind the dots): red for overdue, white for later today.
                    Rectangle().fill(overdue ? Theme.overdue : Color.white).frame(width: 3)
                        .padding(.leading, 14).padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Stats

    // The three numbers as small inline chips — no card, no timeline.
    private var statChips: some View {
        HStack(spacing: 10) {
            NeoChip(
                text: "\(overdueCount) overdue",
                foreground: overdueCount > 0 ? Theme.overdue : Theme.ink,
                size: 14,
                borderColor: overdueCount > 0 ? Theme.overdue : Theme.ink
            )
            NeoChip(text: "\(laterToday.count) later today", size: 14)
            NeoChip(text: "\(Planner.label(minutes: Planner.openMinutes(slice))) left", size: 14)
            Spacer(minLength: 0)
        }
    }
}
