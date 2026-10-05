import XCTest

final class TaskRepositoryTests: XCTestCase {
    private var directory: URL!
    private var repository: TaskRepository!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("dw-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = TaskRepository(directory: directory, reloadsWidgets: false)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func task(_ id: String, title: String = "Task", date: String? = "2026-10-05", start: Int? = 540, end: Int? = 570, updatedAt: String = "2026-10-05T00:00:00Z") -> PlannerTask {
        PlannerTask(id: id, date: date, start: start, end: end, title: title, createdAt: updatedAt, updatedAt: updatedAt, updatedBy: "test")
    }

    func testLoadWithoutFileIsEmpty() throws {
        XCTAssertEqual(try repository.load(), [])
    }

    func testUpsertInsertsThenReplaces() throws {
        try repository.upsert(task("a", title: "First"))
        try repository.upsert(task("b"))
        try repository.upsert(task("a", title: "Renamed"))
        let tasks = try repository.load()
        XCTAssertEqual(tasks.map(\.id), ["a", "b"])
        XCTAssertEqual(tasks.first?.title, "Renamed")
    }

    /// The case that used to lose data: one process holds an old copy in memory while another writes.
    func testWritersWithStaleMemoryDoNotOverwriteEachOther() throws {
        try repository.upsert(task("a"))
        let appProcess = TaskRepository(directory: directory, reloadsWidgets: false)
        let widgetProcess = TaskRepository(directory: directory, reloadsWidgets: false)
        _ = try appProcess.load()
        try widgetProcess.toggleDone(taskID: "a", dateKey: "2026-10-05", deviceID: "widget")
        try appProcess.upsert(task("b", title: "Added by voice"))
        let tasks = try repository.load()
        XCTAssertEqual(tasks.map(\.id), ["a", "b"])
        XCTAssertEqual(tasks.first?.done, true)
        XCTAssertEqual(tasks.first?.updatedBy, "widget")
    }

    func testToggleDoneOnRecurringTaskUsesTheDate() throws {
        var daily = task("r")
        daily.recurrence = "daily"
        try repository.upsert(daily)
        try repository.toggleDone(taskID: "r", dateKey: "2026-10-06", deviceID: "widget")
        var stored = try XCTUnwrap(try repository.load().first)
        XCTAssertFalse(stored.done)
        XCTAssertEqual(stored.completedDates, ["2026-10-06"])
        try repository.toggleDone(taskID: "r", dateKey: "2026-10-06", deviceID: "widget")
        stored = try XCTUnwrap(try repository.load().first)
        XCTAssertEqual(stored.completedDates, [])
    }

    func testUnreadableFileIsNotReplaced() throws {
        let garbage = Data("not json".utf8)
        try garbage.write(to: repository.tasksURL)
        XCTAssertThrowsError(try repository.upsert(task("a")))
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try Data(contentsOf: repository.tasksURL), garbage)
    }

    func testMutateWritesSnapshotForTodayAndTomorrow() throws {
        let today = Date().dayKey
        try repository.upsert(task("a", date: today), language: "en")
        let snapshot = try XCTUnwrap(WidgetSnapshot.stored(in: directory))
        XCTAssertEqual(snapshot.date, today)
        XCTAssertEqual(snapshot.total, 1)
        XCTAssertEqual(snapshot.language, "en")
        XCTAssertEqual(snapshot.following.count, 1)
    }

    func testMergeKeepsNewerRecordAndBothSides() {
        let local = [task("a", title: "old", updatedAt: "2026-10-05T08:00:00Z"), task("b", title: "local only")]
        let incoming = [task("a", title: "new", updatedAt: "2026-10-05T09:00:00Z"), task("c", title: "remote only")]
        let merged = TaskRepository.merge(local, with: incoming)
        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(merged.first?.title, "new")
        let reversed = TaskRepository.merge(incoming, with: local)
        XCTAssertEqual(reversed.first(where: { $0.id == "a" })?.title, "new")
    }
}

final class TimeDragTests: XCTestCase {
    func testCreateStartsWithThirtyMinutesAndStretchesDown() {
        XCTAssertTrue(TimeDrag.create(anchor: 600, finger: 600) == (600, 630))
        XCTAssertTrue(TimeDrag.create(anchor: 600, finger: 688) == (600, 690))
    }

    func testCreateAboveTheAnchorMovesTheStartUp() {
        XCTAssertTrue(TimeDrag.create(anchor: 600, finger: 541) == (540, 630))
    }

    func testCreateStaysInsideTheDay() {
        XCTAssertTrue(TimeDrag.create(anchor: 1435, finger: 2000) == (1410, 1440))
        XCTAssertTrue(TimeDrag.create(anchor: 10, finger: -50) == (0, 40))
    }

    func testMoveSnapsToFifteenMinutesAndKeepsLength() {
        XCTAssertTrue(TimeDrag.move(start: 660, end: 720, by: 22) == (675, 735))
        XCTAssertTrue(TimeDrag.move(start: 660, end: 720, by: -6) == (660, 720))
    }

    func testMoveStopsAtTheEdgesOfTheDay() {
        XCTAssertTrue(TimeDrag.move(start: 60, end: 120, by: -300) == (0, 60))
        XCTAssertTrue(TimeDrag.move(start: 1320, end: 1380, by: 300) == (1380, 1440))
    }

    func testMovePastMidnightOnlyGoesEarlier() {
        XCTAssertTrue(TimeDrag.move(start: 1380, end: 1500, by: 60) == (1380, 1500))
        XCTAssertTrue(TimeDrag.move(start: 1380, end: 1500, by: -60) == (1320, 1440))
    }

    func testResizeKeepsAtLeastFifteenMinutes() {
        XCTAssertTrue(TimeDrag.resize(start: 600, end: 660, top: true, by: 120) == (645, 660))
        XCTAssertTrue(TimeDrag.resize(start: 600, end: 660, top: false, by: -120) == (600, 615))
        XCTAssertTrue(TimeDrag.resize(start: 600, end: 660, top: false, by: 44) == (600, 705))
        XCTAssertTrue(TimeDrag.resize(start: 600, end: 660, top: true, by: -30) == (570, 660))
    }
}
