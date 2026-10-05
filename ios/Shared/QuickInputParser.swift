import Foundation

/// Rule-based parser for one line of typed or dictated text, e.g. "明天下午三点牙医" or
/// "tomorrow 9:30 run 45m". A Swift port of `parseQuickInput` in src/task-model.js, extended for
/// speech: 后天, 上午/下午/晚上, am/pm, "3点半" and spoken durations. No time found means Inbox.
enum QuickInputParser {
    struct Result: Equatable {
        var date: String?
        var start: Int?
        var end: Int?
        var title: String
        var duration: Int
        var hasExplicitTime: Bool
        /// The day that was named, kept even when there is no time and the task goes to the Inbox.
        var day: String? = nil

        static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.date == rhs.date && lhs.start == rhs.start && lhs.end == rhs.end && lhs.title == rhs.title && lhs.duration == rhs.duration && lhs.hasExplicitTime == rhs.hasExplicitTime
        }
    }

    static func parse(_ text: String, dateKey: String? = nil, now: Date = .now) -> Result {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDate = dateKey.flatMap { DateFormatter.dayKey.date(from: $0) } ?? now
        var remainder = original.replacingOccurrences(of: "：", with: ":")
        // Dictation often ends the sentence for us.
        while let last = remainder.last, "。.!！,，".contains(last) { remainder.removeLast() }
        remainder = stripFiller(remainder)

        var day: Date?
        if let match = firstMatch("^(今晚|tonight\\b)\\s*", in: remainder) {
            // "今晚 8点" keeps its evening meaning for the time step below.
            day = baseDate
            remainder = "晚上" + String(remainder.dropFirst(match[0]!.count))
        } else if let (found, rest) = DatePhrase.leading(in: remainder, now: baseDate) {
            day = found
            remainder = stripFiller(rest)
        }

        var duration = 30
        // "一个半小时" / "2个半小时"
        if let match = firstMatch("(\\d+|[零一二三四五六七八九十两]+)\\s*个半\\s*小时\\s*$", in: remainder), let hours = chineseNumber(match[1] ?? "") {
            duration = max(15, min(8 * 60, hours * 60 + 30))
            remainder = String(remainder.dropLast(match[0]!.count)).trimmingCharacters(in: .whitespaces)
        } else if let match = firstMatch("(\\d+(?:\\.5)?|半|[零一二三四五六七八九十两]+)\\s*个?\\s*(m|mins?|minutes?|分钟|h|hrs?|hours?|小时)\\s*$", in: remainder), let amount = durationAmount(match[1] ?? "") {
            let unit = (match[2] ?? "").lowercased()
            let minutes = unit.hasPrefix("h") || unit == "小时" ? amount * 60 : amount
            duration = max(15, min(8 * 60, Int((minutes / 15).rounded()) * 15))
            remainder = String(remainder.dropLast(match[0]!.count)).trimmingCharacters(in: .whitespaces)
        }

        var start: Int?
        if let (minute, rest) = parseTime(remainder) {
            start = clampMinute(minute)
            remainder = rest.trimmingCharacters(in: .whitespaces)
        }

        remainder = stripFiller(remainder)
        let hasExplicitTime = start != nil
        return Result(date: hasExplicitTime ? (day ?? baseDate).dayKey : nil, start: start, end: start.map { $0 + duration }, title: remainder.isEmpty ? original : remainder, duration: duration, hasExplicitTime: hasExplicitTime, day: day?.dayKey)
    }

    /// Minutes from midnight for a spoken time on its own ("下午三点", "3pm", "9:30"), or nil.
    static func minute(fromTimePhrase phrase: String) -> Int? {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "：", with: ":")
        // parseTime wants something after a bare English time; give it a placeholder.
        return (parseTime(text) ?? parseTime(text + " x")).map { clampMinute($0.0) }
    }

    /// Drops lead-ins that are about the request, not the task: "帮我添加一个", "提醒我", "remind me to".
    static func stripFiller(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespaces)
        for pattern in ["^(请)?(帮我|给我|麻烦)?(添加|加上|加|新建|创建|安排|记一下|记下|记)(一个|一下|个|一条|条)?(日程|任务|提醒|待办)?[，,：:\\s]*", "^(提醒我|记得|别忘了)(一下)?(要|去)?[，,：:\\s]*", "^(please\\s+)?(add|create|schedule)\\s+(a\\s+)?(task|reminder|event)?\\s*(to|for|:)?\\s+", "^remind me\\s+(to\\s+)?"] {
            if let match = firstMatch(pattern, in: value), let whole = match[0], whole.count < value.count { value = String(value.dropFirst(whole.count)) }
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    static func mentionsReminder(_ text: String) -> Bool {
        firstMatch("提醒|别忘|叫我|通知我|remind|don't let me forget", in: text) != nil
    }

    // MARK: Time

    private static let periods = "凌晨|早上|早晨|上午|中午|下午|傍晚|晚上"
    private static let numerals = "零一二三四五六七八九十两"

    /// Returns minutes from midnight and the text after the time, or nil when the text does not start with a time.
    private static func parseTime(_ text: String) -> (Int, String)? {
        var body = text
        var period: String?
        if let match = firstMatch("^(\(periods))\\s*", in: body) {
            period = match[1]
            body = String(body.dropFirst(match[0]!.count))
        }

        // 3点 / 三点半 / 3点15分 / 十点一刻
        if let match = firstMatch("^(\\d{1,2}|[\(numerals)]+)\\s*(?:点|點|时|時)\\s*(半|一刻|三刻|\\d{1,2}|[\(numerals)]+)?\\s*分?\\s*(.*)$", in: body), let hour = chineseNumber(match[1] ?? "") {
            let minute: Int?
            switch match[2] {
            case nil, "": minute = 0
            case "半": minute = 30
            case "一刻": minute = 15
            case "三刻": minute = 45
            case let value?: minute = chineseNumber(value)
            }
            if let minute, let resolved = resolve(hour: hour, minute: minute, period: period) { return (resolved, match[3] ?? "") }
        }

        // 9:30 / at 9 / 3pm / 3:15 pm. A bare hour needs "at", am/pm, or a space before the title,
        // so "3个苹果" is not read as 3:00.
        if let match = firstMatch("^(at\\s*)?(\\d{1,2})(?::(\\d{2}))?\\s*(a\\.?m\\.?|p\\.?m\\.?)?(\\s*)(.+)$", in: body), let hour = Int(match[2] ?? "") {
            let hasAt = match[1] != nil, hasColon = match[3] != nil, meridiem = match[4]?.lowercased(), hasSpace = !(match[5] ?? "").isEmpty
            if hasAt || hasColon || meridiem != nil || hasSpace || period != nil {
                let englishPeriod = meridiem.map { $0.hasPrefix("p") ? "pm" : "am" }
                if let resolved = resolve(hour: hour, minute: Int(match[3] ?? "0") ?? 0, period: englishPeriod ?? period) { return (resolved, match[6] ?? "") }
            }
        }
        return nil
    }

    private static func resolve(hour: Int, minute: Int, period: String?) -> Int? {
        guard hour <= 23, minute <= 59 else { return nil }
        var hour = hour
        switch period {
        case "下午", "傍晚", "晚上", "pm": if hour < 12 { hour += 12 }
        case "中午": if hour < 11 { hour += 12 }
        case "凌晨", "早上", "早晨", "上午", "am": if hour == 12 { hour = 0 }
        default: break
        }
        return hour * 60 + minute
    }

    private static func clampMinute(_ minute: Int) -> Int {
        max(0, min(24 * 60, Int((Double(minute) / 15).rounded()) * 15))
    }

    // MARK: Numbers

    private static func durationAmount(_ value: String) -> Double? {
        if value == "半" { return 0.5 }
        if let number = Double(value) { return number }
        return chineseNumber(value).map(Double.init)
    }

    static func chineseNumber(_ value: String) -> Int? {
        if let number = Int(value) { return number }
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let characters = Array(value)
        if characters.count == 1, let digit = digits[characters[0]] { return digit }
        if value == "十" { return 10 }
        guard let tenIndex = characters.firstIndex(of: "十") else { return nil }
        let tens = tenIndex == 0 ? 1 : digits[characters[0]]
        let ones = tenIndex == characters.count - 1 ? 0 : digits[characters[tenIndex + 1]]
        guard let tens, let ones else { return nil }
        return tens * 10 + ones
    }

    // MARK: Regex

    /// Capture groups of the first match (index 0 is the whole match); unmatched groups are nil.
    static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}

