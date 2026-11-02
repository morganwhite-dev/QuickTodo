// Theme.swift
// Tactile Neo-Brutalist design tokens, chrome modifiers and bundled fonts
// Colours have one meaning each: amber = Next Move,
// red = overdue, green = done; list colours only ever appear as light tints.

import SwiftUI
import CoreText
import AppKit

enum Theme {
    // Tactile Neo-Brutalist tokens. Every colour has exactly one meaning:
    // amber = Next Move / logo / "Plan this time", red = overdue, green = done.
    static let amber = Color(hex: "#F6AE2D") ?? .orange
    static let overdue = Color(hex: "#E63946") ?? .red
    static let done = Color(hex: "#57CC99") ?? .green
    static let ink = Color(hex: "#111111") ?? .black
    // Marks the selected sidebar item and selected list. Deep plum: dark enough to read as active, not blue.
    static let selected = Color(hex: "#5B2A86") ?? .purple
    static let inkMuted = Color(hex: "#374151") ?? .gray
    static let navBar = Color(hex: "#EEF5F3") ?? .white
    static let panel = Color(hex: "#E3E9EF") ?? .gray
    static let card = Color.white
    // Slightly deeper than navBar, for popups that sit on a dark scrim.
    static let popup = Color(hex: "#8FAEAB") ?? .gray
    static let freePill = Color(hex: "#0E3B43") ?? .black
    static let railLine = ink
    static let freeDash = Color(hex: "#2B2F36")?.opacity(0.75) ?? .gray
    static let mint = Color(hex: "#DDF3E8") ?? .green
    static let sand = Color(hex: "#F5E6C8") ?? .yellow

    static let bgGradient = LinearGradient(
        stops: [
            .init(color: Color(hex: "#0B1E3A") ?? .black, location: 0),
            .init(color: Color(hex: "#0E4D64") ?? .blue, location: 0.55),
            .init(color: Color(hex: "#137A7F") ?? .teal, location: 1),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Aliases so older call sites keep compiling; each maps onto a token above.
    static let bg = bgGradient
    static let accent = amber
    static let critical = overdue
    static let warning = amber
    static let lowPressure = done
    static let success = done
    static let dueSoon = amber
    static let onDeck = Color(hex: "#8EB8F2") ?? .blue
    static let keepInMind = Color(hex: "#F5C6D9") ?? .pink
    static let sidebar = navBar
    static let panelRaised = card
    static let panelBorder = ink
    static let divider = ink
    static let mutedText = inkMuted
    static let general = Color(hex: "#9CA3AF") ?? .gray
}

enum Categories {
    // Distinct, legible hues for list dots — vivid enough to tell apart at 8px, calm
    // enough not to fight with the rest of the UI (they're never used as big fills).
    // Mockup defaults first (sage, blue, sand), then more light-friendly hues. These are
    // mixed ~40% with white by `tint(_:)` before use behind black text.
    private static let colorPalette: [Color] = [
        Color(hex: "#9FE2A8") ?? .green,   // sage
        Color(hex: "#8EB8F2") ?? .blue,    // blue
        Color(hex: "#F5E6C8") ?? .yellow,  // sand
        Color(hex: "#F4A9B8") ?? .pink,    // rose
        Color(hex: "#C7B3F0") ?? .purple,  // lavender
        Color(hex: "#9ADBD6") ?? .teal,    // teal
        Color(hex: "#F5C28F") ?? .orange,  // apricot
        Color(hex: "#C9D3A0") ?? .green,   // olive
    ]

    /// Light tint (about 40% list colour, 60% white) used behind black text.
    static func tint(_ c: Color) -> Color {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor.gray
        let k: CGFloat = 0.4
        return Color(.sRGB,
                     red: Double(ns.redComponent * k + (1 - k)),
                     green: Double(ns.greenComponent * k + (1 - k)),
                     blue: Double(ns.blueComponent * k + (1 - k)))
    }

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

// MARK: - Neo-brutalist chrome

/// 2px black border + flat offset shadow (no blur).
struct NeoCard: ViewModifier {
    var fill: Color = Theme.card
    var radius: CGFloat = 4
    var shadow: CGFloat = 4
    var border: CGFloat = 2
    var borderColor: Color = Theme.ink

    func body(content: Content) -> some View {
        content
            // Later .background modifiers sit *behind* earlier ones: fill first, shadow behind it.
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.ink).offset(x: shadow, y: shadow)
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(borderColor, lineWidth: border))
    }
}

extension View {
    func neoCard(_ fill: Color = Theme.card, radius: CGFloat = 4, shadow: CGFloat = 4, border: CGFloat = 2) -> some View {
        modifier(NeoCard(fill: fill, radius: radius, shadow: shadow, border: border))
    }
    /// Panels (day columns, side panels): 5px shadow.
    func neoPanel(_ fill: Color = Theme.panel) -> some View { neoCard(fill, radius: 5, shadow: 5) }
}

/// Pressing offsets the view by its shadow distance and drops the shadow to 0.
/// The shadow is drawn by `neoCard`, so the button draws its own and moves with it.
struct PressableStyle: ButtonStyle {
    /// `hover: false` for the controls that mark a task done or not done.
    var hover = true
    var fill: Color = Theme.card
    var foreground: Color = Theme.ink
    var radius: CGFloat = 4
    var shadow: CGFloat = 3
    var capsule = false

