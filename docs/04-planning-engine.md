# 04 · 自动规划引擎（Focus Planning Engine）

状态：技术设计，尚未实现。目标：自动、可信、稳定地维护每日事项清单；**不是**让 LLM 随机生成 5 个听起来有意义的任务。

## 1. 输入与输出

输入：
- 用户明确确认的 Goals、RoutineRules、用户添加的 Task 与 Inbox。
- 今天与近期的日历事件及可用时间约束（用户明确选定的 Calendar）。
- 授权 GitHub 仓库的 Issue/PR/指派、状态、可核实 Deadline、近期进展摘要。
- 历史 DailyPlan、完成记录、Deferred/Dismissed 和手动排序。
- 本地时间、时区、配置、上次同步时间和连接健康状态。

输出：当日 `DailyPlan`，包含有序 `DailyPlanItem[]`、Must Do/Priorities/Routine 分组、推荐理由、来源与新鲜度标记。**不限定 3 项**；宁可清单短而真实，也不凑数。

## 2. 四层流水线

```text
Collect Source Records
    ↓ Normalize / Deduplicate / Validate
    ↓ Apply Hard Rules and User Overrides
    ↓ Rank Candidate Actions (deterministic)
    ↓ Optional LLM: summarize/re-rank eligible suggestions
    ↓ Validate structured result against invariants
    ↓ Merge into today's stable DailyPlan
```

### 2.1 数据收集
- 每个连接器实现相同接口：fetch changes / normalize / health / cursors。
- 按增量时间戳与分页获取；来源可用性独立显示。
- 仅从用户选定仓库/日历抓取，不默认扫描所有仓库或全部事件。
- 对同一来源数据记录稳定 ID、lastUpdated、最后同步时间。
- 不把“最近活动”自动当作承诺。

### 2.2 确定性约束
优先判断：用户直接设定的当日截止、明确日期的任务、被置顶的任务、已处理状态、日历时间占用、Routine 规则。必须处理事项优先展示，即使超出用户可用时间，也不应消失。

**Must Do 入选条件**：用户明确指定今天必须处理；或可靠源记录具有确认过的当日/逾期截止，且存在可执行的行动项。普通会议只占用时间，不自动等价 Must Do。

**Priorities 入选条件**：源任务未完成、与活跃 Goal 关联、当前具有合理可执行性和价值；无证据的推断降至 Needs Review。要防止长期技术项目被近期噪音永久挤掉。

**Routine 入选条件**：符合当前日期的重复规则，今日实例尚未完成；按 RoutineRule 生成，不从昨天的 Done 复用。

### 2.3 候选评分（建议初始参数）

```text
score = 0.35 * goalValue
      + 0.30 * urgency
      + 0.20 * impact
      + 0.10 * feasibility
      + 0.05 * continuity
```

各项归一化至 0–100。分数是排序辅助，不是自动判定 Must Do 的依据。

- GoalValue：与活跃长期目标的匹配度；无法可靠关联时不得高估。
- Urgency：只有明确可信的截止日期才能带来强截止加权；其他近期信号低于明确截止。
- Impact：用户定义的项目价值/阻塞关系；不能从 Commit 数量直接推导。
- Feasibility：预计耗时与今日可用时间是否匹配；耗时未知时允许未知，不编造精准分钟数。
- Continuity：昨日未完成且仍应继续时给予小幅加权。
- 多样性限制：不要让 10 条同一仓库的低价值候选淹没学业与重要工作；可按 Goal/项目做软上限，但 Must Do 不受此限制。
- 对连续多天没有完成且仍缺少具体行动的任务，改成“需要拆分/确认”而不是不断强推。

### 2.4 可选 LLM 层
LLM 负责：
1. 从可信候选和 Goals 中提出具体可执行的建议。
2. 对候选的重要性进行语义比较，并给出短理由。
3. 将模糊任务改写为清晰行动，但不得引入未经证实的新事实。
4. 识别重复/近义任务候选并提出合并建议（最终仍由规则与身份键决定）。

LLM **不得**：
- 创造新的明确 Deadline、用户承诺、会议事实和项目状态。
- 决定删除、完成、推迟或自动写入外部服务。
- 覆盖用户固定、编辑或当日移除的任务。
- 将来源文档或 GitHub Issue 中的恶意指令当作系统指令执行。

#### 结构化输出契约（示例）

