import Foundation
import SwiftData
import SwiftUI

@MainActor @Observable final class TaskStore {
  private let context: ModelContext
  var error: String?
  private(set) var badgeCount = 0
  private(set) var revision = 0
  init(context: ModelContext) {
    self.context = context
    refreshBadge()
  }

  func tasks(on selected: LocalDay, today: LocalDay) -> [VisibleTask] {
    _ = revision
    do {
      let selectedKey = selected.key
      let todayKey = today.key
      let includeOverdue = selected == today
      let occurrencePredicate = #Predicate<OccurrenceRecord> { occurrence in
        occurrence.dayKey == selectedKey || occurrence.rescheduledDayKey == selectedKey
      }
      let occurrences = try context.fetch(
        FetchDescriptor<OccurrenceRecord>(predicate: occurrencePredicate))
      let movedSeriesIDs =
        occurrences
        .filter { $0.rescheduledDayKey == selectedKey && !$0.hidden }
        .map(\.seriesID)
      let taskPredicate = #Predicate<TaskRecord> { task in
        !task.deleted
          && (task.dayKey == selectedKey
            || (includeOverdue && task.dayKey < todayKey && task.frequency == "never"
              && !task.completed)
            || (task.dayKey <= selectedKey && task.frequency != "never")
            || movedSeriesIDs.contains(task.id))
      }
      let records = try context.fetch(FetchDescriptor<TaskRecord>(predicate: taskPredicate))
      let overrides = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.key, $0) })
      let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
      var result: [VisibleTask] = []
      for task in records {
        if task.recurrence == .never {
          let isOverdue = selected == today && task.day < today && !task.completed
          if task.day == selected || isOverdue {
            result.append(
              .init(
                id: task.id.uuidString, title: task.title, notes: task.notes, day: task.day,
                dueDay: task.dueDay,
                minuteOfDay: task.minuteOfDay, completed: task.completed,
                completedAt: task.completedAt,
                overdue: isOverdue,
                isRecurring: false, sourceID: task.id, sortOrder: task.sortOrder,
                occurrenceDay: nil, movedFromDay: nil
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
                dueDay: occurrence?.hasDueDayOverride == true ? occurrence?.dueDay : nil,
                minuteOfDay: occurrence?.hasMinuteOverride == true
                  ? occurrence?.minuteOverride : task.minuteOfDay,
                completed: occurrence?.completed ?? false, completedAt: occurrence?.completedAt,
                overdue: false,
                isRecurring: true,
                sourceID: task.id, sortOrder: task.sortOrder, occurrenceDay: selected,
                movedFromDay: nil))
          }
        }
      }
      for occurrence in occurrences
      where occurrence.rescheduledDayKey == selected.key && !occurrence.hidden {
        guard let task = recordsByID[occurrence.seriesID],
          !result.contains(where: { $0.id == occurrence.key })
        else { continue }
        result.append(
          .init(
            id: occurrence.key, title: occurrence.titleOverride ?? task.title,
            notes: occurrence.notesOverride ?? task.notes, day: selected,
            dueDay: occurrence.hasDueDayOverride ? occurrence.dueDay : nil,
            minuteOfDay: occurrence.hasMinuteOverride
              ? occurrence.minuteOverride : task.minuteOfDay,
            completed: occurrence.completed, completedAt: occurrence.completedAt, overdue: false,
            isRecurring: true, sourceID: task.id,
            sortOrder: task.sortOrder, occurrenceDay: LocalDay(key: occurrence.dayKey),
            movedFromDay: LocalDay(key: occurrence.dayKey)))
      }
      return result
    } catch {
      self.error = String(localized: "Unable to load tasks.")
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
          record.dueDayKey = draft.dueDay?.key
          record.hasDueDayOverride = true
          record.rescheduledDayKey = draft.day == editing.occurrenceSourceDay ? nil : draft.day.key
        } else if let task = try task(id: editing.sourceID) {
          task.title = title
          task.notes = draft.notes
          task.dayKey = draft.day.key
          task.dueDayKey = draft.dueDay?.key
          task.minuteOfDay = draft.minuteOfDay
        }
      } else {
        let count = try context.fetchCount(FetchDescriptor<TaskRecord>())
        let newTask = TaskRecord(
          title: title, notes: draft.notes, day: draft.day, minuteOfDay: draft.minuteOfDay,
          sortOrder: count, frequency: draft.frequency,
          weekdays: draft.frequency == .weekly
            ? [Calendar.current.component(.weekday, from: draft.day.date)] : [],
          dueDay: draft.frequency == .never ? draft.dueDay : nil)
        context.insert(newTask)
        if draft.frequency != .never, let dueDay = draft.dueDay {
          let occurrence = OccurrenceRecord(seriesID: newTask.id, day: draft.day)
          occurrence.dueDayKey = dueDay.key
          occurrence.hasDueDayOverride = true
          context.insert(occurrence)
        }
      }
      try context.save()
      error = nil
      tasksDidChange()
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
      tasksDidChange()
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
      tasksDidChange()
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
      tasksDidChange()
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
      tasksDidChange()
    } catch {
      context.rollback()
      self.error = String(localized: "Unable to save. Try again.")
    }
  }

  func clearError() {
    error = nil
  }

  func refreshBadge(today: LocalDay = LocalDay(.now)) {
    badgeCount = tasks(on: today, today: today).filter { !$0.completed }.count
  }

  private func tasksDidChange() {
    revision &+= 1
    refreshBadge()
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
