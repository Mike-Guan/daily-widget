import XCTest

final class QuickInputParserTests: XCTestCase {
    private typealias Result = QuickInputParser.Result
    private let today = "2026-08-20"

    private func parse(_ text: String, on dateKey: String? = nil) -> Result {
        QuickInputParser.parse(text, dateKey: dateKey ?? today)
    }

    // MARK: Cases shared with test/task-model.test.js — results must stay identical to the JS parser.

    func testChineseRelativeDateTimeAndDuration() {
        XCTAssertEqual(parse("明天 9:30 跑步 45m"), Result(date: "2026-08-21", start: 570, end: 615, title: "跑步", duration: 45, hasExplicitTime: true))
    }

    func testFullWidthPunctuationAndTightChineseTime() {
        XCTAssertEqual(parse("明天9：30跑步45分钟", on: "2026-08-22"), Result(date: "2026-08-23", start: 570, end: 615, title: "跑步", duration: 45, hasExplicitTime: true))
    }

    // MARK: Behaviour the JS parser also has (no JS test yet).

    func testNoTimeGoesToInbox() {
        XCTAssertEqual(parse("买牛奶"), Result(date: nil, start: nil, end: nil, title: "买牛奶", duration: 30, hasExplicitTime: false))
        XCTAssertEqual(parse("明天 买牛奶"), Result(date: nil, start: nil, end: nil, title: "买牛奶", duration: 30, hasExplicitTime: false))
    }

    func testEnglishInput() {
        XCTAssertEqual(parse("tomorrow 9:30 run 1h"), Result(date: "2026-08-21", start: 570, end: 630, title: "run", duration: 60, hasExplicitTime: true))
        XCTAssertEqual(parse("at 14 dentist"), Result(date: today, start: 840, end: 870, title: "dentist", duration: 30, hasExplicitTime: true))
        XCTAssertEqual(parse("Today 8:00 standup"), Result(date: today, start: 480, end: 510, title: "standup", duration: 30, hasExplicitTime: true))
    }

    func testChineseNumeralTime() {
        XCTAssertEqual(parse("九点半开会"), Result(date: today, start: 570, end: 600, title: "开会", duration: 30, hasExplicitTime: true))
        XCTAssertEqual(parse("十二点吃饭"), Result(date: today, start: 720, end: 750, title: "吃饭", duration: 30, hasExplicitTime: true))
    }

    func testTimesRoundToQuarterHours() {
        XCTAssertEqual(parse("9:20 call").start, 555)
        XCTAssertEqual(parse("9:40 call 50m").duration, 45)
    }

    func testDurationIsClamped() {
        XCTAssertEqual(parse("9:00 deep work 12h").duration, 480)
        XCTAssertEqual(parse("9:00 stretch 5m").duration, 15)
        XCTAssertEqual(parse("9:00 read 1.5h").end, 630)
    }

    func testChineseNumbers() {
        XCTAssertEqual(QuickInputParser.chineseNumber("两"), 2)
        XCTAssertEqual(QuickInputParser.chineseNumber("十"), 10)
        XCTAssertEqual(QuickInputParser.chineseNumber("十五"), 15)
        XCTAssertEqual(QuickInputParser.chineseNumber("二十三"), 23)
        XCTAssertNil(QuickInputParser.chineseNumber("百"))
    }

    // MARK: Speech extensions (Swift only).

    func testSpokenChineseAfternoon() {
        XCTAssertEqual(parse("明天下午三点牙医"), Result(date: "2026-08-21", start: 900, end: 930, title: "牙医", duration: 30, hasExplicitTime: true))
        XCTAssertEqual(parse("明天下午3点牙医。"), Result(date: "2026-08-21", start: 900, end: 930, title: "牙医", duration: 30, hasExplicitTime: true))
    }

    func testPeriodsOfTheDay() {
        XCTAssertEqual(parse("晚上8点半健身一个小时"), Result(date: today, start: 1230, end: 1290, title: "健身", duration: 60, hasExplicitTime: true))
        XCTAssertEqual(parse("今晚七点看电影").start, 1140)
        XCTAssertEqual(parse("中午12点午饭").start, 720)
        XCTAssertEqual(parse("中午1点午睡").start, 780)
        XCTAssertEqual(parse("凌晨12点发布").start, 0)
        XCTAssertEqual(parse("上午十点一刻站会").start, 615)
        XCTAssertEqual(parse("下午3点15分取快递").start, 915)
    }

    func testDayAfterTomorrow() {
        XCTAssertEqual(parse("后天上午九点面试").date, "2026-08-22")
    }

    func testEnglishMeridiem() {
        XCTAssertEqual(parse("tomorrow 3pm dentist"), Result(date: "2026-08-21", start: 900, end: 930, title: "dentist", duration: 30, hasExplicitTime: true))
        XCTAssertEqual(parse("3:30 PM call mom").start, 930)
        XCTAssertEqual(parse("12am deploy").start, 0)
        XCTAssertEqual(parse("tonight 8 movie").start, 1200)
    }

    func testSpokenDurations() {
        XCTAssertEqual(parse("九点跑步半小时").duration, 30)
        XCTAssertEqual(parse("九点写作两个小时").end, 660)
        XCTAssertEqual(parse("晚上七点吃饭一个半小时"), Result(date: today, start: 1140, end: 1230, title: "吃饭", duration: 90, hasExplicitTime: true))
        XCTAssertEqual(parse("9:00 review 45 minutes").duration, 45)
    }

    func testLeadingNumberThatIsNotATimeStaysInTheTitle() {
        XCTAssertEqual(parse("3个苹果"), Result(date: nil, start: nil, end: nil, title: "3个苹果", duration: 30, hasExplicitTime: false))
        XCTAssertEqual(parse("下午牙医").title, "下午牙医")
        XCTAssertNil(parse("下午牙医").start)
    }

    func testMonthBoundary() {
        XCTAssertEqual(parse("明天 8:00 月初计划", on: "2026-08-31").date, "2026-09-01")
    }
}
