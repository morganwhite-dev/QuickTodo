// CategoryManagement.swift
// Color picker, new-category modal, and the Lists manager sheet.

import SwiftUI
import SwiftData

// ─────────────────────────────────────────────────────────────────────────────
// MARK: Views

struct ColorPickerView: View {
    @Binding var selectedColor: Color
    @Binding var isPresented: Bool
    let onSelect: (Color) -> Void

    @State private var hue: Double = 0.05
    @State private var saturation: Double = 0.85
    @State private var brightness: Double = 0.95
    @State private var cursorLocation: CGPoint = .zero
    @State private var isHoveringWheel: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Choose Color")
                    .font(Fonts.black(22)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            VStack(spacing: 16) {
                GeometryReader { geo in
                    ZStack {
                        Canvas { context, size in
                            let center = CGPoint(x: size.width / 2, y: size.height / 2)
                            let radius = min(size.width, size.height) / 2

                            for y in stride(from: 0, to: Int(size.height), by: 1) {
                                for x in stride(from: 0, to: Int(size.width), by: 1) {
                                    let dx = CGFloat(x) - center.x
                                    let dy = CGFloat(y) - center.y
                                    let distance = sqrt(dx * dx + dy * dy)

                                    if distance <= radius {
                                        let angle = atan2(dy, dx)
                                        let normalizedAngle = (angle + .pi) / (2 * .pi)
                                        let sat = distance / radius

                                        let pixelColor = Color(
                                            hue: normalizedAngle,
                                            saturation: sat,
                                            brightness: brightness
                                        )
                                        context.fill(
                                            Path(CGRect(x: x, y: y, width: 1, height: 1)),
                                            with: .color(pixelColor)
                                        )
                                    }
                                }
                            }
                        }

                        if isHoveringWheel {
                            Image(systemName: "eyedropper")
                                .font(Fonts.ui(18, .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                                .offset(x: cursorLocation.x - geo.size.width / 2, y: cursorLocation.y - geo.size.height / 2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                            let radius = min(geo.size.width, geo.size.height) / 2

                            let dx = location.x - center.x
                            let dy = location.y - center.y
                            let distance = sqrt(dx * dx + dy * dy)

                            let isOnWheel = distance <= radius

                            if isOnWheel && !isHoveringWheel {
                                NSCursor.hide()
                            } else if !isOnWheel && isHoveringWheel {
                                NSCursor.unhide()
                            }

                            isHoveringWheel = isOnWheel
                            cursorLocation = location

                            if isOnWheel {
                                let angle = atan2(dy, dx)
                                hue = (angle + .pi) / (2 * .pi)
                                saturation = min(distance / radius, 1.0)
                            }
                        case .ended:
                            isHoveringWheel = false
                            NSCursor.unhide()
                            break
                        }
                    }
                }
                .frame(height: 240)

                VStack(spacing: 10) {
                    Text("Brightness")
                        .font(Fonts.ui(13, .bold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Slider(value: $brightness, in: 0...1)
                        .tint(Theme.accent)
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Theme.ink, lineWidth: 2))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Selected Color")
                            .font(Fonts.ui(13, .bold))
                            .foregroundStyle(Theme.inkMuted)

                        Text(Color(hue: hue, saturation: saturation, brightness: brightness).toHex() ?? "#FF6B35")
                            .font(Fonts.ui(13, .semibold))
                            .foregroundStyle(Theme.ink)
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(NeoButtonStyle())
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .help("Close without changing the color")
                        .modifier(HoverButtonModifier())

                    Button("Select") {
                        onSelect(Color(hue: hue, saturation: saturation, brightness: brightness))
                        isPresented = false
                    }
                    .buttonStyle(NeoButtonStyle(fill: Theme.amber))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .help("Use this color")
                    .modifier(HoverButtonModifier())
                }
            }
            .padding(16)
            .frame(minWidth: 380, minHeight: 420)
            .background(Theme.panel)
        }
    }
}

// New Category modal, rebuilt from the design mockup (NewCategoryModal.jsx in Downloads).
// Behavior is unchanged: name is required, Create is disabled while it is empty, Return
// submits, Escape and Cancel close, the custom swatch opens the themed color picker.
private let newCategorySwatches: [Color] = [
    Color(hex: "#F5B73B") ?? .orange,   // Amber
    Color(hex: "#F25C54") ?? .red,      // Coral red
    Color(hex: "#3DBE6B") ?? .green,    // Green
    Color(hex: "#4F8EF7") ?? .blue,     // Blue (default)
    Color(hex: "#B05CF2") ?? .purple,   // Purple
    Color(hex: "#F472B6") ?? .pink,     // Pink
]
private let newCategoryMaxLength = 24
private let modalCream = Color(hex: "#F6F3EC") ?? .white
private let modalSand = Color(hex: "#EAE5D8") ?? .gray

/// Black or white, whichever reads better on the given color (same rule as the mockup).
private func modalInk(on color: Color) -> Color {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
    func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let lum = 0.2126 * linear(ns.redComponent) + 0.7152 * linear(ns.greenComponent) + 0.0722 * linear(ns.blueComponent)
    return lum > 0.18 ? Theme.ink : .white
}

struct AddCategoryModal: View {
    @Binding var isPresented: Bool
    @Binding var newName: String
    let onAdd: (String, Color) -> Void

    @State private var selectedColor = newCategorySwatches[3]
    @State private var categoryName = ""
    @State private var showColorPicker = false
    @State private var customColor = Color(hex: "#14B8A6") ?? .teal
    @State private var isCustom = false
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { categoryName.trimmingCharacters(in: .whitespaces) }
    private var fg: Color { modalInk(on: selectedColor) }

    private func createCategory() {
        guard !trimmedName.isEmpty else { return }
        onAdd(categoryName, selectedColor)
        isPresented = false
        categoryName = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("New Category")
                    .font(Fonts.black(22)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(NeoButtonStyle(capsule: false))
                .help("Close")
            }
            .padding(.leading, 24).padding(.trailing, 16).padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 2) }

            // Body
            VStack(alignment: .leading, spacing: 22) {
                // Name
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("NAME").font(Fonts.ui(12, .heavy)).tracking(1.0).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(categoryName.count) / \(newCategoryMaxLength)")
                            .font(Fonts.ui(12, .semibold)).foregroundStyle(Theme.inkMuted)
                    }
                    TextField("e.g. Work, Personal, Finance", text: $categoryName.autoCapitalized())
                        .textFieldStyle(.plain)
                        .font(Fonts.ui(16, .semibold))
                        .foregroundStyle(Theme.ink)
                        .focused($nameFocused)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .neoCard(Theme.card, radius: 12, shadow: nameFocused ? 4 : 3)
                        .onSubmit(createCategory)
                        .help("Name the category that will appear in the sidebar")
                        .onChange(of: categoryName) { _, new in
                            if new.count > newCategoryMaxLength { categoryName = String(new.prefix(newCategoryMaxLength)) }
                        }
                }

