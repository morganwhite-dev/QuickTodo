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
}

// ─────────────────────────────────────────────────────────────────────────────
