import SQLite3
import SwiftData
import XCTest

@testable import FocusBar

final class DomainTests: XCTestCase {
  private func day(_ value: String) -> LocalDay { LocalDay(key: value) }

  func testDateOnlyRoundTripsAcrossCalendarDays() {
    let selected = day("2026-11-22")
    XCTAssertEqual(LocalDay(selected.date).key, "2026-11-22")
    XCTAssertEqual(selected.addingDays(1).key, "2026-11-23")
  }

  func testQuickAddDoesNotSubmitDuringIMECompositionOrDuplicateSaves() {
    XCTAssertFalse(canSubmitQuickAdd(title: "中文", hasMarkedText: true, isSubmitting: false))
    XCTAssertFalse(canSubmitQuickAdd(title: "   ", hasMarkedText: false, isSubmitting: false))
    XCTAssertFalse(canSubmitQuickAdd(title: "Task", hasMarkedText: false, isSubmitting: true))
    XCTAssertTrue(canSubmitQuickAdd(title: "Task", hasMarkedText: false, isSubmitting: false))
  }

  func testRecurrenceUsesOnlyFrequencyAndWeekday() {
    let previous = day("2026-11-22")
    let current = day("2026-11-23")
    let weekday = Calendar.current.component(.weekday, from: current.date)

    XCTAssertTrue(recurrenceMatches(frequency: .daily, date: current, weekdays: []))
    XCTAssertTrue(recurrenceMatches(frequency: .weekly, date: current, weekdays: [weekday]))
    XCTAssertFalse(recurrenceMatches(frequency: .weekly, date: current, weekdays: []))
    XCTAssertFalse(recurrenceMatches(frequency: .never, date: previous, weekdays: [weekday]))
  }

  func testSectionsSortByDeadlineTimeAndStableOrder() {
    func task(
      _ id: String, _ minute: Int?, _ order: Int, dueDay: LocalDay? = nil,
      completed: Bool = false, overdue: Bool = false
    ) -> VisibleTask {
      VisibleTask(
        id: id, title: id, notes: "", dueDay: dueDay, minuteOfDay: minute,
        completed: completed, completedAt: nil, overdue: overdue, isRecurring: false,
        sourceID: UUID(), sortOrder: order, occurrenceDay: nil)
    }

    let result = taskSections(tasks: [
      task("late", 900, 1), task("early", 600, 2), task("any-2", nil, 2),
      task("any-1", nil, 1), task("overdue", nil, 3, dueDay: day("2026-11-20"), overdue: true),
      task("done", nil, 4, completed: true),
    ])
    XCTAssertEqual(result.overdue.map(\.id), ["overdue"])
    XCTAssertEqual(result.scheduled.map(\.id), ["early", "late"])
    XCTAssertEqual(result.anytime.map(\.id), ["any-1", "any-2"])
    XCTAssertEqual(result.completed.map(\.id), ["done"])
  }
}

@MainActor final class TaskStoreTests: XCTestCase {
  private final class BackupSpy: TaskBackupSyncing {
    var scheduledCount = 0
    func scheduleSync() { scheduledCount += 1 }
  }

  private struct Fixture {
    let container: ModelContainer
    let store: TaskStore
  }

  private func makeStore() throws -> Fixture {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return Fixture(container: container, store: TaskStore(context: container.mainContext))
  }

  func testLegacyPlannedDateDoesNotHideOrMarkTaskOverdue() throws {
    let fixture = try makeStore()
    let container = fixture.container
    let store = fixture.store
    let today = LocalDay(key: "2026-11-25")
    let task = TaskRecord(title: "Long-term")
    task.dayKey = "2026-11-22"
    container.mainContext.insert(task)
    try container.mainContext.save()

    let visible = try XCTUnwrap(store.tasks(today: today).first)
    XCTAssertEqual(visible.title, "Long-term")
    XCTAssertFalse(visible.overdue)
    XCTAssertNil(visible.dueDay)
  }

