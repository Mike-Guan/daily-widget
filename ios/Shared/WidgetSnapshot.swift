import Foundation

struct WidgetSnapshot: Codable {
    struct Item: Codable, Identifiable {
        var id: String
        var title: String
        var start: Int?
        var end: Int?
        var done: Bool
        var category: String
        var recurrence: String = "none"
        var date: String = ""
    }

    var date: String
    var completed: Int
    var total: Int
    var current: Item?
    var upcoming: [Item]
    var updatedAt: Date
    var language: String = "zh"
}

extension WidgetSnapshot.Item {
    private enum CodingKeys: String, CodingKey { case id, title, start, end, done, category, recurrence, date }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        start = try values.decodeIfPresent(Int.self, forKey: .start)
        end = try values.decodeIfPresent(Int.self, forKey: .end)
        done = try values.decodeIfPresent(Bool.self, forKey: .done) ?? false
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? "personal"
        recurrence = try values.decodeIfPresent(String.self, forKey: .recurrence) ?? "none"
        date = try values.decodeIfPresent(String.self, forKey: .date) ?? ""
    }
}

extension WidgetSnapshot {
    private enum CodingKeys: String, CodingKey { case date, completed, total, current, upcoming, updatedAt, language }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decodeIfPresent(String.self, forKey: .date) ?? Date().dayKey
        completed = try values.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        total = try values.decodeIfPresent(Int.self, forKey: .total) ?? 0
        current = try values.decodeIfPresent(Item.self, forKey: .current)
        upcoming = try values.decodeIfPresent([Item].self, forKey: .upcoming) ?? []
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? "zh"
    }
}
