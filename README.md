# Focus Bar

**A quieter way to keep track of today.**

Focus Bar 是一个 **macOS 原生菜单栏每日事项清单**。用户手动添加任务和日程，指定日期（时间可选），点击菜单栏就能查看当天需要处理的事项、勾选完成或调整安排。

**V1 不接 AI，不读取 GitHub，不同步外部日历，不需要账号或服务器。**

> 点击菜单栏，看今天要做什么。

## 已确定的 V1 范围

- 原生 macOS 菜单栏图标与轻量弹出清单（SwiftUI + AppKit）。
- 手动新增、编辑、完成、撤销完成、删除事项。
- 创建事项时默认日期为今天；可选任意日期及具体时间。
- 今日列表按时间顺序显示；无具体时间的事项放在其后。
- 逾期未完成的事项持续可见，不自动改动其原始日期。
- 切换查看今天、明天和指定日期，可提前安排。
- 可选每日/每周重复事项；各日期的完成记录独立。
- 本地离线保存，关闭面板或重启 Mac 不丢数据。
- 菜单栏显示单色图标，可选择显示未完成数量。
- 原生外观、深浅色、键盘/VoiceOver 支持、可配置登录启动。

## 明确不做

- AI、LLM、自动生成/排序、智能推荐与云端同步。
- GitHub/Calendar/Reminders 的集成或自动读取。
- 专注按钮、计时器、番茄钟、专注时长统计。
- 桌宠、桌面悬浮窗、复杂 Dashboard、团队协作和移动端。

V1 是**手动维护的每日清单**，不宣称能够自动知道用户该做什么。未来 AI/外部连接如果有必要再单独评估，不是本阶段的隐藏依赖。

## 每日体验

1. 点击菜单栏 Focus Bar 图标，打开 Today。
2. 点击 **+** 输入事项标题；日期默认为今天，也可选择其他日期以及时间。
3. 当天事项按时间排列；无时间事项随后显示，逾期未完成事项单独提示。
4. 点击圆形复选框标记完成；右键可编辑、移动日期、删除。
5. 顶部日期控件支持 Today / Tomorrow / 选择某天；清单本地保存，完全离线。

## 文档

| 路径 | 内容 |
| --- | --- |
| [01 产品需求](docs/01-product-requirements.md) | V1 范围与功能 |
| [02 UI/UX](docs/02-design-system-and-ux.md) | macOS 原生设计和交互 |
| [03 数据与状态](docs/03-task-model-and-lifecycle.md) | 日期、重复与完成语义 |
| [04 今日清单规则](docs/04-planning-engine.md) | 无 AI 的筛选、排序和跨日规则 |
| [05 工程架构](docs/05-architecture-and-integrations.md) | 原生 Swift 应用与本地存储 |
| [06 隐私与可靠性](docs/06-privacy-and-security.md) | 离线、权限与恢复 |
| [07 开发验收](docs/07-delivery-and-acceptance.md) | 分阶段目标、测试 |
| [08 使用流程](docs/08-user-journeys-and-edge-cases.md) | 日常情境与边界情况 |
| [09 决策记录](docs/09-decisions.md) | 本次范围决策 |
| [10 Coding Agent 指南](docs/10-implementation-brief.md) | 可直接执行的开发提示与边界 |

## 技术方向

**Swift + SwiftUI + 必要时的 AppKit + SwiftData**，推荐从 macOS 14+ 开始验证。主入口使用 `MenuBarExtra` 的 window 样式，按需要支持原生 Settings 和登录启动。没有网络依赖，没有模型 API Key，没有第三方账号。

目前仓库状态：**设计文档已建立；应用尚未实现或编译验收。**

方案修订：2026-11-22。