  func testOnlyExplicitPastDeadlineCausesOverdue() throws {
    let fixture = try makeStore()
    let store = fixture.store
    let today = LocalDay(key: "2026-11-25")
    XCTAssertTrue(store.save(TaskDraft(title: "No deadline")))
    XCTAssertTrue(store.save(TaskDraft(title: "Past deadline", dueDay: today.addingDays(-1))))
    XCTAssertTrue(store.save(TaskDraft(title: "Due today", dueDay: today)))

    let tasks = store.tasks(today: today)
    XCTAssertTrue(tasks.first(where: { $0.title == "No deadline" })?.overdue == false)
    XCTAssertTrue(tasks.first(where: { $0.title == "Past deadline" })?.overdue == true)
    XCTAssertTrue(tasks.first(where: { $0.title == "Due today" })?.overdue == false)
  }

  func testDeadlineCanBeSetAndClearedWhenEditing() throws {
    let fixture = try makeStore()
    let store = fixture.store
    let due = LocalDay(.now).addingDays(10)
    XCTAssertTrue(store.save(TaskDraft(title: "Long-term")))
    var item = try XCTUnwrap(store.tasks(today: LocalDay(.now)).first)
    XCTAssertNil(item.dueDay)

    XCTAssertTrue(store.save(TaskDraft(title: item.title, dueDay: due), editing: item))
    item = try XCTUnwrap(store.tasks(today: LocalDay(.now)).first)
    XCTAssertEqual(item.dueDay, due)

    XCTAssertTrue(store.save(TaskDraft(title: item.title), editing: item))
    XCTAssertNil(store.tasks(today: LocalDay(.now)).first?.dueDay)
  }

  func testSuccessfulTaskChangesScheduleGitHubBackup() throws {
    let fixture = try makeStore()
    let backup = BackupSpy()
    let store = TaskStore(context: fixture.container.mainContext, backup: backup)
    XCTAssertTrue(store.save(TaskDraft(title: "Sync me")))
    var task = try XCTUnwrap(store.tasks(today: LocalDay(.now)).first)
    XCTAssertEqual(backup.scheduledCount, 1)

    XCTAssertTrue(store.save(TaskDraft(title: "Updated"), editing: task))
    task = try XCTUnwrap(store.tasks(today: LocalDay(.now)).first)
    XCTAssertEqual(backup.scheduledCount, 2)

    store.toggle(task)
    XCTAssertEqual(backup.scheduledCount, 3)
    store.delete(task)
    XCTAssertEqual(backup.scheduledCount, 4)
    store.restore(task, series: false)
    XCTAssertEqual(backup.scheduledCount, 5)
  }

  func testDailyOccurrenceCompletionIsIndependentByDate() throws {
    let fixture = try makeStore()
    let store = fixture.store
    let today = LocalDay(.now)
    XCTAssertTrue(store.save(TaskDraft(title: "Read", frequency: .daily)))
    let todaysTask = try XCTUnwrap(store.tasks(today: today).first)
    let revisionBeforeToggle = store.revision
    store.toggle(todaysTask)
    XCTAssertGreaterThan(store.revision, revisionBeforeToggle)
    XCTAssertTrue(store.tasks(today: today).first?.completed == true)

    XCTAssertFalse(store.tasks(today: today.addingDays(1)).first?.completed == true)
  }

  func testWeeklyOccurrenceUsesSelectedWeekdayWithoutStartDate() throws {
    let fixture = try makeStore()
    let store = fixture.store
    let nextYearDay = LocalDay(key: "2027-11-25")
    let weekday = Calendar.current.component(.weekday, from: nextYearDay.date)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Review", frequency: .weekly, weekdays: [weekday])))

    XCTAssertEqual(store.tasks(today: nextYearDay).map(\.title), ["Review"])
    XCTAssertTrue(store.tasks(today: nextYearDay.addingDays(1)).isEmpty)
  }

  func testRecurringDeadlineAppliesOnlyToCreatedOccurrence() throws {
    let fixture = try makeStore()
    let store = fixture.store
    let today = LocalDay(.now)
    let due = today.addingDays(2)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Read", dueDay: due, frequency: .daily)))
    var occurrence = try XCTUnwrap(store.tasks(today: today).first)
    XCTAssertEqual(occurrence.dueDay, due)
    XCTAssertNil(store.tasks(today: today.addingDays(1)).first?.dueDay)

    let updatedDue = today.addingDays(4)
    XCTAssertTrue(
      store.save(TaskDraft(title: occurrence.title, dueDay: updatedDue), editing: occurrence))
    occurrence = try XCTUnwrap(store.tasks(today: today).first)
    XCTAssertEqual(occurrence.dueDay, updatedDue)
    XCTAssertNil(store.tasks(today: today.addingDays(1)).first?.dueDay)
  }

