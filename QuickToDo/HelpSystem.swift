// HelpSystem.swift
// In-app help tips and the standalone Help window.

import SwiftUI
import AppKit

// MARK: Help Registry

enum QuickTodoHelpContent {
    static let quickAddTips = [
        "Write naturally: essay friday 11:59pm",
        "Add #English to assign a task, or type #English alone to create the category.",
        "Use !high, !medium, or !low when priority matters.",
        "Press ⌃⌥⌘ Space anywhere to capture a task without opening the app.",
        "Open Detailed Task when you need notes, reminders, or exact settings."
    ]

    static let notificationDeniedTip = "Enable notifications in System Settings to receive reminders."

    static let sections: [HelpGuideSection] = [
        HelpGuideSection(
            title: "Create Tasks",
            icon: "plus.circle.fill",
            color: Theme.accent,
            items: [
                HelpGuideItem(title: "Quick Add", body: "Type a task in plain language, then press Return or Add. Example: essay friday 11:59pm #English !high. New categories like #English are created automatically the first time you use them."),
                HelpGuideItem(title: "Detailed Task", body: "Use Detailed Task when you need notes, a precise due date, a reminder, or more control before saving."),
                HelpGuideItem(title: "Recurring Tasks", body: "In Detailed Task, turn on Repeats once a due date is set to bring a task back Daily, Weekdays, Weekly, or Monthly. Completing it leaves the finished one in Completed and schedules the next occurrence."),
                HelpGuideItem(title: "Menu Bar", body: "Use the QuickTodo menu bar icon to capture a task without switching back to the main window."),
                HelpGuideItem(title: "Global Hotkey", body: "Press ⌃⌥⌘ Space from any app to pop up Quick Add. It uses the same plain-language parsing and files uncategorized tasks into General.")
            ]
        ),
        HelpGuideSection(
            title: "Quick Add Language",
            icon: "text.badge.plus",
            color: Theme.accent,
            items: [
                HelpGuideItem(title: "Dates", body: "Use words like today, tomorrow, friday, june 15, 2pm, or in 10 minutes."),
                HelpGuideItem(title: "Categories", body: "Add #Work to file a task there, or type #Work by itself to create the category ahead of time. Category matching is not case-sensitive."),
                HelpGuideItem(title: "Priority", body: "Add !high, !medium, or !low. Set the Decision Board's sort menu to Priority to bring that work to the top.")
            ]
        ),
        HelpGuideSection(
            title: "Organize",
            icon: "square.grid.2x2",
            color: Theme.dueSoon,
            items: [
                HelpGuideItem(title: "Top Bar Tabs", body: "Decision Board is the main workspace. General is your capture inbox, sorted into High, Medium and Low priority lanes. Today shows what's overdue or due later today. Upcoming is the week planner for tomorrow onward, with free-time blocks you can plan into. Lists browses tasks by list. Completed keeps a record of finished work. Settings is the gear icon at the top right. Trash is in the Go menu."),
                HelpGuideItem(title: "Keyboard Shortcuts", body: "⌘1–⌘6 switch tabs and ⇧⌘T opens Trash. ⌘N adds a task, ⌘F searches everything, ⌘D marks the selected task done, ⌘E edits it and ⌘⌫ deletes it. In General, Today, Lists and Completed, press ↑ and ↓ to move between tasks and Space or Return to tick one. In Upcoming, ← and → change the day."),
                HelpGuideItem(title: "Decision Board", body: "The amber Next Move card always shows the one task to do now: an overdue task if there is one, otherwise the soonest due. Start moves it to In Progress and Done completes it. Tasks sit in four columns: Capture (no due date), Ready (overdue or due within a week), Scheduled (due further out; they move up to Ready as the date gets within a week) and In Progress. Use the sort menu at the top right to order them by recommendation, due date, priority, or your own manual order."),
                HelpGuideItem(title: "Today And Upcoming", body: "Today is overdue plus due-later-today work, with a progress ring and an Up Next card. Upcoming shows a 7-day strip and a timeline for the selected day. Gaps of 30 minutes or more between tasks appear as free time with a Plan this time button. Completing a task never turns its slot into extra free time."),
                HelpGuideItem(title: "General And Lists", body: "General sorts captured tasks into High, Medium and Low lanes. Drag a note to another lane to change its priority. Lists shows every list on the left with its progress, and the selected list's open tasks on the right, grouped by when they're due."),
                HelpGuideItem(title: "Categories", body: "Use Manage Categories to create, recolor, delete, and reorder categories."),
                HelpGuideItem(title: "Drag And Drop", body: "On the Decision Board, drag a task card to reorder it or drop it on another column to change its stage. In General, drag a note onto another priority lane. On Lists, drag a list in the left rail to reorder it. You can also right-click any task and choose Move to Today, Move to Tomorrow or Move to Column.")
            ]
        ),
        HelpGuideSection(
            title: "Complete And Clean Up",
            icon: "checkmark.circle.fill",
            color: Theme.lowPressure,
            items: [
                HelpGuideItem(title: "Complete Tasks", body: "Click the circle on a task to mark it complete. A short Undo prompt appears, and an undone task returns to the column it came from."),
                HelpGuideItem(title: "Completed", body: "Finished tasks move out of the board and into the Completed tab, where you can still search them, restore them one at a time, or use Select to restore several at once."),
                HelpGuideItem(title: "Clear Completed", body: "Open Completed and click Clear Completed. QuickTodo asks for confirmation before deleting finished tasks.")
            ]
        ),
        HelpGuideSection(
            title: "Editing And Safety",
            icon: "pencil.circle.fill",
            color: Theme.onDeck,
            items: [
                HelpGuideItem(title: "Edit Tasks", body: "Click any task to open the full editor with notes, steps, progress, due date, repeat, estimate, priority, list, dependency and reminder. Right-click for quick actions: Mark Done, Start Now, Move to Today / Tomorrow / Column, File as Someday and Delete."),
                HelpGuideItem(title: "Steps", body: "In the editor, add checklist steps (or let on-device AI suggest a few) and tick them off as you go. The Progress slider in the editor tracks work you can't finish in one sitting, like a lab, and shows as a bar on the task."),
                HelpGuideItem(title: "Dependencies", body: "Set \"Depends on\" only when a task genuinely can't start until another one is finished. A blocked task shows a lock, and its card says Waiting on the other task. QuickTodo won't let you complete it, or take its progress past 99%, until the other task is done. Many tasks can wait on the same one. Loops are prevented, and a blocked task is never picked as your Next Move."),
                HelpGuideItem(title: "Delete Tasks", body: "Deleted tasks move to Trash, not gone for good. An Undo prompt appears briefly after deletion, and anything you miss can be restored from Trash (Go ▸ Trash, or ⇧⌘T) for 30 days. Emptying the Trash or deleting forever asks for confirmation first."),
                HelpGuideItem(title: "Reminders", body: "Tasks with due dates can schedule local reminders. If reminders do not appear, check macOS notification permission for QuickTodo."),
                HelpGuideItem(title: "Settings", body: "Open QuickTodo ▸ Settings (⌘,), or the gear icon, to mute completion sounds, launch at login, set your focus window, see the global hotkey, check notification status, import a school plan from JSON, back up or restore your data, or replay the welcome screen.")
            ]
        )
    ]
}

