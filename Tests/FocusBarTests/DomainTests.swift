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

  private func instant(_ value: String) throws -> Date {
    try XCTUnwrap(ISO8601DateFormatter().date(from: value))
  }

  func testTodayNavigationFollowsAcrossMidnight() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
    let beforeMidnight = try instant("2026-06-02T23:59:00+08:00")
    var context = LocalDayContext(now: beforeMidnight, timeZone: zone)
    let navigation = DateNavigationState()
    XCTAssertEqual(navigation.displayedDay(today: context.today).key, "2026-06-02")

    context.refresh(now: beforeMidnight.addingTimeInterval(120), timeZone: zone)
    XCTAssertEqual(context.today.key, "2026-06-03")
    XCTAssertEqual(navigation.displayedDay(today: context.today).key, "2026-06-03")
  }

  func testPinnedDateDoesNotMoveAcrossMidnight() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
    let beforeMidnight = try instant("2026-06-02T23:59:00+08:00")
    var context = LocalDayContext(now: beforeMidnight, timeZone: zone)
    let yesterday = LocalDay(key: "2026-06-01")
    var navigation = DateNavigationState()
    navigation.select(yesterday, today: context.today)

    context.refresh(now: beforeMidnight.addingTimeInterval(120), timeZone: zone)
    XCTAssertFalse(navigation.followsToday)
    XCTAssertEqual(navigation.displayedDay(today: context.today), yesterday)
  }

  func testReturningToTodayRestoresFollowMode() throws {
    let current = LocalDay(key: "2026-06-03")
    var navigation = DateNavigationState()
    navigation.select(LocalDay(key: "2026-06-01"), today: current)
    navigation.returnToToday()
    XCTAssertTrue(navigation.followsToday)
    XCTAssertEqual(navigation.displayedDay(today: current), current)
  }

  func testWakeRefreshAdvancesTodayAfterSleep() throws {
    let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
    let beforeSleep = try instant("2026-06-02T22:00:00+08:00")
    var context = LocalDayContext(now: beforeSleep, timeZone: zone)
    let afterWake = try instant("2026-06-03T08:00:00+08:00")
    context.refresh(now: afterWake, timeZone: zone)
    XCTAssertEqual(context.today.key, "2026-06-03")
  }

  func testTimezoneChangeUpdatesTodayButKeepsPinnedCalendarDay() throws {
    let instant = try instant("2026-01-01T00:30:00Z")
    let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    var context = LocalDayContext(now: instant, timeZone: losAngeles)
    var navigation = DateNavigationState()
    let pinned = LocalDay(key: "2025-12-30")
    navigation.select(pinned, today: context.today)
    XCTAssertEqual(context.today.key, "2025-12-31")

    context.refresh(now: instant, timeZone: utc)
    XCTAssertEqual(context.today.key, "2026-01-01")
    XCTAssertEqual(navigation.displayedDay(today: context.today), pinned)
  }

  func testQuickAddDoesNotSubmitDuringIMECompositionOrDuplicateSaves() {
    XCTAssertFalse(canSubmitQuickAdd(title: "中文", hasMarkedText: true, isSubmitting: false))
    XCTAssertFalse(canSubmitQuickAdd(title: "   ", hasMarkedText: false, isSubmitting: false))
    XCTAssertFalse(canSubmitQuickAdd(title: "Task", hasMarkedText: false, isSubmitting: true))
    XCTAssertTrue(canSubmitQuickAdd(title: "Task", hasMarkedText: false, isSubmitting: false))
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
        id: id, title: id, notes: "", day: day ?? self.day("2026-11-22"), dueDay: nil,
        minuteOfDay: minute,
        completed: false, completedAt: nil, overdue: overdue, isRecurring: false, sourceID: UUID(),
        sortOrder: order,
        occurrenceDay: nil, movedFromDay: nil)
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
  func testDeadlineIsOptionalAndCanBeSetAndClearedWhenEditing() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let scheduled = LocalDay(.now)
    let due = scheduled.addingDays(10)

    XCTAssertTrue(store.save(TaskDraft(title: "Long-term", day: scheduled, minuteOfDay: nil)))
    var item = try XCTUnwrap(store.tasks(on: scheduled, today: scheduled).first)
    XCTAssertNil(item.dueDay)

    XCTAssertTrue(
      store.save(
        TaskDraft(title: item.title, day: scheduled, minuteOfDay: nil, dueDay: due), editing: item))
    item = try XCTUnwrap(store.tasks(on: scheduled, today: scheduled).first)
    XCTAssertEqual(item.day, scheduled)
    XCTAssertEqual(item.dueDay, due)

    XCTAssertTrue(
      store.save(TaskDraft(title: item.title, day: scheduled, minuteOfDay: nil), editing: item))
    XCTAssertNil(store.tasks(on: scheduled, today: scheduled).first?.dueDay)
  }

  func testRecurringDeadlineBelongsOnlyToTheCreatedOccurrence() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let today = LocalDay(.now)
    let due = today.addingDays(2)

    XCTAssertTrue(
      store.save(
        TaskDraft(title: "Read", day: today, minuteOfDay: nil, dueDay: due, frequency: .daily)))
    var occurrence = try XCTUnwrap(store.tasks(on: today, today: today).first)
    XCTAssertEqual(occurrence.dueDay, due)
    XCTAssertNil(store.tasks(on: today.addingDays(1), today: today).first?.dueDay)

    let updatedDue = today.addingDays(4)
    XCTAssertTrue(
      store.save(
        TaskDraft(title: occurrence.title, day: today, minuteOfDay: nil, dueDay: updatedDue),
        editing: occurrence))
    occurrence = try XCTUnwrap(store.tasks(on: today, today: today).first)
    XCTAssertEqual(occurrence.dueDay, updatedDue)
    XCTAssertNil(store.tasks(on: today.addingDays(1), today: today).first?.dueDay)
  }

  func testDailyOccurrenceCompletionIsIndependentByDate() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let today = LocalDay(.now)

    XCTAssertTrue(
      store.save(TaskDraft(title: "Read", day: today, minuteOfDay: nil, frequency: .daily)))
    let todaysTask = try XCTUnwrap(store.tasks(on: today, today: today).first)
    let revisionBeforeToggle = store.revision
    store.toggle(todaysTask)
    XCTAssertGreaterThan(store.revision, revisionBeforeToggle)
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
    let collisions = store.tasks(on: tomorrow, today: today)
    XCTAssertEqual(collisions.count, 2)
    XCTAssertEqual(Set(collisions.map(\.id)).count, 2)
    let moved = try XCTUnwrap(collisions.first(where: { $0.movedFromDay == today }))
    let regular = try XCTUnwrap(collisions.first(where: { $0.movedFromDay == nil }))

    store.toggle(moved)
    XCTAssertTrue(
      store.tasks(on: tomorrow, today: today).first(where: { $0.id == moved.id })?.completed == true
    )
    XCTAssertFalse(
      store.tasks(on: tomorrow, today: today).first(where: { $0.id == regular.id })?.completed
        == true)
    store.delete(regular)
    let remaining = store.tasks(on: tomorrow, today: today)
    XCTAssertEqual(remaining.count, 1)
    XCTAssertEqual(remaining.first?.id, moved.id)
    XCTAssertTrue(remaining.first?.completed == true)
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

  func testMovedOccurrenceRemainsVisibleBeforeSeriesStart() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let start = LocalDay(.now)
    let earlier = start.addingDays(-1)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Read", day: start, minuteOfDay: nil, frequency: .daily)))
    let current = try XCTUnwrap(store.tasks(on: start, today: start).first)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Read", day: earlier, minuteOfDay: nil), editing: current))

    let moved = try XCTUnwrap(store.tasks(on: earlier, today: start).first)
    XCTAssertEqual(moved.movedFromDay, start)
  }

  func testWeeklyOccurrenceConflictKeepsBothStableInstances() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let today = LocalDay(.now)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Review", day: today, minuteOfDay: nil, frequency: .weekly)))
    let current = try XCTUnwrap(store.tasks(on: today, today: today).first)
    let nextWeek = today.addingDays(7)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Review", day: nextWeek, minuteOfDay: nil), editing: current))

    let collisions = store.tasks(on: nextWeek, today: today)
    XCTAssertEqual(collisions.count, 2)
    XCTAssertEqual(Set(collisions.map(\.id)).count, 2)
    XCTAssertEqual(collisions.filter { $0.movedFromDay == today }.count, 1)
  }

  func testDeleteSeriesRemovesCurrentAndFutureOccurrences() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let today = LocalDay(.now)
    XCTAssertTrue(
      store.save(TaskDraft(title: "Read", day: today, minuteOfDay: nil, frequency: .daily)))
    let current = try XCTUnwrap(store.tasks(on: today, today: today).first)
    store.toggle(current)
    store.deleteSeries(current)

    XCTAssertTrue(store.tasks(on: today, today: today).isEmpty)
    XCTAssertTrue(store.tasks(on: today.addingDays(1), today: today).isEmpty)
  }

  func testMovedConflictPersistsWithIndependentCompletion() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("sqlite")
    defer {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(atPath: url.path + "-shm")
      try? FileManager.default.removeItem(atPath: url.path + "-wal")
    }
    let today = LocalDay(.now)
    let tomorrow = today.addingDays(1)

    do {
      let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [config])
      let store = TaskStore(context: container.mainContext)
      XCTAssertTrue(
        store.save(TaskDraft(title: "Read", day: today, minuteOfDay: nil, frequency: .daily)))
      let current = try XCTUnwrap(store.tasks(on: today, today: today).first)
      XCTAssertTrue(
        store.save(TaskDraft(title: "Read", day: tomorrow, minuteOfDay: nil), editing: current))
      let moved = try XCTUnwrap(
        store.tasks(on: tomorrow, today: today).first(where: { $0.movedFromDay == today }))
      store.toggle(moved)
    }
    do {
      let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [config])
      let store = TaskStore(context: container.mainContext)
      let firstRead = store.tasks(on: tomorrow, today: today)
      let secondRead = store.tasks(on: tomorrow, today: today)
      XCTAssertEqual(firstRead.count, 2)
      XCTAssertEqual(Set(firstRead.map(\.id)).count, 2)
      XCTAssertEqual(firstRead.count, secondRead.count)
      XCTAssertTrue(firstRead.first(where: { $0.movedFromDay == today })?.completed == true)
      XCTAssertFalse(firstRead.first(where: { $0.movedFromDay == nil })?.completed == true)
    }
  }

  func testFilteredQueryHandlesOneThousandTasks() throws {
    let schema = Schema([TaskRecord.self, OccurrenceRecord.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = TaskStore(context: container.mainContext)
    let today = LocalDay(.now)
    for index in 0..<1_000 {
      container.mainContext.insert(
        TaskRecord(title: "Task \(index)", day: today.addingDays(index % 31), sortOrder: index))
    }
    try container.mainContext.save()

    XCTAssertEqual(store.tasks(on: today.addingDays(30), today: today).count, 32)
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
        store.save(
          TaskDraft(
            title: "Persist me", day: LocalDay(.now), minuteOfDay: nil,
            dueDay: LocalDay(.now).addingDays(7))))
      let task = try XCTUnwrap(store.tasks(on: LocalDay(.now), today: LocalDay(.now)).first)
      store.toggle(task)
    }
    do {
      let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [config])
      let records = try container.mainContext.fetch(FetchDescriptor<TaskRecord>())
      XCTAssertEqual(records.map(\.title), ["Persist me"])
      XCTAssertTrue(records.first?.completed == true)
      XCTAssertEqual(records.first?.dueDay, LocalDay(.now).addingDays(7))
    }
  }

}
