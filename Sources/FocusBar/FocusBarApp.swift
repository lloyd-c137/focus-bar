import AppKit
import SwiftData
import SwiftUI

@main struct FocusBarApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let container: ModelContainer?
  private let startupError: String?
  @AppStorage("showMenuBarCount") private var showCount = false
  @State private var taskStore: TaskStore?

  init() {
    do {
      let modelContainer = try ModelContainer(for: TaskRecord.self, OccurrenceRecord.self)
      container = modelContainer
      startupError = nil
      _taskStore = State(initialValue: TaskStore(context: modelContainer.mainContext))
    } catch {
      container = nil
      startupError = error.localizedDescription
      _taskStore = State(initialValue: nil)
    }
  }

  var body: some Scene {
    MenuBarExtra {
      if let container, let taskStore {
        TodayPanel().modelContainer(container).environment(taskStore)
      } else {
        StorageFailureView(message: startupError ?? "")
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "checklist")
        if showCount { Text("\(taskStore?.badgeCount ?? 0)") }
      }
      .accessibilityLabel("Focus Bar")
    }
    .menuBarExtraStyle(.window)

    Settings {
      if let container, let taskStore {
        SettingsView().modelContainer(container).environment(taskStore).frame(
          width: 360, height: 220)
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
