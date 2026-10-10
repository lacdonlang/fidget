# 架构设计

[English](../en/ARCHITECTURE.md) · **简体中文**

Fidget 与 [automatic-mouse-mover](https://github.com/prashantgupta24/automatic-mouse-mover)（Go + robotgo）目标相同：用户离开时轻微移动鼠标，让 Mac 保持唤醒、让聊天软件里的状态保持“在线”。它从零重写为面向 Apple Silicon 的原生 Swift 应用。

## 目标与约束

| 项目 | 决定 | 原因 |
| --- | --- | --- |
| 平台 | macOS 11+，仅 arm64 | 覆盖 Apple Silicon 能运行的所有系统。更新的 API 必须用 `#available` 守卫并有退路；所有系统走同一条界面代码路径 |
| 工具链 | Swift 6 语言模式、SwiftPM | 编译期检查数据竞争；SwiftPM 是代码与测试的唯一真源 |
| 界面 | SwiftUI 视图 + AppKit 生命周期（`NSStatusItem`、`NSPopover`、`NSWindow`） | 菜单栏应用需要精细控制面板、菜单与窗口，`MenuBarExtra` 做不到 |
| 依赖 | 只有 Sparkle | 安全地替换正在运行的应用，自己实现风险太高；其余都用系统框架 |
| 分发 | Developer ID 签名 + 公证 | 无法上架 App Store（见最后一节） |

## 项目结构

```
Package.swift            SwiftPM（代码与测试的唯一真源）
Sources/FidgetCore       纯逻辑：设置、状态机、轨迹、计划表、规则、统计
Sources/FidgetSystem     macOS 适配：CGEvent、IOKit、锁屏、权限、登录项、快捷键、持久化、日志
Sources/FidgetApp        SwiftUI 界面、菜单栏控制器、组合根、在线更新、本地化资源
Sources/Fidget           可执行入口
Tests/                   Swift Testing：核心、系统与应用层测试
Resources/               Info.plist、entitlements、图标与 asset catalog
scripts/                 构建、签名、公证、DMG、更新清单、图标、冒烟测试、截图
project.yml              XcodeGen 配置（生成 Fidget.xcodeproj）
```

## 分层

依赖方向严格自上而下：`Fidget` → `FidgetApp` → `FidgetSystem` → `FidgetCore`。

- **FidgetCore**：纯 Swift，不依赖 AppKit，可以完整单测。包括设置模型（宽松解码，键缺失或类型错误时回退默认值；`validated()` 把数值收敛到合法范围）、状态机 `Engine`、轨迹生成、计划表、规则、统计、快捷键模型、`fidget://` 解析，以及各项系统能力的协议。
- **FidgetSystem**：每类系统 API 一个适配器，都实现核心层的协议：闲置时间与鼠标事件（`CGEvent` 投递到 HID 事件流）、IOKit 电源断言与电源来源、其他应用持有的断言、锁屏与睡眠通知、辅助功能权限（“重置权限”调用 `tccutil reset`）、登录项（macOS 13+ 用 `SMAppService`，11–12 用用户级 LaunchAgent，升级系统后自动迁移）、Carbon 快捷键（无需权限）、原子写入的 JSON 存储与日志。
- **FidgetApp**：做成库，`swift test` 也能覆盖；对外只公开 `FidgetAppEntry.run()`。
  - `AppDelegate` 是组合根。所有设置修改都在一处统一处理：去抖保存、请求引擎重算、重新注册快捷键、切换语言。
  - `AppModel` 是界面唯一的数据源；每秒变化的运行数据单独放在 `model.live`，设置窗口不会随每个 tick 重算。
  - `EngineDriver` 运行 1 Hz 定时器：采集输入 → `engine.tick` → 执行副作用并应用电源断言 → 更新模型与统计。
  - `StatusItemController`：左键弹出面板，右键弹出菜单。面板和窗口在显示时创建 SwiftUI 内容，关闭时释放。
  - `UpdateController` 在发布构建里包装 Sparkle；`FeedSelector` 按界面语言选择更新清单（见下文“在线更新”）。
  - 本地化 `L` 支持运行时切换语言；日期、时长等也按界面语言格式化。
  - 设置、引导与关于窗口共用参考 CleanMyMac 的视觉风格（`Aurora.swift`）：每个分区一种主题色，控件自绘并支持无障碍。每种颜色都有浅色与深色两个取值，“外观”设置决定 `NSApp.appearance`。
  - `ScreenshotRenderer`（仅调试构建）用示例数据在进程内渲染 README 截图。

## 区分真实输入与自己的移动

系统闲置计时不知道事件是谁产生的，Fidget 自己的移动同样会把它归零。`Engine.updateRealInput` 这样处理：

1. 每个 tick 计算 `observedLastInput = now - systemIdle`。
2. 引擎记录每次移动的时间窗口，两侧各留 0.75 秒容差。
3. 落在窗口内的输入是自己的；否则更新 `lastRealInputAt`。
4. 状态机使用 `realIdle = now - lastRealInputAt`。

用户恰好在 0.3 秒的移动过程中碰鼠标，可能会被漏掉一次，下一次输入就会纠正。“立即移动”也交给引擎执行（`requestJiggle()`），同样被时间窗口覆盖。

## 状态机

```
任意状态 ── isEnabled = false ──► off

enabled ── 缺少权限 ──► blocked
   │    ── 规则或手动暂停 ──► paused(reason) ── 暂停结束 ──► watching
   ▼
watching ── realIdle ≥ threshold ──► active ── 每个间隔 ──► 移动
   ▲                                   │
   └───────────────────────────────────┘ 真实输入
```

- 进入 `active` 时立即移动一次，之后每个间隔一次；移动不会叠加。
- 规则优先级：锁屏、屏保或切换用户 > 电池 > 计划表 > 应用 > 其他应用阻止显示器休眠。
- 电源断言只在 `watching` 与 `active` 持有：引擎每个 tick 声明期望状态，由控制器幂等地应用。
- 连续两次指针没动会产生 `pointerDidNotMove` 警告；Fidget 提示用户，但不停止尝试。

## 并发模型

界面、控制器、驱动与系统适配器都是 `@MainActor`；核心层是 `Sendable` 值类型。移动以异步 `Task` 执行。系统通知与 Carbon 快捷键回调投递到主队列，再用 `MainActor.assumeIsolated` 进入隔离域。`Log` 用锁保护文件输出，可以从任何线程调用。

## 持久化

| 文件 | 位置 | 内容 |
| --- | --- | --- |
| `settings.json` | `~/Library/Application Support/Fidget/` | 全部设置；修改后 400 毫秒保存 |
| `statistics.json` | 同上 | 统计，导出设置时不夹带；每 60 秒及退出时保存 |
| `fidget.log` | `~/Library/Logs/Fidget/` | 可选的文件日志，1 MB 轮转 |

文件损坏时备份为 `*.corrupt-<时间戳>.json` 并回退默认值。环境变量 `FIDGET_CONFIG_DIR` 可以重定向目录，供测试与脚本使用。

## 构建与打包

- 日常开发用 `swift build` 与 `swift test`。`make app` 调用 `scripts/build-app.sh` 组装 `.app`（Info.plist、图标、资源；部署到 macOS 11 时内嵌 Swift 并发运行时），再由 `scripts/sign.sh` 签名。
- `scripts/verify-app.sh` 检查架构、最低系统、依赖库能否解析以及签名，并实际启动 5 秒。
- 构建号由版本号推出（1.3.0 → 10300），与 git 历史无关；Sparkle 靠它判断新旧。
- `project.yml` 经 XcodeGen 生成 Xcode 工程，应用目标只含入口文件与 asset catalog。
- 签名、公证与发布见[发布流程](RELEASING.md)。

## 兼容 macOS 11

| 环节 | 做法 |
| --- | --- |
| 工具链 | Xcode 27 最低只能部署到 macOS 12，会悄悄抬高部署目标。CI 用 `scripts/select-xcode.sh` 挑选仍能部署到 11 的最新 Xcode，并以 `STRICT_MIN_OS=1` 构建：产物最低版本不是 11.0 就失败 |
| 运行时 | macOS 11 没有 Swift 并发运行时，`build-app.sh` 内嵌向后部署的版本；macOS 12+ 仍用系统自带的 |
| API 可用性 | `make check-min-os` 绕过构建系统，直接用 `swiftc` 按 macOS 11 对全部模块与测试做类型检查 |
| SF Symbols | `SymbolAvailabilityTests` 检查每个符号在 macOS 11 上都存在，或在 `Symbols` 里登记了替代品 |
| 验证 | 所有系统走同一条代码路径，再加上述检查；macOS 12+ 的界面可以在虚拟机里手动验收 |

## 在线更新

- Sparkle 锁在 2.9.x：2.10 起要求 macOS 12。
- 应用没有沙盒，打包时删掉 Sparkle 的 XPC 服务；框架只保留 arm64，并由内向外签名：Autoupdate、Updater.app、框架，最后是应用。
- Hardened Runtime 只在 Developer ID 签名时开启：ad-hoc 签名下，库校验会拒绝加载 Sparkle，应用一启动就退出。
- 每次发布生成两份只有更新说明不同的清单：`appcast.xml`（英文，取自 `CHANGELOG.md`）与 `appcast.zh-CN.xml`（中文，取自 `CHANGELOG.zh-CN.md`）。`Info.plist` 指向英文清单；界面是中文时（无论来自系统语言，还是“设置 → 通用 → 语言”里的选择），`FeedSelector` 改用中文清单。

## 决策记录

1. **用 `NSStatusItem` + `NSPopover`，不用 `MenuBarExtra`**：能可靠地程序化关闭面板、区分左右键；内容仍全部由 SwiftUI 绘制。
2. **自管 `NSWindow`，不用 SwiftUI 的 `Settings` 场景**：能从快捷键或 URL 直接打开并定位到某个分区，也不需要私有 selector。
3. **用 `CGEvent`，不用 `CGWarpMouseCursorPosition`**：warp 不产生 HID 事件，不会重置闲置计时，聊天软件仍会判定你离开。代价是需要辅助功能权限，因此引导与状态机都把权限当作一等公民。
4. **设置存 JSON 文件，不用 UserDefaults**：可读，便于导入导出与备份，也能在临时目录里完整测试。
5. **用 Sparkle 做在线更新**：替换正在运行的应用、请求授权、App Translocation、失败回滚与重启它都处理了，还会校验 EdDSA 签名与代码签名。
6. **支持到 macOS 11**：Apple Silicon Mac 首发即搭载 macOS 11。代价是不能用 `@Observable`、`NavigationSplitView`、grouped `Form`；换来所有系统运行同一套界面代码。

### 为什么不上 App Store

App Store 要求沙盒，而沙盒应用拿不到辅助功能权限，也就无法投递真实的鼠标事件。沙盒里只能用 `CGWarpMouseCursorPosition` 加电源断言，能防休眠，但聊天软件仍会判定你离开。因此 Fidget 通过 Developer ID 签名与公证分发；`PointerControlling` 协议为将来的沙盒降级版留了替换点。
