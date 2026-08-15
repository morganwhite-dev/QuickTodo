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
                HelpGuideItem(title: "Detailed Task", body: "Use Detailed Task when you need notes, a precise due date, custom reminders, or more control before saving."),
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
            icon: "sidebar.left",
            color: Theme.dueSoon,
            items: [
                HelpGuideItem(title: "Sidebar Views", body: "General collects quick-adds that have no plan yet. Decision Board is the main workspace. Today shows what's due today and tomorrow. Upcoming covers everything scheduled beyond that. Lists groups tasks by category, and Completed keeps a record of finished work."),
                HelpGuideItem(title: "Decision Board", body: "Ready is a live, computed shortlist of your highest-signal General tasks — it never moves them, it just surfaces them. Use the sort menu above the board to reorder Capture, Scheduled, and In Progress by due date, priority, or your own manual order."),
                HelpGuideItem(title: "Categories", body: "Use Manage Categories to create, rename, recolor, delete, and reorder categories."),
                HelpGuideItem(title: "Drag Reordering", body: "Drag a list directly on the Lists tab to reorder it, or do the same in Manage Categories. On the Decision Board, drag a task card to reorder it or drop it on another lane to change its stage.")
            ]
        ),
        HelpGuideSection(
            title: "Complete And Clean Up",
            icon: "checkmark.circle.fill",
            color: Theme.lowPressure,
            items: [
                HelpGuideItem(title: "Complete Tasks", body: "Click the circle on a task card to mark it complete. Click again to make it active."),
                HelpGuideItem(title: "Completed", body: "Finished tasks move out of the board and into the Completed sidebar section, where you can still search them."),
                HelpGuideItem(title: "Clear Completed", body: "Open Completed and click Clear Completed. QuickTodo asks for confirmation before deleting finished tasks.")
            ]
        ),
        HelpGuideSection(
            title: "Editing And Safety",
            icon: "pencil.circle.fill",
            color: Theme.onDeck,
            items: [
                HelpGuideItem(title: "Edit Tasks", body: "Use the pencil button on a task card to edit details inline."),
                HelpGuideItem(title: "Subtasks", body: "Open a task with the pencil button to add checklist subtasks. Tick them off right on the card as you go."),
                HelpGuideItem(title: "Dependencies", body: "Set \"Depends on\" only when a task genuinely can't start until another one is finished. A 🔗 badge marks the task being waited on; an ⌛ badge marks the one that's stuck. QuickTodo won't let you complete a task while what it depends on is still open."),
                HelpGuideItem(title: "Delete Tasks", body: "Deleted tasks move to Trash, not gone for good. An Undo prompt appears briefly after deletion, and anything you miss can still be restored from Trash for 30 days."),
                HelpGuideItem(title: "Reminders", body: "Tasks with due dates can schedule local reminders. If reminders do not appear, check macOS notification permission for QuickTodo."),
                HelpGuideItem(title: "Settings", body: "Open QuickTodo ▸ Settings (⌘,) to mute completion sounds, launch at login, set your focus window, see the global hotkey, check notification status, or replay the welcome screen.")
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
            .background(Theme.bg)
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(
                    Theme.accent.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("QuickTodo Help")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Quick capture, clean organization, reminders, shortcuts, and safe task cleanup.")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(section.color)
                    .frame(width: 30, height: 30)
                    .background(section.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(section.items.count) \(section.items.count == 1 ? "topic" : "topics")")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    HelpGuideItemRow(item: item)

                    if index < section.items.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.065))
                            .frame(height: 1)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.043), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        }
    }
}

private struct HelpGuideItemRow: View {
    let item: HelpGuideItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 12.8, weight: .semibold))
                .foregroundStyle(.primary)

            Text(item.body)
                .font(.system(size: 12.4))
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
