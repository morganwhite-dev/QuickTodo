// DecisionBoardComponents.swift
// The amber Next Move card and the "This week" summary panel at the top of the board.

import SwiftUI

struct NextMoveCard: View {
    let task: TaskItem?
    var hasOpenTasks = false
    let allTasks: [TaskItem]
    let categories: [CategoryItem]
    let onStart: (TaskItem) -> Void
    let onDone: (TaskItem) -> Void
    let onOpen: (TaskItem) -> Void

    @State private var finishingID: UUID?
    @State private var confetti = 0

    private func isOverdue(_ t: TaskItem) -> Bool { Planner.isOverdue(t) }

    private func why(_ t: TaskItem) -> String {
        if let rec = NextMoveEngine.recommend(for: t, in: allTasks) { return rec.summary }
        return "It's the soonest thing on your plate."
    }

    var body: some View {
        Group {
            if let task { content(task) } else { empty }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .neoCard(Theme.amber, radius: 8, shadow: 6)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            tag("NEXT MOVE", fill: Theme.ink, fg: .white)
            // "Great work" only when nothing is left; open-but-blocked tasks get honest copy.
            Text(hasOpenTasks ? "No next move yet" : "Nothing else due")
                .font(Fonts.bricolage(38, .heavy)).foregroundStyle(Theme.ink)
            Text(hasOpenTasks ? "What's left is waiting on another task to finish first." : "Great work today. Get some rest.")
                .font(Fonts.ui(16, .semibold)).foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 120)
    }

    private func content(_ task: TaskItem) -> some View {
        let color = Categories.color(for: task.category, in: categories)
        let finishing = finishingID == task.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                tag("NEXT MOVE", fill: Theme.ink, fg: .white)
                if isOverdue(task) { tag("OVERDUE", fill: Theme.overdue, fg: .white) }
                if let due = task.dueDate {
                    Text(isOverdue(task) ? "Was due \(relativeDate(due).lowercasedFirst)" : "Due \(relativeDate(due).lowercasedFirst)")
                        .font(Fonts.ui(14, .bold)).foregroundStyle(Theme.ink)
                }
            }
            Button { onOpen(task) } label: {
                Text(task.title)
                    .font(Fonts.black(30)).foregroundStyle(Theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.leading)
            }
            .buttonStyle(HoverPlainStyle())
            HStack(spacing: 8) {
                ListTag(name: task.category, color: color)
                NeoChip(text: "≈ \(Planner.label(minutes: Planner.minutes(of: task)))", size: 13)
            }
            Text(why(task)).font(Fonts.ui(15, .medium)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Button { onStart(task) } label: {
                    Label("Start", systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                        .font(Fonts.ui(16, .heavy)).padding(.horizontal, 20).frame(height: 42)
                }
                .buttonStyle(PressableStyle(fill: .white, radius: 8, shadow: 4))
                Button {
                    guard finishingID == nil else { return }
                    finishingID = task.id
                    confetti += 1
                    Task {
                        try? await Task.sleep(for: .seconds(TaskCard.completionDelay))
                        onDone(task)
                        finishingID = nil
                    }
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(Fonts.ui(16, .heavy)).padding(.horizontal, 20).frame(height: 42)
                }
                .buttonStyle(PressableStyle(hover: false, fill: Theme.done, radius: 8, shadow: 4))
                .overlay { ConfettiBurst(trigger: confetti).allowsHitTesting(false) }
                .disabled(finishing)
            }
            Spacer(minLength: 0)
        }
    }

    private func tag(_ text: String, fill: Color, fg: Color) -> some View {
        Text(text).font(Fonts.ui(12, .heavy)).tracking(1.2).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 3).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ink, lineWidth: 2))
    }
}

private extension String {
    /// "Today at 6 PM" -> "today at 6 PM" so it reads inside a sentence, but weekday names
    /// ("Tuesday at 5:30 PM") keep their capital.
    var lowercasedFirst: String {
        let relative = ["Today", "Tomorrow", "Yesterday"]
        guard relative.contains(where: { hasPrefix($0) }) else { return self }
        return prefix(1).lowercased() + dropFirst()
    }
}

/// Sand-coloured "THIS WEEK" card: done / total, minutes of work left, progress bar.
struct WeekSummaryCard: View {
    let summary: Planner.WeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THIS WEEK").font(Fonts.ui(12, .heavy)).tracking(1.4).foregroundStyle(Theme.ink)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.done)").font(Fonts.black(48)).foregroundStyle(Theme.ink)
                Text("/ \(summary.total)").font(Fonts.black(22)).foregroundStyle(Theme.ink)
            }
            Text("tasks done this week · \(Planner.label(minutes: summary.minutesLeft)) of work left")
                .font(Fonts.ui(15, .semibold)).foregroundStyle(Theme.ink)
            NeoProgressBar(value: summary.total == 0 ? 0 : Double(summary.done) / Double(summary.total), height: 20)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .neoCard(Theme.sand, radius: 8, shadow: 6)
        .accessibilityElement(children: .combine)
    }
}
