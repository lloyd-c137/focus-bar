import Foundation
import Network
import Observation
import SQLite3
import Security

private enum GitHubBackupConfiguration {
  static let owner = "lloyd-c137"
  static let repository = "focus-bar-data-backup"
  static let branch = "main"
  static let path = "FocusBar.sqlite"
  static let keychainService = "com.lloydc137.FocusBar.GitHubBackup"
  static let keychainAccount = "contents-token"
}

@MainActor protocol TaskBackupSyncing: AnyObject {
  func scheduleSync()
}

@MainActor @Observable final class GitHubBackupManager: TaskBackupSyncing {
  private(set) var isSyncing = false
  private(set) var lastError: String?
  private(set) var lastSyncedAt =
    UserDefaults.standard.object(forKey: "githubBackupLastSyncedAt") as? Date

  private var generation: UInt64 = 0
  private var worker: Task<Void, Never>?
  private var hasPendingSync = false
  private let networkMonitor = NWPathMonitor()

  init() {
    networkMonitor.pathUpdateHandler = { [weak self] path in
      guard path.status == .satisfied else { return }
      Task { @MainActor [weak self] in
        guard let self, self.hasPendingSync, self.lastError != nil, self.worker == nil else {
          return
        }
        self.scheduleSync()
      }
    }
    networkMonitor.start(queue: DispatchQueue(label: "FocusBar.GitHubBackup.Network"))
  }

  deinit { networkMonitor.cancel() }

  var isConfigured: Bool { GitHubTokenKeychain.read() != nil }

  func scheduleSync() {
    generation &+= 1
    hasPendingSync = true
    guard worker == nil else { return }
    worker = Task { await drainQueue() }
  }

  func syncNow() async {
    scheduleSync()
    await worker?.value
  }

  private func drainQueue() async {
    while true {
      let targetGeneration = generation
      isSyncing = true
      do {
        let snapshot = try await Task.detached(priority: .utility) {
          try SQLiteSnapshot.make()
        }.value
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try await upload(snapshot: snapshot)
        lastSyncedAt = .now
        UserDefaults.standard.set(lastSyncedAt, forKey: "githubBackupLastSyncedAt")
        lastError = nil
        hasPendingSync = false
        if generation == targetGeneration {
          isSyncing = false
          worker = nil
          return
        }
      } catch {
        lastError = error.localizedDescription
        hasPendingSync = true
        isSyncing = false
        worker = nil
        return
      }
    }
  }

  private func upload(snapshot: URL) async throws {
    guard let token = GitHubTokenKeychain.read() else {
      throw GitHubBackupError.missingToken
    }
    let content = try Data(contentsOf: snapshot).base64EncodedString()
    let path =
      GitHubBackupConfiguration.path.addingPercentEncoding(
        withAllowedCharacters: .urlPathAllowed) ?? GitHubBackupConfiguration.path
    guard
      let url = URL(
        string:
          "https://api.github.com/repos/\(GitHubBackupConfiguration.owner)/\(GitHubBackupConfiguration.repository)/contents/\(path)"
      )
    else { throw GitHubBackupError.invalidResponse }
    for attempt in 0..<3 {
      var get = URLRequest(url: url)
      get.httpMethod = "GET"
      get.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      get.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      get.setValue("FocusBar/1.0", forHTTPHeaderField: "User-Agent")
      get.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
      let (existingData, getResponse) = try await URLSession.shared.data(for: get)
      guard let http = getResponse as? HTTPURLResponse else {
        throw GitHubBackupError.invalidResponse
      }
      let existingSHA: String?
      if http.statusCode == 200 {
        existingSHA = try JSONDecoder().decode(GitHubFile.self, from: existingData).sha
      } else if http.statusCode == 404 {
        existingSHA = nil
      } else {
        throw GitHubBackupError.httpStatus(http.statusCode)
      }

      var put = URLRequest(url: url)
      put.httpMethod = "PUT"
      put.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      put.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      put.setValue("FocusBar/1.0", forHTTPHeaderField: "User-Agent")
      put.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
      put.setValue("application/json", forHTTPHeaderField: "Content-Type")
      put.httpBody = try JSONEncoder().encode(
        GitHubFileUpdate(
          message: "Sync Focus Bar task data",
          content: content,
          sha: existingSHA,
          branch: GitHubBackupConfiguration.branch
        ))
      let (_, putResponse) = try await URLSession.shared.data(for: put)
      guard let putHTTP = putResponse as? HTTPURLResponse else {
        throw GitHubBackupError.invalidResponse
      }
      if (200...201).contains(putHTTP.statusCode) { return }
      if putHTTP.statusCode == 409 || putHTTP.statusCode == 422, attempt < 2 { continue }
      throw GitHubBackupError.httpStatus(putHTTP.statusCode)
    }
    throw GitHubBackupError.invalidResponse
  }
}

