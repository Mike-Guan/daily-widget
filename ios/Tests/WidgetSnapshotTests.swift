import XCTest

final class WidgetSnapshotTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dw-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func task(_ id: String, date: String, start: Int, end: Int, recurrence: String = "none") -> PlannerTask {
        var task = PlannerTask(id: id, date: date, start: start, end: end, title: id, createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z", updatedBy: "test")
        task.recurrence = recurrence
        return task
    }

    func testBuildAttachesTomorrow() {
        let tasks = [task("today", date: "2026-10-05", start: 600, end: 660), task("tomorrow", date: "2026-10-06", start: 540, end: 600)]
        let snapshot = WidgetSnapshot.build(tasks: tasks, now: date(2026, 10, 5, 23, 59), language: "zh")
        XCTAssertEqual(snapshot.date, "2026-10-05")
        XCTAssertEqual(snapshot.upcoming.map(\.id), ["today"])
        XCTAssertEqual(snapshot.following.map(\.date), ["2026-10-06"])
        XCTAssertEqual(snapshot.following.first?.upcoming.map(\.id), ["tomorrow"])
    }

    func testCurrentTaskFollowsTheClock() {
        let tasks = [task("meeting", date: "2026-10-05", start: 600, end: 660)]
        XCTAssertEqual(WidgetSnapshot.build(tasks: tasks, dateKey: "2026-10-05", nowMinute: 610, language: "zh").current?.id, "meeting")
        XCTAssertNil(WidgetSnapshot.build(tasks: tasks, dateKey: "2026-10-05", nowMinute: 0, language: "zh").current)
    }

    func testResolveSwitchesDayAtMidnight() throws {
        let tasks = [task("today", date: "2026-10-05", start: 600, end: 660), task("tomorrow", date: "2026-10-06", start: 540, end: 600)]
        WidgetSnapshot.write(tasks: tasks, now: date(2026, 10, 5, 12, 0), language: "en", to: directory)
        let before = WidgetSnapshot.resolve(for: date(2026, 10, 5, 23, 59), in: directory)
        let after = WidgetSnapshot.resolve(for: date(2026, 10, 6, 0, 0), in: directory)
        XCTAssertEqual(before.date, "2026-10-05")
        XCTAssertEqual(after.date, "2026-10-06")
        XCTAssertEqual(after.upcoming.map(\.id), ["tomorrow"])
        XCTAssertEqual(after.language, "en")
    }

    func testResolveRebuildsFromTasksWhenAppHasNotRunForDays() throws {
        let tasks = [task("daily", date: "2026-10-01", start: 480, end: 510, recurrence: "daily")]
        WidgetSnapshot.write(tasks: tasks, now: date(2026, 10, 5, 12, 0), language: "zh", to: directory)
        try JSONEncoder().encode(tasks).write(to: directory.appendingPathComponent(WidgetSnapshot.tasksFileName))
        let later = WidgetSnapshot.resolve(for: date(2026, 10, 9, 7, 0), in: directory)
        XCTAssertEqual(later.date, "2026-10-09")
        XCTAssertEqual(later.total, 1)
    }

    func testResolveWithNoDataIsAnEmptyDayNotASample() {
        let snapshot = WidgetSnapshot.resolve(for: date(2026, 10, 5, 9, 0), in: directory)
        XCTAssertEqual(snapshot.date, "2026-10-05")
        XCTAssertEqual(snapshot.total, 0)
        XCTAssertNil(snapshot.current)
        XCTAssertTrue(snapshot.upcoming.isEmpty)
    }

    func testOldSnapshotFileWithoutFollowingStillDecodes() throws {
        let old = #"{"date":"2026-10-05","completed":1,"total":2,"upcoming":[],"updatedAt":0}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(old.utf8))
        XCTAssertEqual(snapshot.total, 2)
        XCTAssertTrue(snapshot.following.isEmpty)
    }
}
