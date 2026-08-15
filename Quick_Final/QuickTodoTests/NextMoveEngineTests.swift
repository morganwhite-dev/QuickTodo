// NextMoveEngineTests.swift
// The recommendation engine and dependency-cycle check had zero coverage before this —
// the only prior safety net was a handful of DEBUG-only asserts in NextMoveEngineSelfTest.

import XCTest
@testable import QuickTodo

final class NextMoveEngineTests: XCTestCase {
    // Wednesday, June 10, 2026, 10:00 AM.
    private let now: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 10
        comps.hour = 10; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps)!
    }()

    // FocusWindowSettings reads UserDefaults.standard directly (it's read from a
    // non-View context), so tests that touch it must restore whatever was already
    // there — this is the same defaults domain the real app uses.
    private var savedFocusEnabled: Bool!
    private var savedFocusStart: Int!
    private var savedFocusEnd: Int!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedFocusEnabled = defaults.bool(forKey: FocusWindowSettings.enabledKey)
        savedFocusStart = defaults.integer(forKey: FocusWindowSettings.startKey)
        savedFocusEnd = defaults.integer(forKey: FocusWindowSettings.endKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        defaults.set(savedFocusEnabled, forKey: FocusWindowSettings.enabledKey)
        defaults.set(savedFocusStart, forKey: FocusWindowSettings.startKey)
        defaults.set(savedFocusEnd, forKey: FocusWindowSettings.endKey)
        super.tearDown()
    }

    // MARK: - recommend()

    func testOverdueTaskRecommendsStartNow() {
        let task = TaskItem(
            title: "Overdue", dueDate: now.addingTimeInterval(-3600),
            category: "General", priority: .medium, stage: .scheduled
        )
        let result = NextMoveEngine.recommend(for: task, in: [task], now: now)
        XCTAssertEqual(result?.action, .startNow)
        XCTAssertTrue(result?.headline.localizedCaseInsensitiveContains("overdue") == true)
    }

    func testDueWithinFourHoursRecommendsStartNow() {
        let task = TaskItem(
            title: "Due soon", dueDate: now.addingTimeInterval(2 * 3600),
            category: "General", priority: .medium, stage: .scheduled
        )
        let result = NextMoveEngine.recommend(for: task, in: [task], now: now)
        XCTAssertEqual(result?.action, .startNow)
    }

    func testHighPriorityDuringFocusWindowRecommendsStartNow() {
        UserDefaults.standard.set(true, forKey: FocusWindowSettings.enabledKey)
        UserDefaults.standard.set(9 * 60, forKey: FocusWindowSettings.startKey)
        UserDefaults.standard.set(17 * 60, forKey: FocusWindowSettings.endKey)

        let task = TaskItem(
            title: "Deep work block", dueDate: now.addingTimeInterval(2 * 24 * 3600),
            category: "Work", priority: .high, stage: .general, estimatedMinutes: 90
        )
        let result = NextMoveEngine.recommend(for: task, in: [task], now: now)
        XCTAssertEqual(result?.action, .startNow)
        XCTAssertTrue(result?.headline.localizedCaseInsensitiveContains("focus window") == true)
    }

    func testShortTaskWithNoSubtasksIsAQuickWin() {
        let task = TaskItem(
            title: "Quick", category: "General", priority: .low,
            stage: .general, estimatedMinutes: 15
        )
        XCTAssertEqual(NextMoveEngine.recommend(for: task, in: [task], now: now)?.action, .quickWin)
    }

    func testHighPriorityWithNoPlanRecommendsBreakIntoSteps() {
        let task = TaskItem(
            title: "Plan quarterly roadmap", category: "Work", priority: .high, stage: .general
        )
        XCTAssertEqual(NextMoveEngine.recommend(for: task, in: [task], now: now)?.action, .breakIntoSteps)
    }

    func testUndatedLowPriorityTaskIsFiledForLater() {
        let task = TaskItem(title: "Undated", category: "General", priority: .low, stage: .general)
        XCTAssertEqual(NextMoveEngine.recommend(for: task, in: [task], now: now)?.action, .file)
    }

    func testFutureDueDateKeepsTaskScheduled() {
        let task = TaskItem(
            title: "Future", dueDate: now.addingTimeInterval(2 * 24 * 3600),
            category: "General", priority: .medium, stage: .scheduled
        )
        XCTAssertEqual(NextMoveEngine.recommend(for: task, in: [task], now: now)?.action, .schedule)
    }

    func testHighPriorityWithNoDueDateButAPlanAsksToChooseADeadline() {
        // estimatedMinutes set so this doesn't fall into breakIntoSteps (which requires
        // no explicit estimate) or quickWin (30 min > the 20 min quick-win ceiling).
        let task = TaskItem(
            title: "Redesign onboarding", category: "Work", priority: .high,
            stage: .general, estimatedMinutes: 30
        )
        let result = NextMoveEngine.recommend(for: task, in: [task], now: now)
        XCTAssertEqual(result?.action, .schedule)
        XCTAssertTrue(result?.headline.localizedCaseInsensitiveContains("deadline") == true)
    }

    func testCompletedTaskHasNoRecommendation() {
        let task = TaskItem(title: "Done", isCompleted: true, category: "General", stage: .done)
        XCTAssertNil(NextMoveEngine.recommend(for: task, in: [task], now: now))
    }

    // MARK: - suggested()

    func testSuggestedRanksOverdueAboveDueSoonAboveNoSignal() {
        let overdue = TaskItem(title: "Overdue", dueDate: now.addingTimeInterval(-3600), category: "General", priority: .low, stage: .general)
        let dueSoon = TaskItem(title: "Due soon", dueDate: now.addingTimeInterval(2 * 3600), category: "General", priority: .low, stage: .general)
        let noSignal = TaskItem(title: "No signal", category: "General", priority: .low, stage: .general)
        let all = [overdue, dueSoon, noSignal]

        let suggested = NextMoveEngine.suggested(from: all, in: all, limit: 5, now: now)
        XCTAssertEqual(suggested.map(\.id), [overdue.id, dueSoon.id])
        XCTAssertFalse(suggested.contains { $0.id == noSignal.id })
    }

    func testSuggestedRespectsLimit() {
        let tasks = (0..<5).map { i in
            TaskItem(title: "High \(i)", category: "General", priority: .high, stage: .general)
        }
        let suggested = NextMoveEngine.suggested(from: tasks, in: tasks, limit: 2, now: now)
        XCTAssertEqual(suggested.count, 2)
    }

    func testSuggestedExcludesCompletedTasks() {
        let completed = TaskItem(title: "Done", dueDate: now.addingTimeInterval(-3600), isCompleted: true, category: "General", stage: .done)
        let suggested = NextMoveEngine.suggested(from: [completed], in: [completed], limit: 5, now: now)
        XCTAssertTrue(suggested.isEmpty)
    }

    // MARK: - wouldCreateCycle()

    func testTaskDependingOnItselfIsACycle() {
        let task = TaskItem(title: "Solo", category: "General")
        XCTAssertTrue(task.wouldCreateCycle(dependingOn: task.id, in: [task]))
    }

    func testTransitiveCycleIsDetected() {
        let a = TaskItem(title: "A", category: "General")
        let b = TaskItem(title: "B", category: "General")
        let c = TaskItem(title: "C", category: "General")
        a.dependsOnTaskID = b.id
        b.dependsOnTaskID = c.id
        let all = [a, b, c]

        // C depending on A would close the loop C -> A -> B -> C.
        XCTAssertTrue(c.wouldCreateCycle(dependingOn: a.id, in: all))
    }

    func testUnrelatedDependencyIsNotACycle() {
        let a = TaskItem(title: "A", category: "General")
        let b = TaskItem(title: "B", category: "General")
        let c = TaskItem(title: "C", category: "General")
        a.dependsOnTaskID = b.id
        let all = [a, b, c]

        XCTAssertFalse(c.wouldCreateCycle(dependingOn: a.id, in: all))
    }
}
