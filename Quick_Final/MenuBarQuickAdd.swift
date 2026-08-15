// MenuBarQuickAdd.swift
// Global hotkey + the floating Quick Add panel it opens, and the menu bar extra's own quick-add field.

import SwiftUI
import AppKit
import Carbon.HIToolbox
import SwiftData

// MARK: Global Quick Add Hotkey

/// Registers a process-wide hotkey using Carbon's RegisterEventHotKey. It fires even when
/// QuickTodo is in the background and does not require Accessibility permission, so it is
/// safe for the Mac App Store.
final class GlobalHotKeyManager: @unchecked Sendable {
    static let shared = GlobalHotKeyManager()
    private init() {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    // ⌃⌥⌘ Space
    static let keyCode = UInt32(kVK_Space)
    static let modifierFlags = UInt32(controlKey | optionKey | cmdKey)
    static let shortcutLabel = "⌃⌥⌘ Space"

    func register(onTrigger: @escaping () -> Void) {
        guard hotKeyRef == nil else { return }
        self.onTrigger = onTrigger

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onTrigger?()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x51544B59), id: 1) // 'QTKY'
        RegisterEventHotKey(Self.keyCode, Self.modifierFlags, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

/// A floating HUD panel that pops up anywhere (via the global hotkey or the Tasks menu) for
/// frictionless capture into the shared SwiftData store.
@MainActor
final class QuickAddPanelController {
    static let shared = QuickAddPanelController()
    private init() {}

    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let container = SwiftDataBridge.shared.modelContainer else { return }

        if panel == nil {
            let hosting = NSHostingView(
                rootView: QuickAddPanelView(onClose: { [weak self] in self?.panel?.orderOut(nil) })
                    .modelContainer(container)
            )
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
                styleMask: [.titled, .closable, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Quick Add"
            panel.contentView = hosting
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
        }

        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}

struct QuickAddPanelView: View {
    @Environment(\.modelContext) private var context
    @State private var text: String = ""
    @FocusState private var focused: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Theme.accent)
                Text("Quick Add")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(GlobalHotKeyManager.shortcutLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("essay friday 11:59pm #English !high", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit(save)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
                )

            HStack {
                Text("Return to add • Esc to close")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add", action: save)
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
        }
        .onExitCommand(perform: onClose)
    }

    private func save() {
        let parsed = QuickDateParser.parse(text)
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let category = ensureCategoryExists(named: parsed.category ?? "General")
        let item = TaskItem(
            title: parsed.title,
            notes: "",
            dueDate: parsed.date,
            category: category,
            priority: parsed.priority ?? .low,
            sortIndex: nextTaskSortIndex(),
            stage: TaskStage.suggestedInitial(forDueDate: parsed.date)
        )
        context.insert(item)
        context.saveOrReport()
        if parsed.date != nil { NotificationManager.shared.schedule(for: item) }
        NotificationCenter.default.post(name: .quickToDoTaskCreated, object: item.id)
        text = ""
        onClose()
    }

    private func nextTaskSortIndex() -> Int {
        let descriptor = FetchDescriptor<TaskItem>()
        let existingTasks = (try? context.fetch(descriptor)) ?? []
        return (existingTasks.compactMap(\.sortIndex).max() ?? existingTasks.count) + 1
    }

    private func ensureCategoryExists(named raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "General" }

        let descriptor = FetchDescriptor<CategoryItem>()
        if let existing = try? context.fetch(descriptor).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.name
        }

        let existingCategories = (try? context.fetch(descriptor)) ?? []
        let nextIndex = ((existingCategories.compactMap(\.sortIndex).max() ?? existingCategories.count) + 1)
        context.insert(CategoryItem(name: name, sortIndex: nextIndex))
        context.saveOrReport()
        return name
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Menu Bar Quick Add View

struct MenuBarView: View {
    @Environment(\.modelContext) private var context
    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                TextField("Quick add… (#tag optional)", text: $text)
                    .textFieldStyle(.plain)
                    .onSubmit(save)
                    .help("Quick add a task from the menu bar. Example: email Sam tomorrow #Work !medium")

            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))

            Button { save() } label: { Label("Add Task", systemImage: "plus.circle.fill") }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .help("Save this menu bar task")
        }
        .padding(12)
        .frame(width: 320)
    }

    private func save() {
        let parsed = QuickDateParser.parse(text)
        guard !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let category = ensureCategoryExists(named: parsed.category ?? "General")
        let item = TaskItem(
            title: parsed.title,
            notes: "",
            dueDate: parsed.date,
            category: category,
            priority: parsed.priority ?? .low,
            sortIndex: nextTaskSortIndex(),
            stage: TaskStage.suggestedInitial(forDueDate: parsed.date)
        )
        context.insert(item)
        context.saveOrReport()
        if parsed.date != nil { NotificationManager.shared.schedule(for: item) }
        NotificationCenter.default.post(name: .quickToDoTaskCreated, object: item.id)
        text = ""
    }

    private func nextTaskSortIndex() -> Int {
        let descriptor = FetchDescriptor<TaskItem>()
        let existingTasks = (try? context.fetch(descriptor)) ?? []
        return (existingTasks.compactMap(\.sortIndex).max() ?? existingTasks.count) + 1
    }

    private func ensureCategoryExists(named raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "General" }

        let descriptor = FetchDescriptor<CategoryItem>()
        if let existing = try? context.fetch(descriptor).first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.name
        }

        let existingCategories = (try? context.fetch(descriptor)) ?? []
        let nextIndex = ((existingCategories.compactMap(\.sortIndex).max() ?? existingCategories.count) + 1)
        context.insert(CategoryItem(name: name, sortIndex: nextIndex))
        context.saveOrReport()
        return name
    }
}


// ─────────────────────────────────────────────────────────────────────────────