/// Resolves a spoken day ("明天", "10月23日", "下周三", "Friday", "Oct 23") with calendar math.
/// Language models are unreliable at this, so it is always done here.
enum DatePhrase {
    private static let numerals = "零一二三四五六七八九十两"
    private static let weekdays: [String: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
    private static let englishWeekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
    private static let englishMonths = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    /// A day phrase on its own.
    static func resolve(_ phrase: String, now: Date) -> Date? {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let (date, rest) = leading(in: text, now: now), rest.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return date
    }

    /// A day phrase at the start of `text`, and what follows it.
    static func leading(in text: String, now: Date) -> (Date, String)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        func rest(_ match: [String?]) -> String { String(text.dropFirst(match[0]!.count)) }
        func day(_ offset: Int) -> Date? { calendar.date(byAdding: .day, value: offset, to: today) }
        let match = { (pattern: String) in QuickInputParser.firstMatch(pattern, in: text) }

        for (pattern, offset) in [("^(今天|today\\b)\\s*", 0), ("^(明天|tomorrow\\b)\\s*", 1), ("^(大后天)\\s*", 3), ("^(后天|後天|the day after tomorrow\\b)\\s*", 2)] {
            if let found = match(pattern), let date = day(offset) { return (date, rest(found)) }
        }

        // 10月23日 / 十月二十三号 / 2027年1月5日; a day that has passed this year means next year.
        if let found = match("^(?:(\\d{4})年)?(\\d{1,2}|[\(numerals)]+)月(\\d{1,2}|[\(numerals)]+)[日号號]?\\s*"), let month = QuickInputParser.chineseNumber(found[2] ?? ""), let dayNumber = QuickInputParser.chineseNumber(found[3] ?? ""), let date = monthDay(month: month, day: dayNumber, year: found[1].flatMap(Int.init), today: today) { return (date, rest(found)) }
        // 23号: this month, or next month if it has passed.
        if let found = match("^(\\d{1,2}|[\(numerals)]+)[号號]\\s*"), let dayNumber = QuickInputParser.chineseNumber(found[1] ?? "") {
            var components = calendar.dateComponents([.year, .month], from: today)
            components.day = dayNumber
            if let date = calendar.date(from: components), calendar.component(.day, from: date) == dayNumber {
                if date >= today { return (date, rest(found)) }
                if let next = calendar.date(byAdding: .month, value: 1, to: date), calendar.component(.day, from: next) == dayNumber { return (next, rest(found)) }
            }
        }
        // 周五 / 这周五 / 下周三 / 下下周一 / 星期天 / 礼拜二
        if let found = match("^(这|本|下下|下)?(?:个)?(?:周|星期|礼拜)([一二三四五六日天])\\s*"), let weekday = weekdays[found[2] ?? ""], let date = weekdayDate(weekday, modifier: found[1], today: today) { return (date, rest(found)) }
        // Friday / next Friday / this Friday / on Friday
        if let found = match("^(?:on\\s+)?(next|this)?\\s*(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\\b\\s*"), let weekday = englishWeekdays[(found[2] ?? "").lowercased()], let date = weekdayDate(weekday, modifier: found[1]?.lowercased() == "next" ? "下" : nil, today: today) { return (date, rest(found)) }
        // Oct 23 / October 23rd / on Oct 23
        if let found = match("^(?:on\\s+)?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b\\s*"), let month = englishMonths[(found[1] ?? "").lowercased()], let dayNumber = Int(found[2] ?? ""), let date = monthDay(month: month, day: dayNumber, year: nil, today: today) { return (date, rest(found)) }
        return nil
    }

