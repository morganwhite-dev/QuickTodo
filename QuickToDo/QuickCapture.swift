// QuickCapture.swift
// The Quick Capture card (dropdown under the top bar) and the live "QuickToDo understood"
// card. Parsing stays shared with menu-bar Quick Add through QuickDateParser.

import SwiftUI

/// Live parse of what the user typed: title, due, list, priority. When the text has no
/// date of its own and a free slot was passed in ("+ Plan this time"), the slot wins.
func parseCapture(_ text: String, prefill: Date?) -> QuickDateParser.Result {
    let parsed = QuickDateParser.parse(text)
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
    @State private var justAdded: String?
    @FocusState private var isFocused: Bool

    private var parsed: QuickDateParser.Result { parseCapture(text, prefill: prefillDate) }
    private var canAdd: Bool { !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
                    .onSubmit(capture)
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
