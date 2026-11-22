import AppKit
import Foundation
import Observation

@MainActor @Observable final class CalendarState {
  private(set) var dateContext = LocalDayContext()
  private let taskStore: TaskStore
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []

  init(taskStore: TaskStore) {
    self.taskStore = taskStore
    observe(NotificationCenter.default, for: .NSCalendarDayChanged)
    observe(NotificationCenter.default, for: .NSSystemTimeZoneDidChange)
    observe(NotificationCenter.default, for: .NSSystemClockDidChange)
    observe(NotificationCenter.default, for: NSApplication.didBecomeActiveNotification)
    observe(NSWorkspace.shared.notificationCenter, for: NSWorkspace.didWakeNotification)
    refresh()
  }

  func refresh() {
    dateContext.refresh(now: .now, timeZone: .current)
    taskStore.refreshBadge(today: dateContext.today)
  }

  private func observe(_ center: NotificationCenter, for name: Notification.Name) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.refresh()
      }
    }
    observers.append((center, token))
  }
}
