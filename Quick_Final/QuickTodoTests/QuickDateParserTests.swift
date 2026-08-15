// QuickDateParserTests.swift
// Promotes the existing QuickDateParserSelfTest DEBUG cases into real, build-failing
// XCTest assertions, and adds coverage for code paths the self-test never exercised
// (word-form time offsets, priority synonyms, empty input, year-rollover for past dates).

import XCTest
@testable import QuickTodo

final class QuickDateParserTests: XCTestCase {
    // Wednesday, June 10, 2026, 9:00 AM — matches the self-test's fixed "now".
    private let fixedNow: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 10
        comps.hour = 9; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps)!
    }()

    private struct ExpectedDate {
        let year: Int, month: Int, day: Int, hour: Int, minute: Int
    }

    private func assertParses(
        _ input: String,
        title: String,
        category: String? = nil,
        priority: TaskPriority? = nil,
        date expected: ExpectedDate? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let result = QuickDateParser.parse(input, now: fixedNow)
        XCTAssertEqual(result.title, title, "title for '\(input)'", file: file, line: line)
        XCTAssertEqual(result.category, category, "category for '\(input)'", file: file, line: line)
        XCTAssertEqual(result.priority, priority, "priority for '\(input)'", file: file, line: line)

        guard let expected else {
            XCTAssertNil(result.date, "expected no date for '\(input)'", file: file, line: line)
            return
        }
        guard let date = result.date else {
            XCTFail("expected a date for '\(input)' but got nil", file: file, line: line)
            return
        }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(comps.year, expected.year, "year for '\(input)'", file: file, line: line)
        XCTAssertEqual(comps.month, expected.month, "month for '\(input)'", file: file, line: line)
        XCTAssertEqual(comps.day, expected.day, "day for '\(input)'", file: file, line: line)
        XCTAssertEqual(comps.hour, expected.hour, "hour for '\(input)'", file: file, line: line)
        XCTAssertEqual(comps.minute, expected.minute, "minute for '\(input)'", file: file, line: line)
    }

    // MARK: - Ported from QuickDateParserSelfTest

    func testHighPriorityTagAndExplicitTime() {
        assertParses(
            "essay friday 11:59pm #English !high",
            title: "Essay", category: "English", priority: .high,
            date: ExpectedDate(year: 2026, month: 6, day: 12, hour: 23, minute: 59)
        )
    }

    func testTomorrowMorningWithTagAndMediumPriority() {
        assertParses(
            "pay rent tomorrow 9am #Bills !medium",
            title: "Pay rent", category: "Bills", priority: .medium,
            date: ExpectedDate(year: 2026, month: 6, day: 11, hour: 9, minute: 0)
        )
    }

    func testTagAndPriorityWithNoDate() {
        assertParses("gym #Fitness !low", title: "Gym", category: "Fitness", priority: .low)
    }

    func testDigitFormMinuteOffset() {
        assertParses(
            "call mom in 10 minutes",
            title: "Call mom",
            date: ExpectedDate(year: 2026, month: 6, day: 10, hour: 9, minute: 10)
        )
    }

    func testExplicitMonthDayWithTimeAndTag() {
        assertParses(
            "submit report june 15th at 10pm #Work",
            title: "Submit report", category: "Work",
            date: ExpectedDate(year: 2026, month: 6, day: 15, hour: 22, minute: 0)
        )
    }

    func testNextWeekdayDefaultsToNoon() {
        assertParses(
            "project next monday #Schoolwork",
            title: "Project", category: "Schoolwork",
            date: ExpectedDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
        )
    }

    func testQuotedMultiWordCategory() {
        assertParses(
            #"quiz tomorrow 5pm #"Senior Seminar" !high"#,
            title: "Quiz", category: "Senior Seminar", priority: .high,
            date: ExpectedDate(year: 2026, month: 6, day: 11, hour: 17, minute: 0)
        )
    }

    func testCategoryOnlyInputFallsBackToCategoryAsTitle() {
        assertParses("#Work", title: "Work", category: "Work")
    }

    func testCategoryAndDateBeforeTitleText() {
        assertParses(
            "test task #school tomorrow 1am",
            title: "Test task", category: "School",
            date: ExpectedDate(year: 2026, month: 6, day: 11, hour: 1, minute: 0)
        )
    }

    func testCategoryBeforeTitleNoDate() {
        assertParses("#Work submit report", title: "Submit report", category: "Work")
    }

    func testLeadingPriorityMarker() {
        assertParses("!high call mom", title: "Call mom", priority: .high)
    }

    // MARK: - Additional coverage beyond the original DEBUG self-test

    func testWordFormTimeOffset() {
        // Exercises the numberWords dictionary branch of extractTimeOffset, which the
        // original self-test never hit (it only covered the digit form "in 10 minutes").
        assertParses(
            "stretch in two hours",
            title: "Stretch",
            date: ExpectedDate(year: 2026, month: 6, day: 10, hour: 11, minute: 0)
        )
    }

    func testUrgentSynonymMapsToHighPriority() {
        assertParses("call the bank urgent", title: "Call the bank", priority: .high)
    }

    func testDoubleBangIsHighPriority() {
        assertParses("renew passport !!", title: "Renew passport", priority: .high)
    }

    func testEmptyInputProducesEmptyResult() {
        let result = QuickDateParser.parse("   ", now: fixedNow)
        XCTAssertEqual(result.title, "")
        XCTAssertNil(result.date)
        XCTAssertNil(result.category)
        XCTAssertNil(result.priority)
    }

    func testMonthDayInThePastRollsToNextYear() {
        // fixedNow is June 10, 2026 — "march 3rd" has already passed this year, so the
        // parser should infer March 3, 2027 rather than a date in the past.
        assertParses(
            "renew license march 3rd",
            title: "Renew license",
            date: ExpectedDate(year: 2027, month: 3, day: 3, hour: 12, minute: 0)
        )
    }
}
