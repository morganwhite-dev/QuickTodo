// QuickCapture.swift
// The Quick Capture card (dropdown under the top bar) and the live "QuickToDo understood"
// card. Parsing stays shared with menu-bar Quick Add through QuickDateParser.

import SwiftUI

/// Live parse of what the user typed: title, due, list, priority. When the text has no
/// date of its own and a free slot was passed in ("+ Plan this time"), the slot wins.
func parseCapture(_ text: String, prefill: Date?, knownCategories: [String] = []) -> QuickDateParser.Result {
    let parsed = QuickDateParser.parse(text, knownCategories: knownCategories)
    guard parsed.date == nil, let prefill else { return parsed }
    return QuickDateParser.Result(title: parsed.title, date: prefill, category: parsed.category, priority: parsed.priority)
}

/// "QUICKTODO UNDERSTOOD" card with the parsed title and chips.
struct UnderstoodCard: View {
    let parsed: QuickDateParser.Result
    var categoryColor: Color = Theme.sand

    private var dueText: String {
        guard let d = parsed.date else { return "None" }
        let hasTime = Calendar.current.component(.hour, from: d) != 0 || Calendar.current.component(.minute, from: d) != 0
        let day = d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return hasTime ? "\(day) · \(d.formatted(date: .omitted, time: .shortened))" : day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT WILL BE SAVED")
                .font(Fonts.ui(11, .heavy)).tracking(1.2).foregroundStyle(Theme.inkMuted)
            Text(parsed.title.isEmpty ? "Start typing…" : parsed.title)
                .font(Fonts.ui(19, .heavy))
                .foregroundStyle(parsed.title.isEmpty ? Theme.inkMuted : Theme.ink)
            HStack(spacing: 8) {
                NeoChip(text: "Due · \(dueText)", fill: Theme.panel, size: 13)
                NeoChip(text: "List · \(parsed.category ?? "General")", fill: categoryColor, size: 13)
                NeoChip(text: "Priority · \((parsed.priority ?? .low).label)", fill: Theme.panel, size: 13)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoCard(Theme.card, radius: 10, shadow: 0)
    }
}

struct QuickCapture: View {
    var prefillDate: Date? = nil
    var categories: [CategoryItem] = []
    let onCapture: (QuickDateParser.Result) -> Void
    var onOpenDetailed: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @State private var text = ""
    @State private var highlighted = 0
    @State private var arrowed = false   // true once the arrow keys moved the highlight
    @State private var justAdded: String?
    @FocusState private var isFocused: Bool

