import Foundation
import SwiftData
import SwiftUI

@MainActor @Observable final class TaskStore {
  private let context: ModelContext
  private let backup: (any TaskBackupSyncing)?
  var error: String?
  private(set) var badgeCount = 0
  private(set) var revision = 0
  init(context: ModelContext, backup: (any TaskBackupSyncing)? = nil) {
    self.context = context
    self.backup = backup
    refreshBadge()
  }

  func tasks(today: LocalDay) -> [VisibleTask] {
    _ = revision
    do {
      let todayKey = today.key
      let occurrencePredicate = #Predicate<OccurrenceRecord> { occurrence in
        occurrence.dayKey == todayKey
      }
      let occurrences = try context.fetch(
        FetchDescriptor<OccurrenceRecord>(predicate: occurrencePredicate))
      let taskPredicate = #Predicate<TaskRecord> { !$0.deleted }
      let records = try context.fetch(FetchDescriptor<TaskRecord>(predicate: taskPredicate))
      let overrides = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.key, $0) })
      var result: [VisibleTask] = []
      for task in records {
        if task.recurrence == .never {
          let isOverdue = task.dueDay.map { $0 < today } == true && !task.completed
          result.append(
            .init(
              id: task.id.uuidString, title: task.title, notes: task.notes,
              dueDay: task.dueDay,
              minuteOfDay: task.minuteOfDay, completed: task.completed,
              completedAt: task.completedAt, overdue: isOverdue,
              isRecurring: false, sourceID: task.id, sortOrder: task.sortOrder,
              occurrenceDay: nil))
        } else if recurrenceMatches(
          frequency: task.recurrence, date: today, weekdays: task.weekdaySet)
        {
          let key = "\(task.id.uuidString)-\(today.key)"
          let occurrence = overrides[key]
          if occurrence?.hidden != true {
            let dueDay = occurrence?.hasDueDayOverride == true ? occurrence?.dueDay : nil
            result.append(
              .init(
                id: key, title: occurrence?.titleOverride ?? task.title,
                notes: occurrence?.notesOverride ?? task.notes,
                dueDay: dueDay,
                minuteOfDay: occurrence?.hasMinuteOverride == true
                  ? occurrence?.minuteOverride : task.minuteOfDay,
                completed: occurrence?.completed ?? false, completedAt: occurrence?.completedAt,
                overdue: dueDay.map { $0 < today } == true && occurrence?.completed != true,
                isRecurring: true,
                sourceID: task.id, sortOrder: task.sortOrder, occurrenceDay: today))
          }
        }
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
        } else if let task = try task(id: editing.sourceID) {
          task.title = title
          task.notes = draft.notes
          task.dueDayKey = draft.dueDay?.key
          task.minuteOfDay = draft.minuteOfDay
        }
      } else {
        let count = try context.fetchCount(FetchDescriptor<TaskRecord>())
        let newTask = TaskRecord(
          title: title, notes: draft.notes, minuteOfDay: draft.minuteOfDay,
          sortOrder: count, frequency: draft.frequency,
          weekdays: draft.frequency == .weekly
            ? (draft.weekdays.isEmpty
              ? [Calendar.current.component(.weekday, from: .now)] : draft.weekdays) : [],
          dueDay: draft.frequency == .never ? draft.dueDay : nil)
        context.insert(newTask)
        if draft.frequency != .never, let dueDay = draft.dueDay {
          let occurrenceDay = nextOccurrenceDay(
            frequency: draft.frequency, from: LocalDay(.now), weekdays: newTask.weekdaySet)
          let occurrence = OccurrenceRecord(seriesID: newTask.id, day: occurrenceDay)
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

  /// Reverses `delete` / `deleteSeries`; both only set soft-delete flags.
  func restore(_ item: VisibleTask, series: Bool) {
    do {
      if item.isRecurring && !series {
        let record = try occurrence(for: item.sourceID, day: item.occurrenceSourceDay)
        record.hidden = false
      } else if let task = try task(id: item.sourceID) {
        task.deleted = false
      }
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
    badgeCount = tasks(today: today).filter { !$0.completed }.count
  }

  private func tasksDidChange() {
    revision &+= 1
    refreshBadge()
    backup?.scheduleSync()
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
