import Foundation

/// What will be written if the user confirms: the result of understanding one sentence.
struct TaskDraft: Equatable {
    enum Source: Equatable { case rules, model }

    var title: String
    var date: String?
    var start: Int?
    var end: Int?
    var category: String = "personal"
    var recurrence: String = "none"
    var notes: String = ""
    var source: Source = .rules
    /// The user asked to be reminded ("提醒我", "remind me").
    var wantsReminder = false
    /// A day was named without a time, so the default time of day was used.
    var usesDefaultTime = false

    var isScheduled: Bool { date != nil && start != nil && end != nil }
}

/// The one switch for how a spoken task is committed, shared by the app, Siri and the Action Button.
enum QuickAddPolicy {
    /// true: add as soon as the sentence is understood and offer Undo. false: always ask first.
    static let addsImmediately = true
    static let undoWindow: TimeInterval = 5
    /// Where a task goes when a day was named but no time: 09:00.
    static let defaultStartMinute = 9 * 60
}

/// When a task's reminder should fire. Reminders are local notifications on this iPhone; which
/// tasks want one is kept in the App Group, not in the synced task file, so the data format the
/// Mac reads does not change.
enum ReminderPlan {
    static let defaultsKey = "reminderTaskIDs"

    static func fireDate(for task: PlannerTask) -> Date? {
        guard !task.isDeleted, !task.done, let date = task.date, let start = task.start, let day = DateFormatter.dayKey.date(from: date) else { return nil }
        return Calendar.current.date(byAdding: .minute, value: start, to: Calendar.current.startOfDay(for: day))
    }

    static var sharedDefaults: UserDefaults { UserDefaults(suiteName: WidgetSnapshot.appGroupID) ?? .standard }

    static func wantedIDs(in defaults: UserDefaults = sharedDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    static func setWanted(_ wanted: Bool, taskID: String, in defaults: UserDefaults = sharedDefaults) {
        var ids = wantedIDs(in: defaults)
        if wanted { ids.insert(taskID) } else { ids.remove(taskID) }
        defaults.set(ids.sorted(), forKey: defaultsKey)
    }
}

/// Raw fields as a language model returned them. The model only points at the words for the day
/// and the time; turning those words into a date is done in code. Nothing here is trusted until
/// `TaskUnderstanding` has checked it.
struct ModelTaskOutput: Equatable {
    var title: String = ""
    var dateText: String?
    var timeText: String?
    var durationMinutes: Int?
    var wantsReminder: Bool = false
    var category: String?
    var recurrence: String?
}

/// Combines the rule parser with an optional model answer. The rules are exact when they match, so
/// they keep the date and time they found; the model fills in what rules cannot see (a day or time
/// in the middle of the sentence, category, a cleaner title). Every model field is validated on its
/// own and dropped if it is out of range or not grounded in what was said.
enum TaskUnderstanding {
    static let categories = ["personal", "health", "home", "social", "learning", "errands"]
    static let recurrences = ["none", "daily", "weekdays", "weekly"]

    static func draft(text: String, model: ModelTaskOutput?, now: Date = .now, guessCategory: Bool = true) -> TaskDraft {
        let rules = QuickInputParser.parse(text, now: now)
        var draft = TaskDraft(title: rules.title, date: rules.date, start: rules.start, end: rules.end, recurrence: rules.recurrence, usesDefaultTime: rules.assumedTime)
        var day = rules.day
        var usedModel = false

        if let model {
            // The model may only make the title tidier than the rules did, never put the lead-in or the date back.
            if let title = groundedTitle(model.title, in: text), title.count <= rules.title.count, title != rules.title { draft.title = title; usedModel = true }
            if let category = model.category, categories.contains(category), category != "personal" { draft.category = category; usedModel = true }
            if rules.recurrence == "none", let recurrence = model.recurrence, recurrences.contains(recurrence), recurrence != "none" { draft.recurrence = recurrence; usedModel = true }

            if day == nil, let phrase = model.dateText, contains(text, phrase), let resolved = DatePhrase.resolve(phrase, now: now) { day = resolved.dayKey; usedModel = true }
            if !rules.hasExplicitTime || rules.assumedTime, let phrase = model.timeText, contains(text, phrase), let minute = QuickInputParser.minute(fromTimePhrase: phrase) {
                let duration = model.durationMinutes.flatMap { (15...8 * 60).contains($0) ? snap($0) : nil } ?? rules.duration
                draft.date = day ?? now.dayKey
                draft.start = minute
                draft.end = minute + max(15, duration)
                draft.usesDefaultTime = false
                usedModel = true
            }
        }

        // Without a model (Apple Intelligence off, unsupported region or language) a keyword guess still sets the category.
        if guessCategory, draft.category == "personal", let guess = keywordCategory(for: draft.title) { draft.category = guess }
        // Only when the words are there: small models say "remind: true" for sentences that never asked.
        draft.wantsReminder = QuickInputParser.mentionsReminder(text)
        if draft.isScheduled {
            if let day { draft.date = day }
        } else if let day {
            // A day without a time lands on that day at the default time, where it is visible and can be dragged.
            draft.date = day
            draft.start = QuickAddPolicy.defaultStartMinute
            draft.end = QuickAddPolicy.defaultStartMinute + 30
            draft.usesDefaultTime = true
        } else {
            // Neither day nor time: Inbox.
            draft.date = nil; draft.start = nil; draft.end = nil
            draft.recurrence = "none"
            draft.wantsReminder = false
        }
        if usedModel { draft.source = .model }
        return draft
    }

