import AppKit
import SwiftData
import SwiftUI

@main struct FocusBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let container: ModelContainer?
  private let startupError: String?
  @AppStorage("showMenuBarCount") private var showCount = false
  @State private var taskStore: TaskStore?
  @State private var calendarState: CalendarState?

  init() {
    do {
      let modelContainer = try ModelContainer(for: TaskRecord.self, OccurrenceRecord.self)
      container = modelContainer
      startupError = nil
      let store = TaskStore(context: modelContainer.mainContext)
      _taskStore = State(initialValue: store)
      _calendarState = State(initialValue: CalendarState(taskStore: store))
    } catch {
      container = nil
      startupError = error.localizedDescription
      _taskStore = State(initialValue: nil)
      _calendarState = State(initialValue: nil)
    }
  }

  var body: some Scene {
    MenuBarExtra {
      if let container, let taskStore, let calendarState {
        TodayPanel().modelContainer(container).environment(taskStore).environment(calendarState)
      } else {
        StorageFailureView(message: startupError ?? "")
      }
    } label: {
      // Menu bar labels render a single Text/Image reliably; an inline symbol keeps the count
      // next to the icon. A zero count is hidden so the item stays a plain icon.
      if showCount, let count = taskStore?.badgeCount, count > 0 {
        Text("\(Image(systemName: "checklist")) \(count)")
          .accessibilityLabel("Focus Bar")
      } else {
        Image(systemName: "checklist")
          .accessibilityLabel("Focus Bar")
      }
    }
    .menuBarExtraStyle(.window)

    Settings {
      if let container, let taskStore {
        SettingsView().modelContainer(container).environment(taskStore)
      } else {
        StorageFailureView(message: startupError ?? "").frame(width: 360, height: 220)
      }
    }
    .commands {
      CommandGroup(replacing: .appTermination) {
        Button("Quit Focus Bar") { NSApp.terminate(nil) }.keyboardShortcut("q")
      }
    }
  }
}

private struct StorageFailureView: View {
  let message: String
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(
        String(localized: "The local task store could not be opened."),
        systemImage: "externaldrive.badge.exclamationmark"
      )
      .font(.headline)
      Text(String(localized: "Your data has not been reset."))
        .font(.subheadline).foregroundStyle(.secondary)
      if !message.isEmpty {
        Text(message).font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
      }
      Button(String(localized: "Quit Focus Bar")) { NSApp.terminate(nil) }
        .buttonStyle(.borderedProminent)
    }
    .padding(20).frame(width: 360)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}
