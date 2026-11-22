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
  var day: LocalDay
  var minuteOfDay: Int?
  var frequency: TaskFrequency = .never
}

struct VisibleTask: Identifiable {
  let id: String
  let title: String
  let notes: String
  let day: LocalDay
  let minuteOfDay: Int?
  let completed: Bool
  let completedAt: Date?
  let overdue: Bool
  let isRecurring: Bool
  let sourceID: UUID
  let sortOrder: Int
  let occurrenceDay: LocalDay?
  var occurrenceSourceDay: LocalDay { occurrenceDay ?? day }
}

func daySections(tasks: [VisibleTask], selected: LocalDay, today: LocalDay) -> (
  overdue: [VisibleTask], scheduled: [VisibleTask], anytime: [VisibleTask], completed: [VisibleTask]
) {
  let overdue = tasks.filter { $0.overdue && !$0.completed }
    .sorted { $0.day == $1.day ? $0.sortOrder < $1.sortOrder : $0.day < $1.day }
  let current = tasks.filter { !$0.overdue && ($0.day == selected || $0.completed) }
  let completed = current.filter(\.completed).sorted {
    ($0.completedAt ?? .distantPast) == ($1.completedAt ?? .distantPast)
      ? $0.sortOrder > $1.sortOrder
      : ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
  }
  let open = current.filter { !$0.completed }
  let scheduled = open.filter { $0.minuteOfDay != nil }.sorted {
    $0.minuteOfDay == $1.minuteOfDay
      ? $0.sortOrder < $1.sortOrder : $0.minuteOfDay! < $1.minuteOfDay!
  }
  let anytime = open.filter { $0.minuteOfDay == nil }.sorted { $0.sortOrder < $1.sortOrder }
  return (selected == today ? overdue : [], scheduled, anytime, completed)
}

func formatMinuteOfDay(_ minute: Int, locale: Locale = .current) -> String {
  let formatter = DateFormatter()
  formatter.locale = locale
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.setLocalizedDateFormatFromTemplate("jmm")
  return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(minute * 60)))
}

func recurrenceMatches(
  frequency: TaskFrequency, start: LocalDay, date: LocalDay, weekdays: Set<Int>
) -> Bool {
  guard date >= start else { return false }
  switch frequency {
  case .never: return date == start
  case .daily: return true
  case .weekly:
    let weekday = Calendar.current.component(.weekday, from: date.date)
    return weekdays.contains(weekday)
  }
}