private struct GitHubFile: Decodable {
  let sha: String
}

private struct GitHubFileUpdate: Encodable {
  let message: String
  let content: String
  let sha: String?
  let branch: String
}

private enum GitHubBackupError: LocalizedError {
  case missingToken
  case invalidResponse
  case httpStatus(Int)
  case storeUnavailable
  case sqlite(String)

  var errorDescription: String? {
    switch self {
    case .missingToken:
      return String(localized: "GitHub backup token is missing from Keychain.")
    case .invalidResponse:
      return String(localized: "GitHub returned an invalid response.")
    case .httpStatus(let status):
      return String(format: String(localized: "GitHub backup failed (HTTP %d)."), status)
    case .storeUnavailable:
      return String(localized: "The local task database could not be found.")
    case .sqlite(let message):
      return message
    }
  }
}

private enum GitHubTokenKeychain {
  static func read() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: GitHubBackupConfiguration.keychainService,
      kSecAttrAccount as String: GitHubBackupConfiguration.keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

enum SQLiteSnapshot {
  static func make() throws -> URL {
    guard
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else { throw GitHubBackupError.storeUnavailable }
    let source = appSupport.appendingPathComponent("default.store")
    return try make(from: source)
  }

  static func make(from source: URL) throws -> URL {
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw GitHubBackupError.storeUnavailable
    }
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("FocusBar-\(UUID().uuidString).sqlite")
    var sourceDB: OpaquePointer?
    var destinationDB: OpaquePointer?
    let sourceResult = sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY, nil)
    guard sourceResult == SQLITE_OK, let sourceDB else {
      if let sourceDB { sqlite3_close(sourceDB) }
      throw GitHubBackupError.sqlite("Could not open the local task database.")
    }
    defer { sqlite3_close(sourceDB) }
    let destinationResult = sqlite3_open(destination.path, &destinationDB)
    guard destinationResult == SQLITE_OK, let destinationDB else {
      if let destinationDB { sqlite3_close(destinationDB) }
      throw GitHubBackupError.sqlite("Could not create a temporary backup file.")
    }
    defer { sqlite3_close(destinationDB) }
    guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
      throw GitHubBackupError.sqlite("Could not start the SQLite backup.")
    }
    var stepResult = sqlite3_backup_step(backup, -1)
    var retries = 0
    while stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED, retries < 40 {
      Thread.sleep(forTimeInterval: 0.025)
      stepResult = sqlite3_backup_step(backup, -1)
      retries += 1
    }
    let finishResult = sqlite3_backup_finish(backup)
    guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
      try? FileManager.default.removeItem(at: destination)
      throw GitHubBackupError.sqlite("Could not finish the SQLite backup.")
    }
    var sqliteMessage: UnsafeMutablePointer<CChar>?
    let journalResult = sqlite3_exec(
      destinationDB, "PRAGMA journal_mode=DELETE", nil, nil, &sqliteMessage)
    if let sqliteMessage { sqlite3_free(sqliteMessage) }
    guard journalResult == SQLITE_OK else {
      try? FileManager.default.removeItem(at: destination)
      throw GitHubBackupError.sqlite("Could not finalize the SQLite snapshot.")
    }
    return destination
  }
}
