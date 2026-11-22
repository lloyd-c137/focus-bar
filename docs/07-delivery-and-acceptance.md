# 07 · V1 工程里程碑与验收标准

状态：V1 源码与本地构建已交付；下面的里程碑是验收基线，逐项证据见文末当前实现记录。未完成真实交互验证的项目仍标为 NOT_TESTED。

## M0 · Native Menu Bar Shell

交付：
- 标准 Xcode 项目或 Swift Package + App target。
- `MenuBarExtra` window style，系统原生弹出面板。
- App 图标、菜单栏模板图标、Settings / Quit。
- Today 空状态、示例任务 fixture、Light/Dark 基础布局。

验收：
- [ ] 启动后有菜单栏图标，关闭面板不退出应用。
- [ ] 原生菜单栏窗口开关正常，Settings 和 Quit 可访问。
- [ ] 3、20、50 条 fixture 展示有序、可滚动。
- [ ] 无 Start Focus、计时器、桌宠、AI 面板。

## M1 · 手动 CRUD + 日期安排

交付：
- Task SwiftData 模型、增删改查、完成/撤销。
- 内联快速添加、日期选择（Today/Tomorrow/指定日期）、可选时刻。
- 右键菜单编辑/改期/删除、状态持久化。

验收：
- [ ] 新增时只输入标题即可，默认日期为当前查看日。
- [ ] 指定日期与时间保存后按本地日历正确显示。
- [ ] 单击完成/撤销，关闭/重启程序仍保留状态。
- [ ] 改期不产生重复任务，删除可确认或撤销。
- [ ] 中文输入法不因 Enter 选字而误提交。
- [ ] 没有任何网络调用或外部授权要求。

## M2 · 重复、逾期和生命周期

交付：
- 每日/每周重复规则，单个 occurrence 完成记录。
- Today Overdue（过去未完成的单次任务）。
- 稳定排序、已完成折叠、日期跨越与系统唤醒刷新。
- 独立时区/时刻处理单元测试。

验收：
- [ ] 昨天未完成单次事项在 Today 的 Overdue，但原日期不被更改。
- [ ] 每日重复项今天勾选后，明天仍是未完成的新实例。
- [ ] 多次打开/刷新不会生成重复 occurrence。
- [ ] 不无限累积未完成的历史 Routine 实例。
- [ ] 改时区、睡眠跨午夜不会随意改任务计划日。

## M3 · macOS 品质、稳定性和交付

交付：
- 完整 Light/Dark、系统强调色与辅助功能支持。
- 键盘操作/VoiceOver、Reduced Motion 和高对比度适配。
- 可配置登录启动、菜单栏计数。
- SwiftData 迁移和失败恢复策略。
- 本机构建与安装说明、测试记录。

验收：
- [ ] 应用像原生 macOS 工具，不像网页套壳。
- [ ] 在离线环境完成 100% 主要用户操作。
- [ ] 0/3/20/50 项、超长标题、多屏场景可用。
- [ ] VoiceOver 可以理解每个事项标题和完成状态。
- [ ] 数据写入失败提示清晰；迁移失败不清空数据。
- [ ] 不申请无关权限、不包含第三方账号登录。
- [ ] 真机连续使用至少 7 天验证状态可靠性。

## 必测矩阵

| 模块 | 场景 |
| --- | --- |
| 日期 | 今天、明天、指定日期、DST、时区变化 |
| CRUD | 创建、编辑、完成、撤销、改期、删除恢复 |
| 复发 | 每日/每周、修改系列、单次例外、结束日期 |
| Overdue | 昨日未完成显示、已完成不出现、重新安排 |
| 排序 | 时间升序、无时间稳定顺序、已完成折叠 |
| 稳定性 | 重启、崩溃恢复、数据库写入/迁移失败 |
| UI | 空、3/20/50 项、Light/Dark、文本缩放 |
| 无障碍 | 键盘、VoiceOver、高对比度、Reduce Motion |
| 隐私 | 无网络、无 AI、无日历/GitHub 访问、无多余 entitlement |

## 发布前硬性门槛

1. **核心流程可运行**：打开菜单栏 → 添加日期任务 → 完成 → 重启仍保留。
2. **完全本地**：没有 API Key、云端功能、外部同步或后台网络任务。
3. **美学合格**：使用系统字体/材质/颜色/原生控件，避免自绘网页式 UI。
4. **边界严格**：没有 Start Focus、计时器、桌宠或项目仪表盘。
5. **证据明确**：未真机编译的项目一律标 NOT_TESTED，不宣称 PASS。

建议每个里程碑单独提交 PR，附变更说明和可复现测试命令。若只提交设计或 mock，不得误称完成真实应用。

## Current implementation evidence (2026-11-22, stabilization pass)

- **Implemented:** Swift Package macOS app target, `MenuBarExtra` window, local SwiftData tasks and per-occurrence records, date navigation, CRUD, completion, overdue handling, Daily/Weekly recurrence, English/Simplified Chinese strings, menu-bar count preference, completed visibility, and login-item control.
- **PASS:** `swift test` — 19 domain/store tests, including follow-Today midnight/wake/time-zone state, Quick Add IME submission guard, 1,000-task query, daily/weekly reschedule collisions, per-instance state, and reopening a disk-backed SwiftData store.
- **PASS:** `swift format lint --strict --recursive Sources Tests`.
- **PASS:** `./scripts/build-app.sh` — Release `.app` bundle.
- **PASS:** `codesign --verify --deep --strict ".FocusBarBuild/Focus Bar.app"` and `plutil -lint ".FocusBarBuild/Focus Bar.app/Contents/Info.plist"`.
- **PASS:** explicit follow-Today state refreshes the local date and badge in response to calendar-day, time-zone, system-clock, app-activation, and workspace-wake notifications; manual date selection remains pinned.
- **PASS:** recurring-instance conflicts retain stable independent records and show their origin date; Quick Add is inline with optional Details and native marked-text detection.
- **NOT_TESTED:** real menu-bar click-through, Light/Dark screenshots and visual audit, VoiceOver, actual Chinese IME candidate interaction, UI automation, actual sleep/wake/time-zone changes on-device, and login-item registration/restart/error behavior. Unit simulations do not replace those macOS interaction checks; native UI inspection was unavailable in the current computer-use session.
- **NOT_READY_FOR_DISTRIBUTION:** the local bundle is ad-hoc signed and not notarized. No migration UI, import/export, or automatic recovery UI is included.
