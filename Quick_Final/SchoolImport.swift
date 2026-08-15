// SchoolImport.swift
// Local JSON import for school task plans (e.g. produced by reviewing a syllabus,
// Brightspace module, or rubric). Mirrors BackupManager's "stage, then commit" shape
// in DataBackup.swift, but surfaces a real preview list first since these rows carry
// fields (course, module, materials) worth checking before they become real tasks.

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - Decoding model

// Only `title` is required. Real syllabus/Brightspace exports are inconsistent, so a
// missing module or due time should never fail the whole import.
struct ImportedSchoolTask: Codable, Identifiable {
    let id = UUID()
    var title: String
    var course: String?
    var module: String?
    var dueDate: String?
    var dueTime: String?
    var type: String?
    var priority: String?
    var materialsNeeded: [String]?
    var notes: String?

    // `id` is local-only (List identity for the preview) and intentionally excluded
    // here so decoding never fails just because the JSON doesn't include it. `source`
    // (e.g. "Brightspace > Module 3 > Readings") is accepted in the JSON but not
    // decoded — it isn't shown anywhere, so there's no point carrying it around.
    private enum CodingKeys: String, CodingKey {
        case title, course, module, dueDate, dueTime, type, priority, materialsNeeded, notes
    }
}

enum SchoolImportError: LocalizedError {
    case fileUnreadable
    case invalidJSON
    case empty

    var errorDescription: String? {
        switch self {
        case .fileUnreadable: return "That file couldn't be opened."
        case .invalidJSON: return "That file isn't a valid school plan JSON file. Check that it's a JSON array of tasks."
        case .empty: return "That file doesn't contain any tasks."
        }
    }
}

extension ImportedSchoolTask {
    // True once the due date couldn't be resolved to a real Date — covers a missing
    // key, blank string, the literal "Needs review", or text that doesn't parse.
    var needsDateReview: Bool {
        ImportedSchoolTask.parseDueDate(dateString: dueDate, timeString: dueTime) == nil
    }

    var resolvedDueDate: Date? {
        ImportedSchoolTask.parseDueDate(dateString: dueDate, timeString: dueTime)
    }

    var resolvedPriority: TaskPriority {
        switch priority?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return .medium
        }
    }

    // Builds the real TaskItem QuickToDo stores. TaskItem has no school-specific
    // columns, so module/materials/source are folded into `notes`. Course isn't
    // repeated here — each course becomes its own list (see SchoolImportManager),
    // so the list itself already says the class; no need to say it again in the
    // title or notes.
    func makeTaskItem(category: String, sortIndex: Int) -> TaskItem {
        let due = resolvedDueDate
        let needsReview = due == nil

        var displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayTitle.isEmpty { displayTitle = "Untitled Task" }
        if needsReview { displayTitle += " (Needs Review)" }

        var noteLines: [String] = []
        if let module, !module.isEmpty { noteLines.append("Module: \(module)") }
        if let materialsNeeded, !materialsNeeded.isEmpty {
            noteLines.append("Materials needed:")
            noteLines.append(contentsOf: materialsNeeded.map { "  • \($0)" })
        }
        if needsReview {
            let raw = dueDate?.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = (raw?.isEmpty ?? true) ? "missing" : "\"\(raw!)\""
            noteLines.append("⚠ Needs review: original due date was \(shown) and couldn't be imported.")
        }
        if let notes, !notes.isEmpty { noteLines.append(notes) }

        return TaskItem(
            title: displayTitle,
            notes: noteLines.joined(separator: "\n"),
            dueDate: due,
            category: category,
            priority: resolvedPriority,
            sortIndex: sortIndex,
            stage: TaskStage.suggestedInitial(forDueDate: due)
        )
    }

    // dueDate is normally "YYYY-MM-DD" and dueTime "HH:mm". Missing/blank/"Needs
    // review"/unparseable input all resolve to nil rather than throwing, so one bad
    // row never crashes the import. A date with no time defaults to noon, matching
    // QuickDateParser's convention for bare dates elsewhere in the app.
    //
    // NOTE: We intentionally avoid DateFormatter here. Using DateFormatter with
    // timeZone = .current can produce off-by-one-day results in certain timezone
    // configurations because intermediate Date values are stored in UTC and the
    // round-trip through dateComponents can land on a different calendar day.
    // Building DateComponents directly from the parsed integers and calling
    // Calendar.current.date(from:) is unambiguous — it always produces the date
    // the JSON literally says, at the given local time, in the device's timezone.
    fileprivate static func parseDueDate(dateString: String?, timeString: String?) -> Date? {
        guard let dateString else { return nil }
        let trimmedDate = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDate.isEmpty, trimmedDate.localizedCaseInsensitiveCompare("needs review") != .orderedSame else {
            return nil
        }

        // Parse "YYYY-MM-DD" by splitting on "-" to avoid any formatter/locale edge cases.
        let dateParts = trimmedDate.split(separator: "-")
        guard dateParts.count == 3,
              let year  = Int(dateParts[0]),
              let month = Int(dateParts[1]),
              let day   = Int(dateParts[2]) else { return nil }

        // Default to noon when no time is supplied.
        var hour = 12, minute = 0
        let trimmedTime = timeString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTime.isEmpty {
            let timeParts = trimmedTime.split(separator: ":")
            if timeParts.count >= 2,
               let h = Int(timeParts[0]),
               let m = Int(timeParts[1]) {
                hour = h; minute = m
            }
        }

        var comps        = DateComponents()
        comps.year       = year
        comps.month      = month
        comps.day        = day
        comps.hour       = hour
        comps.minute     = minute
        comps.second     = 0
        return Calendar.current.date(from: comps)
    }
}

