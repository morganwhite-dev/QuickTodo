// PlannerTests.swift
// Locks in the free-time rule and the "minutes left / done n of total" maths, so ticking
// or unticking a task can never silently create, enlarge or lose free time.

import XCTest
@testable import QuickTodo

final class PlannerTests: XCTestCase {
    private let cal = Calendar.current
    private var day: Date { cal.date(byAdding: .day, value: 3, to: cal.startOfDay(for: .now))! }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func task(_ title: String, _ due: Date?, minutes: Int = 10, done: Bool = false) -> TaskItem {
        TaskItem(title: title, dueDate: due, isCompleted: done, completedAt: done ? .now : nil, estimatedMinutes: minutes)
    }

    func testFreeBlocksAreGapsBetweenTasks() {
        let tasks = [task("a", at(12), minutes: 10), task("b", at(17), minutes: 5)]
        let blocks = Planner.freeBlocks(forDay: tasks, day: day)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].minutes, 4 * 60)              // 8:00 -> 12:00
        XCTAssertEqual(blocks[1].minutes, 4 * 60 + 50)         // 12:10 -> 17:00
    }

    func testCompletingATaskNeverChangesFreeBlocks() {
        let a = task("a", at(12)), b = task("b", at(17)), c = task("c", at(18))
        let before = Planner.freeBlocks(forDay: [a, b, c], day: day)
        for t in [a, b, c] {
            t.isCompleted = true
            XCTAssertEqual(Planner.freeBlocks(forDay: [a, b, c], day: day), before,
                           "ticking \(t.title) must not create or enlarge free time")
        }
        a.isCompleted = false
        XCTAssertEqual(Planner.freeBlocks(forDay: [a, b, c], day: day), before, "unticking restores the same layout")
    }

    func testNoTrailingBlockAfterLastTask() {
        let tasks = [task("last", at(9))]
        XCTAssertEqual(Planner.freeBlocks(forDay: tasks, day: day).map(\.minutes), [60])
    }

    func testShortGapsAreHidden() {
        let tasks = [task("a", at(8), minutes: 10), task("b", at(8, 30), minutes: 10)]
        XCTAssertTrue(Planner.freeBlocks(forDay: tasks, day: day).isEmpty)   // 20 min gap < 30
    }

    func testMinutesLeftDropsWhenTaskCompleted() {
        let a = task("a", at(9), minutes: 20), b = task("b", at(10), minutes: 35)
        XCTAssertEqual(Planner.openMinutes([a, b]), 55)
        a.isCompleted = true
        XCTAssertEqual(Planner.openMinutes([a, b]), 35)
    }

    func testWeekSummaryDoneAndMinutesTrackCompletion() {
        let soon = cal.date(byAdding: .day, value: 2, to: .now)!
        let a = task("a", soon, minutes: 15), b = task("b", soon, minutes: 25)
        var s = Planner.weekSummary([a, b])
        XCTAssertEqual([s.total, s.done, s.minutesLeft], [2, 0, 40])
        a.isCompleted = true
        s = Planner.weekSummary([a, b])
        XCTAssertEqual([s.total, s.done, s.minutesLeft], [2, 1, 25])
    }

    func testCompletedOverdueTaskStaysInTotalWhenFinishedToday() {
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now)!
        let t = task("late", yesterday, minutes: 15)
        XCTAssertEqual(Planner.weekSummary([t]).total, 1)
        XCTAssertEqual(Planner.weekSummary([t]).overdue, 1)
        t.isCompleted = true; t.completedAt = .now
        let s = Planner.weekSummary([t])
        XCTAssertEqual([s.total, s.done, s.overdue], [1, 1, 0])
    }

    func testNextMovePrefersOverdueThenSoonest() {
        let yesterday = cal.date(byAdding: .day, value: -1, to: .now)!
        let soon = cal.date(byAdding: .hour, value: 2, to: .now)!
        let late = task("late", yesterday), later = task("soon", soon), none = task("undated", nil)
        XCTAssertEqual(Planner.nextMove(from: [none, later, late])?.title, "late")
        late.isCompleted = true
        XCTAssertEqual(Planner.nextMove(from: [none, later, late])?.title, "soon")
    }
}

final class CompactDueTests: XCTestCase {
    private let cal = Calendar.current
    private func at(days: Int, hour: Int = 17, minute: Int = 30) -> Date {
        let d = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: .now))!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
    }

    func testRelativeWordsAndTimes() {
        XCTAssertTrue(Planner.compactDue(at(days: 0)).hasPrefix("Today · "))
        XCTAssertTrue(Planner.compactDue(at(days: 1)).hasPrefix("Tomorrow · "))
        XCTAssertTrue(Planner.compactDue(at(days: -1)).hasPrefix("Yesterday · "))
    }

    func testWeekdayWithinSixDaysAndDateBeyond() {
        let inThree = Planner.compactDue(at(days: 3))
        XCTAssertEqual(inThree.components(separatedBy: " · ").count, 2)
        XCTAssertEqual(inThree.components(separatedBy: " · ")[0].count, 3)   // "Tue"
        let inTwenty = Planner.compactDue(at(days: 20))
        XCTAssertTrue(inTwenty.contains("·"))
        XCTAssertGreaterThan(inTwenty.components(separatedBy: " · ")[0].count, 3) // "Nov 12"
    }

    func testDateOnlyDropsTheTime() {
        let dateOnly = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        XCTAssertEqual(Planner.compactDue(dateOnly), "Tomorrow")
    }
}
