// SidebarView.swift
// The 7-item sidebar: General, Decision Board, Today, Upcoming, Lists, Completed,
// Settings — plus the persistent tagline footer card. Calm by design: only the
// selected row gets any color treatment.

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
    let generalCount: Int
    let todayCount: Int
    let upcomingCount: Int
    let completedCount: Int
    let trashCount: Int

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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.accent.opacity(0.17))
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("QuickToDo")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Decision workspace")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.mutedText)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 22)

            Text("WORKSPACE")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 7)

            VStack(spacing: 2) {
                ForEach(SidebarSection.allCases) { section in
                    SidebarRow(
                        section: section,
                        count: count(for: section),
                        isSelected: selection == section
                    )
                    .onTapGesture { selection = section }
                }
            }
            .padding(.horizontal, 10)

            Divider()
                .overlay(Theme.divider)
                .padding(.horizontal, 14)
                .padding(.top, 16)

            SettingsLink {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").frame(width: 18)
                    Text("Settings")
                    Spacer()
                }
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            TaglineCard()
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .frame(minWidth: 205, idealWidth: 220, maxWidth: 245)
        .background(.ultraThinMaterial)
        // A tint goes on top of the material, not behind it — stacking another
        // .background() behind the material gave it nothing translucent to show
        // through, so it rendered as a flat color with no visible blur at all.
        .overlay(Theme.sidebar.opacity(0.22).allowsHitTesting(false))
    }
}

private struct SidebarRow: View {
    let section: SidebarSection
    let count: Int?
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Theme.mutedText)
                .frame(width: 18)

            Text(section.label)
                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.67))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Theme.mutedText)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Theme.accent.opacity(0.22) : (isHovered ? Color.white.opacity(0.045) : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.snappy(duration: Motion.hover)) { isHovered = hovering }
        }
        .help(section.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TaglineCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Theme.lowPressure).frame(width: 6, height: 6)
                Text("DECISION ENGINE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.mutedText)
            }

            Text("Capture freely. QuickToDo will surface the next move when the signals are real.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }
}
