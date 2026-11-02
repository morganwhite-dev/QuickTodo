// ThemedPopups.swift
// Themed replacements for the remaining system pop-ups: right-click menus and alert dialogs.
// Both are drawn by the same host as the dropdowns (see Dropdown.swift), so they share the
// neo-brutalist look: cream card, black border, hard shadow.

import SwiftUI
import AppKit

// MARK: - Alerts

struct AlertButton: Identifiable {
    enum Role { case normal, cancel, destructive }
    let id = UUID()
    let title: String
    var role: Role = .normal
    var action: () -> Void = {}
}

struct AlertSpec {
    let title: String
    let message: String
    let buttons: [AlertButton]
}

struct ThemedAlertOverlay: View {
    @ObservedObject var controller: DropdownController

    var body: some View {
        if let alert = controller.alert {
            ZStack {
                Color.black.opacity(0.55).contentShape(Rectangle()).onTapGesture {}
                VStack(alignment: .leading, spacing: 14) {
                    Text(alert.title).font(Fonts.black(22)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !alert.message.isEmpty {
                        Text(alert.message).font(Fonts.ui(15, .semibold)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 12) {
                        Spacer(minLength: 0)
                        ForEach(alert.buttons) { button in
                            Button {
                                controller.dismissAlert()
                                button.action()
                            } label: {
                                Text(button.title).font(Fonts.ui(15, .heavy))
                                    .padding(.horizontal, 20).frame(height: 42)
                            }
                            .buttonStyle(style(for: button.role))
                            .modifier(AlertShortcut(role: button.role))
                        }
                    }
                    .padding(.trailing, 3).padding(.bottom, 3)
                }
                .padding(24)
                .frame(width: 460)
                .neoCard(Theme.navBar, radius: 8, shadow: 8)
                .padding(.trailing, 8).padding(.bottom, 8)
            }
            .transition(.opacity)
            .onExitCommand {
                if let cancel = alert.buttons.first(where: { $0.role == .cancel }) {
                    controller.dismissAlert(); cancel.action()
                } else { controller.dismissAlert() }
            }
        }
    }

    private func style(for role: AlertButton.Role) -> PressableStyle {
        switch role {
        case .cancel: return PressableStyle(fill: Theme.card, radius: 10, shadow: 3)
        case .destructive: return PressableStyle(fill: Theme.overdue, foreground: .white, radius: 10, shadow: 3)
        case .normal: return PressableStyle(fill: Theme.ink, foreground: .white, radius: 10, shadow: 3)
        }
    }
}

private struct AlertShortcut: ViewModifier {
    let role: AlertButton.Role
    func body(content: Content) -> some View {
        switch role {
        case .cancel: content.keyboardShortcut(.cancelAction)
        case .normal: content.keyboardShortcut(.defaultAction)
        case .destructive: content
        }
    }
}

// MARK: - Context menu

struct ContextItem: Identifiable {
    enum Kind {
        case action(title: String, icon: String?, destructive: Bool, enabled: Bool, run: () -> Void)
        case divider
        case group(title: String, items: [ContextItem])
    }
    let id = UUID()
    let kind: Kind

    static func action(_ title: String, icon: String? = nil, destructive: Bool = false, enabled: Bool = true, _ run: @escaping () -> Void) -> ContextItem {
        ContextItem(kind: .action(title: title, icon: icon, destructive: destructive, enabled: enabled, run: run))
    }
    static var divider: ContextItem { ContextItem(kind: .divider) }
    static func group(_ title: String, _ items: [ContextItem]) -> ContextItem {
        ContextItem(kind: .group(title: title, items: items))
    }

    /// Rough height of the collapsed menu, used to keep it on screen.
    static func estimatedHeight(_ items: [ContextItem]) -> CGFloat {
        items.reduce(16) { total, item in
            if case .divider = item.kind { return total + 10 }
            return total + 38
        }
    }
}

struct ContextMenuCard: View {
    let items: [ContextItem]
    let controller: DropdownController
    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                switch item.kind {
                case .divider:
                    Rectangle().fill(Theme.ink).frame(height: 2).padding(.vertical, 4).padding(.horizontal, 4)
                case .action(let title, let icon, let destructive, let enabled, let run):
                    ContextRow(title: title, icon: icon, destructive: destructive, enabled: enabled) {
                        controller.close(); run()
                    }
                case .group(let title, let children):
                    ContextRow(title: title, icon: nil, destructive: false, enabled: true, chevron: expanded == item.id ? "chevron.down" : "chevron.right") {
                        withAnimation(.easeOut(duration: 0.12)) { expanded = expanded == item.id ? nil : item.id }
                    }
                    if expanded == item.id {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(children) { child in
                                if case .action(let t, let i, let d, let e, let run) = child.kind {
                                    ContextRow(title: t, icon: i, destructive: d, enabled: e) { controller.close(); run() }
                                }
                            }
                        }
                        .padding(.leading, 14)
                    }
                }
            }
        }
        .padding(8)
    }
}

private struct ContextRow: View {
    let title: String
    let icon: String?
    let destructive: Bool
    let enabled: Bool
    var chevron: String? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .bold)).frame(width: 16) }
                Text(title).font(Fonts.ui(14, .heavy)).lineLimit(1)
                Spacer(minLength: 6)
                if let chevron { Image(systemName: chevron).font(.system(size: 10, weight: .black)) }
            }
            .foregroundStyle(destructive ? Theme.overdue : Theme.ink)
            .padding(.horizontal, 10).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovered && enabled ? Theme.panel : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink, lineWidth: hovered && enabled ? 2 : 0))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(HoverPlainStyle())
        .disabled(!enabled)
        .onHover { hovered = $0 }
    }
}

// MARK: - Right-click catcher

/// Invisible overlay that only reacts to right-clicks (and control-clicks); everything else
/// falls straight through to the view underneath.
private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.handler = onRightClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.handler = onRightClick }

    final class CatcherView: NSView {
        var handler: ((CGPoint) -> Void)?
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let isRight = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return isRight ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            handler?(convert(event.locationInWindow, from: nil))
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { rightMouseDown(with: event) } else { super.mouseDown(with: event) }
        }
    }
}

private struct ThemedContextMenu: ViewModifier {
    let items: () -> [ContextItem]
    @Environment(\.dropdownController) private var controller
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dropdownSpace")) } action: { frame = $0 }
            .overlay {
                RightClickCatcher { local in
                    controller?.showContextMenu(at: CGPoint(x: frame.minX + local.x, y: frame.minY + local.y), items: items())
                }
            }
    }
}

extension View {
    /// Right-click menu in the app's own style (replaces `.contextMenu`).
    func themedContextMenu(_ items: @escaping () -> [ContextItem]) -> some View {
        modifier(ThemedContextMenu(items: items))
    }
}
