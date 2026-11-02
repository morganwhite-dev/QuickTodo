// SidebarView.swift
// The app's top navigation bar (replaces the old sidebar): logo, section pills with
// count bubbles, search, "+ Capture", and a menu for Trash / Settings. Selected pill is
// black with white text.

import SwiftUI
import SwiftData

enum SidebarSection: String, Identifiable, CaseIterable {
    case general, decisionBoard, today, upcoming, lists, completed, trash

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .decisionBoard: return "Decision Board"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .lists: return "Lists"
        case .completed: return "Completed"
        case .trash: return "Trash"
        }
    }

    var icon: String {
        switch self {
        case .general: return "tray"
        case .decisionBoard: return "square.grid.2x2"
        case .today: return "sun.max"
        case .upcoming: return "calendar"
        case .lists: return "list.bullet"
        case .completed: return "checkmark.circle"
        case .trash: return "trash"
        }
    }

    // Sidebar labels reserved so Quick Capture / the composer never mistakes one of
    // these for a real list name when no list is specified.
    static var reservedNames: Set<String> {
        Set(allCases.map(\.label))
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSection
    @Binding var search: String
    @Binding var showCapture: Bool
    let generalCount: Int
    let todayCount: Int
    let upcomingCount: Int
    let completedCount: Int
    let trashCount: Int

    private static let pillSections: [SidebarSection] = [.decisionBoard, .general, .today, .upcoming, .lists, .completed]

    private func count(for section: SidebarSection) -> Int? {
        switch section {
        case .general: return generalCount
        case .today: return todayCount
        case .upcoming: return upcomingCount
        case .completed: return completedCount
        case .trash: return trashCount > 0 ? trashCount : nil
        case .decisionBoard, .lists: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("Q")
                    .font(Fonts.black(20))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .neoCard(Theme.amber, radius: 10, shadow: 3)
                Text("QuickToDo")
                    .font(Fonts.black(20))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.trailing, 14)

            ForEach(Self.pillSections) { section in
                NavPill(section: section, count: count(for: section), isSelected: selection == section) {
                    withAnimation(.easeOut(duration: 0.16)) { selection = section }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkMuted).accessibilityHidden(true)
                TextField("Search...", text: $search)
                    .textFieldStyle(.plain)
                    .font(Fonts.ui(14, .medium))
                    .foregroundStyle(Theme.ink)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(HoverPlainStyle()).foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(.horizontal, 16)
            .frame(width: 260, height: 42)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))

            Button { withAnimation(.easeOut(duration: 0.15)) { showCapture.toggle() } } label: {
                Text("+ Capture")
                    .font(Fonts.ui(14, .heavy))
                    .padding(.horizontal, 18)
                    .frame(height: 42)
            }
            .buttonStyle(PressableStyle(fill: Theme.amber, shadow: 3, capsule: true))
            .help("Capture a task quickly")

            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(PressableStyle(fill: Theme.card, shadow: 3, capsule: true))
            .foregroundStyle(Theme.ink)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
        .frame(maxWidth: .infinity)
        .background(Theme.navBar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 2) }
    }
}

private struct NavPill: View {
    let section: SidebarSection
    let count: Int?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(section.label)
                    .font(Fonts.ui(14, isSelected ? .heavy : .semibold))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Fonts.ui(11, .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 18)
                        .background(Capsule().fill(Theme.ink))
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(isSelected || hovered ? Theme.amber : Theme.card))
            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(HoverPlainStyle(hover: false))
        .help(section.label)
        .accessibilityLabel((count ?? 0) > 0 ? "\(section.label), \(count ?? 0) tasks" : section.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
