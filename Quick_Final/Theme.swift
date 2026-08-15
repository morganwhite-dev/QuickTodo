// Theme.swift
// Calm dark palette. Principle: almost the entire app is muted slate/gray — color shows
// up only in small doses (list dots, a few semantic icons). There is exactly one
// saturated, glowing zone in the whole app: the Next Move recommendation card. Don't
// spread accent glow across sidebar rows, columns, or cards the way an earlier pass did.

import SwiftUI

enum Theme {
    // The one signature accent — primary buttons, Decision Board nav highlight, and
    // the Next Move recommendation card.
    static let accent = Color(red: 0.35, green: 0.55, blue: 0.95)
    static let accentDim = Color(red: 0.27, green: 0.44, blue: 0.78)
    static let accentSoft = Color(red: 0.22, green: 0.34, blue: 0.58)

    static let critical = Color(red: 0.92, green: 0.4, blue: 0.45)     // overdue / high priority
    static let warning  = Color(red: 0.88, green: 0.66, blue: 0.32)    // due soon / suggested
    static let lowPressure = Color(red: 0.38, green: 0.78, blue: 0.52) // done / calm
    static let success = lowPressure

    // Kept as aliases so existing call sites (composer, editor, category manager, settings)
    // didn't all need touching for this pass — same calm family, slightly different roles.
    static let dueSoon = warning
    static let onDeck = Color(red: 0.52, green: 0.5, blue: 0.85)
    static let keepInMind = Color(red: 0.78, green: 0.55, blue: 0.68)

    // Calm slate backdrop — almost the entire app lives in these neutrals.
    static let bg = LinearGradient(
        colors: [Color(red: 0.055, green: 0.062, blue: 0.077), Color(red: 0.035, green: 0.04, blue: 0.052)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let sidebar = Color(red: 0.045, green: 0.05, blue: 0.063)
    static let panel = Color(red: 0.095, green: 0.105, blue: 0.125)
    static let panelRaised = Color(red: 0.125, green: 0.135, blue: 0.16)
    static let panelBorder = Color.white.opacity(0.075)
    static let divider = Color.white.opacity(0.065)
    static let mutedText = Color.white.opacity(0.52)

    // Quiet neutral for the General list/category and anywhere "no special color" is needed.
    static let general = Color(red: 0.56, green: 0.59, blue: 0.67)
}

enum Categories {
    // Distinct, legible hues for list dots — vivid enough to tell apart at 8px, calm
    // enough not to fight with the rest of the UI (they're never used as big fills).
    private static let colorPalette: [Color] = [
        Color(red: 0.56, green: 0.42, blue: 0.95),  // purple
        Color(red: 0.92, green: 0.4, blue: 0.42),   // red
        Color(red: 0.88, green: 0.66, blue: 0.32),  // amber
        Color(red: 0.38, green: 0.78, blue: 0.52),  // green
        Color(red: 0.4, green: 0.62, blue: 0.93),   // blue
        Color(red: 0.85, green: 0.45, blue: 0.7),   // pink
        Color(red: 0.45, green: 0.78, blue: 0.78),  // teal
        Color(red: 0.78, green: 0.65, blue: 0.5),   // tan
    ]

    // Fallback stable color (used when a category has no saved custom color)
    static func fallbackColor(for name: String) -> Color {
        var hash: UInt = 5381
        for char in name.lowercased().utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt(char)
        }
        let index = Int(bitPattern: hash) % colorPalette.count
        return colorPalette[abs(index)]
    }

    // Resolve a color for a CategoryItem (custom if set, otherwise stable fallback)
    static func color(for category: CategoryItem) -> Color {
        if category.name.caseInsensitiveCompare("General") == .orderedSame { return Theme.general }
        if let hex = category.colorHex, let c = Color(hex: hex) {
            return c
        }
        return fallbackColor(for: category.name)
    }

    // Resolve a color by name, given the categories list (custom if exists, otherwise fallback)
    static func color(for name: String, in categories: [CategoryItem]) -> Color {
        if name.caseInsensitiveCompare("General") == .orderedSame { return Theme.general }
        if let cat = categories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return color(for: cat)
        }
        return fallbackColor(for: name)
    }

}

// Soft accent halo built from stacked shadows. Use sparingly — see the file header.
struct Glow: ViewModifier {
    let color: Color
    var radius: CGFloat = 16
    var intensity: Double = 0.4

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(intensity), radius: radius, x: 0, y: 0)
            .shadow(color: color.opacity(intensity * 0.6), radius: radius * 2, x: 0, y: 0)
    }
}

extension View {
    func glow(_ color: Color, radius: CGFloat = 16, intensity: Double = 0.4) -> some View {
        modifier(Glow(color: color, radius: radius, intensity: intensity))
    }
}

// Shared quiet card chrome for panels (columns, suggestion cards, summary strip).
struct PanelCard: ViewModifier {
    var tint: Color = Theme.panelBorder
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [Theme.panelRaised.opacity(0.88), Theme.panel.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint, lineWidth: 1)
            )
    }
}

extension View {
    func panelCard(tint: Color = Theme.panelBorder, cornerRadius: CGFloat = 14) -> some View {
        modifier(PanelCard(tint: tint, cornerRadius: cornerRadius))
    }
}

// Named durations for the handful of distinct animation speeds reused across the app.
// Values are unchanged from wherever they previously lived inline — this only gives
// each one a name so the same kind of feedback can't silently drift out of sync with
// itself across files.
enum Motion {
    static let hover: Double = 0.15
    static let prioritySelect: Double = 0.16
    static let dragReorder: Double = 0.18
    static let select: Double = 0.2
    static let panelReveal: Double = 0.22
    static let stepDot: Double = 0.25
    static let completionSweep: Double = 0.3

    static let toggleSwitch: Animation = .spring(response: 0.24, dampingFraction: 0.82)
    static let pageStep: Animation = .spring(response: 0.4, dampingFraction: 0.9)
}

// Scales with the user's text-size setting (System Settings > Accessibility > Display >
// Larger Text) while keeping today's exact look at the default size — unlike switching to
// semantic styles (.body, .headline), this doesn't restyle anything, it just stops being
// frozen at one fixed point size for people who've turned text size up.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        self._scaledSize = ScaledMetric(wrappedValue: size)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}