    /// A category from everyday words in the title; nil when nothing matches.
    static func keywordCategory(for title: String) -> String? {
        let table: [(String, [String])] = [
            ("health", ["医院", "牙医", "医生", "体检", "挂号", "看病", "复诊", "吃药", "疫苗", "跑步", "健身", "瑜伽", "游泳", "散步", "锻炼", "冥想", "doctor", "dentist", "gym", "workout", "run", "yoga", "checkup", "hospital"]),
            ("social", ["吃饭", "聚会", "聚餐", "约会", "朋友", "同学", "生日", "婚礼", "妈妈", "爸爸", "家人", "打电话", "晚餐", "午饭", "喝咖啡", "见面", "dinner", "lunch", "party", "call mom", "call dad", "birthday", "coffee with", "meet"]),
            ("learning", ["学习", "复习", "上课", "网课", "考试", "读书", "看书", "阅读", "背单词", "练习", "作业", "论文", "study", "read", "class", "lesson", "exam", "homework", "course"]),
            ("home", ["大扫除", "打扫", "洗衣", "做饭", "买菜", "收拾", "整理", "倒垃圾", "维修", "修理", "搬家", "浇花", "房租", "clean", "laundry", "cook", "groceries", "tidy", "rent", "repair"]),
            ("errands", ["银行", "快递", "取件", "寄", "办理", "缴费", "交费", "续费", "报销", "签证", "护照", "邮局", "加油", "洗车", "取钱", "bank", "pick up", "post office", "renew", "pay ", "errand"]),
        ]
        let lowered = title.lowercased()
        return table.first { $0.1.contains { lowered.contains($0) } }?.0
    }

    /// The model may tidy the title ("记一下明天牙医" → "牙医") but may not invent one.
    static func groundedTitle(_ candidate: String, in text: String) -> String? {
        let title = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 80, contains(text, title) else { return nil }
        return title
    }

    private static func snap(_ minute: Int) -> Int { Int((Double(minute) / 15).rounded()) * 15 }

    private static func contains(_ text: String, _ part: String) -> Bool {
        func normalized(_ value: String) -> String { value.lowercased().filter { !$0.isWhitespace } }
        return normalized(text).contains(normalized(part))
    }
}

/// The instructions given to the bundled model and the reading of its one-line JSON answer.
enum LocalModelPrompt {
    static let instructions = """
    你从用户说的一句话里标出日程的各个部分，只输出一行 JSON，不要解释，不要换行。
    字段：
    title：事情本身。照抄原话里的词，不要改写或翻译；去掉日期、时间、时长，以及“帮我添加”“帮我预约”“提醒我”“记一下”这类话头。
    date：原话里表示哪一天的词，原样照抄，例如“10月23号”“下周三”“明天”“周五”。没说就是 ""。
    time：原话里表示几点的词，原样照抄，例如“下午三点”“晚上8点半”“9:30”。没说就是 ""。
    duration_minutes：持续多少分钟，整数。没说就是 0。
    remind：用户是否要求提醒（“提醒我”“别忘了”“叫我”），true 或 false。
    category：personal、health、home、social、learning、errands 之一。
    repeat：none、daily、weekdays、weekly 之一。只有说了“每天”“工作日”“每周”才不是 none。

    例子：
    帮我预约10月23号提醒我华山医院公众号挂号
    {"title":"华山医院公众号挂号","date":"10月23号","time":"","duration_minutes":0,"remind":true,"category":"health","repeat":"none"}
    下周三上午十点和客户开会一个半小时
    {"title":"和客户开会","date":"下周三","time":"上午十点","duration_minutes":90,"remind":false,"category":"personal","repeat":"none"}
    每天早上七点跑步
    {"title":"跑步","date":"","time":"早上七点","duration_minutes":0,"remind":false,"category":"health","repeat":"daily"}
    remind me to call mom tomorrow at 3pm
    {"title":"call mom","date":"tomorrow","time":"3pm","duration_minutes":0,"remind":true,"category":"social","repeat":"none"}
    买牛奶
    {"title":"买牛奶","date":"","time":"","duration_minutes":0,"remind":false,"category":"errands","repeat":"none"}
    """

    /// Reads the first JSON object in the answer. Anything unexpected becomes nil or an empty field;
    /// `TaskUnderstanding` still checks every field against what was said.
    static func parse(_ answer: String) -> ModelTaskOutput? {
        guard let open = answer.firstIndex(of: "{"), let close = answer.lastIndex(of: "}"), open < close,
              let object = try? JSONSerialization.jsonObject(with: Data(answer[open...close].utf8)) as? [String: Any] else { return nil }
        func text(_ key: String) -> String? {
            guard let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        let duration = (object["duration_minutes"] as? NSNumber)?.intValue
        return ModelTaskOutput(title: text("title") ?? "", dateText: text("date"), timeText: text("time"), durationMinutes: duration.flatMap { $0 > 0 ? $0 : nil }, wantsReminder: (object["remind"] as? Bool) ?? false, category: text("category"), recurrence: text("repeat"))
    }
}
