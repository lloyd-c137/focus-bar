import ServiceManagement
import SwiftUI

struct SettingsView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(GitHubBackupManager.self) private var backup
  @AppStorage("showMenuBarCount") private var showCount = false
  @AppStorage("showCompleted") private var showCompleted = true
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginError: String?

  private var smoothMotion: Animation? {
    reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)
  }

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
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      Section(String(localized: "Menu Bar")) {
        Toggle(String(localized: "Show unfinished count in menu bar"), isOn: $showCount)
        Toggle(String(localized: "Show completed tasks"), isOn: $showCompleted)
      }
      Section(String(localized: "GitHub Backup")) {
        HStack {
          Label {
            Text(
              !backup.isConfigured
                ? String(localized: "Backup is not configured")
                : (backup.isSyncing
                  ? String(localized: "Syncing backup…")
                  : (backup.lastError == nil && backup.lastSyncedAt != nil
                    ? String(localized: "Backup is up to date")
                    : String(localized: "Backup needs attention")))
            )
            .contentTransition(.opacity)
          } icon: {
            Image(
              systemName: backup.isConfigured && backup.lastError == nil
                && backup.lastSyncedAt != nil
                ? "checkmark.icloud" : "exclamationmark.icloud"
            )
            .contentTransition(.symbolEffect(.replace))
          }
          Spacer()
          if backup.isSyncing {
            ProgressView()
              .controlSize(.small)
              .transition(.opacity.combined(with: .scale(scale: 0.8)))
          }
        }
        .animation(smoothMotion, value: backup.isSyncing)
        .animation(smoothMotion, value: backup.lastError)
        if let lastSyncedAt = backup.lastSyncedAt {
          Text(
            String(
              format: String(localized: "Last synced %@"),
              lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
            )
          )
          .font(.caption).foregroundStyle(.secondary)
          .transition(.opacity)
        }
        if let lastError = backup.lastError {
          Text(lastError)
            .font(.caption)
            .foregroundStyle(.red)
            .transition(.opacity.combined(with: .move(edge: .top)))
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
    .animation(smoothMotion, value: loginError == nil)
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
