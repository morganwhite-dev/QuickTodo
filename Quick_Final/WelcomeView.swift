// WelcomeView.swift
// First-run onboarding — rewritten to introduce the Decision Board and Next Move.

import SwiftUI
import AppKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: First-Run Onboarding

private struct TrackpadSwipeMonitor: NSViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.start()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        weak var view: NSView?

        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void

        private var monitor: Any?
        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private var didTrigger = false

        init(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
        }

        func start() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            guard let window = view?.window, event.window === window else { return }

            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                accumulatedX = 0
                accumulatedY = 0
                didTrigger = false
            }

            accumulatedX += event.scrollingDeltaX
            accumulatedY += event.scrollingDeltaY

            let isHorizontalSwipe =
                abs(accumulatedX) > 60 &&
                abs(accumulatedX) > abs(accumulatedY) * 1.35

            if isHorizontalSwipe && !didTrigger {
                didTrigger = true

                if accumulatedX > 0 {
                    onSwipeRight()
                } else {
                    onSwipeLeft()
                }
            }

            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                accumulatedX = 0
                accumulatedY = 0
                didTrigger = false
            }
        }
    }
}


struct WelcomeView: View {
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    private var stepAnimation: Animation {
        reduceMotion ? .easeInOut(duration: Motion.select) : Motion.pageStep
    }

    // MARK: Content model (keep in sync with features — see help/tips)

