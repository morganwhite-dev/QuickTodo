// Dropdown.swift
// Themed replacement for the system pop-up menus (Picker / Menu): a neo-brutalist button
// that opens a card of options, drawn by a host view so it floats above everything and is
// never clipped by a scroll view. Same look as the gear menu. A view that wants to use
// `NeoDropdown` must sit under `.dropdownHost()` (the Decision Board and the task editor do).

import SwiftUI
import Combine

struct DropdownOption: Identifiable {
    let id: AnyHashable
    let title: String
}

@MainActor
final class DropdownController: ObservableObject {
    @Published var isOpen = false
    @Published var anchor: CGRect = .zero
    @Published var options: [DropdownOption] = []
    @Published var selectedID: AnyHashable?
    // A custom card (e.g. the date picker) instead of a list of options.
    @Published var custom: AnyView?
    @Published var customSize: CGSize = .zero
    // True for cards that size themselves (context menus) instead of using `customSize`.
    @Published var customFits = false
    @Published var alert: AlertSpec?
    var onPick: ((AnyHashable) -> Void)?

    func open(anchor: CGRect, options: [DropdownOption], selected: AnyHashable?, onPick: @escaping (AnyHashable) -> Void) {
        self.anchor = anchor
        self.options = options
        self.selectedID = selected
        self.onPick = onPick
        self.custom = nil
        withAnimation(.easeOut(duration: 0.12)) { isOpen = true }
    }

    func openCustom<Content: View>(anchor: CGRect, size: CGSize, @ViewBuilder content: () -> Content) {
        self.anchor = anchor
        self.options = []
        self.custom = AnyView(content())
        self.customSize = size
        self.customFits = false
        withAnimation(.easeOut(duration: 0.12)) { isOpen = true }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.1)) { isOpen = false }
    }

    /// Right-click menu at a point (in the host's coordinate space).
    func showContextMenu(at point: CGPoint, items: [ContextItem]) {
        anchor = CGRect(x: point.x, y: point.y - 6, width: 0, height: 0)
        options = []
        custom = AnyView(ContextMenuCard(items: items, controller: self))
        customSize = CGSize(width: 250, height: ContextItem.estimatedHeight(items))
        customFits = true
        withAnimation(.easeOut(duration: 0.1)) { isOpen = true }
    }

    func showAlert(title: String, message: String = "", buttons: [AlertButton]) {
        withAnimation(.easeOut(duration: 0.12)) { alert = AlertSpec(title: title, message: message, buttons: buttons) }
    }

    func dismissAlert() {
        withAnimation(.easeOut(duration: 0.1)) { alert = nil }
    }

    func pick(_ id: AnyHashable) {
        onPick?(id)
        close()
    }
}

private struct DropdownControllerKey: EnvironmentKey { static let defaultValue: DropdownController? = nil }
extension EnvironmentValues {
    var dropdownController: DropdownController? {
        get { self[DropdownControllerKey.self] }
        set { self[DropdownControllerKey.self] = newValue }
    }
}

/// Button showing the current choice; tapping it opens the themed option card.
struct NeoDropdown<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var minWidth: CGFloat? = nil
    var fillsWidth = false

    @Environment(\.dropdownController) private var controller
    @State private var frame: CGRect = .zero

    private var currentTitle: String { options.first { $0.value == selection }?.title ?? "—" }

    var body: some View {
        Button {
            controller?.open(
                anchor: frame,
                options: options.map { DropdownOption(id: AnyHashable($0.value), title: $0.title) },
                selected: AnyHashable(selection),
                onPick: { picked in
                    if let value = picked.base as? Value { selection = value }
                }
            )
        } label: {
            HStack(spacing: 8) {
                Text(currentTitle).font(Fonts.ui(14, .heavy)).lineLimit(1)
                if fillsWidth { Spacer(minLength: 4) }
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .black))
            }
            .padding(.horizontal, 14).frame(height: 36)
            .frame(minWidth: minWidth, maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        }
        .buttonStyle(PressableStyle(fill: Theme.card, shadow: 3, capsule: true))
        .padding(.trailing, 3).padding(.bottom, 3)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dropdownSpace")) } action: { frame = $0 }
        .accessibilityLabel(currentTitle)
    }
}