// MARK: - Manager

// Lives outside the view hierarchy and talks to SwiftData directly, same reason as
// BackupManager in DataBackup.swift: Settings isn't wired to the SwiftData @Environment.
enum SchoolImportManager {
    private static var context: ModelContext? { SwiftDataBridge.shared.modelContainer?.mainContext }

    // Opens a file picker and decodes the chosen JSON into preview rows. Nothing
    // touches SwiftData until commit(_:) is called — picking and previewing a file
    // is always safe to cancel out of.
    static func chooseFile(completion: @escaping (Result<[ImportedSchoolTask], SchoolImportError>) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url) else {
                completion(.failure(.fileUnreadable))
                return
            }
            guard let parsed = try? JSONDecoder().decode([ImportedSchoolTask].self, from: data) else {
                completion(.failure(.invalidJSON))
                return
            }
            guard !parsed.isEmpty else {
                completion(.failure(.empty))
                return
            }
            completion(.success(parsed))
        }
    }

    // The list name a row would resolve to, without creating anything — reused by
    // both commit(_:) (which does create missing lists) and duplicateRowIDs(in:)
    // (which only needs the name to compare against existing tasks).
    private static func resolvedCategoryName(for course: String?, categories: [CategoryItem]) -> String {
        let trimmed = course?.trimmingCharacters(in: .whitespacesAndNewlines)
        let desired = (trimmed?.isEmpty ?? true) ? "School" : trimmed!
        return categories.first { $0.name.caseInsensitiveCompare(desired) == .orderedSame }?.name ?? desired
    }

    // Same calendar day, "none" if unresolved — two undated/needs-review rows are
    // treated as a potential match, but a resolved date never matches an
    // unresolved one.
    private static func dayKey(_ date: Date?) -> String {
        guard let date else { return "none" }
        return Calendar.current.startOfDay(for: date).description
    }

    private static func matchKey(title: String, category: String, due: Date?) -> String {
        "\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(category.lowercased())|\(dayKey(due))"
    }

    // Flags rows that already match a task in QuickToDo — same title, same
    // resolved list, and the same due date (or both unresolved) — so re-running an
    // import from a regenerated weekly file doesn't pile up the same tasks again.
    // A recurring assignment with a *new* due date is a different occurrence, not
    // a repeat, so it's intentionally left unflagged. Trashed tasks don't count as
    // a match either: if it was deleted on purpose, a fresh export bringing it
    // back is presumably wanted.
    static func duplicateRowIDs(in rows: [ImportedSchoolTask]) -> Set<UUID> {
        guard let context else { return [] }
        let existingTasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { $0.deletedAt == nil }
        let categories = (try? context.fetch(FetchDescriptor<CategoryItem>())) ?? []

        let existingKeys = Set(existingTasks.map { task -> String in
            var title = task.title
            if title.hasSuffix(" (Needs Review)") { title.removeLast(" (Needs Review)".count) }
            return matchKey(title: title, category: task.category, due: task.dueDate)
        })

        return Set(rows.compactMap { row -> UUID? in
            let category = resolvedCategoryName(for: row.course, categories: categories)
            let key = matchKey(title: row.title, category: category, due: row.resolvedDueDate)
            return existingKeys.contains(key) ? row.id : nil
        })
    }

    // Converts approved preview rows into real TaskItems and saves them. Each
    // distinct course becomes its own list (auto-created if missing, reused if it
    // already exists) — that way the list itself says the class, and rows with no
    // course fall back to a generic "School" list instead of being dropped.
    static func commit(_ rows: [ImportedSchoolTask]) {
        guard let context else { return }
        var categories = (try? context.fetch(FetchDescriptor<CategoryItem>())) ?? []
        let existingTasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        var nextIndex = (existingTasks.compactMap(\.sortIndex).max() ?? existingTasks.count) + 1
        var resolvedNames: [String: String] = [:]

        func categoryName(for course: String?) -> String {
            let desired = resolvedCategoryName(for: course, categories: categories)
            let key = desired.lowercased()
            if let cached = resolvedNames[key] { return cached }
            if categories.contains(where: { $0.name.caseInsensitiveCompare(desired) == .orderedSame }) {
                resolvedNames[key] = desired
                return desired
            }
            let nextCategoryIndex = (categories.compactMap(\.sortIndex).max() ?? categories.count) + 1
            let category = CategoryItem(name: desired, sortIndex: nextCategoryIndex)
            context.insert(category)
            categories.append(category)
            resolvedNames[key] = desired
            return desired
        }

        for row in rows {
            let task = row.makeTaskItem(category: categoryName(for: row.course), sortIndex: nextIndex)
            nextIndex += 1
            context.insert(task)
            if let due = task.dueDate, !task.isCompleted, due > Date() {
                NotificationManager.shared.schedule(for: task)
            }
        }
        context.saveOrReport()
    }
}

