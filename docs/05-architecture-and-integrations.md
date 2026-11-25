# 05 · Focus Bar 本地清单架构

状态：已实现的 SwiftUI / SwiftData 菜单栏应用；计划日期已于 2026-11-25 删除。

## 1. 技术栈

- macOS 14+、Swift 6、SwiftUI `MenuBarExtra`、必要 AppKit、SwiftData。
- SMAppService 管理登录启动。
- 完全离线，不使用 HTTP、LLM、GitHub API、EventKit 或后端。

## 2. 应用结构

```text
FocusBarApp
├── MenuBarScene
│   ├── TaskPanel
│   │   ├── OverdueSection (explicit past deadline only)
│   │   ├── ScheduledSection (time-of-day)
│   │   ├── AnytimeSection
│   │   ├── CompletedSection
│   │   └── QuickAdd / TaskInspector
│   └── NativeContextMenus
├── SettingsScene
├── Domain
│   ├── Task / RecurrenceRule / OccurrenceOverride
│   ├── LocalDay (DDL and recurrence only)
│   └── TaskSections
├── Persistence
│   └── SwiftData Models
└── System
    ├── Calendar / TimeZone notifications
    └── Login item
```

Domain 规则与 SwiftUI 分离；`TaskStore` 查询和持久化任务。SwiftData 中的旧版计划日期列保留以兼容现存数据库，但不被业务逻辑读取。

## 3. 查询接口

```swift
func tasks(today: LocalDay) -> [VisibleTask]
func save(_ draft: TaskDraft, editing: VisibleTask?) -> Bool
func toggle(_ item: VisibleTask)
func delete(_ item: VisibleTask)
```

查询返回所有未删除单次事项，以及今天符合规则的重复 occurrence。单次任务仅由可选 DDL 判定 Overdue。

## 4. 状态与生命周期

- 启动时打开本地 SwiftData 容器并显示 `Tasks` 菜单栏面板。
- 快速新增仅需标题；可选设置 DDL、时刻和重复规则。
- 完成、撤销、删除和编辑写入 SwiftData。
- 日期变化/唤醒用于更新 DDL 逾期状态、重复 occurrence 和计数；不会改变单次事项。
- 关闭面板不退出应用。

## 5. 数据兼容

- 旧版 Task 的 `dayKey` 和 occurrence 的 `rescheduledDayKey` 保留为兼容列。
- 旧 `dayKey` 不再用于隐藏任务、筛选任务或判定逾期。
- DDL 使用本地 calendar day 字符串，避免 UTC 午夜导致偏移。
- 删除支持 Undo；数据写入失败不会显示成功。

## 6. 测试

覆盖无计划日期的旧数据显示、仅显式 DDL 触发逾期、每日/每周实例、完成状态、删除、1000 条事项和 SwiftData 重启持久化。
