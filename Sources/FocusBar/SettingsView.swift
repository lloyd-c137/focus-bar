import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @AppStorage("showMenuBarCount") private var showCount = false
  @AppStorage("showCompleted") private var showCompleted = true
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginError: String?

  var body: some View {
    Form {
      Toggle(String(localized: "Show unfinished count in menu bar"), isOn: $showCount)
      Toggle(String(localized: "Show completed tasks"), isOn: $showCompleted)
      Toggle(String(localized: "Launch at login"), isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, enabled in
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
      if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
    }
    .padding(20)
    .navigationTitle(String(localized: "General"))
  }
}
