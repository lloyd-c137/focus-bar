# 10 · 当前实现基线

Focus Bar 是一款原生 macOS 菜单栏长期待办清单，任务主数据保存在本地 SwiftData，并按用户明确要求自动备份到私有 GitHub 仓库。

## 产品规则

- 没有计划日期、日期选择或按日导航。
- 新增任务只需标题；截止日期默认不设置，时刻、重复规则和备注可选。
- 无 DDL 的任务持续显示且永不因创建时间而逾期。
- 只有 DDL 早于本地今天且未完成的事项进入 Overdue。
- 每日/每周 occurrence 独立完成；每周规则选择星期。
- 完成、撤销、编辑和删除均本地持久化；删除可撤销。
- 核心任务操作保持离线可用；不接 AI、日历、自建云账户或服务器。
- 每次任务写入后后台同步完整 SQLite 快照到私有 `lloyd-c137/focus-bar-data-backup`；快照按用户要求不加密。
- GitHub PAT 由 macOS Keychain 保存，只授予备份仓库 Contents 读写；同步失败不阻止本地任务操作。
- 断网期间保留待同步状态，网络恢复或手动触发后重试。

## 关键架构

- `FocusBarApp`：菜单栏场景与设置场景。
- `TodayPanel`：长期清单、快速新增、任务详情和键盘操作；内部类型名保留，不代表日期视图。
- `TaskStore`：SwiftData 查询与任务写操作；不使用旧计划日期。
- `Domain`：DDL、重复规则和清单排序。
- `Models`：本地任务和重复 occurrence。旧版 `dayKey` / `rescheduledDayKey` 仅保留用于数据库兼容。

## 验收命令

```sh
swift format lint --strict --recursive Sources Tests
swift test
./scripts/build-app.sh
codesign --verify --deep --strict ".FocusBarBuild/Focus Bar.app"
plutil -lint ".FocusBarBuild/Focus Bar.app/Contents/Info.plist"
```

实际运行的菜单栏交互与 Light/Dark 视觉验收需在 macOS 图形会话中完成；不能以单元测试替代。
