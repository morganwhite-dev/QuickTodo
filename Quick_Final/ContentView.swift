//
//  ContentView.swift
//  QuickTodo
//
//  Created by Morgue White on 11/10/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [TaskItem]
    @State private var isPresentingAdd = false

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        TaskDetailView(task: item)
                    } label: {
                        TaskRowView(task: item)
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button { isPresentingAdd = true } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .focusEffectDisabled()
                    .help("Add Task")
                    .controlSize(.small)
                }
            }
        } detail: {
            ContentUnavailableView(
                "Select a Task",
                systemImage: "checklist",
                description: Text("Choose a task to review its details or edit it.")
            )
        }
        .sheet(isPresented: $isPresentingAdd) {
            TaskEditorView()
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

private struct TaskRowView: View {
    let task: TaskItem
    @State private var isPresentingEditor = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let color = task.category?.color.swiftUIColor {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                    }

                    Text(task.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Label(task.createdAt.formatted(date: .numeric, time: .shortened), systemImage: "calendar")

                    if let dueDate = task.dueDate {
                        Text("due")
                        Text(dueDate.formatted(date: .numeric, time: .shortened))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 8)

            Menu {
                Section("Task Details") {
                    Button {} label: {
                        Label(task.dueDate.map { "Due \($0.formatted(date: .abbreviated, time: task.isAllDay ? .omitted : .shortened))" } ?? "No due date", systemImage: "clock")
                    }
                    .disabled(true)

                    Button {} label: {
                        Label(task.repeatRule.label, systemImage: "repeat")
                    }
                    .disabled(true)

                    Button {} label: {
                        Label(alertSummary, systemImage: "bell")
                    }
                    .disabled(true)

                    Button {} label: {
                        Label(task.category?.name ?? "No category", systemImage: "tag")
                    }
                    .disabled(true)
                }

                Divider()

                Button { isPresentingEditor = true } label: {
                    Label("Edit Task", systemImage: "square.and.pencil")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help("Task Details")
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $isPresentingEditor) {
            TaskEditorView(task: task)
        }
    }

    private var alertSummary: String {
        let labels = task.alertOffsets.map(alertLabel(for:))
        return labels.isEmpty ? "No alerts" : labels.joined(separator: ", ")
    }
}

private struct TaskDetailView: View {
    let task: TaskItem
    @State private var isPresentingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(spacing: 0) {
                    DetailRow(icon: "calendar.badge.clock", title: "Created", value: task.createdAt.formatted(date: .abbreviated, time: .shortened))

                    if let dueDate = task.dueDate {
                        Divider()
                        DetailRow(icon: "clock", title: "Due", value: dueDate.formatted(date: .abbreviated, time: task.isAllDay ? .omitted : .shortened))
                    }

                    Divider()
                    DetailRow(icon: "repeat", title: "Repeat", value: task.repeatRule.label)

                    Divider()
                    DetailRow(icon: "bell", title: "Alerts", value: alertSummary)

                    if let category = task.category {
                        Divider()
                        DetailRow(icon: "tag", title: "Category", value: category.name, tint: category.color.swiftUIColor)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.separator.opacity(0.6))
                }

                if let notes = task.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes", systemImage: "note.text")
                            .font(.headline)
                        Text(notes)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.separator.opacity(0.6))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .navigationTitle("Task Details")
        .toolbar {
            ToolbarItem {
                Button { isPresentingEditor = true } label: {
                    Label("Edit Task", systemImage: "square.and.pencil")
                }
                .help("Edit Task")
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            TaskEditorView(task: task)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((task.category?.color.swiftUIColor ?? .accentColor).opacity(0.16))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(task.category?.color.swiftUIColor ?? .accentColor)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(task.dueDate.map { "Due \($0.formatted(date: .abbreviated, time: task.isAllDay ? .omitted : .shortened))" } ?? "No due date")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var alertSummary: String {
        let labels = task.alertOffsets.map(alertLabel(for:))
        return labels.isEmpty ? "None" : labels.joined(separator: ", ")
    }
}

private struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 24)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 16)

            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TaskItem.self, inMemory: true)
}
