# 05 · 系统架构与数据集成

## 1. 技术定位

原生 macOS 菜单栏应用，建议最低 macOS 14+。主体使用 Swift + SwiftUI、必要的 AppKit；状态使用明确的 observable/view model；存储使用 SwiftData；系统事件由 EventKit 读取；凭证使用 Keychain。V1 不需要后端账号/服务器，不使用 Electron/WebView。

**注意：本文是实现建议，不表示目前已经创建、编译或验证任何 Swift 工程。** 在真实 Mac 及目标系统版本上运行预研样例后再锁定部署目标与 UI 行为。

## 2. 分层架构

```text
FocusBarApp (SwiftUI App)
├── MenuBar Scene (MenuBarExtra + window style)
│   ├── TodayPanel (Header / Groups / Rows / Footer)
│   ├── QuickAdd
│   └── Context Menus
├── Settings Scene (Goals / Integrations / AI / Appearance / Privacy)
├── Presentation / ViewModels
├── Application Services
│   ├── DailyPlanCoordinator
│   ├── TaskCommandService
│   ├── CaptureService
│   ├── BackgroundRefreshCoordinator
│   └── Notification/StatusService (minimal)
├── Domain
│   ├── Models and Invariants
│   ├── RulePlanner / OptionalLLMPlanner
│   ├── MergeEngine / Provenance
│   └── Repositories (protocols)
├── Data
│   ├── SwiftData Persistence / Migration
│   ├── CalendarConnector (EventKit, selected calendars)
│   ├── GitHubConnector (URLSession REST, selected repos)
│   ├── LLMProvider (opt-in, HTTPS)
│   └── KeychainCredentialStore
└── Infrastructure
    ├── Log / Error Handling / Clock / Connectivity
    └── Scheduler / Wake / Timezone Events
```

分层原则：Domain/Planner 不依赖 AppKit、HTTP 或真实时间；通过协议注入 Clock、Repositories、Connectors、LLM，保证单元测试可确定重放。

## 3. 建议仓库结构（开始编码时）

```text
FocusBar/
  App/
  Features/
    Today/
    Capture/
    Settings/
  Domain/
    Models/
    Planning/
    Commands/
  Data/
    Persistence/
    Integrations/Calendar/
    Integrations/GitHub/
    AI/
  Infrastructure/
    Keychain/
    Scheduling/
    Logging/
  Resources/
FocusBarTests/
  Unit/
  Integration/
  Fixtures/
FocusBarUITests/
docs/
README.md
```

优先采用标准 Xcode project / Swift Package 模块，避免为了第一版制造复杂 monorepo。项目 bundle identifier、team、签名由部署环境确定，不在文档中编造。

## 4. MenuBarExtra 与窗口行为
- 菜单栏使用 `MenuBarExtra` 和 window 样式，内容为 SwiftUI View。
- 需要独立 Settings Scene；验证以 accessory/agent app 运行时的 Settings 打开方式，若系统控制无法满足才局部使用 AppKit。
- 应用可以不在 Dock 显示，但必须提供清晰的 Quit 命令、辅助功能及错误恢复通道。
- 点击外部关闭弹层，内容更新不重建整个菜单栏 Scene，避免闪烁/焦点丢失。
- 菜单栏图标支持模板着色及可选文字进度；空间不足时图标优先。
- 多显示器、多 Space、全屏应用、菜单栏自动隐藏时需要实测表现。

参考：https://developer.apple.com/documentation/swiftui/menubarextra

## 5. CalendarConnector
- 使用 EventKit 读取用户选择的日历与事件。
- macOS 14+ 读取日历需要适合读取的 **full calendar access** 授权流程；“App 逻辑只读”不等于 macOS 授予纯只读系统权限。应用不得写入或修改日历事件。
- 配置所需的 Info.plist 隐私说明与沙盒 Entitlement（当启用 sandbox 时），缺失时应在测试中检测并明确报错。
- 用户手动选择共享给 Focus Bar 的日历；支持撤销和重新同步。
- 使用系统提供的事件 ID、开始结束时间、时区和重复实例身份去重；取消事件时不得无脑删除用户已确认的独立任务。
- 时间占用与“要做的事”严格区分：Calendar Event 默认只生成 availability constraint，只有可信 action data 才生成候选 Task。

