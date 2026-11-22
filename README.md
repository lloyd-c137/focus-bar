# Focus Bar

**A quieter way to know what matters today.**

Focus Bar 是一款 **macOS 原生菜单栏智能每日事项清单**。它从用户明确设定的长期目标、手动捕获的事项、日历以及授权的 GitHub 仓库中收集可信上下文，自动整理和排序今天需要处理的事情。

> 打开 Mac，点击菜单栏，就知道今天要做什么。

## 产品原则

1. **List first**：用户需要的是每日事项清单，不是计时器、专注模式或任务管理仪表盘。
2. **Automatic, not opaque**：自动生成和维护，但可查看来源、推荐原因，并随时编辑或推迟。
3. **Native by default**：使用 SwiftUI / AppKit，遵循 macOS 的字体、材质、键盘、辅助功能与交互约定。
4. **Quiet by design**：默认静默更新，不使用惩罚、催促、游戏化或高频通知。
5. **Local-first, permission-based**：本地保存数据，外部数据和云端模型均由用户显式授权。
6. **No invented commitments**：不得把 GitHub 活动、AI 猜测或不确定信息伪装成真实截止日期与用户承诺。

## V1 边界

**包含：** 菜单栏常驻；今日全部相关事项（不限定 3 项）；Must Do / Priorities / Routine 分组；完成、推迟、编辑、添加；Quick Capture；本地历史；日历只读使用；选定 GitHub 仓库的只读同步；AI 辅助排序与生成；无网络降级；偏好与隐私设置。

**不包含：** 桌宠、桌面悬浮窗、Start Focus、番茄钟、计时器、专注统计、屏幕监控、完整项目管理器、手机端及云端账号系统。

## 产品文档

| 文档 | 说明 |
| --- | --- |
| [01 · 产品需求](docs/01-product-requirements.md) | 目标、受众、范围、功能和成功指标 |
| [02 · UI/UX 与设计系统](docs/02-design-system-and-ux.md) | macOS 视觉规则、菜单栏、交互和状态 |
| [03 · 任务模型与生命周期](docs/03-task-model-and-lifecycle.md) | 领域模型、状态机、去重、日期与用户覆盖 |
| [04 · 自动规划引擎](docs/04-planning-engine.md) | 数据采集、约束规则、评分、AI 输出与稳定性 |
| [05 · 系统架构与集成](docs/05-architecture-and-integrations.md) | Swift 组件、EventKit、GitHub、调度、错误处理 |
| [06 · 隐私与安全](docs/06-privacy-and-security.md) | 权限边界、密钥、隐私保护、威胁模型 |
| [07 · 工程里程碑与验收](docs/07-delivery-and-acceptance.md) | 分阶段交付、自动化测试、发布与验收标准 |
| [08 · 用户流程与边界情况](docs/08-user-journeys-and-edge-cases.md) | 首次启动、日常使用、无数据和异常场景 |
| [09 · 决策与待验证问题](docs/09-decisions.md) | 已确定产品决定、尚需验证的实现细节 |
| [10 · Coding Agent 执行规范](docs/10-implementation-brief.md) | 后续代码实现可直接使用的开发约束和任务划分 |

## 建议技术栈

- **平台**：macOS 14+（待首个真实构建验证）
- **应用**：Swift、SwiftUI、少量 AppKit，`MenuBarExtra` + `.window`
- **本地数据**：SwiftData；敏感凭证放在 Keychain
- **外部上下文**：EventKit 日历、选定 GitHub 仓库的只读 REST API
- **规划**：可测试的确定性规则引擎 + 可选的结构化 LLM 推荐
- **发布**：先本机 Xcode 构建验证；随后确定分发、签名、公证与许可证策略

## 当前状态

**DESIGN SPECIFICATION / NOT IMPLEMENTED**。本仓库首批提交只包含产品和工程设计文档，并非已完成或已编译通过的 macOS 应用。实现阶段以文档中的验收条件为准，不应将规划中的能力表述为已可用。

## 官方参考

- [Apple · MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [Apple · Building and customizing the menu bar](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui)
- [Apple · EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
- [GitHub · Fine-grained token permissions](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens)

_方案基线：2026-11-22。_