```json
{
  "schema_version": 1,
  "local_date": "2026-11-22",
  "suggestions": [
    {
      "candidate_id": "existing-candidate-id",
      "suggested_title": "核对本轮验收中尚未通过的测试",
      "bucket": "priorities",
      "reason": "与当前活跃项目里程碑有关，且存在尚未关闭的候选事项",
      "source_keys": ["github:owner/repo:issue:12"],
      "estimated_minutes": null,
      "confidence": "medium"
    }
  ],
  "warnings": []
}
```

严格 schema 校验：candidate_id 必须引用本轮允许的候选；source_keys 必须为已知来源；bucket 在允许枚举内；限制最大长度、数量、类型；禁止模型输出自称已完成的事实。模型不能为 `dueAt` 赋值。

LLM Provider 设计为可替换接口：provider ID、model ID、timeout、budget、privacy mode。V1 默认不开启云端模型，需用户主动授权并输入凭证。无模型或异常时确定性引擎照常工作。

## 3. 今日快照合并策略

```text
function refreshToday(existingPlan, newCandidates, overrides):
  keep every user-confirmed done/deferred/dismissed state
  keep edited title/date/order and pinned items
  match candidates by stable sourceKey or Task ID
  update safe unedited source fields, record changed facts
  add verified Must Do not yet present
  put uncertain new suggestions into review/optional area
  preserve user-visible order unless explicit replan requested
  never delete on fetch/LLM failure
  commit transactionally; return same snapshot on repeated input
```

自动生成“每日快照”与“日间同步”应区别处理。晨间生成可以排序，日间更新则保持列表稳定。人工刷新也默认保留用户优先顺序；提供明确“重新规划”选项才做整体重排。

### 异常与静默降级
- 外部数据不可用：保留本地任务、原计划和来源时间标记。
- AI 失败/超时：保留确定性结果并显示“规则模式”，不阻断面板。
- 权限被撤销：停止后续抓取，清晰标记来源已断开。
- 跨午夜：生成新计划，但不能将昨天的 Done 当成今天完成。
- 时区变化：按源事件真实时间转换，date-only 截止必须保留日期语义。
- 并发刷新：single-flight + idempotency key，避免多个计划覆盖。
- 空结果：显示真实空状态，不编造任务。

## 4. 数据源质量与可信度

| 数据 | 可直接判断 | 不可直接推断 |
| --- | --- | --- |
| Calendar 有会议 | 有日程占用 | 一定需要准备材料 |
| GitHub Issue 被指派 | 存在工作候选 | 必须今天完成 |
| PR OPEN | 存在进行中的候选 | 用户今天必须 review/merge |
| 最近 Commit | 有项目活动 | 代表唯一优先目标 |
| 用户明示 Deadline | 需要在指定日期前处理 | 已完成 |
| RoutineRule 每日阅读 | 今天应出现一个阅读实例 | 已经阅读 |

学校课程系统若无授权连接，完全不从浏览器/屏幕偷读。

## 5. 成本与可观测性

- 默认每天一次主规划；手动更新和显著变更可能触发增量评估。
- 请求使用摘要化和上下文预算，最多上传必要任务标题、日期、项目简述与任务候选，避免原文批量传输。
- 开关分别控制云模型访问和 GitHub/Calendar 授权。
- 本地记录 planner version、inputs fingerprint、候选数、最终项数、失败类型与耗时；不在日志记录 token、全量日历内容或敏感提示词。
- 对模型输出保留结构化校验结果，方便定位幻觉/越权/重复。

## 6. 必测用例

1. LLM 编造“今晚 18:00 截止” → 拒绝 Deadline 字段。
2. GitHub Issue 字符串内带提示注入 → 只按数据文本处理。
3. 用户推迟事项后刷新 3 次 → 今日不会回来。
4. 用户勾选任务后 GitHub 仍 Open → 不撤销 Done。
5. 两来源指向同一真实记录 → 只生成一个 Task。
6. 有 20 个 Issues、2 个 Deadline → 不全部塞进 Must Do。
7. Calendar 权限撤销 → 清单仍可离线使用。
8. 凌晨睡眠后唤醒 → 生成当日唯一新计划。
9. 对同样候选重复规划 → 输出有界、稳定、无无故大改。
10. 初始没有任何数据 → 真实空状态。

相关：[数据模型](03-task-model-and-lifecycle.md) · [安全](06-privacy-and-security.md) · [验收](07-delivery-and-acceptance.md)
