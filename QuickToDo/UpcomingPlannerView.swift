// UpcomingPlannerView.swift
// The Upcoming week planner: a 7-day strip, a rail-based day timeline with free blocks,
// and the "This week" dashboard. Every number here is derived through `Planner`, from the
// same live task list the rest of the app uses, so ticking a task updates the strip,
// the timeline header, the tiles and the charts together.

import SwiftUI

struct UpcomingView: View {
    let tasks: [TaskItem]
    let categories: [CategoryItem]
    @Binding var search: String
    @Binding var selectedTask: TaskItem?
    let onToggle: (TaskItem) -> Void
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onNewTask: () -> Void
    let onPlanTime: (Date) -> Void
    let onReschedule: (TaskItem, Date) -> Void

    @State private var stripStart: Date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var selectedDay: Date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var showDone = false
    @State private var focusedID: UUID?
    @FocusState private var hasKeyboardFocus: Bool

    private let calendar = Calendar.current

    // MARK: Derived data

    private var visibleTasks: [TaskItem] {
        guard !search.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.notes.localizedCaseInsensitiveContains(search)
        }
    }

    private var days: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: stripStart) } }

    private func dayTasks(_ day: Date) -> [TaskItem] { Planner.tasks(on: day, in: visibleTasks, calendar: calendar) }

    private var weekTasks: [TaskItem] { days.flatMap { dayTasks($0) } }
    private var openWeek: [TaskItem] { weekTasks.filter { !$0.isCompleted } }

    private var selectedDayTasks: [TaskItem] { dayTasks(selectedDay) }
    private var selectedOpen: [TaskItem] { selectedDayTasks.filter { !$0.isCompleted } }
    private var selectedDone: [TaskItem] { selectedDayTasks.filter(\.isCompleted) }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upcoming").font(Fonts.black(46)).foregroundStyle(.white)
                }
                Spacer()
                weekNav
            }

            weekStrip

            HStack(alignment: .top, spacing: 14) {
                timelinePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(5)
                dashboard
                    .frame(width: 390)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 32).padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusable()
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { shiftDay(-1); return .handled }
        .onKeyPress(.rightArrow) { shiftDay(1); return .handled }
        .onKeyPress(.upArrow) { moveFocus(-1); return .handled }
        .onKeyPress(.downArrow) { moveFocus(1); return .handled }
        .onKeyPress(.space) { toggleFocused() }
        .onKeyPress(.return) { toggleFocused() }
        .onAppear { hasKeyboardFocus = true }
        .onChange(of: selectedDay) { _, _ in focusedID = nil; showDone = false }
    }

    private var weekNav: some View {
        HStack(spacing: 10) {
            navButton("chevron.left", help: "Previous 7 days") { shiftWeek(-1) }
            navButton("chevron.right", help: "Next 7 days") { shiftWeek(1) }
        }
    }

    private func navButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .black)).frame(width: 40, height: 40)
        }
        .buttonStyle(PressableStyle(fill: Theme.card, radius: 8, shadow: 3))
        .help(help).accessibilityLabel(help)
    }

    private func shiftWeek(_ by: Int) {
        guard let s = calendar.date(byAdding: .day, value: 7 * by, to: stripStart),
              let d = calendar.date(byAdding: .day, value: 7 * by, to: selectedDay) else { return }
        stripStart = s; selectedDay = d
    }

    private func shiftDay(_ by: Int) {
        guard let d = calendar.date(byAdding: .day, value: by, to: selectedDay) else { return }
        if d < stripStart { shiftWeek(-1); selectedDay = d }
        else if d >= (calendar.date(byAdding: .day, value: 7, to: stripStart) ?? d) { shiftWeek(1); selectedDay = d }
        else { selectedDay = d }
    }

    // Up/Down move a 3px focus ring between task rows on the selected day.
    private func moveFocus(_ by: Int) {
        let ids = selectedOpen.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = focusedID, let i = ids.firstIndex(of: current) else {
            focusedID = by > 0 ? ids.first : ids.last
            return
        }
        focusedID = ids[max(0, min(ids.count - 1, i + by))]
    }

    private func toggleFocused() -> KeyPress.Result {
        guard let id = focusedID, let task = selectedOpen.first(where: { $0.id == id }) else { return .ignored }
        onToggle(task)
        return .handled
    }

    // MARK: Week strip

    private var weekStrip: some View {
        HStack(spacing: 14) {
            ForEach(days, id: \.self) { day in dayTile(day) }
        }
    }

    private func dayTile(_ day: Date) -> some View {
        let all = dayTasks(day)
        let open = all.filter { !$0.isCompleted }
        let minutes = Planner.openMinutes(all)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let label = all.isEmpty ? "Free" : (open.isEmpty ? "All done" : "\(open.count) task\(open.count == 1 ? "" : "s")")
        return Button { withAnimation(.easeOut(duration: 0.16)) { selectedDay = day } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(Fonts.ui(13, .heavy)).tracking(1.2)
                    Spacer()
                    Text(day.formatted(.dateTime.day())).font(Fonts.black(26))
                }
                Text(label).font(Fonts.ui(13, .bold))
                NeoProgressBarDark(value: min(1, Double(minutes) / 480))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .neoCard(isSelected ? .white : Theme.panel, radius: 8, shadow: isSelected ? 6 : 3)
            .offset(y: isSelected ? -2 : 0)
        }
        .buttonStyle(PressableCardStyle(shadow: 3))
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).month().day())), \(label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Timeline

    private enum Row: Identifiable {
        case free(Planner.FreeBlock)
        case task(TaskItem)
        var id: String {
            switch self {
            case .free(let b): return "free-\(b.id)"
            case .task(let t): return "task-\(t.id)"
            }
        }
    }

    // Open tasks and free blocks in time order. Finished tasks aren't rows — they collapse
    // into the pill below — but they still shaped the free blocks (see Planner.freeBlocks).
    private var rows: [Row] {
        let untimed = selectedOpen.filter { !($0.dueDate.map { Planner.hasClockTime($0) } ?? false) }.map(Row.task)
        let blocks = Planner.freeBlocks(forDay: selectedDayTasks, day: selectedDay, calendar: calendar)
        let timedOpen = selectedOpen.filter { $0.dueDate.map { Planner.hasClockTime($0) } ?? false }
        let timed: [(Date, Row)] =
            blocks.map { ($0.start, Row.free($0)) } + timedOpen.map { ($0.dueDate ?? .distantFuture, Row.task($0)) }
        return untimed + timed.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private var timelinePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(Fonts.black(26)).foregroundStyle(Theme.ink)
                if !selectedDayTasks.isEmpty {
                    Text("\(selectedOpen.count) task\(selectedOpen.count == 1 ? "" : "s") · \(Planner.openMinutes(selectedDayTasks)) min of work")
                        .font(Fonts.ui(15, .bold)).foregroundStyle(Theme.ink)
                }
                Spacer()
                Text("Timeline · 8 AM to midnight").font(Fonts.ui(13, .bold)).foregroundStyle(Theme.inkMuted)
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 2) }

            // The day's content cross-fades when you pick another day instead of snapping.
            Group {
            if selectedDayTasks.isEmpty {
                freeDay
            } else if selectedOpen.isEmpty {
                allDoneState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            switch row {
                            case .free(let block): freeRow(block)
                            case .task(let task): taskRow(task)
                            }
                        }
                        Text("✦ Nothing else due after this")
                            .font(Fonts.ui(15, .bold)).foregroundStyle(Theme.ink.opacity(0.4))
                            .frame(maxWidth: .infinity).padding(.top, 16)
                    }
                    .padding(.leading, 40)
                    .background(alignment: .topLeading) {
                        // One continuous 3px rail (behind the dots); its centre is 15.5px from the content edge.
                        Rectangle().fill(Theme.railLine).frame(width: 3).padding(.leading, 14).padding(.vertical, 6)
                    }
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                if !selectedDone.isEmpty { donePill }
            }
            }
            .id(selectedDay)
            .transition(.opacity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .neoPanel()
    }

    private func freeRow(_ block: Planner.FreeBlock) -> some View {
        HStack(spacing: 16) {
            Text("\(Planner.label(minutes: block.minutes)) free")
                .font(Fonts.bricolage(15, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 6)
                .background(Capsule().fill(Theme.freePill))
            DashedLine()
                .stroke(Theme.freeDash, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                .frame(height: 3)
            Button { onPlanTime(block.start) } label: {
                Text("+ Plan this time").font(Fonts.ui(14, .heavy)).padding(.horizontal, 18).frame(height: 38)
            }
            .buttonStyle(PressableStyle(fill: Theme.amber, shadow: 3, capsule: true))
            .padding(.trailing, 3)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .leading) {
            Circle().fill(Theme.ink).frame(width: 8, height: 8).offset(x: -40 + 15.5 - 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Planner.label(minutes: block.minutes)) free from \(block.start.formatted(date: .omitted, time: .shortened))")
    }

    private func taskRow(_ task: TaskItem) -> some View {
        TimelineTaskRow(
            task: task, allTasks: tasks, categories: categories,
            isFocused: focusedID == task.id,
            onSelect: { selectedTask = selectedTask?.id == task.id ? nil : task },
            onToggle: { onToggle(task) }, onEdit: { onEdit(task) }, onDelete: { onDelete(task) }
        )
        .overlay(alignment: .leading) {
            Circle().fill(Theme.card).frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 3))
                .offset(x: -40 + 15.5 - 8)
        }
        .padding(.trailing, 3).padding(.bottom, 3)
    }

    private var donePill: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy(duration: 0.2)) { showDone.toggle() } } label: {
                Text("✓ \(selectedDone.count) completed · \(showDone ? "hide" : "show")")
                    .font(Fonts.ui(14, .heavy)).padding(.horizontal, 14).frame(height: 34)
            }
            .buttonStyle(PressableStyle(fill: Theme.done, shadow: 3, capsule: true))
            if showDone {
                FlowChips(items: selectedDone) { task in
                    Button { onToggle(task) } label: {
                        HStack(spacing: 8) {
                            Text(task.title).strikethrough().lineLimit(1)
                            Text("undo").font(Fonts.ui(12, .bold)).foregroundStyle(Theme.inkMuted)
                        }
                        .font(Fonts.ui(14, .bold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .neoCard(Theme.card, radius: 10, shadow: 0)
                    }
                    .buttonStyle(HoverPlainStyle(hover: false))
                }
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 2) }
    }

    // Every task that day is done: the whole panel becomes a calm "nothing else due".
    private var allDoneState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text("Nothing else due").font(Fonts.bricolage(34, .heavy)).foregroundStyle(Theme.ink.opacity(0.32))
            Text("Great work today. Get some rest.").font(Fonts.ui(16, .semibold)).foregroundStyle(Theme.ink.opacity(0.5))
            Spacer(minLength: 0)
            donePill
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .modifier(active: BlurFade(radius: 10), identity: BlurFade(radius: 0))))
    }

    // MARK: Free day

    private var aheadSuggestions: [TaskItem] {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDay)) ?? selectedDay
        return visibleTasks
            .filter { !$0.isCompleted && ($0.dueDate ?? .distantPast) >= end }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(3).map { $0 }
    }

    private var freeDay: some View {
        let dayName = calendar.isDateInToday(selectedDay) ? "today" : selectedDay.formatted(.dateTime.weekday(.wide))
        return VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Text("Free day.").font(Fonts.black(88)).foregroundStyle(Theme.ink).minimumScaleFactor(0.5).lineLimit(1)
                Text("Rest up, or get a head start on the week.").font(Fonts.ui(18, .semibold)).foregroundStyle(Theme.ink)
            }
            if !aheadSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("WANT TO GET AHEAD?").font(Fonts.ui(13, .heavy)).tracking(1.5)
                    Text("These are due later. Do one \(dayName) instead and that day gets lighter.")
                        .font(Fonts.ui(14, .semibold)).foregroundStyle(Color(hex: "#1F2937") ?? Theme.ink)
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(aheadSuggestions) { task in aheadCard(task, dayName: dayName) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .neoCard(Theme.mint, radius: 8, shadow: 4)
        .padding(.top, 4).padding(.trailing, 4).padding(.bottom, 4)
    }

    private func aheadCard(_ task: TaskItem, dayName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ListTag(name: task.category, color: Categories.color(for: task.category, in: categories))
            Text(task.title).font(Fonts.ui(16, .heavy)).foregroundStyle(Theme.ink).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("From \(task.dueDate.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "later") · ≈ \(Planner.label(minutes: Planner.minutes(of: task)))")
                .font(Fonts.ui(13, .semibold)).foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 0)
            Button { onReschedule(task, selectedDay) } label: {
                Text("Do \(dayName)").font(Fonts.ui(14, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 36)
            }
            .buttonStyle(PressableStyle(fill: Theme.ink, foreground: .white, radius: 6, shadow: 0))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard(Theme.card, radius: 8, shadow: 3)
    }

    // MARK: Dashboard ("This week")

    private struct ListSlice: Identifiable {
        let name: String; let color: Color; let count: Int; let minutes: Int
        var id: String { name }
    }

    private var slices: [ListSlice] {
        Dictionary(grouping: openWeek, by: { $0.category.lowercased() })
            .compactMap { _, items -> ListSlice? in
                guard let name = items.first?.category else { return nil }
                return ListSlice(name: name, color: Categories.color(for: name, in: categories),
                                 count: items.count, minutes: items.reduce(0) { $0 + Planner.minutes(of: $1) })
            }
            .sorted { $0.minutes > $1.minutes }
    }

    private var dashboard: some View {
        let open = openWeek
        let totalMinutes = Planner.openMinutes(open)
        let perDay = days.map { day in (day, Planner.openMinutes(dayTasks(day))) }
        let busiest = perDay.max { $0.1 < $1.1 }
        return VStack(alignment: .leading, spacing: 12) {
            Text("THIS WEEK").font(Fonts.ui(13, .heavy)).tracking(1.4).foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("\(weekTasks.count)", "TASKS")
                tile(Planner.label(minutes: totalMinutes), "BOOKED")
                tile("\(weekTasks.filter(\.isCompleted).count) / \(weekTasks.count)", "DONE")
                tile(busiest.flatMap { $0.1 > 0 ? "\($0.0.formatted(.dateTime.weekday(.abbreviated))) · \(dayTasks($0.0).filter { !$0.isCompleted }.count)" : nil } ?? "—", "BUSIEST DAY")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("TIME BY LIST").font(Fonts.ui(12, .heavy)).tracking(1.2)
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(slices) { s in
                            Rectangle().fill(s.color)
                                .frame(width: totalMinutes == 0 ? 0 : geo.size.width * CGFloat(s.minutes) / CGFloat(totalMinutes))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
                }
                .frame(height: 20)
                VStack(spacing: 6) {
                    ForEach(slices) { s in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: 12, height: 12)
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink, lineWidth: 2))
                            Text(s.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(s.count) · \(s.minutes) min").foregroundStyle(Theme.inkMuted)
                            Text(totalMinutes == 0 ? "0%" : "\(Int((Double(s.minutes) / Double(totalMinutes) * 100).rounded()))%")
                                .frame(width: 38, alignment: .trailing)
                        }
                        .font(Fonts.ui(13, .bold)).foregroundStyle(Theme.ink)
                    }
                    if slices.isEmpty {
                        Text("Nothing left to do this week.").font(Fonts.ui(13, .semibold)).foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .neoCard(Theme.card, radius: 12, shadow: 0)

            VStack(alignment: .leading, spacing: 8) {
                Text("MINUTES PER DAY").font(Fonts.ui(12, .heavy)).tracking(1.2)
                minutesChart
            }
            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .neoCard(Theme.card, radius: 12, shadow: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .neoPanel()
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Fonts.black(24)).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Fonts.ui(12, .bold)).tracking(0.8).foregroundStyle(Theme.inkMuted)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard(Theme.card, radius: 12, shadow: 0)
    }

    private var minutesChart: some View {
        let perDay = days.map { day -> (Date, [(Color, Int)]) in
            let open = dayTasks(day).filter { !$0.isCompleted }
            let grouped = Dictionary(grouping: open, by: { $0.category.lowercased() })
            let parts = grouped.values.map { items -> (Color, Int) in
                (Categories.color(for: items[0].category, in: categories), items.reduce(0) { $0 + Planner.minutes(of: $1) })
            }
            return (day, parts)
        }
        let maxMinutes = max(60, perDay.map { $0.1.reduce(0) { $0 + $1.1 } }.max() ?? 60)
        return VStack(spacing: 6) {
            GeometryReader { geo in
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(perDay, id: \.0) { day, parts in
                        let selected = calendar.isDate(day, inSameDayAs: selectedDay)
                        let total = parts.reduce(0) { $0 + $1.1 }
                        let h = geo.size.height * CGFloat(total) / CGFloat(maxMinutes)
                        VStack(spacing: 0) {
                            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                                Rectangle().fill(part.0)
                                    .frame(height: total == 0 ? 0 : h * CGFloat(part.1) / CGFloat(total))
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: max(h, total == 0 ? 3 : 0))
                        .background(Theme.card)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
                        .opacity(selected ? 1 : 0.6)
                        .help("\(day.formatted(.dateTime.weekday(.wide))): \(total) min")
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 2) }
            }
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let selected = calendar.isDate(day, inSameDayAs: selectedDay)
                    Text(String(day.formatted(.dateTime.weekday(.abbreviated)).prefix(2)))
                        .font(Fonts.ui(11, .heavy))
                        .foregroundStyle(selected ? .white : Theme.ink)
                        .fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(selected ? Theme.ink : .clear))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(minHeight: 120)
    }
}

