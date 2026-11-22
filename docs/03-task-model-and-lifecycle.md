# 03 · 数据模型与任务生命周期（V1 手动版）

本版没有 AI 候选池、外部 SourceRecord、GitHub 数据模型或外部同步冲突。唯一任务来源是用户本人输入，所有记录本地存储。

## 1. 核心模型

### Task
```text
id: UUID
title: String                       // 必填，trim 后非空
notes: String?                      // 可选
scheduledDate: LocalDate            // YYYY-MM-DD 语义；默认当前所查看日期
scheduledTime: LocalTime?           // HH:mm，可空
dueDate: LocalDate?                 // 可选 DDL；默认 nil，与计划日期独立
status: open | completed            // 用户明确勾选
createdAt: Date
updatedAt: Date
completedAt: Date?
sortOrder: Int                      // 同时间/无时间稳定排序
seriesID: UUID?                     // 重复事项关联
isDeleted: Bool                     // 或软删除模型，用于 Undo
```

这里的 LocalDate / LocalTime 是领域层概念；SwiftData 中可以用独立年月日数字字段、或提供安全转换的编码字段。**不要直接存 UTC 午夜 Date 作为用户选定日期的唯一真相**，否则跨时区可能移到前一天。

### RecurrenceRule
```text
id: UUID
titleTemplate: String
notesTemplate: String?
startDate: LocalDate
time: LocalTime?
frequency: none | daily | weekly
weekdays: Set<Weekday>?             // weekly，按选定星期
endDate: LocalDate?                 // 可空
isEnabled: Bool
createdAt: Date
updatedAt: Date
```

重复规则生成按日 **occurrence**，通过 `seriesID + localDate` 唯一键避免多次刷新重复。完成/跳过状态与可选 DDL 按 occurrence 单独保存。V1 默认编辑当前实例；若提供“编辑此系列”必须明确确认作用范围。

### CompletionRecord / OccurrenceOverride
对重复事项记录 `seriesID, occurrenceDate, completedAt?, hidden?, overrideTitle?, overrideTime?`；不因次日进入新日将昨天状态沿用。生成可视 occurrence 可以采用按需虚拟展开 + 独立覆盖记录，避免一次创建无限任务。

### Preferences
`showMenuBarCount`、`launchAtLogin`、`showCompleted`、`defaultDateView`、`useSystemAppearance`。

## 2. 任务生命周期

```text
Create → Open → Completed ⇄ Reopened
                 ↓
             Delete (with Undo/confirmation)
Open → Rescheduled → Open (new scheduled date)
```

- 所有完成都由用户勾选；无自动完成。
- 已完成单次事项不会出现在 Overdue。
- 单次未完成事项跨日后出现在 Today 的 Overdue，仍保留原始 scheduledDate。
- “移动到明天”是用户明确改动 scheduledDate，不会制造第二条重复任务。
- 删除要有 Undo 或确认，防止误触后永久丢失。建议可以选择软删除和归档恢复策略。
- 重复规则按 occurrence 独立完成；修改规则后，用户手动覆盖/完成的历史记录不应该丢失。

## 3. 展示查询

选中日期 D 时：
1. 选中日期的未完成非重复 Task。
2. 按规则匹配 D 的未完成重复 occurrence（扣除例外）。
3. 如果 D 为 Today，额外展示 `scheduledDate < Today` 的未完成单次任务于 Overdue。查看其他日期默认不混入 Today Overdue。
4. 选中日期已完成事项折叠显示。
5. 排序：Overdue 按原日期升序；当日有时间事项按时刻升序；无时间事项按 sortOrder/createdAt；已完成按完成时间倒序。
6. 任务数量没有 3 件等上限；长清单滚动。

## 4. 日期与时区

- 计划日期作为用户选择的 **calendar date** 存储，不随系统时区变化而意外改日。
- 具体时间是用户选择的该日当地墙上时间，V1 只做清单显示，不为 DST 缺失/重复时刻自动发送提醒；若时间无效需标注并要求用户确认。
- Today 由系统当前 Calendar 和 TimeZone 获取，检测日期变更/唤醒并刷新查询。
- 系统时间改动可能改变“今日”和“逾期”的判断，但不修改源任务日期。
- 12/24 小时显示尊重系统 Locale。

## 5. 数据一致性

- 同一任务每次打开只有同一个 UUID。
- 重复 occurrence 的唯一键保证幂等，不重复生成。
- 完成/撤销操作跨重启不丢失。
- 一次事务更新任务与对应重复 occurrence 状态。
- 修改编辑状态时不丢输入；SQLite/SwiftData 错误则明确呈现，不能假成功。
- 数据模型升级要有 migration plan 和旧版本迁移测试。
- 本地完全离线，无外部数据来源冲突或 AI 生成结果覆盖用户操作。

相关：[显示规则](04-planning-engine.md) · [测试](07-delivery-and-acceptance.md)
