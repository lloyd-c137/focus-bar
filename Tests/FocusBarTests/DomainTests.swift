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

  func testDailyAndWeeklyRecurrenceBoundaries() {
    XCTAssertTrue(
      recurrenceMatches(
        frequency: .daily, start: day("2026-11-22"), date: day("2026-11-23"), weekdays: []))
    XCTAssertFalse(
      recurrenceMatches(
        frequency: .daily, start: day("2026-11-23"), date: day("2026-11-22"), weekdays: []))
    let weekday = Calendar.current.component(.weekday, from: day("2026-11-23").date)
    XCTAssertTrue(
      recurrenceMatches(
        frequency: .weekly, start: day("2026-11-22"), date: day("2026-11-23"), weekdays: [weekday]))
  }

  func testSectionsSortTimedTasksAndPreserveAnytimeOrder() {
    func task(
      _ id: String, _ minute: Int?, _ order: Int, day: LocalDay? = nil, overdue: Bool = false
    ) -> VisibleTask {
      VisibleTask(
        id: id, title: id, notes: "", day: day ?? self.day("2026-11-22"), minuteOfDay: minute,
        completed: false, completedAt: nil, overdue: overdue, isRecurring: false, sourceID: UUID(),
        sortOrder: order,
        occurrenceDay: nil)
    }
    let selected = day("2026-11-22")
    let result = daySections(
      tasks: [
        task("late", 900, 1), task("early", 600, 2), task("any-2", nil, 2), task("any-1", nil, 1),
      ], selected: selected, today: selected)
    XCTAssertEqual(result.scheduled.map(\.id), ["early", "late"])
    XCTAssertEqual(result.anytime.map(\.id), ["any-1", "any-2"])
  }
}

@MainActor final class TaskStoreTests: XCTestCase {
  func testDailyOccurrenceCompletionIsIndependentByDate() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let today = LocalDay(.now)

    XCTAssertTrue(
      store.save(TaskDraft(title: "Read", day: today, minuteOfDay: nil, frequency: .daily)))
    let todaysTask = try XCTUnwrap(store.tasks(on: today, today: today).first)
    store.toggle(todaysTask)
    XCTAssertTrue(store.tasks(on: today, today: today).first?.completed == true)

    let tomorrow = today.addingDays(1)
    let tomorrowTask = try XCTUnwrap(store.tasks(on: tomorrow, today: today).first)
    XCTAssertFalse(tomorrowTask.completed)
  }

  func testRecurringOccurrenceCanBeRescheduledWithoutChangingSeries() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let today = LocalDay(.now)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Walk", day: today, minuteOfDay: nil, frequency: .daily)))
    let current = try XCTUnwrap(store.tasks(on: today, today: today).first)
    let tomorrow = today.addingDays(1)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Walk", day: tomorrow, minuteOfDay: nil), editing: current))

    XCTAssertTrue(store.tasks(on: today, today: today).isEmpty)
    XCTAssertEqual(store.tasks(on: tomorrow, today: today).count, 2)
    XCTAssertEqual(store.tasks(on: today.addingDays(2), today: today).count, 1)
  }

  func testOverdueClassificationDependsOnTheSelectedDay() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let today = LocalDay(.now)
    let yesterday = today.addingDays(-1)
    container.mainContext.insert(TaskRecord(title: "Earlier", day: yesterday))
    try container.mainContext.save()

    XCTAssertTrue(store.tasks(on: yesterday, today: today).first?.overdue == false)
    XCTAssertTrue(store.tasks(on: today, today: today).first?.overdue == true)
  }

  func testRecurringOccurrenceCanClearItsTimeWithoutChangingSeries() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let today = LocalDay(.now)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Read", day: today, minuteOfDay: 600, frequency: .daily)))
    let item = try XCTUnwrap(store.tasks(on: today, today: today).first)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Read", day: today, minuteOfDay: nil), editing: item))
    XCTAssertNil(store.tasks(on: today, today: today).first?.minuteOfDay)
    XCTAssertEqual(store.tasks(on: today.addingDays(1), today: today).first?.minuteOfDay, 600)
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

    do {
      let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [config])
      let store = TaskStore(context: container.mainContext)
      XCTAssertTrue(
        store.save(TaskDraft(title: "Persist me", day: LocalDay(.now), minuteOfDay: nil)))
      let task = try XCTUnwrap(store.tasks(on: LocalDay(.now), today: LocalDay(.now)).first)
      store.toggle(task)
    }
    do {
      let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [config])
      let records = try container.mainContext.fetch(FetchDescriptor<TaskRecord>())
      XCTAssertEqual(records.map(\.title), ["Persist me"])
      XCTAssertTrue(records.first?.completed == true)
    }
  }

}
