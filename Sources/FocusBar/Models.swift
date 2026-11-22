import Foundation
import SwiftData

@Model final class TaskRecord {
  @Attribute(.unique) var id: UUID
  var title: String
  var notes: String
  var dayKey: String
  var dueDayKey: String?
  var minuteOfDay: Int?
  var sortOrder: Int
  var frequency: String
  var weekdays: String
  var createdAt: Date
  var completed: Bool
  var completedAt: Date?
  var deleted: Bool

  init(
    title: String, notes: String = "", day: LocalDay, minuteOfDay: Int? = nil, sortOrder: Int = 0,
    frequency: TaskFrequency = .never, weekdays: Set<Int> = [], dueDay: LocalDay? = nil,
    id: UUID = UUID()
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.dayKey = day.key
    self.dueDayKey = dueDay?.key
    self.minuteOfDay = minuteOfDay
    self.sortOrder = sortOrder
    self.frequency = frequency.rawValue
    self.weekdays = weekdays.sorted().map(String.init).joined(separator: ",")
    self.createdAt = .now
    self.completed = false
    self.completedAt = nil
    self.deleted = false
  }
  var day: LocalDay { LocalDay(key: dayKey) }
  var dueDay: LocalDay? { dueDayKey.map(LocalDay.init(key:)) }
  var recurrence: TaskFrequency { TaskFrequency(rawValue: frequency) ?? .never }
  var weekdaySet: Set<Int> { Set(weekdays.split(separator: ",").compactMap { Int($0) }) }
}

@Model final class OccurrenceRecord {
  @Attribute(.unique) var key: String
  var seriesID: UUID
  var dayKey: String
  var completed: Bool
  var hidden: Bool
  var dueDayKey: String?
  var hasDueDayOverride = false
  var titleOverride: String?
  var notesOverride: String?
  var minuteOverride: Int?
  var hasMinuteOverride: Bool
  var rescheduledDayKey: String?
  var completedAt: Date?
  var dueDay: LocalDay? { dueDayKey.map(LocalDay.init(key:)) }
  init(seriesID: UUID, day: LocalDay) {
    self.seriesID = seriesID
    self.dayKey = day.key
    self.key = "\(seriesID.uuidString)-\(day.key)"
    self.completed = false
    self.hasMinuteOverride = false
    self.hidden = false
  }
}