/// Draws the open option card above everything under it.
private struct DropdownOverlay: View {
    @ObservedObject var controller: DropdownController

    private let rowHeight: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            if controller.isOpen {
                let isCustom = controller.custom != nil
                let width = isCustom ? controller.customSize.width : max(controller.anchor.width, 200)
                let height = isCustom ? controller.customSize.height : min(CGFloat(controller.options.count) * rowHeight + 20, 300)
                let x = max(12, min(controller.anchor.minX, geo.size.width - width - 16))
                let below = controller.anchor.maxY + 6
                // Open upward when there isn't room underneath.
                let y = below + height > geo.size.height - 12 ? max(12, controller.anchor.minY - 6 - height) : below
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture { controller.close() }
                    Group {
                        if let custom = controller.custom {
                            custom
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(controller.options) { option in
                                        DropdownRow(title: option.title, isSelected: option.id == controller.selectedID) {
                                            controller.pick(option.id)
                                        }
                                    }
                                }
                                .padding(10)
                            }
                            .scrollIndicators(.never)
                        }
                    }
                    .modifier(CardSizing(fits: controller.customFits, width: width, height: height))
                    .neoCard(Theme.navBar, radius: 5, shadow: 5)
                    .offset(x: x, y: y)
                    .transition(.opacity)
                }
                .onExitCommand { controller.close() }
            }
        }
    }
}

private struct CardSizing: ViewModifier {
    let fits: Bool
    let width: CGFloat
    let height: CGFloat
    func body(content: Content) -> some View {
        if fits { content.frame(width: width).fixedSize(horizontal: false, vertical: true) }
        else { content.frame(width: width, height: height) }
    }
}

private struct DropdownRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(Fonts.ui(14, .heavy)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: 6)
                if isSelected { Image(systemName: "checkmark").font(.system(size: 12, weight: .black)).foregroundStyle(Theme.ink) }
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Theme.sand : (hovered ? Theme.panel : Color.clear)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink, lineWidth: isSelected || hovered ? 2 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverPlainStyle())
        .onHover { hovered = $0 }
    }
}

private struct DropdownHost: ViewModifier {
    @ObservedObject var controller: DropdownController

    func body(content: Content) -> some View {
        content
            .environment(\.dropdownController, controller)
            .coordinateSpace(name: "dropdownSpace")
            .overlay {
                ZStack {
                    DropdownOverlay(controller: controller)
                    ThemedAlertOverlay(controller: controller)
                }
            }
    }
}

private struct OwnedDropdownHost: ViewModifier {
    @StateObject private var controller = DropdownController()
    func body(content: Content) -> some View { content.modifier(DropdownHost(controller: controller)) }
}

extension View {
    /// Lets dropdowns, right-click menus and alerts inside this view open themed cards over
    /// everything else. Pass your own controller when the view itself needs to show an alert.
    func dropdownHost() -> some View { modifier(OwnedDropdownHost()) }
    func dropdownHost(using controller: DropdownController) -> some View { modifier(DropdownHost(controller: controller)) }
}

// MARK: - Themed date / time picker

/// Button that shows the date and/or time and opens a themed calendar + time card.
struct NeoDatePicker: View {
    @Binding var date: Date
    var includesDate = true
    @Environment(\.dropdownController) private var controller
    @State private var frame: CGRect = .zero

    private var title: String {
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let time = date.formatted(date: .omitted, time: .shortened)
        return includesDate ? "\(day) · \(time)" : time
    }

    var body: some View {
        Button {
            controller?.openCustom(anchor: frame, size: CGSize(width: includesDate ? 320 : 250, height: includesDate ? 392 : 90)) {
                DatePickerCard(date: $date, includesDate: includesDate)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: includesDate ? "calendar" : "clock").font(.system(size: 12, weight: .bold))
                Text(title).font(Fonts.ui(14, .heavy)).lineLimit(1)
            }
            .padding(.horizontal, 14).frame(height: 36)
        }
        .buttonStyle(PressableStyle(fill: Theme.card, shadow: 3, capsule: true))
        .padding(.trailing, 3).padding(.bottom, 3)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("dropdownSpace")) } action: { frame = $0 }
        .accessibilityLabel(title)
    }
}

