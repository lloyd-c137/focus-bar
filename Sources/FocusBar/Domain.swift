import Foundation

struct LocalDay: Hashable, Comparable, Codable {
  let key: String
  init(_ date: Date, calendar: Calendar = .current) {
    var localGregorian = Calendar(identifier: .gregorian)
    localGregorian.timeZone = calendar.timeZone
    let parts = localGregorian.dateComponents([.year, .month, .day], from: date)
    key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
  init(key: String) { self.key = key }
  var date: Date {
    let p = key.split(separator: "-").compactMap { Int($0) }
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .current
    return c.date(from: DateComponents(year: p[safe: 0], month: p[safe: 1], day: p[safe: 2]))
      ?? .now
  }
  static func < (lhs: Self, rhs: Self) -> Bool { lhs.key < rhs.key }
  func addingDays(_ count: Int, calendar: Calendar = .current) -> Self {
    Self(calendar.date(byAdding: .day, value: count, to: date) ?? date, calendar: calendar)
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

enum TaskFrequency: String, CaseIterable, Identifiable {
  case never, daily, weekly
  var id: String { rawValue }
  var label: String {
    switch self {
    case .never: String(localized: "Never")
    case .daily: String(localized: "Daily")
    case .weekly: String(localized: "Weekly")
    }
  }
}

struct TaskDraft {
  var title = ""
  var notes = ""
  var minuteOfDay: Int?
  var dueDay: LocalDay? = nil
  var frequency: TaskFrequency = .never
  var weekdays: Set<Int> = []
}

struct VisibleTask: Identifiable {
  let id: String
  let title: String
  let notes: String
  let dueDay: LocalDay?
  let minuteOfDay: Int?
  let completed: Bool
  let completedAt: Date?
  let overdue: Bool
  let isRecurring: Bool
  let sourceID: UUID
  let sortOrder: Int
  let occurrenceDay: LocalDay?
  var occurrenceSourceDay: LocalDay { occurrenceDay ?? LocalDay(.now) }
}

struct TaskSections {
  let overdue: [VisibleTask]
  let scheduled: [VisibleTask]
  let anytime: [VisibleTask]
  let completed: [VisibleTask]
  var hasOpen: Bool { !(overdue.isEmpty && scheduled.isEmpty && anytime.isEmpty) }
}

func taskSections(tasks: [VisibleTask]) -> TaskSections {
  let overdue = tasks.filter { $0.overdue && !$0.completed }
    .sorted {
      if $0.dueDay != $1.dueDay {
        return ($0.dueDay?.key ?? "") < ($1.dueDay?.key ?? "")
      }
      if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
      return $0.id < $1.id
    }
  let completed = tasks.filter(\.completed).sorted {
    ($0.completedAt ?? .distantPast) == ($1.completedAt ?? .distantPast)
      ? ($0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder > $1.sortOrder)
      : ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
  }
  let open = tasks.filter { !$0.completed && !$0.overdue }
  let scheduled = open.filter { $0.minuteOfDay != nil }.sorted {
    if $0.minuteOfDay != $1.minuteOfDay { return $0.minuteOfDay! < $1.minuteOfDay! }
    if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
    return $0.id < $1.id
  }
  let anytime = open.filter { $0.minuteOfDay == nil }.sorted {
    $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder
  }
  return TaskSections(
    overdue: overdue, scheduled: scheduled, anytime: anytime, completed: completed)
}

private final class MinuteFormatterCache: @unchecked Sendable {
  static let shared = MinuteFormatterCache()
  private let lock = NSLock()
  private var formatters: [String: DateFormatter] = [:]

  func string(for minute: Int, locale: Locale) -> String {
    lock.lock()
    defer { lock.unlock() }
    let key = locale.identifier
    let formatter: DateFormatter
    if let existing = formatters[key] {
      formatter = existing
    } else {
      let created = DateFormatter()
      created.locale = locale
      created.timeZone = TimeZone(secondsFromGMT: 0)
      created.setLocalizedDateFormatFromTemplate("jmm")
      formatters[key] = created
      formatter = created
    }
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(minute * 60)))
  }
}

func formatMinuteOfDay(_ minute: Int, locale: Locale = .current) -> String {
  MinuteFormatterCache.shared.string(for: minute, locale: locale)
}

func recurrenceMatches(frequency: TaskFrequency, date: LocalDay, weekdays: Set<Int>) -> Bool {
  switch frequency {
  case .never: return false
  case .daily: return true
  case .weekly:
    let weekday = Calendar.current.component(.weekday, from: date.date)
    return weekdays.contains(weekday)
  }
}

func nextOccurrenceDay(
  frequency: TaskFrequency, from day: LocalDay, weekdays: Set<Int>
) -> LocalDay {
  (0...7).map { day.addingDays($0) }.first {
    recurrenceMatches(frequency: frequency, date: $0, weekdays: weekdays)
  } ?? day
}

struct LocalDayContext: Equatable {
  private(set) var today: LocalDay
  private(set) var timeZoneIdentifier: String

  init(now: Date = .now, timeZone: TimeZone = .current) {
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    today = LocalDay(now, calendar: calendar)
    timeZoneIdentifier = timeZone.identifier
  }

  mutating func refresh(now: Date, timeZone: TimeZone) {
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    today = LocalDay(now, calendar: calendar)
    timeZoneIdentifier = timeZone.identifier
  }
}

func canSubmitQuickAdd(title: String, hasMarkedText: Bool, isSubmitting: Bool) -> Bool {
  !hasMarkedText && !isSubmitting && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
