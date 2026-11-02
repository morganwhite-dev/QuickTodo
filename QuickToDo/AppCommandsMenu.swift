// AppCommandsMenu.swift
// Menu bar commands (File > New Task) and the FocusedValue plumbing that wires them to the active window.

import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Menu & Shortcuts

struct AppCommands: Commands {
    @FocusedValue(\.taskActions) var actions

    var body: some Commands {
        CommandMenu("Tasks") {
            Button("New Task", action: { actions?.newTask() }).keyboardShortcut("n", modifiers: [.command])
            Button("Quick Capture (\(GlobalHotKeyManager.shortcutLabel))") {
                Task { @MainActor in
                    QuickAddPanelController.shared.show()
                }
            }
            Divider()
            Button("Find Task…", action: { actions?.focusSearch() }).keyboardShortcut("f", modifiers: [.command])
            Button("Toggle Done", action: { actions?.toggleSelected() }).keyboardShortcut("d", modifiers: [.command])
            Button("Edit Task…", action: { actions?.editSelected() }).keyboardShortcut("e", modifiers: [.command])
            Button("Delete Task", action: { actions?.deleteSelected() }).keyboardShortcut(.delete, modifiers: [.command])
        }

        CommandMenu("Go") {
            Button("Decision Board") { actions?.goToTab(.decisionBoard) }.keyboardShortcut("1", modifiers: [.command])
            Button("General") { actions?.goToTab(.general) }.keyboardShortcut("2", modifiers: [.command])
            Button("Today") { actions?.goToTab(.today) }.keyboardShortcut("3", modifiers: [.command])
            Button("Upcoming") { actions?.goToTab(.upcoming) }.keyboardShortcut("4", modifiers: [.command])
            Button("Lists") { actions?.goToTab(.lists) }.keyboardShortcut("5", modifiers: [.command])
            Button("Completed") { actions?.goToTab(.completed) }.keyboardShortcut("6", modifiers: [.command])
            Divider()
            Button("Trash") { actions?.goToTab(.trash) }.keyboardShortcut("t", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button("QuickTodo Help") {
                Task { @MainActor in
                    QuickTodoHelpWindowController.shared.show()
                }
            }
        }
    }
}

struct TaskActionsKey: FocusedValueKey { typealias Value = TaskActions }
extension FocusedValues { var taskActions: TaskActions? { get { self[TaskActionsKey.self] } set { self[TaskActionsKey.self] = newValue } } }
struct TaskActions {
    let newTask: () -> Void
    let focusSearch: () -> Void
    let toggleSelected: () -> Void
    let editSelected: () -> Void
    let deleteSelected: () -> Void
    let goToTab: (SidebarSection) -> Void
}

// ─────────────────────────────────────────────────────────────────────────────
