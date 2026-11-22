# 02 · Focus Bar 原生 macOS 设计与交互规范

状态：设计 / 未实现 · 目标：**像 macOS 自带的一张清单。**

## 1. 不可妥协的视觉方向

- Native macOS Minimalism：系统标准字体 SF Pro、语义颜色、SF Symbols、原生 window 材质与窗口阴影。
- 一行一项，默认不堆砌多层卡片、彩色优先级、统计进度或动画装饰。
- Light / Dark Mode 自适应，支持提高对比度、减少透明度和减少动画效果。
- 不复制网页的自绘输入框和浮动按钮；只在系统组件不足时局部定制。
- 点击区域舒适、焦点明确、VoiceOver 完整可用。

## 2. 信息架构

### 菜单栏状态
- 默认图标：简洁单色清单符号，模板渲染。
- 可选图标旁的未完成数量（如 `4`）。空间不足优先仅显示图标。
- 不在菜单栏持续滚动文字、不做计时器。

### Today 面板
面板约 350–380 pt 宽；内容高度不超过当前屏幕可用高度约 75%，列表内部滚动；最终尺寸以真实 macOS 渲染检验。

```text
┌───────────────────────────────────┐
│ Today                    ···      │
│ Sunday, November 22      ▾        │
│                                   │
│ OVERDUE                           │  [可选]
│ ○ Submit draft                   │
│                                   │
│ 10:30                             │  [有时间才显示]
│ ○ Discuss project                │
│ 15:00                             │
│ ○ Review assignments             │
│                                   │
│ ANYTIME                           │  [有无时间事项才显示]
│ ○ Order materials                 │
│ ○ Read 30 minutes                 │
│                                   │
│ ▸ COMPLETED (2)                   │
│ ───────────────────────────────── │
│ + Add a task                  ⚙   │
└───────────────────────────────────┘
```

这是一张清单，不是日历周视图。时刻信息若有则作为任务副信息或左侧时间标签。不要预设每日只有三个任务。

### 日期导航
点击日期显示 macOS 原生日期选择器 / 简洁 popover；提供 Today、Tomorrow 快捷入口。切换日期不更改任务本身的安排；点击标题 Today 返回当日。

### 新增表单
- 底部 Add 始终容易访问，点击打开内联编辑。
- 必填仅 Title。创建日期默认为当前所查看日期（在 Today 就是今天，在 Tomorrow 就是明天）。
- Date、Time（可选）、Notes（可选）、Repeat（日/周/不重复）作为轻量展开字段，不放进单行默认界面。
- 保存后列表立即更新，键盘焦点行为符合原生控件习惯。
- 禁止输入法候选态误保存（特别是中英文混输）。

### 任务行
- 未完成：原生圆形勾选行为；已完成：弱化/删除线并进入折叠 Completed。
- 右键原生 Context Menu：Edit / Move to Tomorrow / Change Date / Delete。
- 长标题最多显示两行，支持详情展开查看全文；不截断时隐藏关键时间信息。
- 只有明确配置时间的事项才显示时间，使用系统 locale 的 12/24h 约定。
- 每行有充分点击区域；任务数多时维持稳定行高。

## 3. 设计 Tokens（推荐，不是硬编码强制值）

| 元素 | 方向 |
| --- | --- |
| 容器边距 | 约 16 pt |
| 主标题 | 系统字体、Semibold，20–24 pt |
| 任务标题 | 系统 13–14 pt、正文颜色 |
| 次信息 | 11–12 pt、secondaryLabel |
| 行内间距 | 约 10–12 pt |
| 组间距 | 约 16–20 pt |
| 分割线 | 原生 separator，极低对比度 |
| 强调色 | 系统 Accent Color，仅在需要时 |
| 圆角/阴影 | 尽量交给系统 window |

避免固定浅色白底导致深色模式崩坏。不要每一行包卡片，别为了“高级感”添加没有实际用途的彩色 Badge。

## 4. 交互与微动画

- 完成/撤销即时反馈，本地提交确认后持久化；折叠列表变化不能吞掉正在编辑的行。
- 不用花哨弹跳、音效或庆祝动画。
- 新增成功时列表平滑更新，短暂突出即可，尊重 `Reduce Motion`。
- 点击窗口外关闭；关闭不会丢失已保存任务。
- Esc 关闭当前编辑/日期浮层；Tab/Shift+Tab 遍历控件；Space 勾选；Return 保存（考虑 IME 状态）。
- 系统 Settings 可编辑登录启动、菜单栏计数和已完成事项显示方式。

## 5. 全状态设计

| 状态 | UI |
| --- | --- |
| 今日无事项 | “Nothing scheduled for today.” + Add |
| 特定日期无事项 | “No items for this day.” + Add |
| 全部完成 | “All done for today.”；可展开 Completed |
| 逾期事项 | 顶部小节，保留原安排日期 |
| 20+ 条任务 | 内部滚动，顶部日期与底部添加可访问 |
| 标题特别长 | 自动换行/详情查看 |
| 存储失败 | 明确的本地错误提示和重试，不能假成功 |
| 数据迁移失败 | 安全只读/恢复提示，不静默清空 |
| Light/Dark | 系统色与材质适配 |
| 键盘/VoiceOver | 所有主要任务可操作 |

## 6. 明确排除的界面

不显示：
- AI 提示、推荐原因、LLM 提供方。
- Start Focus / Pause / Timer / Pomodoro。
- 桌宠、桌面浮层、项目统计图、复杂指标面板。
- “连接 GitHub/Calendar”入口（V1 没有这些集成）。

## 7. QA 验收截图集

提供原生 macOS 截图：Light、Dark、空状态、3 项、20 项、50 项、逾期、重复任务、日期选择、内联添加、已完成折叠、设置与异常提示。应当看起来像系统工具，而不是网页 UI。

官方参考：https://developer.apple.com/design/human-interface-guidelines/ · https://developer.apple.com/documentation/swiftui/menubarextra