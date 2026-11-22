# 03 · 任务模型、状态机与本地数据

## 1. 基本对象

**Goal（长期目标）**：名称、重要程度、领域、是否激活、优先顺序、可选时间预算。它不是直接可勾选的 Task。Goals 可被一次性配置并长期沿用。

**SourceRecord（来源事实）**：原始日历事件/GitHub Issue/PR/个人输入的最小可追溯元数据。包含来源类型、外部稳定 ID、抓取时间、原始摘要、只读 URL、证据等级与最后修改时间。只在授权范围内采集。

**Candidate（候选行动）**：从目标、SourceRecord 或用户输入提取的行动，可能尚未适合进入今天清单。必须附有出处及类型：确定的用户承诺 / 已知截止 / AI 推断建议。

**Task（可操作任务）**：持久化的任务实体。具备稳定 UUID、标题、可选说明/截止时间/建议日期/预计投入、标签、来源链接、用户编辑标记和 lifecycle 状态。

**DailyPlan（日计划）**：`localDate + timeZoneID` 标识的一个当日快照，记录生成时间、运行模式、输入来源摘要、任务顺序、数据新鲜度和版本。不得只用 UTC 日期作为本地日界线。

**DailyPlanItem（当日任务引用）**：关联 Task、分组与排序位置、当日状态及生成理由。相同 Task 可以关联到不同日期，但不重复复制为多个任务实体。

**UserOverride（用户覆盖）**：pin、edit、defer、dismiss-for-today、mark-done、explicitly-reopen 等用户行为事件，带时间戳和作用范围。合并计划时最高优先。

**RoutineRule（重复规则）**：日常阅读等固定习惯的周期、启用状态及可选时间；按日期生成当天实例，永不沿用昨天的“已完成”状态。

## 2. Task 最小字段（建议 SwiftData Model）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | UUID | 内部稳定 ID |
| title / notes | String | 用户可改，保留原始文本 |
| origin | enum | manual / calendar / github / routine / aiSuggestion |
| sourceKey | String? | 例如 github:owner/repo:issue:123，唯一去重参考 |
| sourceURL | URL? | 官方来源链接，绝不自造 |
| provenance | enum | explicit / verified / inferred |
| goalIDs | [UUID] | 与多个长期目标的关系 |
| dueAt | Date? | 确认来源的绝对时间，不能 AI 编造 |
| scheduledFor | local date? | 建议处理日期，不等于截止时间 |
| createdAt / updatedAt | Date | 审计和合并 |
| status | enum | open / done / deferred / dismissed / archived |
| userEditedFields | Set | 合并时不得覆盖的字段 |
| priorityScore | Double? | 规划计算值，非事实 |
| reasoning | String? | 简短推荐理由 |
| confidence | enum | high / medium / low |
| lastSeenAt | Date? | 最近一次从来源看到 |
| estimationMinutes | Int? | 推测须标明，不能当承诺 |

实现阶段可以将数组/集合关系映射为额外模型或可编码字段，避免把示意结构当成已经验证的 SwiftData schema。

## 3. 生命周期状态机

```text
Capture / Sync → Candidate
Candidate → Planned (Today) / Backlog / Needs Review
Planned → Done / Deferred / Dismissed for Today
Done → Reopened (explicit user action only)
Deferred → Candidate on chosen date
Dismissed for Today → May be reconsidered tomorrow, not today
Archive → History (retain provenance)
```

状态规则：
- **Done 是用户操作**：不允许自动读取到 PR merged 就标记任务完成。
- **Deferred 不是 Done**：推迟到指定日期并保留用户操作记录。
- **Dismissed for Today**：当日不再自动插回；明确的新用户操作或严重截止变更可请求确认，默认不强插。
- **Archive**：旧计划和任务历史可查询；数据保留策略可配置。
- 完成状态与日计划关联：Routine 每天新实例，不跨日带 Done；长期任务的完成可保持 Task Done，而当日快照另存事件。

## 4. 日期与时间边界

- `dueAt` 存储 UTC 时刻与来源给定时区；显示按 Mac 当前本地时区转换。日期型 Deadline（没有具体时刻）另以 `dueLocalDate` 与源时区表示，**不得假装 00:00 截止**。
- `scheduledFor` 是本地日期，`DailyPlan.localDate` 使用本地日期 + timeZoneID。
- 用户在旅行/修改时区时，对截止时间与每日快照做清晰转换策略。不能自动把昨天已完成的 Routine 迁移到今天。
- macOS 睡眠、关机、跨过午夜后，下一次唤醒/启动进行日界线检查、幂等生成，不会在每次打开面板时覆盖今日修改。

## 5. 去重与冲突
- 首选稳定外部 ID（calendar event identifier + occurrence time，GitHub repo + item type + number）与 sourceKey 去重。
- 单一事件在多个来源出现时，根据证据与匹配规则关联 SourceRecord；标题相似不能自动合并不同事项。
- 跨日延续任务与新候选重合时沿用 Task ID，不制造第二个复选框。
- 用户修改标题之后外部来源更新，只同步未锁定字段；发生实质差异应写入变更记录而非静默覆盖。
- 重复抓取、并发定时调用需使用 idempotency key；事务内维护任务及计划关联。
- AI 建议与确定性来源相矛盾时，以来源证据和用户覆盖为准。

## 6. 优先级与信任等级

| 级别 | 说明 | 是否能进入 Must Do |
| --- | --- | --- |
| explicit | 用户直接创建/确认具体当日承诺 | 可以 |
| verified | 外部数据存在可核实截止或已承诺行动 | 有清晰行动证据才可以 |
| inferred | 从活动推断出的可选工作 | 不可以，最多 Priorities/Needs Review |

仅凭“今天有会议”不能生成“必须准备会议材料”；仅凭 GitHub 有新 Commit 不能生成“必须审核 PR”；仅凭历史兴趣不能生成虚构的任务。

## 7. 用户行为优先合并（核心不变量）

1. **今天已完成的任务不会因后台同步恢复为未完成。**
2. **今天被移除的任务不会因刷新重新出现。**
3. **用户改写的任务标题/日期不被 LLM 或源抓取覆盖。**
4. **同一源记录在一天内不会生成两个任务。**
5. **Routine 每个日期有独立完成记录。**
6. **没有可核实来源的 Deadline 必须为空。**
7. **失败刷新不删除已有计划。**

## 8. 建议本地模型关系

```text
Goal 1---N GoalTaskLink N---1 Task
Task 1---N DailyPlanItem N---1 DailyPlan
SourceRecord N---N Task (TaskSourceLink)
Task 1---N UserOverride
RoutineRule 1---N Task instances
SyncCursor 1---1 IntegrationConfig
```

使用迁移版本和数据库 backup/restore 测试；敏感原始载荷只存必要摘要，避免将整份日历和仓库内容长期复制到本地。

关联：[PRD](01-product-requirements.md) · [规划引擎](04-planning-engine.md) · [测试](07-delivery-and-acceptance.md)