private struct DatePickerCard: View {
    @Binding var date: Date
    let includesDate: Bool
    @State private var month: Date

    private let calendar = Calendar.current

    init(date: Binding<Date>, includesDate: Bool) {
        _date = date
        self.includesDate = includesDate
        let c = Calendar.current
        _month = State(initialValue: c.date(from: c.dateComponents([.year, .month], from: date.wrappedValue)) ?? date.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 14) {
            if includesDate {
                header
                weekdayRow
                grid
            }
            timeRow
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Month

    private var header: some View {
        HStack {
            navButton("chevron.left") { shift(-1) }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year())).font(Fonts.black(18)).foregroundStyle(Theme.ink)
            Spacer()
            navButton("chevron.right") { shift(1) }
        }
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .black)).frame(width: 34, height: 34)
        }
        .buttonStyle(PressableStyle(fill: Theme.card, radius: 8, shadow: 2))
    }

    private func shift(_ by: Int) {
        if let m = calendar.date(byAdding: .month, value: by, to: month) { month = m }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(calendar.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol).font(Fonts.ui(12, .heavy)).foregroundStyle(Theme.inkMuted).frame(maxWidth: .infinity)
            }
        }
    }

    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: lead)
        for day in range { out.append(calendar.date(byAdding: .day, value: day - 1, to: month)) }
        return out
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    let selected = calendar.isDate(day, inSameDayAs: date)
                    let today = calendar.isDateInToday(day)
                    Button { pick(day) } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .font(Fonts.ui(14, .heavy))
                            .foregroundStyle(selected ? Color.white : Theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.ink : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.ink, lineWidth: today && !selected ? 2 : 0))
                    }
                    .buttonStyle(HoverPlainStyle())
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
    }

    private func pick(_ day: Date) {
        let t = calendar.dateComponents([.hour, .minute], from: date)
        date = calendar.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    // MARK: Time

    private var hour12: Int {
        let h = calendar.component(.hour, from: date) % 12
        return h == 0 ? 12 : h
    }
    private var minute: Int { calendar.component(.minute, from: date) }
    private var isPM: Bool { calendar.component(.hour, from: date) >= 12 }

    private func setTime(hour12 h: Int, minute m: Int, pm: Bool) {
        let hour24 = (h % 12) + (pm ? 12 : 0)
        date = calendar.date(bySettingHour: hour24, minute: m, second: 0, of: date) ?? date
    }

    private var timeRow: some View {
        HStack(spacing: 10) {
            stepper(value: String(hour12)) { setTime(hour12: hour12 == 1 ? 12 : hour12 - 1, minute: minute, pm: isPM) }
                  plus: { setTime(hour12: hour12 == 12 ? 1 : hour12 + 1, minute: minute, pm: isPM) }
            Text(":").font(Fonts.black(18)).foregroundStyle(Theme.ink)
            stepper(value: String(format: "%02d", minute)) { setTime(hour12: hour12, minute: (minute + 55) % 60, pm: isPM) }
                  plus: { setTime(hour12: hour12, minute: (minute + 5) % 60, pm: isPM) }
            HStack(spacing: 4) {
                ampm("AM", selected: !isPM) { setTime(hour12: hour12, minute: minute, pm: false) }
                ampm("PM", selected: isPM) { setTime(hour12: hour12, minute: minute, pm: true) }
            }
        }
    }

    private func stepper(value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: minus) { Image(systemName: "minus").font(.system(size: 11, weight: .black)).frame(width: 28, height: 32) }
                .buttonStyle(PressableStyle(fill: Theme.card, radius: 8, shadow: 2))
            Text(value).font(Fonts.black(18)).foregroundStyle(Theme.ink).frame(minWidth: 30)
            Button(action: plus) { Image(systemName: "plus").font(.system(size: 11, weight: .black)).frame(width: 28, height: 32) }
                .buttonStyle(PressableStyle(fill: Theme.card, radius: 8, shadow: 2))
        }
    }

    private func ampm(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Fonts.ui(13, .heavy)).frame(width: 40, height: 32)
        }
        .buttonStyle(PressableStyle(fill: selected ? Theme.ink : Theme.card, foreground: selected ? .white : Theme.ink, radius: 8, shadow: 2))
    }
}