参考：https://developer.apple.com/documentation/eventkit/accessing-the-event-store

## 6. GitHubConnector
- V1 采用只读 REST API，优先支持用户明确选中的仓库；可用 fine-grained PAT 做本地个人版本，使用 Keychain 保存。商业化/共享版再评估 OAuth/GitHub App。
- 按当前 API 端点要求申请最小权限（通常涉及 Issues / Pull requests / Contents 的 read；应以 GitHub 官方 endpoint permission 文档复核），不要使用宽泛写权限。
- 读取：仓库基本信息、参与/指派相关 Issue、PR 状态、必要时近期提交摘要；必须做分页、条件请求、速率限制和错误恢复。
- 用 sourceKey 标识类型：`github:owner/repo:issue:#`、`github:owner/repo:pr:#`；URL 永远来自验证过的 GitHub 响应。
- 不默认扫描用户所有 repository，也不自动全文上传私有仓库代码给 LLM。
- 选定仓库可以设角色权重：核心项目/普通项目/暂缓项目。活跃度不等于优先级。
- 从 API 读取到任何未受信任文本只当数据处理，防止提示注入。
- 断联时保留上次可信摘要与 lastSyncAt，绝不生成伪“已同步”。

参考：https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens

## 7. AI Provider 与网络
- `PlanningModelProvider` 协议，支持可配置的兼容提供方和模型；默认无云端 AI 也可运行规则引擎。
- 只通过 HTTPS 传输必要的最小上下文；API Key 不出现在 URL、日志、异常界面中。
- JSON Schema、超时、取消、重试上限、错误类别和调用预算明确。
- 不应自行假设“ChatGPT 订阅”自动附带 API 用量；用户必须单独配置可用模型服务。

## 8. 调度与系统事件
- 当日首次启动、登录启动、日期变更、休眠唤醒、时区变更、用户手动刷新触发检查。
- 定时器只能保证运行中的近似刷新，Mac 关机不保证任务按时执行；唤醒后补偿刷新。
- 每日计划主生成与来源增量更新分离，避免频繁重新排序。
- 使用本地数据库记录 refresh attempt、lastSuccess、source health，避免重复触发。
- 同步是 async 可取消任务，不得阻塞菜单栏 UI 主线程。
- 登录启动使用 macOS 支持的系统机制（例如 SMAppService），需提供一键启停和相应授权说明。

## 9. 工程要求
- 严格 Swift concurrency，避免后台任务竞态与 MainActor 更新越界。
- SwiftData 模型明确迁移版本和恢复流程。
- 仓库没有凭证、真实私人日历、用户隐私数据、token fixture。
- HTTP/日历/LLM 均有 mock provider，可离线跑单元及集成测试。
- 错误分类：permissionDenied / invalidCredentials / rateLimited / offline / timeout / invalidSchema / persistenceFailure。
- 使用工具记录任务候选数量、耗时与失败码即可，默认不开启远程 telemetry。
- 签名、公证、更新机制放在打包发布阶段评估，不作为 MVP 核心功能先行实现。

## 10. 技术预研 Checklist
1. 在目标 Mac 上运行 MenuBarExtra window style，验证菜单栏展示及关闭行为。
2. 验证隐藏 Dock 图标同时正常打开 Settings、系统权限弹窗和原生 Context Menu。
3. 验证 EventKit macOS 14+ 权限流程/重启授权状态。
4. 验证 GitHub API 限额/分页/选定仓库的 read-only 权限。
5. 验证 SwiftData schema migration、并发合并及崩溃重启一致性。
6. 验证全局快捷键在 Spotlight/输入法或现有快捷键冲突时的降级方式。
