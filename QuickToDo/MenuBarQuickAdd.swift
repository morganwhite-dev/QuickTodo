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
/// Borderless panels refuse key status by default, which would stop the text field typing.
final class QuickAddPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

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
            let panel = QuickAddPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovableByWindowBackground = true
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
    @State private var justAdded = false
    @FocusState private var focused: Bool
    let onClose: () -> Void

    private var parsed: QuickDateParser.Result { QuickDateParser.parse(text) }
    private var canAdd: Bool { !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Q").font(Fonts.black(18)).foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36).neoCard(Theme.amber, radius: 9, shadow: 0)
                Text("Quick Add").font(Fonts.black(22)).foregroundStyle(Theme.ink)
                Spacer()
                Text(GlobalHotKeyManager.shortcutLabel)
                    .font(Fonts.ui(12, .bold)).foregroundStyle(Theme.inkMuted)
            }

            TextField("essay friday 11:59pm #English !high", text: $text)
                .textFieldStyle(.plain)
                .font(Fonts.ui(18, .bold))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onSubmit(save)
                .padding(.horizontal, 16).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink, lineWidth: 2))

            if justAdded {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(Fonts.ui(14, .heavy)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .neoCard(Theme.done, radius: 8, shadow: 0)
            } else {
                HStack(spacing: 8) {
                    NeoChip(text: parsed.date.map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()) } ?? "No date", size: 13)
                    NeoChip(text: parsed.category ?? "General", fill: Theme.sand, size: 13)
                    NeoChip(text: parsed.priority.map { $0.label } ?? "None", size: 13)
                }
            }

            HStack {
                Text("Return to add · Esc to close")
                    .font(Fonts.ui(13, .semibold)).foregroundStyle(Theme.inkMuted)
                Spacer()
                Button(action: save) {
                    Text("Add").font(Fonts.ui(16, .heavy)).padding(.horizontal, 24).frame(height: 42)
                }
                .buttonStyle(PressableStyle(fill: Theme.amber, radius: 10, shadow: 4))
                .disabled(!canAdd).opacity(canAdd ? 1 : 0.5)
            }
        }
        .padding(20)
        .frame(width: 440)
        .neoCard(Theme.navBar, radius: 14, shadow: 6)
        .padding(.trailing, 6).padding(.bottom, 6)
        .background(Color.clear)
        .preferredColorScheme(.light)
        .onAppear {
            Fonts.register()
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
        VStack(spacing: 12) {
            TextField("Quick add… (#tag optional)", text: $text)
                .textFieldStyle(.plain)
                .font(Fonts.ui(15, .bold)).foregroundStyle(Theme.ink)
                .onSubmit(save)
                .help("Quick add a task from the menu bar. Example: email Sam tomorrow #Work !medium")
                .padding(.horizontal, 12).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink, lineWidth: 2))

            Button { save() } label: {
                Text("Add Task").font(Fonts.ui(14, .heavy)).frame(maxWidth: .infinity).frame(height: 38)
            }
            .buttonStyle(PressableStyle(fill: Theme.amber, radius: 10, shadow: 3))
            .help("Save this menu bar task")
        }
        .padding(16)
        .padding(.trailing, 3).padding(.bottom, 3)
        .frame(width: 340)
        .background(Theme.navBar)
        .preferredColorScheme(.light)
        .onAppear { Fonts.register() }
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
