// SettingsView.swift

import SwiftUI
import SwiftData
import ServiceManagement
import UserNotifications

// MARK: Settings

struct SettingsView: View {
    @AppStorage("muteSounds") private var muteSounds = false
    @AppStorage("hasSeenWelcomeV1") private var hasSeenWelcome = false
    @AppStorage(FocusWindowSettings.enabledKey) private var focusWindowEnabled = false
    @AppStorage(FocusWindowSettings.startKey) private var focusWindowStartMinutes = 19 * 60
    @AppStorage(FocusWindowSettings.endKey) private var focusWindowEndMinutes = 21 * 60
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @StateObject private var dropdown = DropdownController()
    // Wrapped in one Identifiable value (instead of a separate Bool + array) so the
    // sheet is always presented with the exact rows it was created with — no risk of
    // the sheet's content closure reading a stale/empty array from a second @State var.
    @State private var schoolImportPreview: SchoolImportPreview?

    private var focusStartDate: Binding<Date> {
        Binding(
            get: { Self.date(fromMinutes: focusWindowStartMinutes) },
            set: { focusWindowStartMinutes = Self.minutes(from: $0) }
        )
    }

    private var focusEndDate: Binding<Date> {
        Binding(
            get: { Self.date(fromMinutes: focusWindowEndMinutes) },
            set: { focusWindowEndMinutes = Self.minutes(from: $0) }
        )
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized, .provisional: return "Enabled"
        case .denied: return "Off"
        case .notDetermined: return "Not requested"
        default: return "Unknown"
        }
    }

    private var notificationDetailText: String {
        switch notificationStatus {
        case .authorized, .provisional: return "Due-date reminders are ready."
        case .denied: return "Turn notifications on in System Settings to receive task reminders."
        case .notDetermined: return "QuickTodo will ask when a reminder is first scheduled."
        default: return "Open System Settings if reminders are not appearing."
        }
    }

    private var notificationAccent: Color {
        switch notificationStatus {
        case .authorized, .provisional: return Theme.lowPressure
        case .denied: return Theme.dueSoon
        case .notDetermined: return Theme.onDeck
        default: return Theme.keepInMind
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader

            ScrollView {
                VStack(spacing: 12) {
                    SettingsCard(title: "General", icon: "gearshape.fill", accent: Theme.accent) {
                        SettingsToggleRow(
                            title: "Completion sound",
                            detail: "Play a subtle sound when you finish a task.",
                            isOn: Binding(
                                get: { !muteSounds },
                                set: { muteSounds = !$0 }
                            )
                        )
                        

                        SettingsDivider()

                        SettingsToggleRow(
                            title: "Launch at login",
                            detail: "Start QuickTodo automatically when you sign in.",
                            isOn: $launchAtLogin
                        )
                        .onChange(of: launchAtLogin) { _, enable in
                            do {
                                if enable {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                // Revert the toggle to the real system state if the change failed.
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                    }

                    SettingsCard(title: "Quick Capture", icon: "bolt.fill", accent: Theme.accent) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Global hotkey")
                                    .font(Fonts.ui(13, .bold))
                                Text("Open Quick Add from any app. Use #category to file it instantly, or leave it in General.")
                                    .font(Fonts.ui(13, .medium))
                                    .foregroundStyle(Theme.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)

                            Text(GlobalHotKeyManager.shortcutLabel)
                                .font(Fonts.ui(13, .heavy))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(Theme.ink, lineWidth: 2)
                                )
                        }
                    }

                    SettingsCard(title: "Focus Window", icon: "moon.stars.fill", accent: Theme.warning) {
                        SettingsToggleRow(
                            title: "Preferred focus hours",
                            detail: "Set the real hours you reserve for focused work. Next Move only cites this window after you enable it here.",
                            isOn: $focusWindowEnabled
                        )

                        if focusWindowEnabled {
                            SettingsDivider()
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("From").font(Fonts.ui(13, .medium)).foregroundStyle(Theme.inkMuted)
                                    NeoDatePicker(date: focusStartDate, includesDate: false)
                                }
                                Image(systemName: "arrow.right")
                                    .font(Fonts.ui(12.5, .bold))
                                    .foregroundStyle(Theme.inkMuted)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("To").font(Fonts.ui(13, .medium)).foregroundStyle(Theme.inkMuted)
                                    NeoDatePicker(date: focusEndDate, includesDate: false)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    SettingsCard(title: "Notifications", icon: "bell.badge.fill", accent: notificationAccent) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Reminder status")
                                    .font(Fonts.ui(13, .bold))
                                Text(notificationDetailText)
                                    .font(Fonts.ui(13, .medium))
                                    .foregroundStyle(Theme.inkMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 12)

                            SettingsStatusPill(text: notificationStatusText, color: notificationAccent)
                        }

                        SettingsDivider()

                        HStack(spacing: 8) {
                            SettingsActionButton(title: "System Settings", icon: "arrow.up.right.square", accent: notificationAccent) {
                                openNotificationSettings()
                            }

                            SettingsActionButton(title: "Check Again", icon: "arrow.clockwise", accent: Theme.accent) {
                                refreshStatus()
                            }
                        }
                    }

                    SettingsCard(title: "Help", icon: "questionmark.circle.fill", accent: Theme.onDeck) {
                        HStack(spacing: 8) {
                            SettingsActionButton(title: "Open Help", icon: "book.pages.fill", accent: Theme.onDeck) {
                                Task { @MainActor in
                                    QuickTodoHelpWindowController.shared.show()
                                }
                            }

                            SettingsActionButton(title: "Replay Welcome", icon: "sparkles.rectangle.stack.fill", accent: Theme.accent) {
                                hasSeenWelcome = false
                            }
                        }
                    }

                    SettingsCard(title: "Import School Plan", icon: "graduationcap.fill", accent: Theme.accent) {
                        Text("Import school tasks from a JSON file (e.g. one Claude/Cowork built from a syllabus or Brightspace page). You'll preview every task before anything is added.")
                            .font(Fonts.ui(13, .medium))
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        SettingsDivider()

                        SettingsActionButton(title: "Choose File…", icon: "doc.badge.plus", accent: Theme.accent) {
                            importSchoolPlan()
                        }
                    }

                    SettingsCard(title: "Backup", icon: "externaldrive.fill", accent: Theme.lowPressure) {
                        Text("QuickTodo's data lives only on this Mac. Export a backup before reinstalling or moving to a new machine.")
                            .font(Fonts.ui(13, .medium))
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        SettingsDivider()

                        HStack(spacing: 8) {
                            SettingsActionButton(title: "Export Backup", icon: "square.and.arrow.up", accent: Theme.lowPressure) {
                                BackupManager.exportBackup()
                            }

                            SettingsActionButton(title: "Import Backup", icon: "square.and.arrow.down", accent: Theme.critical) {
                                BackupManager.chooseImportFile { summary in
                                    guard let summary else { return }
                                    Task { @MainActor in
                                        dropdown.showAlert(
                                            title: "Replace All Data?",
                                            message: "This backup has \(summary.tasks) task\(summary.tasks == 1 ? "" : "s") and \(summary.categories) list\(summary.categories == 1 ? "" : "s"). Importing replaces everything currently in QuickTodo — this can't be undone.",
                                            buttons: [
                                                AlertButton(title: "Cancel", role: .cancel, action: { BackupManager.cancelImport() }),
                                                AlertButton(title: "Replace Everything", role: .destructive, action: { BackupManager.commitImport() })
                                            ]
                                        )
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard(title: "Reset", icon: "exclamationmark.triangle.fill", accent: Theme.critical) {
                        Text("Start completely fresh. Every task and list is permanently deleted — this skips Trash entirely, so export a backup first if there's any chance you'll want this data back.")
                            .font(Fonts.ui(13, .medium))
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        SettingsDivider()

                        Button("Clear Everything", role: .destructive) {
                            dropdown.showAlert(
                                title: "Clear Everything?",
                                message: "This permanently deletes every task and list. Nothing will be retrievable afterward — not even from Trash. Are you sure?",
                                buttons: [
                                    AlertButton(title: "Cancel", role: .cancel),
                                    AlertButton(title: "Clear Everything", role: .destructive, action: { BackupManager.eraseEverything() })
                                ]
                            )
                        }
                        .buttonStyle(NeoButtonStyle(fill: Theme.overdue, foreground: .white))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 640)
        .background(Theme.bgGradient)
        .preferredColorScheme(.light)
        .dropdownHost(using: dropdown)
        .task { refreshStatus() }
        // Nothing here touches SwiftData yet — approving in the preview is the only
        // path that calls SchoolImportManager.commit(_:).
        .sheet(item: $schoolImportPreview) { preview in
            SchoolImportPreviewView(
                rows: preview.rows,
                duplicateIDs: preview.duplicateIDs,
                onApprove: { selectedRows in
                    SchoolImportManager.commit(selectedRows)
                    schoolImportPreview = nil
                },
                onCancel: { schoolImportPreview = nil }
            )
        }
    }

    // Opens the file picker, decodes the chosen JSON, and hands the parsed rows to
    // the preview sheet for the user to approve or cancel.
    private func importSchoolPlan() {
        SchoolImportManager.chooseFile { result in
            switch result {
            case .success(let rows):
                let duplicateIDs = SchoolImportManager.duplicateRowIDs(in: rows)
                schoolImportPreview = SchoolImportPreview(rows: rows, duplicateIDs: duplicateIDs)
            case .failure(let error):
                dropdown.showAlert(
                    title: "Import Failed",
                    message: error.errorDescription ?? "Something went wrong reading that file.",
                    buttons: [AlertButton(title: "OK", role: .normal)]
                )
            }
        }
    }

    @ViewBuilder
    private var settingsHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(Theme.ink)
                .frame(width: 54, height: 54)
                .neoCard(Theme.amber, radius: 12, shadow: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .font(Fonts.black(34)).foregroundStyle(.white)
                Text("Keep the controls tight, clear, and easy to scan.")
                    .font(Fonts.ui(14, .bold))
                    .foregroundStyle(.white)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private func refreshStatus() {
        NotificationManager.shared.getAuthorizationStatus { status in
            notificationStatus = status
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let accent: Color
    let content: Content

    init(title: String, icon: String, accent: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(Fonts.ui(13, .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 28, height: 28)
                    .neoCard(Theme.card, radius: 6, shadow: 0)

                Text(title.uppercased())
                    .font(Fonts.black(15)).tracking(0.5)
                    .foregroundStyle(Theme.ink)

                Spacer(minLength: 0)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neoPanel()
        .padding(.trailing, 5).padding(.bottom, 5)
    }
}

private struct QuickTodoSwitchStyle: ToggleStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(Motion.toggleSwitch) {
                configuration.isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(configuration.isOn ? accent.opacity(0.92) : Color.white.opacity(0.13))
                .frame(width: 58, height: 30)
                .overlay(
                    Circle()
                        .fill(Theme.card)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                        .padding(3),
                    alignment: configuration.isOn ? .trailing : .leading
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            configuration.isOn ? accent.opacity(0.38) : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(HoverPlainStyle())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}


private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Fonts.ui(13, .bold))
                Text(detail)
                    .font(Fonts.ui(13, .medium))
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            NeoToggle(isOn: $isOn)
        }
    }
}

private struct SettingsActionButton: View {
    let title: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(Fonts.ui(12.5, .bold))
                Text(title)
                    .font(Fonts.ui(12.5, .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
        }
        .buttonStyle(PressableStyle(fill: Theme.card, radius: 10, shadow: 3))
        .padding(.trailing, 3).padding(.bottom, 3)
    }
}

private struct SettingsStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(Fonts.ui(12.5, .bold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.card, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(Theme.ink, lineWidth: 2))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.ink)
            .frame(height: 2)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