    func makeBody(configuration: Configuration) -> some View {
        if capsule {
            styled(configuration, Capsule())
        } else {
            styled(configuration, RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    private func styled<S: InsettableShape>(_ configuration: Configuration, _ shape: S) -> some View {
        HoverReader(enabled: hover) { hovered in
            let p = configuration.isPressed
            let lift: CGFloat = hovered && !p ? 1 : 0
            let d = p ? 0 : shadow + lift
            configuration.label
                .foregroundStyle(foreground)
                .background { shape.fill(fill) }
                .background { shape.fill(Theme.ink).offset(x: d, y: d) }
                .overlay { shape.strokeBorder(Theme.ink, lineWidth: 2) }
                .offset(x: p ? shadow : -lift, y: p ? shadow : -lift)
                .animation(.easeOut(duration: 0.08), value: p)
        }
    }
}

/// Standard text button: padded capsule (or rounded rect) that presses in. Used wherever the
/// old glass / glassProminent buttons were. Amber is reserved (see Theme), so the default
/// is white; pass `fill:` for green (done), amber (editor Save) or black.
struct NeoButtonStyle: ButtonStyle {
    var hover = true
    var fill: Color = Theme.card
    var foreground: Color = Theme.ink
    var capsule = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Fonts.ui(14, .heavy))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(minHeight: 40)
            .modifier(PressBody(configuration: configuration, fill: fill, foreground: foreground, capsule: capsule, hover: hover))
            .opacity(isEnabled ? 1 : 0.45)
    }

    private struct PressBody: ViewModifier {
        let configuration: Configuration
        let fill: Color
        let foreground: Color
        let capsule: Bool
        let hover: Bool
        func body(content: Content) -> some View {
            if capsule {
                content.buttonChrome(Capsule(), pressed: configuration.isPressed, fill: fill, foreground: foreground, hover: hover)
            } else {
                content.buttonChrome(RoundedRectangle(cornerRadius: 8, style: .continuous), pressed: configuration.isPressed, fill: fill, foreground: foreground, hover: hover)
            }
        }
    }
}

extension View {
    fileprivate func buttonChrome<S: InsettableShape>(_ shape: S, pressed: Bool, fill: Color, foreground: Color, shadow: CGFloat = 3, hover: Bool = true) -> some View {
        HoverReader(enabled: hover) { hovered in
            let lift: CGFloat = hovered && !pressed ? 1 : 0
            self.foregroundStyle(foreground)
                .background { shape.fill(fill) }
                .background { shape.fill(Theme.ink).offset(x: pressed ? 0 : shadow + lift, y: pressed ? 0 : shadow + lift) }
                .overlay { shape.strokeBorder(Theme.ink, lineWidth: 2) }
                .offset(x: pressed ? shadow : -lift, y: pressed ? shadow : -lift)
                .animation(.easeOut(duration: 0.08), value: pressed)
        }
    }
}

/// Same press-in behaviour for a card that is tappable but already drawn with `neoCard`.
struct PressableCardStyle: ButtonStyle {
    var hover = true
    var shadow: CGFloat = 4
    func makeBody(configuration: Configuration) -> some View {
        HoverReader(enabled: hover) { hovered in
            let lift: CGFloat = hovered && !configuration.isPressed ? 1 : 0
            configuration.label
                .offset(x: configuration.isPressed ? shadow : -lift, y: configuration.isPressed ? shadow : -lift)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

/// Tracks pointer hover for a button style and hands the state to its content.
struct HoverReader<Content: View>: View {
    var enabled = true
    @ViewBuilder var content: (Bool) -> Content
    @State private var hovered = false

    var body: some View {
        content(enabled && hovered)
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.12)) { hovered = enabled && inside }
            }
    }
}

/// Plain buttons (icons, text links, chips): dims a little on hover and presses in slightly.
struct HoverPlainStyle: ButtonStyle {
    var hover = true
    func makeBody(configuration: Configuration) -> some View {
        HoverReader(enabled: hover) { hovered in
            configuration.label
                .opacity(hovered ? 0.7 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }
}

/// Small black-bordered chip ("≈ 20m", "5:30 PM", list tag).
struct NeoChip: View {
    let text: String
    var fill: Color = Theme.card
    var foreground: Color = Theme.ink
    var size: CGFloat = 12
    var borderColor: Color = Theme.ink

    var body: some View {
        Text(text)
            .font(Fonts.ui(size, .bold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 2))
    }
}

/// List tag: light tint of the list colour behind black text.
struct ListTag: View {
    let name: String
    let color: Color
    /// Override the tinted fill (e.g. white when the tag sits on a card already tinted with the list colour).
    var fill: Color? = nil
    var body: some View {
        Text(name)
            .font(Fonts.ui(12, .heavy))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(fill ?? Categories.tint(color)))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
    }
}

/// Progress ring: green stroke on a panel-coloured track, black outline, label in the middle.
struct ProgressRing: View {
    let value: Double
    let label: String
    var size: CGFloat = 96
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().stroke(Theme.panel, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(Theme.done, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
            Circle().strokeBorder(Theme.ink, lineWidth: 2).padding(-lineWidth / 2 + 1)
            Circle().strokeBorder(Theme.ink, lineWidth: 2).padding(lineWidth / 2 + 1)
            Text(label).font(Fonts.black(size * 0.28)).foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
    }
}

/// Number + caption tile used by the Today stats column.
struct StatTile<Extra: View>: View {
    let value: String
    let label: String
    var valueColor: Color = Theme.ink
    /// Stretch to share the column's height with sibling tiles.
    var fills = false
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(Fonts.black(34)).foregroundStyle(valueColor)
                .contentTransition(.numericText())
            Text(label).font(Fonts.ui(13, .heavy)).tracking(0.8).foregroundStyle(Theme.ink)
            extra
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
        .neoCard(Theme.card, radius: 4, shadow: 4)
        .padding(.trailing, 4).padding(.bottom, 4)
    }
}

// MARK: - Fonts

enum Fonts {
    private static var registered = false
    /// Registers the bundled Archivo / Archivo Black / Bricolage files. Call once at launch.
    static func register() {
        guard !registered else { return }
        registered = true
        for name in ["Archivo", "ArchivoBlack-Regular", "BricolageGrotesque"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Archivo", size: size).weight(weight)
    }
    static func black(_ size: CGFloat) -> Font { .custom("Archivo Black", size: size) }
    static func bricolage(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom("Bricolage Grotesque", size: size).weight(weight)
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

    // Drag and drop: cards glide into their new slot (soft spring, a hint of settle) and the
    // rest of the column eases out of the way, instead of snapping.
    static let dropSettle: Animation = .spring(response: 0.42, dampingFraction: 0.82)
    static let layoutShift: Animation = .spring(response: 0.38, dampingFraction: 0.86)
    static let dragLift: Animation = .spring(response: 0.25, dampingFraction: 0.75)

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
        content.font(Fonts.ui(max(scaledSize, 12), weight))
    }
}

extension View {
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

/// The picture that follows the cursor while a task is dragged: a compact neo-brutalist card
/// (tinted with the list colour, hard shadow, tiny tilt) instead of a flat screenshot of the row.
struct DragCardPreview: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(Fonts.ui(16, .heavy)).foregroundStyle(Theme.ink)
            .lineLimit(2)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(width: 240, alignment: .leading)
            .neoCard(Categories.tint(tint), radius: 4, shadow: 6)
            .padding(.trailing, 6).padding(.bottom, 6)
            .rotationEffect(.degrees(-2))
    }
}
