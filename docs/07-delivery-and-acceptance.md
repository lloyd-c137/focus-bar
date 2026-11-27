# 07 · 交付与验收标准

状态：计划日期机制已移除；GitHub 自动备份按 ADR-011 实施中。

## 产品验收

- 面板显示 `Tasks`，无 Today/Tomorrow/指定日期导航。
- 新增事项无计划日期；只输入标题即可保存。
- 无 DDL 的事项跨日后仍显示，不会进入 Overdue。
- 只有显式 DDL 早于本地今天且未完成的事项进入 Overdue。
- DDL 可在新建和编辑时设置或清除。
- 时刻只表示一天中的时间，不绑定日期或触发提醒。
- Daily/Weekly recurrence 正确生成实例，完成状态相互独立。
- 旧 SwiftData 事项和完成状态保留，旧计划日期不再影响展示。
- 右键菜单不再提供 Move to Today/Tomorrow、Change Date。
- 任务写入成功后本地保存不等待网络；随后生成一致 SQLite 快照并上传到私有备份仓库。
- 上传失败显示可读状态且不回滚数据；网络恢复、重新启动或手动重试会继续同步。
- GitHub 凭据仅存 macOS Keychain；同步内容未加密。

## 必测矩阵

| 模块 | 场景 |
| --- | --- |
| 长期事项 | 新建无 DDL；模拟旧计划日期；跨日后持续可见且不逾期 |
| DDL | 无 DDL、未来 DDL、当天 DDL、过去 DDL、已完成过期项 |
| 重复 | 每日、每周星期选择、实例完成/撤销、单次删除、系列删除 |
| 排序 | Overdue 按 DDL、有时间按时刻、Anytime 稳定顺序、Completed 折叠 |
| 持久化 | 旧数据库字段可读，重启后标题/完成/DDL 保持 |
| GitHub backup | 快照一致性、首次上传、文件更新、失败重试、权限错误提示、断网后重试 |
| 性能 | 1000 条任务查询和展示 |
| UI | 空、普通、逾期、重复、Light/Dark、VoiceOver、IME、Reduce Motion |

## 计划日期移除验证记录（2026-11-25）

- `swift format lint --strict --recursive Sources Tests` — PASS
- `swift test` — PASS（14 项）
- `./scripts/build-app.sh` — PASS
- `codesign --verify --deep --strict ".FocusBarBuild/Focus Bar.app"` — PASS
- `plutil -lint ".FocusBarBuild/Focus Bar.app/Contents/Info.plist"` — PASS
- `git diff --check` — PASS
- 菜单栏真实交互、截图、VoiceOver 和中文输入法图形验收：尚未验证

## GitHub 自动备份实现状态（2026-11-28）

- SQLite 在线快照一致性单元测试：PASS。
- GitHub token：fnox 凭据尚待用户录入，然后安全写入 macOS Keychain。
- 远程同步路径与首次启动同步：凭据配置后实际验证。

## 发布门槛

1. 所有用户可见流程不再暴露计划日期。
2. 无 DDL 的历史事项不因旧 `dayKey` 进入 Overdue。
3. 旧 SwiftData 数据保留；不能清空或重置用户 Store。
4. 格式、测试、构建、签名和 Info.plist 检查通过。
5. 未验证的菜单栏视觉/交互必须标 `NOT_TESTED`。
