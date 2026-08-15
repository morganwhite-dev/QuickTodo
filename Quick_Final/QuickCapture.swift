// QuickCapture.swift
// A compact inline capture field. Parsing stays shared with menu-bar Quick Add.

import SwiftUI

struct QuickCapture: View {
    @State private var text = ""
    @FocusState private var isFocused: Bool
    let onCapture: (QuickDateParser.Result) -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "bolt.fill").foregroundStyle(.secondary)
            TextField("Quick capture: essay Friday 11:59pm #English !high", text: $text)
                .textFieldStyle(.plain).focused($isFocused).onSubmit(capture)
            Button("Add", action: capture)
                .buttonStyle(.glass).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func capture() {
        let parsed = QuickDateParser.parse(text)
        guard !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onCapture(parsed)
        text = ""
    }
}
