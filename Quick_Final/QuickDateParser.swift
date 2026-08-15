// QuickDateParser.swift
// Plain-language date/category/priority parsing for Quick Capture.

import Foundation

// MARK: Date Parsing (quick entry with #category)
//
// Drop-in replacement for your existing `QuickDateParser` enum.
// Fix: an explicit month/day ("july 4th") no longer short-circuits before the
// time is parsed. Date phrase, time, and #category are now ALL stripped out of
// the title in every code path, so the title comes out clean.
//
// Examples:
//   "submit rationale quiz july 4th at 10am" -> title "submit rationale quiz", Jul 4 10:00 AM
//   "submit report june 15th at 10pm"        -> title "submit report",        Jun 15 10:00 PM
//   "Pay rent tomorrow 9am #Personal"        -> title "Pay rent",  tomorrow 9:00 AM, cat Personal
//   "call mom friday 5pm"                     -> title "call mom",  next Friday 5:00 PM
//   "review notes december 7th"              -> title "review notes", Dec 7 12:00 PM (noon default)

enum QuickDateParser {
    struct Result { let title: String; let date: Date?; let category: String?; let priority: TaskPriority? }

    static func parse(_ raw: String, now: Date = .now) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(title: "", date: nil, category: nil, priority: nil)
        }

        var working = trimmed
        let cal = Calendar.current

        // 1) Priority/category can appear at the end in either order:
        //    "Essay tomorrow #English !high" OR "Essay tomorrow !high #English".
        let firstPriority = extractPriority(&working)
        let category = extractCategory(&working)
        let priority = firstPriority ?? extractPriority(&working)

        // 3) Date phrase — explicit month/day first, then today / tomorrow / weekday.
        //    Each helper strips the matched phrase out of `working`.
        var baseDate = extractMonthDay(&working, now: now)
        if baseDate == nil { baseDate = extractRelativeDate(&working, now: now) }

        // 3.5) Time offset — "in 10 minutes", "in 2 hours", etc.
        let timeOffset = extractTimeOffset(&working)

        // 3) Time — strips the time phrase (and a leading "at"/"@") out of `working`,
        //    then applies the hour/minute onto whatever date we found.
        var finalDate = baseDate
        if let time = extractTime(&working) {
            let base = baseDate ?? now
            finalDate = cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base)
            // Time given but no explicit date, and it's already past today → roll to tomorrow.
            if baseDate == nil, let d = finalDate, d < now {
                finalDate = cal.date(byAdding: .day, value: 1, to: d)
            }
        }

        // Apply time offset if specified
        if let offset = timeOffset {
            let base = finalDate ?? now
            finalDate = cal.date(byAdding: offset.unit, value: offset.value, to: base)
        }

        let title = cleanup(working)
        // If parsing consumed the entire input (e.g. the whole capture was just "#Work"),
        // fall back to the category name rather than the raw "#Work" text.
        let fallbackTitle = category ?? trimmed
        return Result(
            title: capitalizedFirst(title.isEmpty ? fallbackTitle : title),
            date: finalDate,
            category: category.map(capitalizedFirst),
            priority: priority
        )
    }

    // Capitalizing here (the parsed result) rather than the raw text field is the
    // only way this works reliably — whatever ends up as the title is often not at
    // the start of what was typed (date/tag/priority words get stripped from
    // anywhere), so capitalizing index 0 of the raw input would usually capitalize
    // a word that's about to be removed, not the actual title.
    private static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }

    private static func extractPriority(_ working: inout String) -> TaskPriority? {
        // (?:^|\s) so a marker with nothing before it (just "!high" on its own) still
        // matches, not only when it follows other words. (?=\s|$) instead of \s*$ so
        // it's recognized anywhere in the input ("!high call mom" and "call mom !high"
        // parse the same) — a lookahead instead of a trailing match so it doesn't
        // consume the space after it, and so "!highlight the issue" correctly isn't
        // mistaken for "!high" followed by more text.
        let patterns: [String: TaskPriority] = [
            #"(?i)(?:^|\s)!high(?=\s|$)"#: .high,
            #"(?i)(?:^|\s)!medium(?=\s|$)"#: .medium,
            #"(?i)(?:^|\s)!low(?=\s|$)"#: .low,
            #"(?:^|\s)!!(?=\s|$)"#: .high,
            #"(?:^|\s)!(?=\s|$)"#: .low,

            #"(?i)(?:^|\s)(?:high\s+priority|priority\s+high)(?=\s|$)"#: .high,
            #"(?i)(?:^|\s)(?:medium\s+priority|priority\s+medium)(?=\s|$)"#: .medium,
            #"(?i)(?:^|\s)(?:low\s+priority|priority\s+low)(?=\s|$)"#: .low,
            #"(?i)(?:^|\s)(?:urgent|important|asap)(?=\s|$)"#: .high
        ]

        let ns = working as NSString
        let full = NSRange(location: 0, length: ns.length)

        for (pattern, priority) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            if let match = regex.firstMatch(in: working, range: full) {
                working = ns.replacingCharacters(in: match.range, with: "")
                return priority
            }
        }

        return nil
    }

    // MARK: - #category

    private static func extractCategory(_ working: inout String) -> String? {
        // No trailing $ anchor on any of these — a tag should be recognized wherever it
        // appears ("#school tomorrow 1am" and "tomorrow 1am #school" must parse the same),
        // not just when it happens to be the last thing typed. The bracket/quote forms are
        // safe to match anywhere since their own delimiter bounds the tag. The bare form
        // (no brackets/quotes) is always a single word, regardless of position — there used
        // to be a second bare pattern that allowed multiple words when the tag was at the
        // very end, but with no delimiter to mark where it stopped, it would also match
        // "#Work submit report" as one giant category ("Work submit report"), swallowing
        // the actual title. Multi-word categories need #[...] or #"..." now — unambiguous
        // wherever they appear, which a bare multi-word form never could be.
        let tagPatterns: [String] = [
            #"(?i)(?:^|\s)#\[(.+?)\]"#,           // #[Senior Seminar], anywhere
            #"(?i)(?:^|\s)#\"(.+?)\""#,           // #"Senior Seminar", anywhere
            #"(?i)(?:^|\s)#([a-z0-9_-]+)"#        // #school, single word, anywhere
        ]
        for p in tagPatterns {
            guard let r = try? NSRegularExpression(pattern: p) else { continue }
            let ns = working as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let m = r.firstMatch(in: working, range: full), m.numberOfRanges >= 2 {
                let tag = ns.substring(with: m.range(at: 1))
                working = ns.replacingCharacters(in: m.range, with: "")
                return tag.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    // MARK: - Explicit month/day ("july 4th", "march 3 2027", typo "decemeber")

    private static func extractMonthDay(_ working: inout String, now: Date) -> Date? {
        let pattern = #"(?i)\b(january|february|march|april|may|june|july|august|september|october|november|december|decemeber)\s+(\d{1,2})(st|nd|rd|th)?(,?\s+(\d{4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = working as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: working, range: full) else { return nil }

        let monthName = ns.substring(with: match.range(at: 1)).lowercased()
        let dayString = ns.substring(with: match.range(at: 2))
        let yearString: String? = match.range(at: 5).location != NSNotFound
            ? ns.substring(with: match.range(at: 5)) : nil

        let months: [String: Int] = [
            "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
            "july": 7, "august": 8, "september": 9, "october": 10, "november": 11,
            "december": 12, "decemeber": 12 // typo support
        ]
        guard let month = months[monthName], let day = Int(dayString) else { return nil }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.month = month
        comps.day = day
        comps.hour = 12; comps.minute = 0; comps.second = 0   // default noon; overridden if a time is found
        if let yStr = yearString, let y = Int(yStr) { comps.year = y }

        var date = cal.date(from: comps)
        // No explicit year and the date already passed this year → assume next year.
        if yearString == nil, let d = date, d < now {
            comps.year = (comps.year ?? cal.component(.year, from: now)) + 1
            date = cal.date(from: comps)
        }
        guard let finalDate = date else { return nil }

        working = ns.replacingCharacters(in: match.range, with: " ")
        return finalDate
        
    }

    // MARK: - Relative dates (today / tomorrow / weekday)

    private static func extractRelativeDate(_ working: inout String, now: Date) -> Date? {
        let cal = Calendar.current

        func noon(_ date: Date) -> Date {
            cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        }
        @discardableResult
        func strip(_ pattern: String) -> Bool {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
            let ns = working as NSString
            let full = NSRange(location: 0, length: ns.length)
            guard let m = re.firstMatch(in: working, range: full) else { return false }
            working = ns.replacingCharacters(in: m.range, with: " ")
            return true
        }

        if strip(#"(?i)\btomorrow\b"#) {
            return noon(cal.date(byAdding: .day, value: 1, to: now) ?? now)
        }
        if strip(#"(?i)\btoday\b"#) {
            return noon(now)
        }

        // Full names FIRST so "monday" isn't half-eaten by the "mon" abbreviation.
        let weekdays: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7),
            ("sun", 1), ("mon", 2), ("tues", 3), ("tue", 3), ("wed", 4),
            ("thurs", 5), ("thu", 5), ("fri", 6), ("sat", 7)
        ]
        for (name, index) in weekdays {
            if strip(#"(?i)\b(?:on\s+|next\s+)?"# + name + #"\b"#) {
                guard let d = next(index, now: now) else { return nil }
                return noon(d)
            }
        }
        return nil
    }

    private static func next(_ weekday: Int, now: Date) -> Date? {
        let cal = Calendar.current
        let today = cal.component(.weekday, from: now) // 1=Sun ... 7=Sat
        var offset = weekday - today
        if offset <= 0 { offset += 7 }                 // always the NEXT occurrence
        return cal.date(byAdding: .day, value: offset, to: now)
    }

    // MARK: - Time ("10am", "10:30 pm", "at 9am", "@5pm", "14:30")

    private static func extractTime(_ working: inout String) -> (hour: Int, minute: Int)? {
        // Colon form first so "10:30" isn't half-matched by the bare-hour pattern.
        // A leading "at " or "@" is consumed so it doesn't linger in the title.
        let withMinutes = #"(?i)(?:\bat\s+|@\s*)?\b(\d{1,2}):(\d{2})\s*(am|pm)?\b"#
        let bareHour    = #"(?i)(?:\bat\s+|@\s*)?\b(\d{1,2})\s*(am|pm)\b"#

        let ns = working as NSString
        let full = NSRange(location: 0, length: ns.length)

        if let re = try? NSRegularExpression(pattern: withMinutes),
           let m = re.firstMatch(in: working, range: full), m.numberOfRanges >= 4 {
            let h = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let mn = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let ampm = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : nil
            working = ns.replacingCharacters(in: m.range, with: " ")
            return normalize(hour: h, minute: mn, ampm: ampm)
        }

        if let re = try? NSRegularExpression(pattern: bareHour),
           let m = re.firstMatch(in: working, range: full), m.numberOfRanges >= 3 {
            let h = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let ampm = ns.substring(with: m.range(at: 2))
            working = ns.replacingCharacters(in: m.range, with: " ")
            return normalize(hour: h, minute: 0, ampm: ampm)
        }
        return nil
    }

    private static func normalize(hour: Int, minute: Int, ampm: String?) -> (hour: Int, minute: Int) {
        var h = hour % 24
        let m = minute % 60
        if let ampm = ampm?.lowercased() {
            if ampm == "am" { if h == 12 { h = 0 } }
            else if ampm == "pm" { if h < 12 { h += 12 } }
        }
        return (h, m)
    }

    // MARK: - Time offset ("in 10 minutes", "in two hours", etc.)

    private static func extractTimeOffset(_ working: inout String) -> (unit: Calendar.Component, value: Int)? {
        let numberWords: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
            "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60
        ]
        let wordPattern = numberWords.keys.joined(separator: "|")
        let pattern = #"(?i)\bin\s+(?:(\d+)|("# + wordPattern + #"))\s+(second|minute|hour|day)s?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let ns = working as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: working, range: full), match.numberOfRanges >= 4 else {
            return nil
        }

        var value: Int?
        // Try digit form first
        if match.range(at: 1).location != NSNotFound {
            value = Int(ns.substring(with: match.range(at: 1)))
        }
        // Then try word form
        else if match.range(at: 2).location != NSNotFound {
            let word = ns.substring(with: match.range(at: 2)).lowercased()
            value = numberWords[word]
        }

        guard let finalValue = value else { return nil }
        let unit = ns.substring(with: match.range(at: 3)).lowercased()

        let component: Calendar.Component
        switch unit {
        case "second": component = .second
        case "minute": component = .minute
        case "hour": component = .hour
        case "day": component = .day
        default: return nil
        }

        working = ns.replacingCharacters(in: match.range, with: " ")
        return (component, finalValue)
    }

    // MARK: - Title cleanup

    private static func cleanup(_ s: String) -> String {
        var out = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove a dangling connector left at the end (e.g. "submit report at").
        out = out.replacingOccurrences(of: #"(?i)\s*(?:\bat\b|@)\s*$"#, with: "", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#if DEBUG
enum QuickDateParserSelfTest {
    private struct ExpectedDate {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
    }

    private struct Case {
        let input: String
        let expectedTitle: String
        let expectedCategory: String?
        let expectedPriority: TaskPriority?
        let expectedDate: ExpectedDate?
    }

    static func run() {
        let calendar = Calendar.current

        guard let fixedNow = calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 10,
            hour: 9,
            minute: 0,
            second: 0
        )) else {
            print("[ParserTest] Could not create fixed test date.")
            return
        }

        let cases: [Case] = [
            Case(
                input: "essay friday 11:59pm #English !high",
                expectedTitle: "Essay",
                expectedCategory: "English",
                expectedPriority: .high,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 12, hour: 23, minute: 59)
            ),
            Case(
                input: "pay rent tomorrow 9am #Bills !medium",
                expectedTitle: "Pay rent",
                expectedCategory: "Bills",
                expectedPriority: .medium,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 11, hour: 9, minute: 0)
            ),
            Case(
                input: "gym #Fitness !low",
                expectedTitle: "Gym",
                expectedCategory: "Fitness",
                expectedPriority: .low,
                expectedDate: nil
            ),
            Case(
                input: "call mom in 10 minutes",
                expectedTitle: "Call mom",
                expectedCategory: nil,
                expectedPriority: nil,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 10, hour: 9, minute: 10)
            ),
            Case(
                input: "submit report june 15th at 10pm #Work",
                expectedTitle: "Submit report",
                expectedCategory: "Work",
                expectedPriority: nil,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 15, hour: 22, minute: 0)
            ),
            Case(
                input: "project next monday #Schoolwork",
                expectedTitle: "Project",
                expectedCategory: "Schoolwork",
                expectedPriority: nil,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
            ),
            Case(
                input: #"quiz tomorrow 5pm #"Senior Seminar" !high"#,
                expectedTitle: "Quiz",
                expectedCategory: "Senior Seminar",
                expectedPriority: .high,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 11, hour: 17, minute: 0)
            ),
            Case(
                input: "#Work",
                expectedTitle: "Work",
                expectedCategory: "Work",
                expectedPriority: nil,
                expectedDate: nil
            ),
            Case(
                input: "test task #school tomorrow 1am",
                expectedTitle: "Test task",
                expectedCategory: "School",
                expectedPriority: nil,
                expectedDate: ExpectedDate(year: 2026, month: 6, day: 11, hour: 1, minute: 0)
            ),
            Case(
                input: "#Work submit report",
                expectedTitle: "Submit report",
                expectedCategory: "Work",
                expectedPriority: nil,
                expectedDate: nil
            ),
            Case(
                input: "!high call mom",
                expectedTitle: "Call mom",
                expectedCategory: nil,
                expectedPriority: .high,
                expectedDate: nil
            )
        ]

        print("──────── QuickDateParser Self-Test ────────")

        var passed = 0

        for testCase in cases {
            let result = QuickDateParser.parse(testCase.input, now: fixedNow)

            let titleOK = result.title == testCase.expectedTitle
            let categoryOK = result.category == testCase.expectedCategory
            let priorityOK = result.priority == testCase.expectedPriority
            let dateOK = matches(result.date, expected: testCase.expectedDate, calendar: calendar)

            if titleOK && categoryOK && priorityOK && dateOK {
                passed += 1
                print("✅ [ParserTest] \(testCase.input)")
            } else {
                print("❌ [ParserTest] \(testCase.input)")
                print("   title:    expected '\(testCase.expectedTitle)', got '\(result.title)'")
                print("   category: expected '\(testCase.expectedCategory ?? "nil")', got '\(result.category ?? "nil")'")
                print("   priority: expected '\(testCase.expectedPriority?.rawValue ?? "nil")', got '\(result.priority?.rawValue ?? "nil")'")
                print("   date:     expected '\(dateDescription(testCase.expectedDate))', got '\(dateDescription(result.date, calendar: calendar))'")
            }
        }

        print("[ParserTest] \(passed)/\(cases.count) passed")
        print("──────────────────────────────────────────")
    }

    private static func matches(_ date: Date?, expected: ExpectedDate?, calendar: Calendar) -> Bool {
        if date == nil && expected == nil {
            return true
        }

        guard let date, let expected else {
            return false
        }

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        return components.year == expected.year &&
            components.month == expected.month &&
            components.day == expected.day &&
            components.hour == expected.hour &&
            components.minute == expected.minute
    }

    private static func dateDescription(_ expected: ExpectedDate?) -> String {
        guard let expected else { return "nil" }
        return "\(expected.year)-\(expected.month)-\(expected.day) \(expected.hour):\(String(format: "%02d", expected.minute))"
    }

    private static func dateDescription(_ date: Date?, calendar: Calendar) -> String {
        guard let date else { return "nil" }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0) \(components.hour ?? 0):\(String(format: "%02d", components.minute ?? 0))"
    }
}
#endif