// MARK: - Pieces

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Load bar on a day tile: teal fill, black border.
private struct NeoProgressBarDark: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card)
                Capsule().fill(Color(hex: "#0E4D64") ?? .blue).frame(width: max(0, min(1, value)) * geo.size.width)
                Capsule().strokeBorder(Theme.ink, lineWidth: 2)
            }
        }
        .frame(height: 12)
    }
}

/// Wrapping row of small controls.
private struct FlowChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(items) { content($0) }
        }
    }
}

/// One task on the timeline rail: checkbox, time, title (+ note), list tag, estimate.
struct TimelineTaskRow: View {
    let task: TaskItem
    let allTasks: [TaskItem]
    let categories: [CategoryItem]
    var isFocused = false
    /// Show the weekday ("Wed 6:00 PM") instead of just the time, for overdue tasks from earlier days.
    var showDay = false
    var isMultiSelecting = false
    var isMultiSelected = false
    var onToggleMultiSelect: (() -> Void)? = nil
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.keyboardFocusedTaskID) private var keyboardFocusedID
    @State private var isOptimisticallyDone = false
    @State private var flash = false
    @State private var confetti = 0
    @State private var isPressed = false

    private var done: Bool { task.isCompleted || isOptimisticallyDone }
    private var isBlocked: Bool { !done && task.isBlocked(in: allTasks) }
    private var timeLabel: String {
        guard let due = task.dueDate, Planner.hasClockTime(due) else {
            return showDay ? (task.dueDate?.formatted(.dateTime.weekday(.abbreviated)) ?? "Anytime") : "Anytime"
        }
        if showDay && !Calendar.current.isDateInToday(due) {
            return due.formatted(.dateTime.weekday(.abbreviated)) + " " + due.formatted(date: .omitted, time: .shortened)
        }
        return due.formatted(date: .omitted, time: .shortened)
    }

    private func tick() {
        if isMultiSelecting { onToggleMultiSelect?(); return }
        guard !isOptimisticallyDone else { return }
        if isBlocked { onToggle(); return }
        isOptimisticallyDone = true
        confetti += 1
        withAnimation(.easeOut(duration: 0.15)) { flash = true }
        Task {
            try? await Task.sleep(for: .seconds(TaskCard.completionDelay))
            onToggle()
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: tick) {
                ZStack {
                    if isMultiSelecting {
                        RoundedRectangle(cornerRadius: 6).fill(isMultiSelected ? Theme.ink : Theme.card)
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink, lineWidth: 2)
                        if isMultiSelected { Image(systemName: "checkmark").font(.system(size: 14, weight: .black)).foregroundStyle(.white) }
                    } else {
                        Circle().fill(done ? Theme.done : Theme.card)
                        Circle().strokeBorder(Theme.ink, lineWidth: 2)
                        if isBlocked { Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold)) }
                        else if done { Image(systemName: "checkmark").font(.system(size: 14, weight: .black)) }
                    }
                }
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
            }
            .buttonStyle(HoverPlainStyle(hover: false))
            .overlay { ConfettiBurst(trigger: confetti).allowsHitTesting(false) }
            .help(isBlocked ? "Waiting on another task" : "Mark as done")
            .accessibilityLabel("Mark \(task.title) as done")

            Text(timeLabel).font(Fonts.ui(15, .bold)).foregroundStyle(Theme.ink).frame(width: showDay ? 104 : 78, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(Fonts.ui(17, .heavy)).foregroundStyle(Theme.ink).lineLimit(2)
                    .strikethrough(done)
                if !task.notes.isEmpty {
                    Text(task.notes).font(Fonts.ui(14, .medium)).foregroundStyle(Theme.inkMuted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ListTag(name: task.category, color: Categories.color(for: task.category, in: categories))
            Text("≈ \(Planner.label(minutes: Planner.minutes(of: task)))")
                .font(Fonts.ui(14, .bold)).foregroundStyle(Theme.ink).frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .neoCard(flash ? Theme.done : Theme.card, radius: 12, shadow: isPressed ? 0 : 3)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.ink, lineWidth: (isFocused || keyboardFocusedID == task.id || (isMultiSelecting && isMultiSelected)) ? 5 : 0))
        .offset(x: isPressed ? 3 : 0, y: isPressed ? 3 : 0)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in isPressed = true }.onEnded { _ in isPressed = false })
        .contentShape(Rectangle())
        .onTapGesture { if isMultiSelecting { onToggleMultiSelect?() } else { onSelect() } }
        .themedContextMenu {
            [
                .action("Mark Done", icon: "checkmark.circle", tick),
                .action("Edit…", icon: "pencil", onEdit),
                .divider,
                .action("Delete", icon: "trash", destructive: true, onDelete)
            ]
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timeLabel), \(task.title), about \(Planner.minutes(of: task)) minutes")
        .accessibilityAction(named: Text("Mark done"), tick)
        .accessibilityAction(named: Text("Edit"), onEdit)
        .accessibilityAction(named: Text("Delete"), onDelete)
    }
}