// MARK: - Preview UI

// Wraps a batch of decoded rows so SettingsView can drive the preview sheet with
// `.sheet(item:)` — one Identifiable value instead of a separate Bool + array, so the
// sheet can never be presented with a stale or mismatched rows array.
struct SchoolImportPreview: Identifiable {
    let id = UUID()
    let rows: [ImportedSchoolTask]
    // Rows that look like they were already imported in a previous weekly upload —
    // see SchoolImportManager.duplicateRowIDs(in:). Unchecked by default below.
    let duplicateIDs: Set<UUID>
}

// Shown as a sheet after a file is chosen. Nothing here is persisted until the user
// taps Approve — Cancel just dismisses, leaving QuickToDo untouched.
struct SchoolImportPreviewView: View {
    let rows: [ImportedSchoolTask]
    let duplicateIDs: Set<UUID>
    let onApprove: ([ImportedSchoolTask]) -> Void
    let onCancel: () -> Void

    // Starts pre-filled with the duplicate rows so they're skipped unless the user
    // opts back in — same shape as macOS's "already exists, skip?" file-copy prompt.
    @State private var excludedIDs: Set<UUID>
    // Checkboxes are hidden until the user explicitly enters selection mode — keeps
    // the preview clean for the common case where no manual deselection is needed.
    @State private var selectionMode = false

