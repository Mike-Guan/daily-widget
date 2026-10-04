import XCTest

final class TaskUnderstandingTests: XCTestCase {
    // Monday 2026-10-05, 10:00 local time.
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10))!

    /// Keyword categories are off here so these tests look at one thing at a time; see testKeywordCategoryWithoutAModel.
    private func draft(_ text: String, _ model: ModelTaskOutput?, guessCategory: Bool = false) -> TaskDraft {
        TaskUnderstanding.draft(text: text, model: model, now: now, guessCategory: guessCategory)
    }

    func testWithoutModelItIsTheRuleParser() {
        let result = draft("明天下午三点牙医", nil)
        XCTAssertEqual(result, TaskDraft(title: "牙医", date: "2026-10-06", start: 900, end: 930, source: .rules))
    }

    func testModelPointsAtDayAndTimeInTheMiddleOfTheSentence() {
        let model = ModelTaskOutput(title: "和老王吃饭", dateText: "周五", timeText: "七点", durationMinutes: 90, category: "social")
        let result = draft("周五和老王吃饭大概七点钟", model)
        XCTAssertEqual(result.date, "2026-10-09")
        XCTAssertEqual(result.start, 420)
        // The rules found the time themselves, so a length nobody said is not taken from the model.
        XCTAssertEqual(result.end, 450)
        XCTAssertEqual(result.title, "和老王吃饭")
        XCTAssertEqual(result.category, "social")
        XCTAssertEqual(result.source, .model)
    }

    func testRulesKeepTheTimeTheyFound() {
        let model = ModelTaskOutput(title: "牙医", dateText: "下午", timeText: "三点", category: "health")
        let result = draft("明天下午三点牙医", model)
        XCTAssertEqual(result.date, "2026-10-06")
        XCTAssertEqual(result.start, 900)
        XCTAssertEqual(result.category, "health")
        XCTAssertEqual(result.source, .model)
    }

    func testInventedTitleIsRejected() {
        XCTAssertEqual(draft("有空买牛奶", ModelTaskOutput(title: "购买乳制品")).title, "有空买牛奶")
        XCTAssertEqual(draft("有空买牛奶", ModelTaskOutput(title: "购买乳制品")).source, .rules)
        XCTAssertEqual(draft("有空买牛奶", ModelTaskOutput(title: "买牛奶")).title, "买牛奶")
    }

    func testInvalidModelFieldsFallBackOneByOne() {
        let model = ModelTaskOutput(title: "开会", dateText: "2月30日", timeText: "二十五点", durationMinutes: 5000, category: "work", recurrence: "monthly")
        let result = draft("和团队开会", model)
        XCTAssertEqual(result, TaskDraft(title: "开会", date: nil, start: nil, end: nil, source: .model))
    }

    func testDayOrTimeTheUserNeverSaidIsIgnored() {
        let result = draft("和团队开会", ModelTaskOutput(title: "开会", dateText: "明天", timeText: "下午三点"))
        XCTAssertFalse(result.isScheduled)
    }

    func testDayWithoutTimeLandsOnThatDayAtNineWithReminder() {
        let rulesOnly = draft("帮我添加一个10月23日提醒我在华山医院公众号挂号", nil)
        XCTAssertEqual(rulesOnly, TaskDraft(title: "在华山医院公众号挂号", date: "2026-10-23", start: 540, end: 570, source: .rules, wantsReminder: true, usesDefaultTime: true))
        let withModel = draft("帮我添加一个10月23日提醒我在华山医院公众号挂号", ModelTaskOutput(title: "华山医院公众号挂号", dateText: "10月23日", wantsReminder: true, category: "health"))
        XCTAssertEqual(withModel, TaskDraft(title: "华山医院公众号挂号", date: "2026-10-23", start: 540, end: 570, category: "health", source: .model, wantsReminder: true, usesDefaultTime: true))
    }

    func testNoDayAndNoTimeIsInboxWithoutReminder() {
        let result = draft("提醒我买牛奶", ModelTaskOutput(title: "买牛奶", wantsReminder: true, recurrence: "weekly"))
        XCTAssertEqual(result, TaskDraft(title: "买牛奶", date: nil, start: nil, end: nil, recurrence: "none", source: .model))
    }

    func testReminderOnlyWhenAsked() {
        XCTAssertFalse(draft("明天下午三点牙医", nil).wantsReminder)
        XCTAssertTrue(draft("明天下午三点提醒我看牙医", nil).wantsReminder)
        XCTAssertTrue(draft("remind me tomorrow 3pm dentist", nil).wantsReminder)
    }

    func testReminderFireDate() {
        var task = PlannerTask(id: "a", date: "2026-10-23", start: 540, end: 570, title: "挂号", createdAt: "", updatedAt: "", updatedBy: "t")
        let expected = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))
        XCTAssertEqual(ReminderPlan.fireDate(for: task), expected)
        task.done = true
        XCTAssertNil(ReminderPlan.fireDate(for: task))
        task.done = false; task.date = nil; task.start = nil; task.end = nil
        XCTAssertNil(ReminderPlan.fireDate(for: task))
    }

    func testReminderWantedSetRoundTrips() {
        let defaults = UserDefaults(suiteName: "dw-tests-\(UUID().uuidString)")!
        ReminderPlan.setWanted(true, taskID: "a", in: defaults)
        ReminderPlan.setWanted(true, taskID: "b", in: defaults)
        ReminderPlan.setWanted(false, taskID: "a", in: defaults)
        XCTAssertEqual(ReminderPlan.wantedIDs(in: defaults), ["b"])
    }

    func testRecurrenceFromModel() {
        let result = draft("每天早上七点跑步", ModelTaskOutput(title: "跑步", timeText: "早上七点", durationMinutes: 30, category: "health", recurrence: "daily"))
        XCTAssertEqual(result, TaskDraft(title: "跑步", date: "2026-10-05", start: 420, end: 450, category: "health", recurrence: "daily", source: .model))
    }

    // MARK: What the speech recognizer actually hands over

    func testMikesSentence() {
        let text = "帮我预约10月23号提醒我我在华山医院公众号挂号"
        XCTAssertEqual(draft(text, nil), TaskDraft(title: "在华山医院公众号挂号", date: "2026-10-23", start: 540, end: 570, source: .rules, wantsReminder: true, usesDefaultTime: true))
        // The model may hand back the day with 号 and a tidier title; both must be accepted.
        let withModel = draft(text, ModelTaskOutput(title: "华山医院公众号挂号", dateText: "10月23号", wantsReminder: true, category: "health"))
        XCTAssertEqual(withModel, TaskDraft(title: "华山医院公众号挂号", date: "2026-10-23", start: 540, end: 570, category: "health", source: .model, wantsReminder: true, usesDefaultTime: true))
    }

    func testMikesSecondSentence() {
        let text = "帮我预约10月23号提醒我华山医院公众号挂号"
        XCTAssertEqual(draft(text, nil), TaskDraft(title: "华山医院公众号挂号", date: "2026-10-23", start: 540, end: 570, source: .rules, wantsReminder: true, usesDefaultTime: true))
        // A model that echoes the whole sentence as the title must not undo the rules' cleanup.
        let echoed = draft(text, ModelTaskOutput(title: text, dateText: "10月23号", wantsReminder: true))
        XCTAssertEqual(echoed.title, "华山医院公众号挂号")
        XCTAssertEqual(echoed.date, "2026-10-23")
    }

    func testRecognizerVariants() {
        for text in ["帮我添加一个10月23日提醒我在华山医院公众号挂号。", "十月二十三号提醒我挂号", "帮我预约 10 月 23 号提醒我挂号", "10/23提醒我挂号", "提醒我１０月２３日挂号", "我想在10月23号去华山医院挂号"] {
            let result = draft(text, nil)
            XCTAssertEqual(result.date, "2026-10-23", text)
            XCTAssertEqual(result.start, 540, text)
            XCTAssertTrue(result.title.hasSuffix("挂号"), "\(text) -> \(result.title)")
            XCTAssertFalse(result.title.contains("23"), "\(text) -> \(result.title)")
        }
        XCTAssertEqual(draft("明天下午三点开会。", nil), TaskDraft(title: "开会", date: "2026-10-06", start: 900, end: 930, source: .rules))
    }

    func testDayAndTimeInTheMiddleOfTheSentence() {
        XCTAssertEqual(draft("帮我约一下牙医明天下午三点", nil).start, 900)
        XCTAssertEqual(draft("帮我约一下牙医明天下午三点", nil).date, "2026-10-06")
        let dinner = draft("和老王周五晚上七点吃饭", nil)
        XCTAssertEqual(dinner, TaskDraft(title: "和老王吃饭", date: "2026-10-09", start: 1140, end: 1170, source: .rules))
        let english = draft("call mom tomorrow at 3pm", nil)
        XCTAssertEqual(english.date, "2026-10-06")
        XCTAssertEqual(english.start, 900)
    }

    func testOrdinaryWordsAreNotReadAsTimes() {
        XCTAssertFalse(draft("有一点事想和你说", nil).isScheduled)
        XCTAssertFalse(draft("买3个苹果", nil).isScheduled)
        XCTAssertFalse(draft("整理照片", nil).isScheduled)
    }

    // MARK: Everyday sentences, rules only

    func testEverydaySentences() {
        func check(_ text: String, _ title: String, _ date: String?, _ start: Int?, _ end: Int?, recurrence: String = "none", reminder: Bool = false, defaultTime: Bool = false, line: UInt = #line) {
            let result = draft(text, nil)
            XCTAssertEqual(result, TaskDraft(title: title, date: date, start: start, end: end, recurrence: recurrence, source: .rules, wantsReminder: reminder, usesDefaultTime: defaultTime), text, line: line)
        }
        check("下周三上午十点和客户开会一个半小时", "和客户开会", "2026-10-14", 600, 690)
        check("周五晚上和老王吃饭", "和老王吃饭", "2026-10-09", 1140, 1170, defaultTime: true)
        check("后天早上七点半提醒我去机场", "去机场", "2026-10-07", 450, 480, reminder: true)
        check("每天早上七点跑步", "跑步", "2026-10-05", 420, 450, recurrence: "daily")
        check("每周五下午四点交周报", "交周报", "2026-10-09", 960, 990, recurrence: "weekly")
        check("工作日上午九点半站会15分钟", "站会", "2026-10-05", 570, 585, recurrence: "weekdays")
        check("买牛奶", "买牛奶", nil, nil, nil)
        check("今晚八点看电影两个小时", "看电影", "2026-10-05", 1200, 1320)
        check("明天上午9点到11点写方案", "写方案", "2026-10-06", 540, 660)
        check("明天下午两点到四点半面试", "面试", "2026-10-06", 840, 990)
        check("tomorrow 9:00-10:30 standup", "standup", "2026-10-06", 540, 630)
        check("晚上十点一刻给爸爸打电话提醒我", "给爸爸打电话", "2026-10-05", 1335, 1365, reminder: true)
        check("十二月二十五号圣诞晚餐晚上七点", "圣诞晚餐", "2026-12-25", 1140, 1170)
        check("周末大扫除", "大扫除", "2026-10-10", 540, 570, defaultTime: true)
        check("月底提醒我交房租", "交房租", "2026-10-31", 540, 570, reminder: true, defaultTime: true)
        check("call mom tomorrow morning", "call mom", "2026-10-06", 480, 510, defaultTime: true)
    }

    func testKeywordCategoryWithoutAModel() {
        XCTAssertEqual(draft("帮我预约10月23号提醒我华山医院公众号挂号", nil, guessCategory: true).category, "health")
        XCTAssertEqual(draft("周五晚上和老王吃饭", nil, guessCategory: true).category, "social")
        XCTAssertEqual(draft("周末大扫除", nil, guessCategory: true).category, "home")
        XCTAssertEqual(draft("23号去银行", nil, guessCategory: true).category, "errands")
        XCTAssertEqual(draft("明天晚上复习英语", nil, guessCategory: true).category, "learning")
        XCTAssertEqual(draft("明天上午9点到11点写方案", nil, guessCategory: true).category, "personal")
        // A valid category from the model wins over the keyword guess.
        XCTAssertEqual(draft("周五晚上和老王吃饭", ModelTaskOutput(title: "和老王吃饭", category: "home"), guessCategory: true).category, "home")
    }

    // MARK: Answers the bundled model really gave (recorded on a Mac)

    func testLocalModelAnswersAreReadAndChecked() throws {
        // Echoes the whole sentence as the title: the rules' cleaner title must win, the category is kept.
        var output = try XCTUnwrap(LocalModelPrompt.parse(#"{"title":"帮我预约10月23号提醒我我在华山医院公众号挂号","date":"10月23号","time":"","duration_minutes":0,"remind":true,"category":"health","repeat":"none"}"#))
        var result = draft("帮我预约10月23号提醒我我在华山医院公众号挂号", output)
        XCTAssertEqual(result, TaskDraft(title: "在华山医院公众号挂号", date: "2026-10-23", start: 540, end: 570, category: "health", source: .model, wantsReminder: true, usesDefaultTime: true))

        // "7:30" was never said ("七点半" was), so the model's time is ignored and the rules' time stands.
        output = try XCTUnwrap(LocalModelPrompt.parse(#"{"title":"老王他们几个吃火锅","date":"周五晚上","time":"7:30","duration_minutes":0,"remind":false,"category":"social","repeat":"none"}"#))
        result = draft("那个啥周五晚上七点半约了老王他们几个吃火锅别让我忘了", output)
        XCTAssertEqual(result.title, "老王他们几个吃火锅")
        XCTAssertEqual(result.date, "2026-10-09")
        XCTAssertEqual(result.start, 19 * 60 + 30)
        XCTAssertEqual(result.category, "social")

        // A tidier title that is not a contiguous part of the sentence is rejected.
        output = try XCTUnwrap(LocalModelPrompt.parse(#"{"title":"去看牙","date":"下周二","time":"下午两点左右","duration_minutes":0,"remind":false,"category":"health","repeat":"none"}"#))
        result = draft("嗯我想想下周二下午吧两点左右去看一下牙", output)
        XCTAssertEqual(result.date, "2026-10-13")
        XCTAssertEqual(result.category, "health")
        XCTAssertFalse(result.title.isEmpty)
    }

    func testComplainingSentence() throws {
        let text = "太讨厌了明天又得和mentor开组会"
        // Rules only take the day out. Feelings and filler are endless, so tidying the title is the model's job.
        XCTAssertEqual(draft(text, nil), TaskDraft(title: "太讨厌了又得和mentor开组会", date: "2026-10-06", start: 540, end: 570, source: .rules, usesDefaultTime: true))
        // The bundled model's real answer: its title is accepted, its invented reminder is not.
        let output = try XCTUnwrap(LocalModelPrompt.parse(#"{"title":"和mentor开组会","date":"明天","time":"","duration_minutes":0,"remind":true,"category":"social","repeat":"none"}"#))
        let result = draft(text, output)
        XCTAssertEqual(result.title, "和mentor开组会")
        XCTAssertEqual(result.category, "social")
        XCTAssertFalse(result.wantsReminder)
        XCTAssertEqual(result.source, .model)
    }

    func testLocalModelGarbageIsIgnored() {
        XCTAssertNil(LocalModelPrompt.parse("好的，我来帮你。"))
        XCTAssertNil(LocalModelPrompt.parse("{not json}"))
        let partial = LocalModelPrompt.parse(#"说明：{"title":"买牛奶","duration_minutes":"很久","remind":"yes"} 完成"#)
        XCTAssertEqual(partial, ModelTaskOutput(title: "买牛奶"))
    }

    // MARK: Date phrases resolved in code

    private func day(_ phrase: String) -> String? { DatePhrase.resolve(phrase, now: now)?.dayKey }

    func testDatePhrases() {
        XCTAssertEqual(day("10月23日"), "2026-10-23")
        XCTAssertEqual(day("十月二十三号"), "2026-10-23")
        XCTAssertEqual(day("明天"), "2026-10-06")
        XCTAssertEqual(day("后天"), "2026-10-07")
        XCTAssertEqual(day("下周三"), "2026-10-14")
        XCTAssertEqual(day("周三"), "2026-10-07")
        XCTAssertEqual(day("周一"), "2026-10-05")
        XCTAssertEqual(day("这周日"), "2026-10-11")
        XCTAssertEqual(day("下下周一"), "2026-10-19")
        XCTAssertEqual(day("23号"), "2026-10-23")
        XCTAssertEqual(day("3号"), "2026-11-03")
        XCTAssertEqual(day("next Friday"), "2026-10-16")
        XCTAssertEqual(day("Friday"), "2026-10-09")
        XCTAssertEqual(day("Oct 23"), "2026-10-23")
        XCTAssertNil(day("2月30日"))
        XCTAssertNil(day("改天"))
    }

    func testPastDateRollsToNextYear() {
        XCTAssertEqual(day("3月1日"), "2027-03-01")
        XCTAssertEqual(day("2026年3月1日"), "2026-03-01")
    }

    func testSentencesThroughTheRuleParser() {
        XCTAssertEqual(QuickInputParser.parse("明天下午三点牙医", now: now).date, "2026-10-06")
        let evening = QuickInputParser.parse("后天晚上8点看电影", now: now)
        XCTAssertEqual(evening.date, "2026-10-07")
        XCTAssertEqual(evening.start, 1200)
        let nextWeek = QuickInputParser.parse("下周三上午十点和客户开会", now: now)
        XCTAssertEqual(nextWeek.date, "2026-10-14")
        XCTAssertEqual(nextWeek.start, 600)
        XCTAssertEqual(nextWeek.title, "和客户开会")
        XCTAssertEqual(QuickInputParser.parse("remind me to call mom tomorrow", now: now).title, "call mom")
        XCTAssertEqual(QuickInputParser.parse("remind me to call mom tomorrow", now: now).day, "2026-10-06")
        XCTAssertEqual(QuickInputParser.minute(fromTimePhrase: "下午三点"), 900)
        XCTAssertEqual(QuickInputParser.minute(fromTimePhrase: "3pm"), 900)
        XCTAssertNil(QuickInputParser.minute(fromTimePhrase: "二十五点"))
    }
}
