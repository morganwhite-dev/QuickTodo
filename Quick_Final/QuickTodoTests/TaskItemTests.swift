// TaskItemTests.swift
// Covers TaskItem's inference logic (planningEstimate, dependency blocking, calibration,
// recurrence) and the ModelContext.saveOrReport() error-surfacing helper — none of this
// had any test coverage before.

import XCTest
import SwiftData
@testable import QuickTodo

final class TaskItemTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, CategoryItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    // MARK: - planningEstimate

    func testExplicitEstimateWins() {
        let task = TaskItem(title: "Anything", category: "General", estimatedMinutes: 45)
        let estimate = task.planningEstimate
        XCTAssertEqual(estimate.minutes, 45)
        XCTAssertEqual(estimate.source, .explicit)
        XCTAssertFalse(estimate.isInferred)
    }

    func testSubtaskCountDrivesEstimateWhenNoExplicitValue() {
        let task = TaskItem(
            title: "Plan trip", category: "General",
            subtasks: [Subtask(title: "Book flights"), Subtask(title: "Book hotel"), Subtask(title: "Pack")]
        )
        // 20 base + 3 subtasks * 15 = 65, already a multiple of 5.
        XCTAssertEqual(task.planningEstimate.minutes, 65)
        XCTAssertEqual(task.planningEstimate.source, .subtasks)
    }

    func testResearchWordingInflatesEstimate() {
        let task = TaskItem(title: "Research the new tax law", category: "General")
        // 25 base + 50 (research) + 2 (5-word title) = 77 -> rounds to 75.
        XCTAssertEqual(task.planningEstimate.minutes, 75)
        XCTAssertEqual(task.planningEstimate.source, .wording)
    }

    func testShortActionWordingReducesEstimate() {
        let task = TaskItem(title: "Email the landlord", category: "General")
        // 25 base - 10 (quick action) = 15.
        XCTAssertEqual(task.planningEstimate.minutes, 15)
        XCTAssertEqual(task.planningEstimate.source, .wording)
    }

    func testNoSignalFallsBackToDefaultPlanning() {
        let task = TaskItem(title: "Think", category: "General")
        XCTAssertEqual(task.planningEstimate.minutes, 25)
        XCTAssertEqual(task.planningEstimate.source, .defaultPlanning)
    }

    // MARK: - isQuickWin

    func testShortTaskWithNoSubtasksIsAQuickWin() {
        let task = TaskItem(title: "Quick", category: "General", estimatedMinutes: 15)
        XCTAssertTrue(task.isQuickWin)
    }

    func testTaskWithSubtasksIsNeverAQuickWinRegardlessOfEstimate() {
        let task = TaskItem(
            title: "Quick but tracked", category: "General",
            subtasks: [Subtask(title: "One step")], estimatedMinutes: 10
        )
        XCTAssertFalse(task.isQuickWin)
    }

    func testCompletedTaskIsNeverAQuickWin() {
        let task = TaskItem(title: "Done", isCompleted: true, category: "General", estimatedMinutes: 5)
        XCTAssertFalse(task.isQuickWin)
    }

    // MARK: - Dependency blocking

    func testTaskIsBlockedByAnIncompleteDependency() {
        let blocker = TaskItem(title: "Blocker", category: "General")
        let dependent = TaskItem(title: "Dependent", category: "General")
        dependent.dependsOnTaskID = blocker.id

        XCTAssertTrue(dependent.isBlocked(in: [blocker, dependent]))
        XCTAssertEqual(blocker.blockedTasks(in: [blocker, dependent]).map(\.id), [dependent.id])
        XCTAssertEqual(blocker.blockedTaskCount(in: [blocker, dependent]), 1)
    }

    func testTaskIsUnblockedOnceDependencyCompletes() {
        let blocker = TaskItem(title: "Blocker", isCompleted: true, category: "General")
        let dependent = TaskItem(title: "Dependent", category: "General")
        dependent.dependsOnTaskID = blocker.id

        XCTAssertFalse(dependent.isBlocked(in: [blocker, dependent]))
    }

    func testTaskIsUnblockedIfDependencyNoLongerExists() {
        let dependent = TaskItem(title: "Dependent", category: "General")
        dependent.dependsOnTaskID = UUID()
        XCTAssertFalse(dependent.isBlocked(in: [dependent]))
    }

    // MARK: - calibrationRatio

    func testCalibrationRatioRequiresAtLeastThreeDataPoints() {
        let now = Date()
        func calibrated(minutesActual: Int) -> TaskItem {
            TaskItem(
                title: "Work item", isCompleted: true, completedAt: now.addingTimeInterval(Double(minutesActual) * 60),
                category: "Work", estimatedMinutes: 60, startedAt: now
            )
        }
        let twoTasks = [calibrated(minutesActual: 90), calibrated(minutesActual: 90)]
        XCTAssertNil(TaskItem.calibrationRatio(forCategory: "Work", in: twoTasks))

        let threeTasks = twoTasks + [calibrated(minutesActual: 90)]
        // Each task took 90 actual minutes against a 60-minute estimate -> ratio 1.5.
        XCTAssertEqual(TaskItem.calibrationRatio(forCategory: "Work", in: threeTasks) ?? 0, 1.5, accuracy: 0.001)
    }

    // MARK: - Recurrence

    func testWeekdaysRecurrenceSkipsTheWeekend() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 12 // Friday
        let friday = Calendar.current.date(from: comps)!

        let next = RecurrenceRule.weekdays.nextDate(after: friday)
        let nextComps = Calendar.current.dateComponents([.year, .month, .day], from: next)
        // Should land on Monday the 15th, not Saturday the 13th.
        XCTAssertEqual(nextComps.day, 15)
    }

    func testSpawnNextOccurrenceAdvancesDueDateAndCarriesFields() throws {
        let context = try makeInMemoryContext()
        let due = Date()
        let original = TaskItem(
            title: "Water plants", dueDate: due, category: "Home",
            priority: .medium, recurrenceRule: .daily, stage: .scheduled
        )
        context.insert(original)

        let next = original.spawnNextOccurrence(in: context)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.title, "Water plants")
        XCTAssertEqual(next?.category, "Home")
        XCTAssertEqual(next?.stage, .scheduled)
        XCTAssertFalse(next?.isCompleted ?? true)
        if let nextDue = next?.dueDate {
            XCTAssertEqual(Calendar.current.dateComponents([.day], from: due, to: nextDue).day, 1)
        } else {
            XCTFail("expected the spawned occurrence to have a due date")
        }
    }

    func testNonRecurringTaskDoesNotSpawnAnOccurrence() throws {
        let context = try makeInMemoryContext()
        let task = TaskItem(title: "One-off", dueDate: Date(), category: "General")
        context.insert(task)
        XCTAssertNil(task.spawnNextOccurrence(in: context))
    }

    // MARK: - ModelContext.saveOrReport()

    func testSaveOrReportReturnsTrueAndPostsNothingOnSuccess() throws {
        let context = try makeInMemoryContext()
        context.insert(TaskItem(title: "Saveable", category: "General"))

        let expectation = expectation(forNotification: .quickToDoSaveFailed, object: nil, handler: nil)
        expectation.isInverted = true

        XCTAssertTrue(context.saveOrReport())
        wait(for: [expectation], timeout: 0.2)
    }
}