  func testRecurringOccurrenceCanClearItsTimeWithoutChangingSeries() throws {
    let fixture = try makeStore()
    let store = fixture.store
    let today = LocalDay(.now)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Read", minuteOfDay: 600, frequency: .daily)))
    let item = try XCTUnwrap(store.tasks(today: today).first)
    XCTAssertTrue(store.save(TaskDraft(title: "Read"), editing: item))
    XCTAssertNil(store.tasks(today: today).first?.minuteOfDay)
    XCTAssertEqual(store.tasks(today: today.addingDays(1)).first?.minuteOfDay, 600)
  }

  func testDeleteOccurrenceAndSeriesRemainIndependent() throws {
    let fixture = try makeStore()
    let store = fixture.store
    let today = LocalDay(.now)
    XCTAssertTrue(store.save(TaskDraft(title: "Read", frequency: .daily)))
    let current = try XCTUnwrap(store.tasks(today: today).first)
    store.delete(current)

    XCTAssertTrue(store.tasks(today: today).isEmpty)
    XCTAssertEqual(store.tasks(today: today.addingDays(1)).count, 1)
    let next = try XCTUnwrap(store.tasks(today: today.addingDays(1)).first)
    store.deleteSeries(next)
    XCTAssertTrue(store.tasks(today: today.addingDays(1)).isEmpty)
    XCTAssertTrue(store.tasks(today: today.addingDays(2)).isEmpty)
  }

  func testThousandTasksAreAllVisibleRegardlessOfLegacyDate() throws {
    let fixture = try makeStore()
    let container = fixture.container
    let store = fixture.store
    for index in 0..<1_000 {
      let item = TaskRecord(title: "Task \(index)", sortOrder: index)
      item.dayKey = "2020-01-01"
      container.mainContext.insert(item)
    }
    try container.mainContext.save()
    XCTAssertEqual(store.tasks(today: LocalDay(.now)).count, 1_000)
  }

  func testTaskSurvivesReopeningPersistentStore() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("sqlite")
    defer {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(atPath: url.path + "-shm")
      try? FileManager.default.removeItem(atPath: url.path + "-wal")
    }
    let today = LocalDay(.now)

    do {
      let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [config])
      let store = TaskStore(context: container.mainContext)
      XCTAssertTrue(
        store.save(TaskDraft(title: "Persist me", dueDay: today.addingDays(7))))
      let task = try XCTUnwrap(store.tasks(today: today).first)
      store.toggle(task)
    }
    do {
      let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [config])
      let records = try container.mainContext.fetch(FetchDescriptor<TaskRecord>())
      XCTAssertEqual(records.map(\.title), ["Persist me"])
      XCTAssertTrue(records.first?.completed == true)
      XCTAssertEqual(records.first?.dueDay, today.addingDays(7))
    }
  }

  func testSQLiteSnapshotIsConsistentWhileStoreIsOpen() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("sqlite")
    defer {
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(atPath: source.path + "-shm")
      try? FileManager.default.removeItem(atPath: source.path + "-wal")
    }
    let configuration = ModelConfiguration(schema: schema, url: source, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    XCTAssertTrue(store.save(TaskDraft(title: "Snapshot test", notes: "Keeps local text")))

    let snapshot = try SQLiteSnapshot.make(from: source)
    defer { try? FileManager.default.removeItem(at: snapshot) }
    var database: OpaquePointer?
    let openResult = sqlite3_open_v2(snapshot.path, &database, SQLITE_OPEN_READONLY, nil)
    guard openResult == SQLITE_OK, let database else {
      XCTFail("Snapshot open failed with SQLite code \(openResult)")
      return
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    let prepareResult = sqlite3_prepare_v2(database, "PRAGMA integrity_check", -1, &statement, nil)
    guard prepareResult == SQLITE_OK, let statement else {
      XCTFail("Snapshot query failed: \(String(cString: sqlite3_errmsg(database)))")
      return
    }
    defer { sqlite3_finalize(statement) }
    XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
    guard let result = sqlite3_column_text(statement, 0) else {
      XCTFail("Snapshot integrity result was empty")
      return
    }
    XCTAssertEqual(String(cString: result), "ok")
  }
}
