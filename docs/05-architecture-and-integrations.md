# 05 · Focus Bar V1 工程架构（Local-only）

版本 V1.0 · 状态：方案，尚未开发或构建

## 1. 技术栈

- **macOS**：建议 14+，需要在真实开发机验证最低版本与系统行为。
- **Swift**：唯一主要开发语言。
- **SwiftUI**：`MenuBarExtra` + window style、任务行、日期选择、原生 Settings。
- **AppKit**：只在 SwiftUI 不足以处理菜单栏状态、窗口焦点、系统菜单或键盘行为时补充。
- **SwiftData**：本地任务、重复系列、完成记录及应用偏好持久化。
- **SMAppService**：可配置登录启动（具体启用方式与签名/沙盒要求需实测）。
- **完全离线**：不使用 HTTP、LLM、GitHub API、EventKit、网络服务或后端。

不得为了所谓“未来扩展能力”提前集成 AI/HTTP 框架或第三方任务同步。

## 2. 应用结构

```text
FocusBarApp
├── MenuBarScene
│   ├── TodayPopover
│   │   ├── Header / DateSwitcher
│   │   ├── OverdueSection
│   │   ├── ScheduledSection
│   │   ├── AnytimeSection
│   │   ├── CompletedSection
│   │   └── QuickAdd / InlineEditor
│   └── NativeContextMenus
├── SettingsScene
│   ├── General (login at start, count display)
│   └── Appearance (completed visibility, system theme)
├── Domain
│   ├── Task / RecurrenceRule / OccurrenceOverride
│   ├── LocalDate / LocalTime (date-only/time-only semantics)
│   ├── TodayQueryService
│   └── TaskCommandService
├── Persistence
│   ├── SwiftData Models / Migration
│   └── TaskRepository
└── System
    ├── Clock / Calendar / TimeZone
    ├── LoginItemCoordinator
    └── LocalDiagnostics
```

Domain 不直接依赖 UI。Clock、Calendar 与 repository 应可注入，以测试跨日期、时区、重复规则和异常行为。

## 3. 关键服务接口（概念 API，非已实现代码）

```swift
protocol TaskRepository {
    func loadTasks(for date: LocalDate) async throws -> [Task]
    func save(_ task: Task) async throws
    func update(_ task: Task) async throws
    func remove(id: UUID) async throws
}

protocol TodayQuerying {
    func items(on date: LocalDate, includeOverdue: Bool) async throws -> DaySections
}
```

实现不要求完全照抄签名，但须确保任务命令与展示查询解耦。

## 4. 状态与生命周期

- App 启动：初始化 SwiftData ModelContainer → 读取偏好 → 显示菜单栏图标。
- 打开面板：读取当前查看日期的任务（Today 默认为系统今天），异步展现，避免主线程阻塞。
- 快速新增：用户输入标题，保存时默认当前查看日期；时间默认无。
- 勾选完成：更新状态和 completedAt；持久化成功后显示稳定完成态。
- 修改日期：仅更新目标 Task / occurrence，不重新生成其他项目。
- 日期变更/唤醒：重新计算 Today、Overdue，不改动用户原始计划。
- 应用退出：通过明确 Quit 菜单退出；面板关闭本身不退出。
- 关闭 Dock 图标的方案须在真机验证 Settings、权限及激活行为。

## 5. 数据存储

- ModelContainer 保存至应用私有容器或标准 Application Support 目录。
- 用户选定的日期和时分采用 **本地日历字段语义**，不是“UTC 午夜”；
  时间戳字段如 createdAt、updatedAt 仍使用 Date。
- SwiftData schema 提前设置明确版本；从最小模型开始并准备迁移测试。
- 操作先保证写成功；不应因 UI 乐观更新把本地错误伪装为成功。
- 可选的删除撤销使用短期本地 Undo / 软删除策略，不需要服务端。
- 避免为未来 GitHub / AI 预设未使用数据库表。

## 6. 菜单栏与 Settings

- 初步使用 `MenuBarExtra("Focus Bar", systemImage: ...)` + `.menuBarExtraStyle(.window)`。
- 主面板宽约 360pt，日期顶部固定、列表可滚动，底部 Add 可访问。
- 右键 Task Row 用原生 Context Menu。
- 为输入框和日期选择器采用原生控件；清单可键盘全流程操作。
- 系统设置独立窗口；提供登录启动与菜单栏计数切换，不出现 AI / Integrations tab。

## 7. 调度

V1 只有轻量的本地日期/系统事件侦测。**没有自动生成任务、无网络轮询、无后台 AI 规划。**

- 活跃时可通过系统通知/适度定时检查是否跨日。
- 睡眠唤醒或重新启动后重新计算 Today。
- 不需要 Mac 关机期间完成任何计算。
- 对重复任务按日期查询、按需展开；避免无限预先生成。

## 8. 测试替身与工程质量

- 注入 Clock 来测试昨天/今天/明天、午夜和时区变更。
- 用 in-memory repository + 假数据运行单元测试，不依赖实际用户数据库。
- SwiftData persistence integration test 验证关闭/重新打开 ModelContainer 后状态仍在。
- 界面截图覆盖 Light/Dark、0/3/20/50 项和长标题。
- UI tests 验证菜单栏、编辑、完成、日期选择、重复规则、Settings。
- 默认不启用自动使用情况上报；如产生错误日志仅在本地保留不敏感元数据。

参考：[Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) · [Apple SwiftData](https://developer.apple.com/documentation/swiftdata) · [Apple ServiceManagement](https://developer.apple.com/documentation/servicemanagement)

## 9. 实施顺序

先做 M0 原生菜单栏框架，再做 M1 本地 CRUD 与日期导航，再做 M2 重复/逾期与可靠性，最后 M3 交互打磨及分发验证。不要一开始搭复杂架构。
