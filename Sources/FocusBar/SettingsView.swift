import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @Environment(GitHubBackupManager.self) private var backup
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
      Section(String(localized: "GitHub Backup")) {
        HStack {
          Label(
            !backup.isConfigured
              ? String(localized: "Backup is not configured")
              : (backup.isSyncing
                ? String(localized: "Syncing backup…")
                : (backup.lastError == nil && backup.lastSyncedAt != nil
                  ? String(localized: "Backup is up to date")
                  : String(localized: "Backup needs attention"))),
            systemImage: backup.isConfigured && backup.lastError == nil
              && backup.lastSyncedAt != nil
              ? "checkmark.icloud" : "exclamationmark.icloud"
          )
          Spacer()
          if backup.isSyncing { ProgressView().controlSize(.small) }
        }
        if let lastSyncedAt = backup.lastSyncedAt {
          Text(
            String(
              format: String(localized: "Last synced %@"),
              lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
            )
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        if let lastError = backup.lastError {
          Text(lastError).font(.caption).foregroundStyle(.red)
        } else if !backup.isConfigured {
          Text(String(localized: "Add FOCUS_BAR_GITHUB_TOKEN with fnox, then restart Focus Bar."))
            .font(.caption).foregroundStyle(.secondary)
        }
        HStack {
          Button(String(localized: "Sync now")) { Task { await backup.syncNow() } }
            .disabled(backup.isSyncing || !backup.isConfigured)
          if let backupURL = URL(string: "https://github.com/lloyd-c137/focus-bar-data-backup") {
            Link(String(localized: "Open private backup repository"), destination: backupURL)
          }
        }
        Text(String(localized: "Backup data is not encrypted."))
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 420, height: loginError == nil ? 400 : 460)
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
