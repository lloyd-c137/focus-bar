# 03 · 数据模型与任务生命周期

本版事项没有计划日期。日期仅用于显式 DDL、重复规则的星期判断和 occurrence 身份。

## 1. Task

```text
id: UUID
 title: String                   // trim 后非空
 notes: String                   // 可选
 dueDate: LocalDate?             // 可选 DDL，默认 nil
 time: LocalTime?                // 可选时刻，不附着某一天
 frequency: never | daily | weekly
 weekdays: Set<Weekday>         // weekly 规则
 status: open | completed
 createdAt: Date
 completedAt: Date?
 sortOrder: Int
 isDeleted: Bool
```

不要添加 scheduledDate、日期导航状态或基于创建日期的逾期判定。SwiftData 旧版任务中的 `dayKey` 只为读取既有 Store 保留，不能用于 UI、查询、排序或任务状态。

## 2. Recurrence / Occurrence

重复规则由频率、星期和创建时间确定。`OccurrenceRecord` 使用 `seriesID + localDate` 唯一标识当天实例，用于独立完成、删除和字段覆盖。Occurrence 日期是内部状态键，不是用户可编辑的计划日期。

重复 DDL 仅属于对应 occurrence。重复系列的后续实例不会继承当前实例的 DDL。

旧版 occurrence 中的 `rescheduledDayKey` 只为 Store 兼容保留，不再生成或筛选任何任务。

## 3. 生命周期

```text
Create → Open → Completed ⇄ Reopened
Open → Overdue view (only explicit dueDate < local today)
Open → Delete (undo)
Recurring Rule → Today's matching occurrence → Completed / Deleted
```

- 无 DDL 的单次事项持续显示，不会随时间自动逾期。
- 设置 DDL 且日期早于今天的未完成事项进入 Overdue。
- 完成的事项进入 Completed，不在 Overdue 中重复显示。
- 不提供按日期改期，因为事项没有计划日期。
- 每日/每周实例状态互不影响；不累积历史漏做实例。

## 4. 查询规则

1. 载入所有未删除的单次事项，不根据旧版 `dayKey` 过滤。
2. 按本地当前日期生成匹配的重复 occurrence。
3. 仅当 `dueDate < today && status == open` 时标记 Overdue。
4. Overdue 按截止日期排序；未逾期有时刻事项按时刻排序；Anytime 按稳定顺序排列。
5. 已完成事项折叠显示，单次事项可在 Completed 中撤销。

## 5. 本地日期

- 本地日历日期只用于 DDL 比较、周几匹配和 occurrence 键。
- 不把 UTC 午夜作为用户选择日期的唯一真相。
- 日历日、系统时区、睡眠唤醒变化后刷新逾期状态、重复实例和菜单栏计数。
