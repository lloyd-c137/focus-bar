import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @AppStorage("showMenuBarCount") private var showCount = false
  @AppStorage("showCompleted") private var showCompleted = true
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginError: String?

  var body: some View {
    Form {
      Section(String(localized: "General")) {
        Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, enabled in updateLoginItem(enabled) }
        if let loginError {
          VStack(alignment: .leading, spacing: 6) {
            Label(loginError, systemImage: "exclamationmark.triangle.fill")
              .font(.callout)
              .foregroundStyle(.secondary)
            Button(String(localized: "Open Login Items Settings…")) {
              SMAppService.openSystemSettingsLoginItems()
            }
          }
        }
      }
      Section(String(localized: "Menu Bar")) {
        Toggle(String(localized: "Show unfinished count in menu bar"), isOn: $showCount)
        Toggle(String(localized: "Show completed tasks"), isOn: $showCompleted)
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .frame(width: 420, height: loginError == nil ? 236 : 300)
    .navigationTitle(String(localized: "Focus Bar Settings"))
  }

  private func updateLoginItem(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      loginError = nil
    } catch {
      loginError = error.localizedDescription
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }
}
