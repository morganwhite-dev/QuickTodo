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
        NavigationStack {
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
                                .font(.system(size: 18, weight: .semibold))
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Slider(value: $brightness, in: 0...1)
                        .tint(Theme.accent)
                }

                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Selected Color")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(Color(hue: hue, saturation: saturation, brightness: brightness).toHex() ?? "#FF6B35")
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .help("Close without changing the color")
                        .modifier(HoverButtonModifier())

                    Button("Select") {
                        onSelect(Color(hue: hue, saturation: saturation, brightness: brightness))
                        isPresented = false
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .help("Use this color")
                    .modifier(HoverButtonModifier())
                }
            }
            .padding(16)
            .navigationTitle("Choose Color")
            .frame(minWidth: 380, minHeight: 420)
        }
    }
}

struct AddCategoryModal: View {
    @Binding var isPresented: Bool
    @Binding var newName: String
    let onAdd: (String, Color) -> Void

    @State private var selectedColor = Theme.accent
    @State private var categoryName = ""
    @State private var showColorPicker = false
    @State private var customColor = Theme.accent

    private let presetColors: [Color] = [Theme.accent, Theme.critical, Theme.dueSoon, Color.green, Color.blue, Color.purple]

    private func createCategory() {
        guard !categoryName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onAdd(categoryName, selectedColor)
        isPresented = false
        categoryName = ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // Category Name Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Category Name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    TextField("e.g. Work, Personal, Finance", text: $categoryName.autoCapitalized())
                        .textFieldStyle(.roundedBorder)
                        .frame(height: 32)
                        .font(.system(size: 14))
                        .help("Name the category that will appear in the sidebar")
                        .onSubmit(createCategory)
                }

                // Color Selection Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Color")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(presetColors.indices, id: \.self) { index in
                            let color = presetColors[index]
                            Button(action: { selectedColor = color }) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 2.5 : 0)
                                    )
                                    .scaleEffect(selectedColor == color ? 1.08 : 1.0)
                                    .animation(.snappy(duration: Motion.hover), value: selectedColor)
                            }
                            .buttonStyle(.plain)
                            .help("Use this preset category color")
                            .modifier(HoverButtonModifier())
                        }

                        Button(action: { showColorPicker = true }) {
                            VStack(spacing: 2) {
                                Image(systemName: "eyedropper.full")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Custom")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .modifier(HoverButtonModifier())
                        .help("Pick custom color")

                        Spacer()
                    }
                }

                // Preview Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 10, height: 10)

                        Text(categoryName.isEmpty ? "Category Name" : categoryName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(categoryName.isEmpty ? .secondary : .primary)

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                }

                Spacer()

                // Action Buttons
                VStack(spacing: 6) {
                    Button(action: createCategory) {
                        Text("Create Category")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .help("Create this category and add it to the sidebar")
                    .modifier(HoverButtonModifier())
                    .disabled(categoryName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Cancel") { isPresented = false }
                        .font(.system(size: 13, weight: .semibold))
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .help("Close without creating a category")
                        .modifier(HoverButtonModifier())
                }
            }
            .padding(14)
            .navigationTitle("New Category")
            .frame(minWidth: 340, minHeight: 320)
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColor: $customColor, isPresented: $showColorPicker) { color in
                    selectedColor = color
                }
            }
        }
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
    @State private var showConfirmDelete = false
    @State private var categories: [CategoryItem] = []
    @State private var hoveredColorPicker: String? = nil
    @State private var showAddCategoryModal = false
    @State private var newCategoryName = ""

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
        NavigationStack {
            List {
                if visibleCategories.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Theme.accent)

                        Text("No categories yet")
                            .font(.headline)

                        Text("Create one here, or type #Category in Quick Add.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(visibleCategories) { cat in
                            HStack(spacing: 12) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)

                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Categories.color(for: cat))
                                    .frame(width: 5, height: 22)

                                Text(cat.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer(minLength: 12)

                                ColorPicker(
                                    "",
                                    selection: Binding(
                                        get: { Categories.color(for: cat) },
                                        set: { newColor in
                                            cat.colorHex = newColor.toHex()
                                            context.saveOrReport()
                                        }
                                    )
                                )
                                .labelsHidden()
                                .frame(width: 30, height: 22)
                                .clipShape(Circle())
                                .contentShape(Circle())
                                .help("Change the color for \(cat.name)")
                                .scaleEffect(hoveredColorPicker == cat.name ? 1.12 : 1.0)
                                .onHover { hovering in
                                    withAnimation(.snappy(duration: Motion.select)) {
                                        hoveredColorPicker = hovering ? cat.name : nil
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDelete = cat
                                    showConfirmDelete = true
                                } label: {
                                    Label("Delete Category", systemImage: "trash")
                                }
                            }
                        }
                        .onMove(perform: moveCategories)
                        .onDelete(perform: handleDelete)
                    } header: {
                        Text("Drag to reorder")
                    }
                }
            }
            .navigationTitle("Manage Categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        context.saveOrReport()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Close")
                    .modifier(HoverButtonModifier())
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.saveOrReport()
                        dismiss()
                    }
                    .help("Save category changes and close")
                    .modifier(HoverButtonModifier())
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddCategoryModal = true
                    } label: {
                        Label("New Category", systemImage: "plus")
                    }
                    .help("Create a new category")
                    .modifier(HoverButtonModifier())
                }
            }
        }
        .frame(minWidth: 520, minHeight: 380)
        .task { reload() }
        .sheet(isPresented: $showAddCategoryModal) {
            AddCategoryModal(
                isPresented: $showAddCategoryModal,
                newName: $newCategoryName,
                onAdd: addCategory
            )
        }
        .alert("Delete Category?", isPresented: $showConfirmDelete, presenting: pendingDelete) { cat in
            Button("Delete", role: .destructive) { delete(cat) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { cat in
            Text("This will move any tasks in \(cat.name) to General.")
        }
    }

    private func handleDelete(_ indexSet: IndexSet) {
        for idx in indexSet {
            guard visibleCategories.indices.contains(idx) else { continue }
            pendingDelete = visibleCategories[idx]
            showConfirmDelete = true
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

        newCategoryName = ""
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