    private var parsed: QuickDateParser.Result { parseCapture(text, prefill: prefillDate, knownCategories: categories.map(\.name)) }
    private var canAdd: Bool { !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The "#..." being typed right now (a # at the start or after a space, running to the end).
    private var activeTag: (range: Range<String.Index>, fragment: String)? {
        guard let hash = text.lastIndex(of: "#") else { return nil }
        if hash != text.startIndex, !text[text.index(before: hash)].isWhitespace { return nil }
        let fragment = String(text[text.index(after: hash)...])
        if fragment.count > 24 || fragment.contains(where: { "![\"".contains($0) }) { return nil }
        return (hash..<text.endIndex, fragment)
    }

    /// Existing lists that fit what follows the #, best matches first. Empty once the typed
    /// name already is a list, so the dropdown gets out of the way.
    private var suggestions: [CategoryItem] {
        guard let tag = activeTag else { return [] }
        let key = QuickDateParser.normalized(tag.fragment)
        let lists = categories.filter { $0.name.caseInsensitiveCompare("General") != .orderedSame }
        if key.isEmpty { return Array(lists.prefix(6)) }
        if lists.contains(where: { QuickDateParser.normalized($0.name) == key }) { return [] }
        let starts = lists.filter { QuickDateParser.normalized($0.name).hasPrefix(key) }
        let inside = lists.filter { !QuickDateParser.normalized($0.name).hasPrefix(key) && QuickDateParser.normalized($0.name).contains(key) }
        return Array((starts + inside).prefix(6))
    }

    private func choose(_ category: CategoryItem) {
        guard let tag = activeTag else { return }
        text.replaceSubrange(tag.range, with: "#\(category.name) ")
    }

    private func moveHighlight(_ step: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        arrowed = true
        highlighted = min(max(highlighted + step, 0), suggestions.count - 1)
        return .handled
    }

    private func submit() {
        if arrowed, suggestions.indices.contains(highlighted) { choose(suggestions[highlighted]) } else { capture() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Quick Capture").font(Fonts.black(22)).foregroundStyle(Theme.ink)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .black)).frame(width: 36, height: 36)
                    }
                    .buttonStyle(PressableStyle(fill: Theme.card, shadow: 0))
                    .accessibilityLabel("Close Quick Capture")
                    .keyboardShortcut(.cancelAction)
                }
            }

            HStack(spacing: 12) {
                TextField("essay friday 11:59pm #English !high", text: $text)
                    .textFieldStyle(.plain)
                    .font(Fonts.ui(18, .bold))
                    .foregroundStyle(Theme.ink)
                    .focused($isFocused)
                    .onSubmit(submit)
                    .onKeyPress(.downArrow) { moveHighlight(1) }
                    .onKeyPress(.upArrow) { moveHighlight(-1) }
                    .onKeyPress(.tab) {
                        guard suggestions.indices.contains(highlighted) else { return .ignored }
                        choose(suggestions[highlighted])
                        return .handled
                    }
                    .onChange(of: text) { _, _ in highlighted = 0; arrowed = false }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink, lineWidth: 2))
                Button(action: capture) {
                    Text("Add").font(Fonts.ui(17, .heavy)).padding(.horizontal, 26).frame(height: 56)
                }
                .buttonStyle(PressableStyle(fill: Theme.amber, radius: 10, shadow: 4))
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.55)
            }

            if !suggestions.isEmpty, justAdded == nil {
                VStack(spacing: 0) {
                    Text("YOUR LISTS")
                        .font(Fonts.ui(11, .heavy)).tracking(1.2).foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, category in
                        Button { choose(category) } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Categories.color(for: category)).frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                                Text(category.name).font(Fonts.ui(15, .heavy)).lineLimit(1)
                                Spacer(minLength: 8)
                                if index == highlighted {
                                    Text(arrowed ? "Return" : "Tab")
                                        .font(Fonts.ui(11, .heavy)).foregroundStyle(Theme.inkMuted)
                                }
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).frame(height: 38)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(index == highlighted ? Theme.amber : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverPlainStyle(hover: false))
                        .onHover { if $0 { highlighted = index } }
                    }
                }
                .padding(.bottom, 4)
                .neoCard(Theme.card, radius: 10, shadow: 3)
                .transition(.opacity)
            }

            if let justAdded {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Added “\(justAdded)”").lineLimit(1)
                }
                .font(Fonts.ui(15, .heavy)).foregroundStyle(Theme.ink)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .neoCard(Theme.done, radius: 10, shadow: 0)
                .transition(.opacity)
            } else {
                UnderstoodCard(parsed: parsed, categoryColor: listTint)
            }

            HStack {
                Text(prefillDate != nil && QuickDateParser.parse(text).date == nil
                     ? "Planning \(prefillDate!.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))"
                     : "TRY: TOMORROW 9AM · #PERSONAL · !LOW · IN 10 MINUTES")
                    .font(Fonts.ui(13, .semibold)).foregroundStyle(Theme.inkMuted)
                Spacer()
                if let onOpenDetailed {
                    Button("Open detailed task", action: onOpenDetailed)
                        .buttonStyle(HoverPlainStyle()).font(Fonts.ui(13, .heavy)).underline().foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(20)
        .frame(width: 620)
        .neoCard(Theme.navBar, radius: 14, shadow: 8)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isFocused = true } }
        .onExitCommand { onClose?() }
    }

    private var listTint: Color {
        guard let name = parsed.category else { return Theme.sand }
        return Categories.tint(Categories.color(for: name, in: categories))
    }

    private func capture() {
        let result = parsed
        guard canAdd else { return }
        onCapture(result)
        withAnimation(.easeOut(duration: 0.15)) { justAdded = result.title }
        text = ""
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { justAdded = nil }
        }
    }
}