    fileprivate struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let detail: String
    }

    fileprivate struct Page: Identifiable {
        let id = UUID()
        let badge: String
        let accent: Color
        let title: String
        let subtitle: String
        let features: [Feature]
        var showQuickAddPreview: Bool = false
        var footnote: String? = nil
    }

    private let pages: [Page] = [
        Page(
            badge: "checkmark.circle.fill",
            accent: Theme.accent,
            title: "Welcome to QuickTodo",
            subtitle: "Turn messy captured tasks into clear next moves, while keeping everything private on your Mac.",
            features: [
                Feature(icon: "lock.fill", color: Theme.lowPressure, title: "Private by design",
                        detail: "Everything stays on this device. No account, no sync, no tracking."),
                Feature(icon: "bolt.fill", color: Theme.accent, title: "Built for speed",
                        detail: "Add a task in seconds from the app, the menu bar, or the global shortcut."),
                Feature(icon: "tray.full.fill", color: Theme.general, title: "A calm capture bucket",
                        detail: "New tasks land in General first, ready to be clarified when you have a moment.")
            ],
            showQuickAddPreview: true
        ),
        Page(
            badge: "text.badge.plus",
            accent: Theme.accent,
            title: "Capture in plain language",
            subtitle: "Type the way you think — QuickTodo fills in the details for you.",
            features: [
                Feature(icon: "calendar", color: Theme.dueSoon, title: "Dates & times",
                        detail: "“essay friday 11:59pm” sets the due date and time automatically."),
                Feature(icon: "tag.fill", color: Theme.onDeck, title: "Categories & priority",
                        detail: "Add #English and !high. Type #Work on its own to create a category."),
                Feature(icon: "command", color: Theme.keepInMind, title: "From anywhere",
                        detail: "Press ⌃⌥⌘ Space in any app to open Quick Add without switching windows.")
            ]
        ),
        Page(
            badge: "square.grid.2x2",
            accent: Theme.dueSoon,
            title: "See the decision, not the clutter",
            subtitle: "The Decision Board shows where work stands and what deserves attention.",
            features: [
                Feature(icon: "tray.fill", color: Theme.general, title: "Capture",
                        detail: "Captured tasks wait here until you decide what they need."),
                Feature(icon: "sparkles", color: Theme.onDeck, title: "Ready",
                        detail: "A live, computed shortlist surfaces high-signal tasks without moving them."),
                Feature(icon: "calendar", color: Theme.accent, title: "Scheduled & In Progress",
                        detail: "Move work through clear stages, then mark it done — finished tasks land in Completed."),
                Feature(icon: "list.bullet", color: Theme.keepInMind, title: "Lists",
                        detail: "Group related tasks in a dedicated overview with live counts.")
            ]
        ),
        Page(
            badge: "sparkles.rectangle.stack",
            accent: Theme.lowPressure,
            title: "Choose one clear next move",
            subtitle: "Select a task and QuickTodo recommends a practical action using only details you provided.",
            features: [
                Feature(icon: "play.fill", color: Theme.accent, title: "Act with confidence",
                        detail: "Start now, schedule it, break it into steps, file it, defer it, or take a quick win."),
                Feature(icon: "text.quote", color: Theme.dueSoon, title: "Reasons you can trust",
                        detail: "Recommendations use real dates, priorities, estimates, subtasks, and dependencies, never invented context."),
                Feature(icon: "link", color: Theme.lowPressure, title: "Keep work connected",
                        detail: "Set dependencies and estimates so the next move reflects how your work actually fits together.")
            ],
            footnote: "Need a hand later? Open Help ▸ QuickTodo Help, or visit Settings (⌘,)."
        )
    ]

    private var isLastStep: Bool { step == pages.count - 1 }

    var body: some View {
        let page = pages[step]

        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 7) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? page.accent : Color.white.opacity(0.18))
                        .frame(width: index == step ? 22 : 7, height: 7)
                        .animation(.snappy(duration: Motion.stepDot), value: step)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 6)

            // Page content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(page.accent.opacity(0.16))
                            Image(systemName: page.badge)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(page.accent)
                        }
                        .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(page.title)
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(page.subtitle)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if page.showQuickAddPreview {
                        quickAddPreview(accent: page.accent)
                    }

                    VStack(spacing: 10) {
                        ForEach(page.features) { item in
                            featureRow(item)
                        }
                    }

                    if let footnote = page.footnote {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(page.accent)
                                .padding(.top, 1)

                            Text(footnote)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(page.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(page.accent.opacity(0.20), lineWidth: 1)
                        )
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Swipe left or right to move between pages")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 30)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                )
            }
            .animation(stepAnimation, value: step)

            Divider().overlay(Color.white.opacity(0.08))

            // Navigation bar
            HStack(spacing: 10) {
                if !isLastStep {
                    Button("Skip", action: onDismiss)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Skip the introduction")
                }

                Spacer()

                if step > 0 {
                    Button(action: goBack) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }

                Button(action: {
                    if isLastStep {
                        onDismiss()
                    } else {
                        goForward()
                    }
                }) {
                    Text(isLastStep ? "Get Started" : "Next")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minWidth: isLastStep ? 120 : 80)
                }
                .buttonStyle(.glassProminent)
                .tint(page.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 640)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 36, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > 72, abs(horizontal) > abs(vertical) * 1.25 else { return }
                    if horizontal < 0 {
                        goForward()
                    } else {
                        goBack()
                    }
                }
        )
        
        .gesture(
            DragGesture(minimumDistance: 36, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > 72, abs(horizontal) > abs(vertical) * 1.25 else { return }
                    if horizontal < 0 {
                        goForward()
                    } else {
                        goBack()
                    }
                }
        )
        .background(
                TrackpadSwipeMonitor(
                    onSwipeLeft: goForward,
                    onSwipeRight: goBack
                )
            )
        .onMoveCommand { direction in
            switch direction {
            case .left: goBack()
            case .right: goForward()
            default: break
            }
        }
    }
    

    @ViewBuilder
    private func featureRow(_ item: Feature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.color)
                .frame(width: 36, height: 36)
                .background(item.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14.5, weight: .semibold))
                Text(item.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func quickAddPreview(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Example quick capture")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 10) {
                Text("essay friday 11:59pm #English !high")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("essay")
                        .font(.system(size: 13.5, weight: .semibold))
                    HStack(spacing: 6) {
                        Label("Fri 11:59 PM", systemImage: "calendar")
                        Text("English")
                        Text("High")
                            .foregroundStyle(Theme.critical)
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: 180, alignment: .leading)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func goForward() {
        guard !isLastStep else { return }

        withAnimation(stepAnimation) {
            step += 1
        }
    }

    private func goBack() {
        guard step > 0 else { return }
        withAnimation(stepAnimation) { step -= 1 }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
