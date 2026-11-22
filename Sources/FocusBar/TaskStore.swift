import Foundation
import SwiftData
import SwiftUI

@MainActor @Observable final class TaskStore {
  private let context: ModelContext
  var error: String?
  private(set) var badgeCount = 0
  init(context: ModelContext) {
    self.context = context
    refreshBadge()
  }

  func tasks(on selected: LocalDay, today: LocalDay) -> [VisibleTask] {
    do {
      let records = try context.fetch(FetchDescriptor<TaskRecord>()).filter { !$0.deleted }
      let occurrences = try context.fetch(FetchDescriptor<OccurrenceRecord>())
      let overrides = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.key, $0) })
      var result: [VisibleTask] = []
      for task in records {
        if task.recurrence == .never {
          let isOverdue = selected == today && task.day < today && !task.completed
          if task.day == selected || isOverdue {
            result.append(
              .init(
                id: task.id.uuidString, title: task.title, notes: task.notes, day: task.day,
                minuteOfDay: task.minuteOfDay, completed: task.completed,
                completedAt: task.completedAt,
                overdue: isOverdue,
                isRecurring: false, sourceID: task.id, sortOrder: task.sortOrder, occurrenceDay: nil
              ))
          }
        } else if recurrenceMatches(
          frequency: task.recurrence, start: task.day, date: selected, weekdays: task.weekdaySet)
        {
          let key = "\(task.id.uuidString)-\(selected.key)"
          let occurrence = overrides[key]
          let visibleOnSelectedDay =
            occurrence?.rescheduledDayKey == nil || occurrence?.rescheduledDayKey == selected.key
          if occurrence?.hidden != true && visibleOnSelectedDay {
            result.append(
              .init(
                id: key, title: occurrence?.titleOverride ?? task.title,
                notes: occurrence?.notesOverride ?? task.notes, day: selected,
                minuteOfDay: occurrence?.hasMinuteOverride == true
                  ? occurrence?.minuteOverride : task.minuteOfDay,
                completed: occurrence?.completed ?? false, completedAt: occurrence?.completedAt,
                overdue: false,
                isRecurring: true,
                sourceID: task.id, sortOrder: task.sortOrder, occurrenceDay: selected))
          }
        }
      }
      for occurrence in occurrences
      where occurrence.rescheduledDayKey == selected.key && !occurrence.hidden {
        guard let task = records.first(where: { $0.id == occurrence.seriesID }),
          !result.contains(where: { $0.id == occurrence.key })
        else { continue }
        result.append(
          .init(
            id: occurrence.key, title: occurrence.titleOverride ?? task.title,
            notes: occurrence.notesOverride ?? task.notes, day: selected,
            minuteOfDay: occurrence.hasMinuteOverride
              ? occurrence.minuteOverride : task.minuteOfDay,
            completed: occurrence.completed, completedAt: occurrence.completedAt, overdue: false,
            isRecurring: true, sourceID: task.id,
            sortOrder: task.sortOrder, occurrenceDay: LocalDay(key: occurrence.dayKey)))
      }
      return result
    } catch {
      self.error = String(localized: "Unable to save. Try again.")
      return []
    }
  }

  func save(_ draft: TaskDraft, editing: VisibleTask? = nil) -> Bool {
    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return false }
    do {
      if let editing {
        if editing.isRecurring {
          let record = try occurrence(for: editing.sourceID, day: editing.occurrenceSourceDay)
          record.titleOverride = title
          record.notesOverride = draft.notes
          record.minuteOverride = draft.minuteOfDay
          record.hasMinuteOverride = true
          record.rescheduledDayKey = draft.day == editing.occurrenceSourceDay ? nil : draft.day.key
        } else if let task = try task(id: editing.sourceID) {
          task.title = title
          task.notes = draft.notes
          task.dayKey = draft.day.key
          task.minuteOfDay = draft.minuteOfDay
        }
      } else {
        let count = try context.fetchCount(FetchDescriptor<TaskRecord>())
        context.insert(
          TaskRecord(
            title: title, notes: draft.notes, day: draft.day, minuteOfDay: draft.minuteOfDay,
            sortOrder: count, frequency: draft.frequency,
            weekdays: draft.frequency == .weekly
              ? [Calendar.current.component(.weekday, from: draft.day.date)] : []))
      }
      try context.save()
      error = nil
      refreshBadge()
      return true
    } catch {
      context.rollback()
      self.error = String(localized: "Unable to save. Try again.")
      return false
    }
  }

  func toggle(_ item: VisibleTask) {
    do {
      if item.isRecurring {
        let record = try occurrence(for: item.sourceID, day: item.occurrenceSourceDay)
        record.completed.toggle()
        record.completedAt = record.completed ? .now : nil
      } else if let task = try task(id: item.sourceID) {
        task.completed.toggle()
        task.completedAt = task.completed ? .now : nil
      }
      try context.save()
      error = nil
      refreshBadge()
    } catch {
      context.rollback()
      self.error = String(localized: "Unable to save. Try again.")
    }
  }

  func moveToTomorrow(_ item: VisibleTask, today: LocalDay) {
    do {
      if item.isRecurring {
        let record = try occurrence(for: item.sourceID, day: item.occurrenceSourceDay)
        record.rescheduledDayKey = today.addingDays(1).key
      } else if let task = try task(id: item.sourceID) {
        task.dayKey = today.addingDays(1).key
      }
      try context.save()
      error = nil
      refreshBadge()
    } catch {
      context.rollback()
      self.error = String(localized: "Unable to save. Try again.")
    }
  }

  func delete(_ item: VisibleTask) {
    do {
      if item.isRecurring {
        let record = try occurrence(for: item.sourceID, day: item.occurrenceSourceDay)
        record.hidden = true
      } else if let task = try task(id: item.sourceID) {
        task.deleted = true
      }
      try context.save()
      error = nil
      refreshBadge()
    } catch {
      context.rollback()
      self.error = String(localized: "Unable to save. Try again.")
    }
  }

  func deleteSeries(_ item: VisibleTask) {
    do {
      if let task = try task(id: item.sourceID) { task.deleted = true }
      try context.save()
      error = nil
      refreshBadge()
    } catch {
      context.rollback()
      self.error = String(localized: "Unable to save. Try again.")
    }
  }

  func refreshBadge() {
    let today = LocalDay(.now)
    badgeCount = tasks(on: today, today: today).filter { !$0.completed }.count
  }

  private func task(id: UUID) throws -> TaskRecord? {
    try context.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first
  }
  private func occurrence(for id: UUID, day: LocalDay) throws -> OccurrenceRecord {
    let key = "\(id.uuidString)-\(day.key)"
    if let record = try context.fetch(
      FetchDescriptor<OccurrenceRecord>(predicate: #Predicate { $0.key == key })
    ).first {
      return record
    }
    let record = OccurrenceRecord(seriesID: id, day: day)
    context.insert(record)
    return record
  }
}