                // Color
                VStack(alignment: .leading, spacing: 10) {
                    Text("COLOR").font(Fonts.ui(12, .heavy)).tracking(1.0).foregroundStyle(Theme.ink)
                    HStack(spacing: 0) {
                        ForEach(newCategorySwatches.indices, id: \.self) { index in
                            let color = newCategorySwatches[index]
                            swatch(selected: !isCustom && selectedColor == color, label: "Preset color \(index + 1)") {
                                selectedColor = color
                                isCustom = false
                            } fill: {
                                Circle().fill(color)
                            } mark: {
                                modalInk(on: color)
                            }
                            .help("Use this color")
                            if index < newCategorySwatches.count - 1 { Spacer(minLength: 0) }
                        }
                        Spacer(minLength: 0)
                        swatch(selected: isCustom, label: "Custom color") {
                            showColorPicker = true
                        } fill: {
                            Circle().fill(isCustom
                                ? AnyShapeStyle(customColor)
                                : AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center)))
                        } mark: {
                            modalInk(on: customColor)
                        }
                        .help("Pick a custom color")
                    }
                    .padding(.horizontal, 6)
                }

                // Preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("PREVIEW").font(Fonts.ui(12, .heavy)).tracking(1.0).foregroundStyle(Theme.ink)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedColor)
                                .frame(width: 32, height: 32)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
                                .overlay(Image(systemName: "tag.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(fg))
                            Text(trimmedName.isEmpty ? "Category name" : trimmedName)
                                .font(Fonts.ui(15, .bold))
                                .foregroundStyle(trimmedName.isEmpty ? Theme.inkMuted : Theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("0 tasks").font(Fonts.ui(12, .semibold)).foregroundStyle(Theme.inkMuted)
                        }
                        .padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 8)
                        .neoCard(Theme.card, radius: 12, shadow: 2)

                        HStack(spacing: 10) {
                            Text("On a task").font(Fonts.ui(12, .semibold)).foregroundStyle(Theme.inkMuted)
                            HStack(spacing: 6) {
                                Circle().fill(fg).frame(width: 8, height: 8)
                                Text(trimmedName.isEmpty ? "Category name" : trimmedName)
                                    .font(Fonts.ui(13, .bold)).lineLimit(1)
                            }
                            .foregroundStyle(fg)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(Capsule().fill(selectedColor))
                            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(modalSand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    )
                }
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(modalCream)

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(NeoButtonStyle(capsule: false))
                    .frame(maxWidth: .infinity)
                    .help("Close without creating a category")
                Button("Create Category", action: createCategory)
                    .buttonStyle(NeoButtonStyle(fill: Theme.ink, foreground: .white, capsule: false))
                    .frame(maxWidth: .infinity)
                    .help("Create this category and add it to the sidebar")
                    .disabled(trimmedName.isEmpty)
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 20)
            .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 2) }
            .background(Theme.card)
        }
        .frame(width: 440)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ink, lineWidth: 2))
        .padding(.bottom, 4)
        .onExitCommand { isPresented = false }
        .onAppear { nameFocused = true }
        .sheet(isPresented: $showColorPicker) {
            ColorPickerView(selectedColor: $customColor, isPresented: $showColorPicker) { color in
                customColor = color
                selectedColor = color
                isCustom = true
            }
        }
    }

    /// One round swatch. The selected one gets a cream gap and a black outer ring.
    private func swatch<Fill: View>(
        selected: Bool, label: String, action: @escaping () -> Void,
        @ViewBuilder fill: () -> Fill, mark: () -> Color
    ) -> some View {
        let markColor = mark()
        return Button(action: action) {
            ZStack {
                fill()
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(markColor)
                }
            }
            .padding(6)
            .overlay(Circle().strokeBorder(modalCream, lineWidth: 3).opacity(selected ? 1 : 0))
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2).padding(-2).opacity(selected ? 1 : 0))
        }
        .buttonStyle(HoverPlainStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// Helper to bind optional Date in DatePicker
extension Binding where Value == Date {
    init(_ source: Binding<Date?>, default defaultValue: Date) {
        self.init(get: { source.wrappedValue ?? defaultValue }, set: { newValue in source.wrappedValue = newValue })
    }
}
struct ManageCategoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Binding var selectedCategory: String

    @State private var pendingDelete: CategoryItem? = nil
    @StateObject private var dropdown = DropdownController()
    @State private var categories: [CategoryItem] = []
    @State private var hoveredColorPicker: String? = nil
    @State private var customRecolor: CategoryItem?
    @State private var customRecolorColor: Color = .white

    private var visibleCategories: [CategoryItem] {
        categories
            .filter { $0.name != "General" }
            .sorted { lhs, rhs in
                let left = lhs.sortIndex ?? Int.max
                let right = rhs.sortIndex ?? Int.max
                if left != right { return left < right }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Manage Lists")
                    .font(Fonts.black(22)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Button { context.saveOrReport(); dismiss() } label: { Text("Save") }
                    .buttonStyle(NeoButtonStyle(fill: Theme.amber))
                    .help("Save category changes and close")
                Button { context.saveOrReport(); dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(NeoButtonStyle())
                    .help("Close")
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            List {
                if visibleCategories.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(Fonts.black(30))
                            .foregroundStyle(Theme.ink)

                        Text("No categories yet")
                            .font(Fonts.ui(17, .heavy))

                        Text("Use + Add List on the Lists page to make one.")
                            .font(Fonts.ui(13, .medium))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(visibleCategories) { cat in
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .font(Fonts.ui(12.5, .bold))
                                    .foregroundStyle(Theme.inkMuted)

                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Categories.color(for: cat))
                                    .frame(width: 5, height: 22)

                                Text(cat.name)
                                    .font(Fonts.ui(14, .bold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)

                                Spacer(minLength: 12)

                                ColorSwatchButton(
                                    color: Categories.color(for: cat),
                                    onPick: { newColor in
                                        cat.colorHex = newColor.toHex()
                                        context.saveOrReport()
                                    },
                                    onCustom: { customRecolor = cat }
                                )
                                .help("Change the color for \(cat.name)")
                                .scaleEffect(hoveredColorPicker == cat.name ? 1.12 : 1.0)
                                .onHover { hovering in
                                    withAnimation(.snappy(duration: Motion.select)) {
                                        hoveredColorPicker = hovering ? cat.name : nil
                                    }
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .neoCard(Theme.card, radius: 10, shadow: 3)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .themedContextMenu {
                                [.action("Delete Category", icon: "trash", destructive: true) { confirmDelete(cat) }]
                            }
                        }
                        .onMove(perform: moveCategories)
                        .onDelete(perform: handleDelete)
                    } header: {
                        Text("DRAG TO REORDER")
                            .font(Fonts.ui(12, .heavy)).tracking(1.2)
                            .foregroundStyle(Theme.inkMuted)
                            .padding(.leading, 4)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
        }
        .frame(minWidth: 520, minHeight: 380)
        .task { reload() }
        .sheet(item: $customRecolor) { cat in
            ColorPickerView(
                selectedColor: $customRecolorColor,
                isPresented: Binding(get: { customRecolor != nil }, set: { if !$0 { customRecolor = nil } })
            ) { color in
                cat.colorHex = color.toHex()
                context.saveOrReport()
            }
        }
        .dropdownHost(using: dropdown)
    }

    private func confirmDelete(_ cat: CategoryItem) {
        pendingDelete = cat
        dropdown.showAlert(
            title: "Delete Category?",
            message: "This will move any tasks in \(cat.name) to General.",
            buttons: [
                AlertButton(title: "Cancel", role: .cancel, action: { pendingDelete = nil }),
                AlertButton(title: "Delete", role: .destructive, action: { delete(cat) })
            ]
        )
    }

    private func handleDelete(_ indexSet: IndexSet) {
        for idx in indexSet {
            guard visibleCategories.indices.contains(idx) else { continue }
            confirmDelete(visibleCategories[idx])
            break
        }
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var ordered = visibleCategories
        ordered.move(fromOffsets: source, toOffset: destination)

        for (index, category) in ordered.enumerated() {
            category.sortIndex = index
        }
        context.saveOrReport()
        reload()
    }

    private func reload() {
        let fd = FetchDescriptor<CategoryItem>()
        categories = (try? context.fetch(fd)) ?? []
        ensureDefaultsIfNeeded()
        categories = (try? context.fetch(fd)) ?? []
        assignMissingSortIndexesIfNeeded()
    }

    private func ensureDefaultsIfNeeded() {
        if categories.first(where: { $0.name == "General" }) == nil {
            context.insert(CategoryItem(name: "General", sortIndex: 0))
            context.saveOrReport()
        }
    }

    private func assignMissingSortIndexesIfNeeded() {
        var changed = false
        for (index, category) in categories.sorted(by: { $0.createdAt < $1.createdAt }).enumerated() where category.sortIndex == nil {
            category.sortIndex = index
            changed = true
        }
        if changed { context.saveOrReport() }
    }

    private func addCategory(name: String, color: Color) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = categories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            existing.colorHex = color.toHex()
            selectedCategory = existing.name
        } else {
            let nextIndex = ((categories.compactMap(\.sortIndex).max() ?? categories.count) + 1)
            let category = CategoryItem(name: trimmed, colorHex: color.toHex(), sortIndex: nextIndex)
            context.insert(category)
            selectedCategory = category.name
        }

        context.saveOrReport()
        reload()
    }

    private func delete(_ cat: CategoryItem) {
        guard cat.name != "General" else { return }

        let fetch = FetchDescriptor<TaskItem>()
        if let allTasks = try? context.fetch(fetch) {
            for task in allTasks where task.category.caseInsensitiveCompare(cat.name) == .orderedSame {
                task.category = "General"
            }
        }

        context.delete(cat)
        context.saveOrReport()

        if selectedCategory.caseInsensitiveCompare(cat.name) == .orderedSame { selectedCategory = "General" }
        pendingDelete = nil
        reload()
    }
}

/// A round swatch that opens a themed palette card (instead of the system colour panel).
struct ColorSwatchButton: View {
    let color: Color
    let onPick: (Color) -> Void
    let onCustom: () -> Void
    @Environment(\.dropdownController) private var controller
    @State private var frame: CGRect = .zero

    static let presets: [Color] = ["#9FE2A8", "#8EB8F2", "#F5E6C8", "#F4A9B8", "#C7B3F0", "#9ADBD6",
                                   "#F5C28F", "#C9D3A0", "#F4D35E", "#A8DADC", "#F28482", "#B8B8F3"].compactMap { Color(hex: $0) }

    var body: some View {
        Button {
            controller?.openCustom(anchor: frame, size: CGSize(width: 232, height: 218)) {
                SwatchCard(onPick: { c in controller?.close(); onPick(c) }, onCustom: { controller?.close(); onCustom() })
            }
        } label: {
            Circle().fill(color).frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
        }
        .buttonStyle(HoverPlainStyle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dropdownSpace")) } action: { frame = $0 }
    }
}

private struct SwatchCard: View {
    let onPick: (Color) -> Void
    let onCustom: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(Array(ColorSwatchButton.presets.enumerated()), id: \.offset) { _, c in
                    Button { onPick(c) } label: {
                        Circle().fill(c).frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                    }
                    .buttonStyle(HoverPlainStyle())
                }
            }
            Button(action: onCustom) {
                Text("Custom…").font(Fonts.ui(14, .heavy)).frame(maxWidth: .infinity).frame(height: 36)
            }
            .buttonStyle(PressableStyle(fill: Theme.card, radius: 10, shadow: 3))
            .padding(.trailing, 3).padding(.bottom, 3)
        }
        .padding(16)
    }
}