// ─────────────────────────────────────────────────────────────────────────────

// MARK: Help

@MainActor
final class QuickTodoHelpWindowController {
    static let shared = QuickTodoHelpWindowController()

    private var window: NSWindow?
    private var windowDelegate: HelpWindowDelegate?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: QuickTodoHelpView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickTodo Help"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        let delegate = HelpWindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        window.delegate = delegate

        self.windowDelegate = delegate
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class HelpWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

struct QuickTodoHelpView: View {
    private let sections = QuickTodoHelpContent.sections

    private let twoColumns = [
        GridItem(.flexible(), spacing: 16, alignment: .top),
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    private let oneColumn = [
        GridItem(.flexible(), spacing: 16, alignment: .top)
    ]

    var body: some View {
        GeometryReader { geo in
            let useTwoColumns = geo.size.width >= 700

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    LazyVGrid(
                        columns: useTwoColumns ? twoColumns : oneColumn,
                        alignment: .center,
                        spacing: 16
                    ) {
                        ForEach(sections) { section in
                            HelpGuideCard(section: section)
                        }
                    }
                }
                .padding(28)
            }
            .background(Theme.navBar)
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(Fonts.black(34))
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .neoCard(Theme.amber, radius: 12, shadow: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text("QuickTodo Help")
                    .font(Fonts.black(28))

                Text("Quick capture, clean organization, reminders, shortcuts, and safe task cleanup.")
                    .font(Fonts.ui(13.5, .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.ink, lineWidth: 2)
        }
    }
}

struct HelpGuideSection: Identifiable, @unchecked Sendable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let items: [HelpGuideItem]
}

struct HelpGuideItem: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let body: String
}

struct HelpGuideCard: View {
    let section: HelpGuideSection

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(Fonts.ui(14, .bold))
                    .foregroundStyle(section.color)
                    .frame(width: 30, height: 30)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(Fonts.ui(16, .heavy))
                        .foregroundStyle(Theme.ink)

                    Text("\(section.items.count) \(section.items.count == 1 ? "topic" : "topics")")
                        .font(Fonts.ui(12.5, .bold))
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    HelpGuideItemRow(item: item)

                    if index < section.items.count - 1 {
                        Rectangle()
                            .fill(Theme.card)
                            .frame(height: 1)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Theme.ink, lineWidth: 2)
        }
    }
}

private struct HelpGuideItemRow: View {
    let item: HelpGuideItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(Fonts.ui(12.8, .bold))
                .foregroundStyle(Theme.ink)

            Text(item.body)
                .font(Fonts.ui(13, .medium))
                .foregroundStyle(Theme.inkMuted)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
