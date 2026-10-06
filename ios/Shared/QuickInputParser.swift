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
        /// none / daily / weekdays / weekly, from "每天", "工作日", "每周五", "every week".
        var recurrence = "none"
        /// Only a part of the day was said ("晚上"), so a usual time for it was filled in.
        var assumedTime = false
        /// A length was actually said ("一个小时", "9点到11点"), as opposed to the 30-minute default.
        var saidDuration = false

        static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.date == rhs.date && lhs.start == rhs.start && lhs.end == rhs.end && lhs.title == rhs.title && lhs.duration == rhs.duration && lhs.hasExplicitTime == rhs.hasExplicitTime
        }
    }

    static func parse(_ text: String, dateKey: String? = nil, now: Date = .now) -> Result {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDate = dateKey.flatMap { DateFormatter.dayKey.date(from: $0) } ?? now
        var remainder = original.replacingOccurrences(of: "：", with: ":").map { character -> Character in
            // Full-width digits from some keyboards and recognizers.
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1, (0xFF10...0xFF19).contains(scalar.value), let ascii = Unicode.Scalar(scalar.value - 0xFF10 + 0x30) else { return character }
            return Character(ascii)
        }.reduce(into: "") { $0.append($1) }
        // Dictation often ends the sentence for us.
        while let last = remainder.last, "。.!！,，".contains(last) { remainder.removeLast() }
        remainder = stripFiller(remainder)

        var day: Date?
        var recurrence = "none"
        func remove(_ phrase: String) {
            guard let range = remainder.range(of: phrase, options: .caseInsensitive) else { return }
            remainder = join(stripFiller(String(remainder[..<range.lowerBound]), mayBeEmpty: true), stripFiller(String(remainder[range.upperBound...]), mayBeEmpty: true))
        }
        if let match = firstMatch("每个?(?:周|星期|礼拜)([一二三四五六日天])", in: remainder), let whole = match[0], let weekday = match[1] {
            recurrence = "weekly"
            day = DatePhrase.resolve("周" + weekday, now: baseDate)
            remove(whole)
        } else if let whole = firstMatch("(每个?)?工作日(每天)?|every weekday|on weekdays|weekdays", in: remainder)?[0] {
            recurrence = "weekdays"; remove(whole)
        } else if let whole = firstMatch("每天|每日|天天|every day|everyday|daily", in: remainder)?[0] {
            recurrence = "daily"; remove(whole)
        } else if let whole = firstMatch("每个?(?:周|星期|礼拜)|every week|weekly", in: remainder)?[0] {
            recurrence = "weekly"; remove(whole)
        }

        if day != nil {
            // "每周五" already named the day.
        } else if let match = firstMatch("^(今晚|tonight\\b)\\s*", in: remainder) {
            // "今晚 8点" keeps its evening meaning for the time step below.
            day = baseDate
            remainder = "晚上" + String(remainder.dropFirst(match[0]!.count))
        } else if let (found, rest) = DatePhrase.leading(in: remainder, now: baseDate) {
            day = found
            remainder = stripFiller(rest)
        } else if let (found, before, after) = DatePhrase.anywhere(in: remainder, now: baseDate) {
            // Spoken sentences put the day in the middle: "帮我预约10月23号提醒我…".
            day = found
            remainder = join(dropTrailingPreposition(stripFiller(before, mayBeEmpty: true)), stripFiller(after))
        }

        var duration = 30
        var saidDuration = false
        // A length anywhere in the sentence: "一个半小时", "开一个小时的组会", "45分钟", "for 2 hours".
        if let match = firstMatch("(?:for\\s+)?(\\d+|[零一二三四五六七八九十两]+)\\s*个半\\s*小时(的)?", in: remainder), let whole = match[0], let hours = chineseNumber(match[1] ?? "") {
            duration = max(15, min(8 * 60, hours * 60 + 30))
            saidDuration = true
            remove(whole)
        } else if let match = firstMatch("(?:for\\s+)?(\\d+(?:\\.5)?|半|[零一二三四五六七八九十两]+)\\s*个?\\s*(mins?\\b|minutes?\\b|分钟|hrs?\\b|hours?\\b|小时|(?<=\\d)[mh]\\b)(的)?", in: remainder), let whole = match[0], let amount = durationAmount(match[1] ?? "") {
            let unit = (match[2] ?? "").lowercased()
            let minutes = unit.hasPrefix("h") || unit == "小时" ? amount * 60 : amount
            duration = max(15, min(8 * 60, Int((minutes / 15).rounded()) * 15))
            saidDuration = true
            remove(whole)
        }

        var start: Int?
        var assumedTime = false
        func takeRangeEnd(from startMinute: Int, _ rest: String) -> String {
            // "9点到11点", "9:00-10:30", "3pm to 5pm"
            guard !saidDuration, let connector = firstMatch("^\\s*(到|至|-|—|–|~|～|to\\b|until\\b)\\s*", in: rest)?[0], let (endMinute, after) = parseTime(String(rest.dropFirst(connector.count)), strict: true) else { return rest }
            var end = clampMinute(endMinute)
            if end <= startMinute, end + 12 * 60 > startMinute, end + 12 * 60 <= 24 * 60 { end += 12 * 60 }
            guard end > startMinute else { return rest }
            duration = min(8 * 60, end - startMinute)
            saidDuration = true
            return after
        }
        // The strict form first, so "9:30pm" on its own keeps its "pm" instead of leaving it as the title.
        if let (minute, rest) = parseTime(remainder, strict: true) ?? parseTime(remainder) {
            start = clampMinute(minute)
            remainder = takeRangeEnd(from: start!, rest).trimmingCharacters(in: .whitespaces)
        } else if let (minute, before, after) = timeAnywhere(in: remainder) {
            start = clampMinute(minute)
            remainder = join(dropTrailingPreposition(stripFiller(before, mayBeEmpty: true)), stripFiller(takeRangeEnd(from: start!, after)))
        } else if let (minute, whole) = partOfDay(in: remainder) {
            // "周五晚上和老王吃饭": no clock time, so use a usual time for that part of the day.
            start = minute
            assumedTime = true
            remove(whole)
        }

        remainder = stripFiller(remainder)
        if let trailing = firstMatch("[，,\\s]*(记得)?提醒我(一下)?$", in: remainder)?[0], trailing.count < remainder.count { remainder = String(remainder.dropLast(trailing.count)) }
        let hasExplicitTime = start != nil
        return Result(date: hasExplicitTime ? (day ?? baseDate).dayKey : nil, start: start, end: start.map { $0 + duration }, title: remainder.isEmpty ? original : remainder, duration: duration, hasExplicitTime: hasExplicitTime, day: day?.dayKey, recurrence: recurrence, assumedTime: assumedTime, saidDuration: saidDuration)
    }

    /// "把健身时间改到晚上9:30" / "move the gym to 9pm": the task being talked about and what follows the verb.
    static func changeRequest(in text: String) -> (target: String, rest: String)? {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = firstMatch("把(.+?)(?:的)?(?:时间|日程|安排)?(?:给我|帮我)?(?:改到了?|改成了?|改为|改在|挪到了?|调到了?|调整到了?|换到了?|移到了?|推迟到了?|提前到了?|延后到了?|延到了?|推到了?)(.*)$", in: sentence), let target = match[1]?.trimmingCharacters(in: .whitespaces), !target.isEmpty {
            return (target, match[2] ?? "")
        }
        if let match = firstMatch("^(?:please\\s+)?(?:move|reschedule|change|push|shift)\\s+(?:my\\s+|the\\s+)?(.+?)\\s+to\\s+(.*)$", in: sentence), let target = match[1]?.trimmingCharacters(in: .whitespaces), !target.isEmpty {
            return (target, match[2] ?? "")
        }
        return nil
    }

    /// A part of the day said without a clock time, and the usual time used for it.
    private static func partOfDay(in text: String) -> (Int, String)? {
        let table: [(String, Int)] = [("早上|早晨|in the morning|this morning|morning", 8 * 60), ("上午", 10 * 60), ("中午|at noon|noon", 12 * 60), ("下午|in the afternoon|this afternoon|afternoon", 15 * 60), ("傍晚", 18 * 60), ("晚上|in the evening|this evening|evening", 19 * 60)]
        for (pattern, minute) in table {
            if let whole = firstMatch(pattern, in: text)?[0] { return (minute, whole) }
        }
        return nil
    }

    /// Minutes from midnight for a spoken time on its own ("下午三点", "3pm", "9:30"), or nil.
    static func minute(fromTimePhrase phrase: String) -> Int? {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "：", with: ":")
        // parseTime wants something after a bare English time; give it a placeholder.
        return (parseTime(text) ?? parseTime(text + " x")).map { clampMinute($0.0) }
    }

    /// Drops lead-ins that are about the request, not the task: "帮我添加一个", "提醒我", "remind me to".
    static func stripFiller(_ text: String, mayBeEmpty: Bool = false) -> String {
        var value = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "，,、")))
        for pattern in ["^(请)?(帮我|给我|麻烦|我要|我想)?(添加|加上|加|新建|创建|安排|预约|预定|预订|订|记一下|记下|记|设置|设)(一个|一下|个|一条|条)?(日程|任务|提醒|待办)?[，,：:\\s]*", "^(请|帮我|给我|麻烦|我要|我想)[，,\\s]*", mayBeEmpty ? "^(在|于)[，,\\s]*$" : "^(的时候|的)[，,\\s]*", "^(提醒我|记得|别忘了|叫我|通知我)(一下)?(要)?[，,：:\\s]*", "^我+(要|得|想|需要)?(?=在|去|到|给|把|跟|和)", "^(please\\s+)?(add|create|schedule)\\s+(a\\s+)?(task|reminder|event)?\\s*(to|for|:)?\\s+", "^remind me\\s+(to\\s+)?"] {
            if let match = firstMatch(pattern, in: value), let whole = match[0], !whole.isEmpty, mayBeEmpty || whole.count < value.count { value = String(value.dropFirst(whole.count)) }
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    static func mentionsReminder(_ text: String) -> Bool {
        firstMatch("提醒|别忘|别让我忘|叫我|通知我|remind|don't let me forget|don't forget", in: text) != nil
    }

    // MARK: Time

    private static let periods = "凌晨|早上|早晨|上午|中午|下午|傍晚|晚上"
    private static let numerals = "零一二三四五六七八九十两"

    /// Returns minutes from midnight and the text after the time, or nil when the text does not start with a time.
    /// A time in the middle of the sentence. Stricter than at the start: it needs 点, a colon,
    /// am/pm or a part of the day, so plain numbers and "一点" (a little) are left alone.
    private static func timeAnywhere(in text: String) -> (Int, String, String)? {
        var index = text.startIndex
        while index < text.endIndex {
            let suffix = String(text[index...])
            if let (minute, rest) = parseTime(suffix, strict: true) { return (minute, String(text[..<index]), rest) }
            index = text.index(after: index)
        }
        return nil
    }

    /// "…开组会在" + (time removed) → "…开组会"
    private static func dropTrailingPreposition(_ text: String) -> String {
        guard let trailing = firstMatch("(在|于|at|on)\\s*$", in: text)?[0] else { return text }
        return String(text.dropLast(trailing.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func join(_ before: String, _ after: String) -> String {
        let needsSpace = before.last?.isASCII == true && after.first?.isASCII == true && !before.isEmpty && !after.isEmpty
        return (before + (needsSpace ? " " : "") + after).trimmingCharacters(in: .whitespaces)
    }

    private static func parseTime(_ text: String, strict: Bool = false) -> (Int, String)? {
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
            let ambiguous = strict && period == nil && match[1] == "一" && (match[2] ?? "").isEmpty
            if !ambiguous, let minute, let resolved = resolve(hour: hour, minute: minute, period: period) { return (resolved, match[3] ?? "") }
        }

        // 9:30 / at 9 / 3pm / 3:15 pm. A bare hour needs "at", am/pm, or a space before the title,
        // so "3个苹果" is not read as 3:00.
        // In the middle of a sentence the time may be the last thing said, so nothing has to follow it.
        if let match = firstMatch("^(at\\s*)?(\\d{1,2})(?::(\\d{2}))?\\s*(a\\.?m\\.?|p\\.?m\\.?)?(\\s*)(\(strict ? ".*" : ".+"))$", in: body), let hour = Int(match[2] ?? "") {
            let hasAt = match[1] != nil, hasColon = match[3] != nil, meridiem = match[4]?.lowercased(), hasSpace = !(match[5] ?? "").isEmpty
            if strict ? (hasColon || meridiem != nil || period != nil) : (hasAt || hasColon || meridiem != nil || hasSpace || period != nil) {
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
    /// Day keys are Gregorian, so the math is too, whatever calendar the phone displays (e.g. Japanese or Buddhist).
    static var gregorian: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current; calendar.firstWeekday = 2; return calendar }

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

    /// The first day phrase anywhere in `text`, with the text before and after it.
    static func anywhere(in text: String, now: Date) -> (Date, String, String)? {
        var index = text.startIndex
        while index < text.endIndex {
            if let (date, rest) = leading(in: String(text[index...]), now: now) { return (date, String(text[..<index]), rest) }
            index = text.index(after: index)
        }
        return nil
    }

    /// A day phrase at the start of `text`, and what follows it.
    static func leading(in text: String, now: Date) -> (Date, String)? {
        let calendar = gregorian
        let today = calendar.startOfDay(for: now)
        func rest(_ match: [String?]) -> String { String(text.dropFirst(match[0]!.count)) }
        func day(_ offset: Int) -> Date? { calendar.date(byAdding: .day, value: offset, to: today) }
        let match = { (pattern: String) in QuickInputParser.firstMatch(pattern, in: text) }

        for (pattern, offset) in [("^(今天|today\\b)\\s*", 0), ("^(明天|tomorrow\\b)\\s*", 1), ("^(大后天)\\s*", 3), ("^(后天|後天|the day after tomorrow\\b)\\s*", 2)] {
            if let found = match(pattern), let date = day(offset) { return (date, rest(found)) }
        }

        // 周末 = this Saturday (today if it already is the weekend); 下周末 = next week's Saturday; 月底 = last day of the month.
        if let found = match("^(这个?|本)?周末\\s*|^this weekend\\b\\s*") {
            let weekday = calendar.component(.weekday, from: today)
            if weekday == 1 || weekday == 7 { return (today, rest(found)) }
            if let date = weekdayDate(7, modifier: "这", today: today) { return (date, rest(found)) }
        }
        if let found = match("^下个?周末\\s*|^next weekend\\b\\s*"), let date = weekdayDate(7, modifier: "下", today: today) { return (date, rest(found)) }
        if let found = match("^(这个?|本)?月底\\s*|^(at )?the end of (the|this) month\\b\\s*"), let range = calendar.range(of: .day, in: .month, for: today), let date = calendar.date(bySetting: .day, value: range.count, of: today) { return (calendar.startOfDay(for: date), rest(found)) }

        // 10月23日 / 十月二十三号 / 2027年1月5日; a day that has passed this year means next year.
        if let found = match("^(?:(\\d{4})\\s*年\\s*)?(\\d{1,2}|[\(numerals)]+)\\s*月\\s*(\\d{1,2}|[\(numerals)]+)\\s*[日号號]?\\s*"), let month = QuickInputParser.chineseNumber(found[2] ?? ""), let dayNumber = QuickInputParser.chineseNumber(found[3] ?? ""), let date = monthDay(month: month, day: dayNumber, year: found[1].flatMap(Int.init), today: today) { return (date, rest(found)) }
        // 10/23 or 10-23, only where a clock time cannot be meant.
        if let found = match("^(\\d{1,2})[/／-](\\d{1,2})(?![\\d:])[日号號]?\\s*"), let month = Int(found[1] ?? ""), let dayNumber = Int(found[2] ?? ""), let date = monthDay(month: month, day: dayNumber, year: nil, today: today) { return (date, rest(found)) }
        // 23号: this month, or next month if it has passed.
        if let found = match("^(\\d{1,2}|[\(numerals)]+)\\s*[号號]\\s*"), let dayNumber = QuickInputParser.chineseNumber(found[1] ?? "") {
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
        let calendar = gregorian
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
        let calendar = gregorian
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
