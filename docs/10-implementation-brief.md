# 10 · Coding Agent 实施指南

**任务：实现 Focus Bar V1 的原生 macOS 菜单栏事项清单。** 当前仓库是设计文档阶段；不要将 README 当成现有可编译项目。

## 产品目标

Focus Bar 允许用户通过 Mac 菜单栏手动添加和查看按日期安排的任务，轻松勾选完成、改期或删除。外观尽可能融入 macOS 系统，美学极简、高级、自然。全部核心功能本地离线运行。

### 必须实现

1. 使用 Swift + SwiftUI + 必要的 AppKit 开发 macOS 菜单栏应用，初步面向 macOS 14+。
2. `MenuBarExtra` + window style；点击图标展开自然、点击外部收起；带原生 Settings 和 Quit。
3. Today 面板主界面：Today 标题、日期切换、列表、内联添加、已完成折叠。
4. 新增：标题必填，当前查看日期默认，具体时刻可选；支持编辑、完成、撤销、改期、删除。
5. 支持 Today / Tomorrow / 指定日期，系统时间变化后更新 Today。
6. Today 顶部可显示非重复单次逾期任务；不自动改期。
7. Daily/Weekly 可选重复，单次 occurrence 完成与系列状态分离。
8. 全部操作使用 SwiftData 本地持久化，重启/断网不丢。
9. 语义系统颜色、SF 字体、SF Symbols、系统材质；自动 Light/Dark；减少动画、键盘、VoiceOver。
10. 编写可运行的日期/重复/生命周期单元测试与至少关键 UI 测试；提供构建、测试与真机验证说明。

### 绝对禁止（V1）

- AI、LLM、自动推荐/生成、自动收集外部数据。
- GitHub、Calendar、Reminders、Gmail、云账户、服务端、在线 API。
- Start Focus、专注计时器、Pomodoro、屏幕监控、桌宠、统计 Dashboard。
- Electron、WebView UI 和与使用场景无关的重型依赖。
- 用虚构的自动任务冒充真实任务；用 mock 成功替代真实功能验收。

## 推荐架构

```text
App/FocusBarApp.swift
Features/Today/{TodayPanel,TaskRow,DateSwitcher,QuickAdd}
Features/Settings/
Domain/{LocalDate,LocalTime,Task,RecurrenceRule,TodayQueryService}
Persistence/{SwiftDataModels,TaskRepository}
System/{Clock,LoginItemCoordinator}
Tests/{TaskTests,RecurrenceTests,DayQueryTests,PersistenceTests}
```

允许合理调整结构，但必须保留 Domain 与 UI、Persistence 的分离，避免业务日期逻辑藏在 SwiftUI View 中。

## UI/UX 硬约束

- 面板宽度建议约 360pt，尊重屏幕尺寸。
- 任务列表为线性文本行，非卡片网格。
- 不要默认展示大片标题、副标题、标签、百分比或进度图。
- 细节靠排版、灰阶、原生动画与留白体现。
- 带时间的任务按时刻显示，未指定时间的归入 Anytime，Completed 折叠。
- 逾期展示须说明原计划日期，不羞辱用户。
- 菜单栏图标单色模板，支持选择显示未完成数量。
- 真实 SwiftUI Preview / screenshot 审核 Light、Dark、长标题、列表过长。

## 实施步骤

### Sprint 1
搭建项目和 `MenuBarExtra`；使用纯本地 fixture 做 UI；设置窗口与退出入口可用。提交截图和构建结果。

### Sprint 2
SwiftData 任务模型、本地 CRUD、日期切换、完成/撤销、编辑、删除、键盘输入法兼容。所有操作真正持久化。

### Sprint 3
Overdue、稳定排序、每天/每周重复和独立 occurrence 状态；针对时区、跨日、重启编写测试。

### Sprint 4
全局 UI polish、无障碍、登录启动、异常与恢复状态，真实 macOS 验收与文档补充。

## 结束时交付

- 可编译的完整 Xcode 工程。
- 清晰的 README 安装/开发步骤。
- 具体 macOS/Xcode 版本、实际构建和测试命令、PASS/FAIL/NOT_TESTED 结果。
- 各关键界面 Light/Dark 截图（真实运行，非生成图）。
- 重要架构决定与原方案差异说明。
- 不得在没有真机/CI 证据时宣称编译通过。

## 验收关键路径

`Launch → click menu bar → add “Tomorrow 10:30 task” → switch to Tomorrow → see task → mark complete → restart app → completion persists`

只要这条路径无法稳定闭环，其他视觉包装都不等于完成 MVP。

详见 [PRD](01-product-requirements.md)、[设计系统](02-design-system-and-ux.md)、[模型](03-task-model-and-lifecycle.md)、[开发验收](07-delivery-and-acceptance.md)。