    init(rows: [ImportedSchoolTask], duplicateIDs: Set<UUID>, onApprove: @escaping ([ImportedSchoolTask]) -> Void, onCancel: @escaping () -> Void) {
        self.rows = rows
        self.duplicateIDs = duplicateIDs
        self.onApprove = onApprove
        self.onCancel = onCancel
        _excludedIDs = State(initialValue: duplicateIDs)
    }

    private var reviewCount: Int { rows.filter(\.needsDateReview).count }
    private var importCount: Int { rows.count - excludedIDs.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(rows) { row in
                        SchoolImportRow(
                            row: row,
                            isDuplicate: duplicateIDs.contains(row.id),
                            showToggle: selectionMode,
                            isExcluded: Binding(
                                get: { excludedIDs.contains(row.id) },
                                set: { excluded in
                                    if excluded { excludedIDs.insert(row.id) } else { excludedIDs.remove(row.id) }
                                }
                            )
                        )
                    }
                }
                .padding(16)
            }

            Divider().background(Theme.divider)

            HStack {
                if reviewCount > 0 {
                    Label("\(reviewCount) need a due date review", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.warning)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.glass)
                Button(importCount > 0 ? "Approve & Import \(importCount) Task\(importCount == 1 ? "" : "s")" : "Nothing to Import") {
                    onApprove(rows.filter { !excludedIDs.contains($0.id) })
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .disabled(importCount == 0)
            }
            .padding(16)
        }
        .frame(width: 560, height: 560)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent.opacity(0.15))
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Import School Plan")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                if duplicateIDs.isEmpty {
                    Text("\(rows.count) task\(rows.count == 1 ? "" : "s") found. Review, then approve to add them.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(rows.count) task\(rows.count == 1 ? "" : "s") found. \(duplicateIDs.count) already in QuickToDo — unchecked below so they won't be added twice.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(selectionMode ? "Done" : "Select") {
                selectionMode.toggle()
            }
            .buttonStyle(.glass)
            .font(.system(size: 12, weight: .medium))
        }
        .padding(16)
    }
}

private struct SchoolImportRow: View {
    let row: ImportedSchoolTask
    let isDuplicate: Bool
    let showToggle: Bool
    @Binding var isExcluded: Bool

    private var dueText: String {
        guard let due = row.resolvedDueDate else { return "Needs review" }
        return row.dueTime?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? due.formatted(date: .abbreviated, time: .shortened)
            : due.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if showToggle {
                    Button {
                        isExcluded.toggle()
                    } label: {
                        Image(systemName: isExcluded ? "circle" : "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(isExcluded ? Color.secondary : Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let priorityText = row.priority {
                    Text(priorityText.capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(row.resolvedPriority.color)
                }
            }

            HStack(spacing: 8) {
                if let course = row.course, !course.isEmpty {
                    SchoolImportPill(text: course, color: Theme.accent)
                }
                if let module = row.module, !module.isEmpty {
                    SchoolImportPill(text: module, color: Theme.keepInMind)
                }
                if let type = row.type, !type.isEmpty {
                    SchoolImportPill(text: type, color: Theme.onDeck)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: row.needsDateReview ? "exclamationmark.triangle.fill" : "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(row.needsDateReview ? Theme.warning : .secondary)
                Text(dueText)
                    .font(.system(size: 11))
                    .foregroundStyle(row.needsDateReview ? Theme.warning : .secondary)
            }

            if let materials = row.materialsNeeded, !materials.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(materials, id: \.self) { item in
                        Text("• \(item)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isDuplicate {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                    Text(isExcluded ? "Already in QuickToDo — skipping" : "Already in QuickToDo — will import again")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(isExcluded ? Theme.mutedText : Theme.warning)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isExcluded ? 0.55 : 1)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isDuplicate && !isExcluded ? Theme.warning.opacity(0.5) : Color.white.opacity(0.075), lineWidth: 1)
        )
    }
}

private struct SchoolImportPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}
