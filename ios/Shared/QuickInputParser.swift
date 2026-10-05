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
    }

    static func parse(_ text: String, dateKey: String? = nil, now: Date = .now) -> Result {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseDate = dateKey.flatMap { DateFormatter.dayKey.date(from: $0) } ?? now
        var dayOffset = 0
        var remainder = original.replacingOccurrences(of: "：", with: ":")
        // Dictation often ends the sentence for us.
        while let last = remainder.last, "。.!！,，".contains(last) { remainder.removeLast() }

        for (pattern, offset) in [("^(今天|today\\b)\\s*", 0), ("^(明天|tomorrow\\b)\\s*", 1), ("^(后天|後天|the day after tomorrow\\b)\\s*", 2), ("^(今晚|tonight\\b)\\s*", 0)] {
            guard let match = firstMatch(pattern, in: remainder) else { continue }
            dayOffset = offset
            let word = match[1] ?? ""
            // "今晚 8点" keeps its evening meaning for the time step below.
            remainder = (word == "今晚" || word.lowercased() == "tonight" ? "晚上" : "") + String(remainder.dropFirst(match[0]!.count))
            break
        }

        var duration = 30
        if let match = firstMatch("(\\d+(?:\\.5)?|半|[零一二三四五六七八九十两]+)\\s*个?\\s*(m|mins?|minutes?|分钟|h|hrs?|hours?|小时)\\s*$", in: remainder), let amount = durationAmount(match[1] ?? "") {
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

        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate) ?? baseDate
        let hasExplicitTime = start != nil
        return Result(date: hasExplicitTime ? date.dayKey : nil, start: start, end: start.map { $0 + duration }, title: remainder.isEmpty ? original : remainder, duration: duration, hasExplicitTime: hasExplicitTime)
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
    private static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}