    private static func monthDay(month: Int, day: Int, year: Int?, today: Date) -> Date? {
        let calendar = Calendar.current
        func make(_ year: Int) -> Date? {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)), calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else { return nil }
            return date
        }
        if let year { return make(year) }
        let thisYear = calendar.component(.year, from: today)
        guard let date = make(thisYear) else { return nil }
        return date >= today ? date : make(thisYear + 1)
    }

    /// Weeks start on Monday. A bare weekday means the next one coming (today counts); "下" means next week's.
    private static func weekdayDate(_ weekday: Int, modifier: String?, today: Date) -> Date? {
        let calendar = Calendar.current
        let mondayIndex = { (value: Int) in (value + 5) % 7 }
        let todayIndex = mondayIndex(calendar.component(.weekday, from: today))
        guard let monday = calendar.date(byAdding: .day, value: -todayIndex, to: today) else { return nil }
        let target = mondayIndex(weekday)
        switch modifier {
        case "下": return calendar.date(byAdding: .day, value: 7 + target, to: monday)
        case "下下": return calendar.date(byAdding: .day, value: 14 + target, to: monday)
        case "这", "本": return calendar.date(byAdding: .day, value: target, to: monday)
        default: return calendar.date(byAdding: .day, value: target >= todayIndex ? target : target + 7, to: monday)
        }
    }
}
