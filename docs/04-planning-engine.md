# 04 · 本地清单与重复规则

Focus Bar 不再有计划日期。它只保存用户输入的事项、可选 DDL、时刻、重复规则和完成状态。

## 1. 展示依据

- 用户手动创建的所有未完成单次事项。
- 用户明确设置的 DDL。只有 DDL 早于本地今天时才归入 Overdue。
- 当前日期符合规则的每日/每周 occurrence。
- 用户明确设置的时刻和重复星期。

## 2. 查询与分组

```text
Fetch active tasks
    ↓
Generate today's matching recurrence occurrences
    ↓
Mark overdue only when dueDate < today and task is incomplete
    ↓
Sort overdue by dueDate, timed tasks by time, anytime by stable order
    ↓
Show completed items in a collapsible section
```

分组顺序：
1. **Overdue**：DDL 已过且未完成。没有 DDL 的事项永不进入此组。
2. **Scheduled**：有时刻、尚未逾期的未完成事项。
3. **Anytime**：没有时刻、尚未逾期的未完成事项。
4. **Completed**：已完成事项，按完成时间倒序。

空分组不显示标题。没有事项时显示空状态。

## 3. 新增默认值

- 标题必填。
- DDL 默认不设置。
- 时刻默认不设置。
- 重复默认关闭。
- 每周重复需要显式选择星期；未指定时使用创建当天的星期。
- 不存在计划日期默认值。

## 4. 重复事项

- `daily`：从创建后按日生成一个 occurrence。
- `weekly`：在选择的星期生成 occurrence。
- 完成、删除和单次编辑作用于对应 occurrence；系列仍继续运行。
- occurrence 唯一键由 `seriesID + localDate` 组成，防止重复生成。
- 重复任务的 DDL 只保存到对应 occurrence。
- 不累积漏做的旧 occurrence；面板只显示当前日期匹配的实例。

## 5. 日期与持久化

- 本地日期只用于 DDL 比较、每周规则以及 occurrence 身份，不作为单次事项的计划日。
- 使用本地年月日语义，避免 UTC 午夜和时区变化造成日期偏移。
- 系统日期、时区变化和唤醒后重新计算 Overdue、当前重复实例与菜单栏计数。
- 旧 SwiftData 记录中的计划日期作为兼容数据保留，但不参与查询、排序、分组或编辑。

## 6. 基础验收

1. 无 DDL 的事项无论跨过多少天仍显示在长期清单，且不进入 Overdue。
2. 显式设置的未来 DDL 不显示为逾期；DDL 过去且未完成后显示在 Overdue。
3. 完成的过期事项显示在 Completed，不显示在 Overdue。
4. 每日事项今天完成，下一次实例仍未完成。
5. 每周事项只在选择的星期出现，实例状态独立。
6. 删除一个重复实例不删除整个系列。
7. 重启后旧事项、完成状态和 DDL 保留；旧计划日期不再隐藏或逾期事项。
8. 1000 条单次事项均可查询和滚动。
