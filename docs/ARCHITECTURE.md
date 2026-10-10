# Fidget 架构设计

Fidget 是 [automatic-mouse-mover](https://github.com/prashantgupta24/automatic-mouse-mover)（Go + robotgo + systray）的精神续作：
目标相同——**用户离开时轻微移动鼠标，让 Mac 保持唤醒、让 Slack/Teams 之类的状态保持“在线”**——但完全重写为仅面向 Apple Silicon 的原生 Swift 应用。

## 1. 目标与约束

| 项目 | 决定 | 原因 |
| --- | --- | --- |
| 平台 | macOS 11 Big Sur+，仅 arm64 | 覆盖 Apple Silicon 能运行的所有系统（M1 首发即为 macOS 11）。只用 macOS 11 就有的 API，更新的 API 必须 `#available` 守卫并有退路；所有系统走同一条界面代码路径，见 §9 |
| 语言/工具链 | Swift 6（语言模式 6，完整并发检查）、SwiftPM | 编译期数据竞争检查；SwiftPM 是代码与测试的唯一真源，不依赖 .xcodeproj |
| 界面 | SwiftUI 视图 + AppKit 生命周期（`NSStatusItem` / `NSPopover` / `NSWindow`） | 菜单栏应用对弹出面板、右键菜单、窗口的控制要求高，`MenuBarExtra` 的限制太多 |
| 依赖 | 零第三方依赖 | 系统框架足够；省掉供应链与签名/公证的麻烦 |
| 分发 | Developer ID 签名 + 公证（非 App Store） | 投递合成鼠标事件需要辅助功能权限，沙盒应用拿不到，App Store 版只能降级（见 §8） |

## 2. 分层

```
┌────────────────────────────────────────────────────────────┐
│ Fidget (executable)   main.swift → FidgetAppEntry.run()     │
├────────────────────────────────────────────────────────────┤
│ FidgetApp (library)   AppDelegate · EngineDriver · AppModel │
│                       StatusItemController · SwiftUI 视图     │
│                       L10n · 资源(.lproj)                     │
├────────────────────────────────────────────────────────────┤
│ FidgetSystem (library)  macOS 适配器：CGEvent 指针 · 空闲时间   │
│                         IOKit 电源断言/电源来源/断言探测         │
│                         锁屏监听 · 权限 · 登录项 · Carbon 快捷键  │
│                         JSON 持久化 · 日志                      │
├────────────────────────────────────────────────────────────┤
│ FidgetCore (library)   纯 Swift，无 AppKit：                   │
│                        Settings · Engine(状态机) · 轨迹生成     │
│                        计划表 · 规则 · 统计 · 快捷键模型 · 协议   │
└────────────────────────────────────────────────────────────┘
```

依赖方向严格自上而下。`FidgetCore` 只依赖 Foundation/CoreGraphics 类型，因而可以在没有 GUI 的环境里完整单测。
`FidgetApp` 做成库而不是直接放在可执行目标里，是为了让 `AppModel`、`EngineDriver`、`StatusPresentation` 也能被 `swift test` 覆盖（测试用 `@testable import`）。它对外只公开 `FidgetAppEntry.run()`。

### 2.1 FidgetCore

| 文件 | 职责 |
| --- | --- |
| `Settings/*` | 设置模型。每个结构体都手写 `init(from:)`，用 `lenient` 解码：键缺失或类型错误时回退默认值，旧配置永远能被读出。`validated()` 把数值收敛到 `SettingsLimits` 范围 |
| `Engine/Engine.swift` | 状态机（值类型）。`tick(EngineInput) -> EngineOutput`，纯函数风格：副作用以 `EngineEffect` 枚举返回，应持有的电源断言作为声明式输出。所有移动（自动移动与“立即移动”请求）都由它发出，合成事件窗口与连续失败计数也只在这里维护 |
| `Engine/EngineTypes.swift` | `EngineInput` / `EnvironmentSnapshot` / `EngineStatus` / `PauseReason` / `EngineEffect` / `EngineWarning` |
| `Movement/MovementPathGenerator.swift` | 五种轨迹（轻推、圆、方、8 字、随机游走）的生成；弧长均匀重采样 + smoothstep 缓动；屏幕边缘/角落安全处理 |
| `Movement/PointerMover.swift` | 按轨迹驱动 `PointerControlling`，睡眠与时钟可注入；读回位置以校验“指针真的动了” |
| `Schedule/Schedule.swift` | 星期 + 时间窗口，支持跨午夜，`nextActiveDate` 用于“何时恢复”的提示 |
| `Rules/RuleSettings.swift` | 锁屏/电池/媒体/应用规则与匹配逻辑 |
| `Services/Services.swift` | 系统能力的协议：空闲时间、电源断言（幂等的 `apply`）、环境快照、权限、通用的 `ValueStore<Value>` 存储 |
| 其余 | 统计（按自然日滚动）、暂停预设、快捷键模型与键码表、倒计时格式化、`fidget://` URL 命令解析 |

### 2.2 FidgetSystem

每个文件对应一类系统 API，全部实现核心层协议：

- `CGIdleTimeProvider`：`CGEventSource.secondsSinceLastEventType(.combinedSessionState, kCGAnyInputEventType)`。
- `CGPointerController`：`CGEvent(mouseEventSource:mouseType:.mouseMoved …).post(tap: .cghidEventTap)`。投递到 HID 层的事件会真正移动光标并重置系统闲置计时（本机实测：CG 与 IOKit 两个计时都归零），这正是让聊天软件认为“用户在操作”的关键。
- `IOPowerAssertionController`：`PreventUserIdleDisplaySleep` / `PreventUserIdleSystemSleep` 断言；`apply` 幂等，只在真实变化时创建/释放并记日志。
- `PowerSourceProbe` / `DisplaySleepAssertionProbe`：电池供电判断；枚举其它进程的显示器断言（视频播放、演示、通话都会持有）。`SystemEnvironmentProvider` 把持有者名单直接放进 `EnvironmentSnapshot`，规则与诊断共用这一份数据。
- `ScreenStateMonitor`：`com.apple.screenIsLocked/Unlocked`、屏保启停、会话切换、睡眠/唤醒；初始值用 `CGSessionCopyCurrentDictionary` 查询。
- `AccessibilityPermission`：`AXIsProcessTrusted` / `AXIsProcessTrustedWithOptions` / 深链到系统设置；`resetPermission` 用 `tccutil reset Accessibility <bundle id>` 删掉自己的授权记录再重新申请——系统按授权时那个版本的签名认人，记录来自签名不同的旧版本（例如本地 ad-hoc 构建）时，开关看似打开，系统却不认。
- `LoginItemManager`：macOS 13+ 用 `SMAppService.mainApp`（需要时引导到系统设置批准）；macOS 11–12 写入用户级 LaunchAgent（登录时 `open -b <bundle id>`，不依赖安装路径），升级到 13+ 后启动时自动迁移到 SMAppService；非 .app 运行时安全降级。
- `HotKeyCenter`：Carbon `RegisterEventHotKey`，不需要任何权限。
- `JSONFileStore<Value>`：实现 `ValueStore`，原子写入；文件缺失或损坏（备份为 `*.corrupt-<时间戳>.json`）时回退默认值；读写都经过可选的 `normalize`（设置用它做范围校验）。`.settings()` / `.statistics()` 两个工厂给出各自的文件与默认值，导入导出也复用它的 `encode` / `decode`。`FIDGET_CONFIG_DIR` 环境变量可重定向目录（测试与脚本用）。
- `Log`：`os.Logger` + 可选文件日志（句柄常开，1 MB 轮转）。

### 2.3 FidgetApp

- `AppDelegate`：组合根与控制中枢。装配 `AppServices.live()`，加载设置/统计，创建 `EngineDriver` 与 `StatusItemController`，处理 `fidget://` URL，实现 `AppActions` 协议供视图调用。所有设置修改都经过 `AppModel.settings` 的 `didSet` 进入 `settingsDidChange`，在这一处统一处理副作用：去抖保存、请求引擎重算、快捷键重注册、日志开关、语言切换。
- `AppModel`（`@MainActor ObservableObject`）：界面唯一数据源：设置、警告、手动暂停、权限、登录项状态。每个 tick 都可能变化的运行数据（状态、统计、诊断）单独放在 `model.live`（`LiveState`）发布——`ObservableObject` 任一属性变化都会让全部订阅者重算，拆开后设置界面只在设置变化时重算，只有显示运行数据的视图（面板、诊断行）每秒刷新。
- `EngineDriver`：1 Hz `Timer`（`.common` 模式，菜单打开时也能触发）。每个 tick 采集输入 → `engine.tick` → 执行副作用（异步移动、清除暂停）并应用电源断言 → 更新模型与统计。设置变更通过 `setNeedsTick()` 合并成下一轮 run loop 的一次重算。写入模型时只在值变化时赋值，状态不变的 tick 不会让界面重绘。
- `StatusItemController`：`NSStatusItem` 左键弹出 `NSPopover`（`NSHostingController`；显示前按内容的理想尺寸设定大小，之后由宿主视图的尺寸约束带动面板伸缩。不要把 SwiftUI 里测得的尺寸写回 `contentSize`：macOS 27 上首次测得 0，面板会先按 0 高度定位再向上撑开，伸出屏幕顶端，1.1.0 即如此），右键临时挂上 `NSMenu`。图标、倒计时与提示文字订阅模型与运行数据的 `objectWillChange`，合并到下一轮 run loop 重绘，没有任何地方需要手动刷新。
- `HostedWindowController`：承载设置/引导/关于三个 SwiftUI 窗口。这三个窗口用 `.immersive` 外观：内容延伸到透明标题栏下方、不显示标题文字。浅色还是深色取决于应用外观：`AppDelegate` 按设置里的“外观”设置 `NSApp.appearance`（跟随系统时为 nil），窗口、弹出面板与菜单随之切换。窗口关闭时释放 SwiftUI 内容（隐藏的视图否则仍会随模型每秒重算、动画仍在绘制），再次打开时重建；窗口标题由调用方提供，切换语言时自动更新（`navigationTitle` 桥接到窗口标题要 macOS 13 才有）。弹出面板同理：内容在显示时创建、关闭时释放。
- 本地化 `L`：当前语言包与区域设置放在加锁的全局状态里。切换语言时 `LanguageState` 发布变化：窗口与弹出面板的根视图（`LocalizedRoot`）以语言为标识整体重建，所有经 `L.t` 取文案的视图——包括 AppKit 包装的控件——都换成新语言；日期、时长、星期名称等格式化也跟随界面语言而不是系统语言。
- `ScreenshotRenderer`（仅调试构建）：`Fidget --render-screenshots <目录>` 用固定示例数据在进程内渲染各个界面，生成 README 截图。`--appearance light|dark` 指定外观，`make screenshots` 每种界面语言、每种外观各渲染一套（`docs/images/<语言>/<外观>/`），英文 README 用英文截图，中文 README 用中文截图。窗口的渐变存成 PNG 每张两三 MB，所以存为 JPEG；弹出面板仍是 PNG。
- 视图：`PopoverView`、`SettingsView`（侧边栏延伸到透明标题栏下 + 六个分区页；分区页停在标题栏下沿，标题栏那一条只有背景，按住即可拖动窗口）、`OnboardingView`、`AboutView`。
  - 弹出面板的组件在 `Components.swift`，只用系统语义色。
  - 设置、引导与关于窗口用另一套视觉语言（参考 CleanMyMac，`Aurora.swift`）：接近中性的底色加淡淡的主题色光晕，每个设置分区有自己的主题色（`Theme`，经环境值 `\.theme` 传给控件），侧边栏图标、页头、窗口光晕和页面里的控件都用它，切换分区时光晕交叉淡入；半透明“玻璃”卡片；自绘的开关 `GlowSwitch`、滑杆 `GlowSlider`、分段选择 `PillPicker`、胶囊按钮 `GlassButtonStyle`（页面里的普通按钮默认用它）与下拉菜单 `GlassMenu`。这些控件都带无障碍标签、数值和调整动作。颜色都有浅色、深色两个取值（`Color.dynamic(light:dark:)`，底层是带外观回调的 `NSColor`），绘制时按视图所在的外观选用，视图里不判断外观；只有窗口光晕在两种外观下取主题的不同端，读 `colorScheme`。
  - 设置页的布局组件在 `SettingsComponents.swift`：页面 `SettingsPage`（页头 + 分组，可滚动，顶部渐隐）、分组 `SettingsGroup` / 行 `SettingsRow`（替代 macOS 13 才有的 grouped `Form`；控件按理想宽度排好，窗口窄时让标题换行）、对数时长滑杆、星期选择、轨迹选择卡片与轨迹预览（`Path` + 帧时钟，替代 macOS 12 的 `Canvas` / `TimelineView`）、时刻输入（无边框的 `NSDatePicker`）、统计卡片与功能卡片。快捷键录制是 `NSViewRepresentable`。
- `Symbols`：SF Symbols 名称的唯一出口。少数比 macOS 11 新的符号登记了替代品，在旧系统上自动换掉；设置界面只列出当前系统能显示的菜单栏图标样式。

## 3. 核心难点：区分真实输入与自己的合成事件

系统闲置计时对“谁产生了事件”一无所知：Fidget 自己投递的鼠标移动同样会把闲置时间归零。如果简单地用系统闲置时间判断，第一次移动之后引擎会以为用户回来了。

解决方案（`Engine.updateRealInput`）：

1. 每个 tick 计算 `observedLastInput = now - systemIdle`。
2. 引擎记录每次移动的时间窗口 `[syntheticWindowStart, syntheticWindowEnd]`（进行中时 end = now），两侧加 0.75 s 容差。
3. 若 `observedLastInput` 落在窗口内 → 这是自己的事件，`lastRealInputAt` 不变；否则 → 用户真的动了，更新 `lastRealInputAt`。
4. `realIdle = now - lastRealInputAt` 才是状态机使用的闲置时间。

代价是用户恰好在 Fidget 移动的那 0.3 s 内碰鼠标会被漏掉一次，下一次输入立刻纠正，可接受。
“立即移动”通过 `requestJiggle()` 交给引擎，在下一个 tick 和自动移动一样发出，同一套窗口记录自然覆盖它；驱动层在每次移动结束后调用 `noteJiggleFinished(at:pointerMoved:)` 关闭窗口并回报结果。

## 4. 状态机

```
                 isEnabled = false
   ┌──────────────────────────────────────────────┐
   │                                              ▼
   │   权限缺失            规则/手动暂停          off
blocked ◄──────── enabled ────────► paused(reason)
                   │  ▲                 │
      realIdle <   │  │ 真实输入         │ 暂停解除
      threshold    ▼  │                 ▼
               watching ──────────► active ──(每 interval)──► performJiggle
                      realIdle ≥ threshold
```

- 进入 `active` 的那一刻立即移动一次，之后每 `jiggleInterval` 一次；移动进行中不叠加。
- 规则优先级：锁屏/屏保/会话切出 > 电池 > 计划表 > 应用列表 > 其它应用阻止显示器休眠。
- 电源断言只在 `watching`/`active` 持有：引擎每个 tick 输出期望状态，驱动层直接 `apply`，由控制器保证幂等。
- 连续两次“指针没动”产生 `pointerDidNotMove` 警告（计数保存在引擎记忆里），界面提示检查权限但不停止尝试。

## 5. 并发模型

- 所有 UI、控制器、驱动与系统适配器都是 `@MainActor`；核心层是 `Sendable` 值类型。
- 移动是异步的（`Task` 继承 MainActor 隔离，`Task.sleep` 做步进），期间 `PointerMover.isMoving` 作为互斥标志进入引擎输入。
- 系统通知回调统一投递到主队列后用 `MainActor.assumeIsolated` 进入隔离域；Carbon 热键回调同理。
- `Log` 用 `Locked`（`NSLock` 包装，替代 macOS 13 才有的 `OSAllocatedUnfairLock`）保护文件 sink，可从任何线程调用。

## 6. 持久化

| 文件 | 位置 | 内容 |
| --- | --- | --- |
| `settings.json` | `~/Library/Application Support/Fidget/` | 全部设置，`schemaVersion` 预留迁移 |
| `statistics.json` | 同上 | 统计，与设置分离，导出设置时不夹带 |
| `fidget.log` | `~/Library/Logs/Fidget/` | 可选文件日志 |

设置保存去抖 400 ms；统计每 60 s 及退出时保存。

## 7. 构建、打包与签名

- `swift build` / `swift test`：日常开发。
- `scripts/build-app.sh`：SwiftPM release 构建 → 组装 `.app`（Info.plist 变量替换、最低系统版本取自二进制、图标、SwiftPM 资源包与 `.lproj` 提升到主包并统一目录名大小写、按需内嵌 Swift 并发运行时、清理 rpath）→ `scripts/sign.sh`（先签内嵌库与资源包再签应用，Hardened Runtime；`CODESIGN_IDENTITY` 未设置时 ad-hoc）。
- `scripts/verify-app.sh`：检查产物的架构、最低系统版本、依赖库能否在最低系统上解析、rpath、签名，并实际启动 5 秒。
- `scripts/notarize.sh` / `scripts/make-dmg.sh`：公证装订与 DMG。
- `project.yml` + XcodeGen：生成 `Fidget.xcodeproj`，应用目标只含入口文件与 asset catalog，代码来自本地包；签名在 `Config/Signing.xcconfig` 配置。
- 图标由 `scripts/make-icon.swift` 用 CoreGraphics 程序化绘制，可重复生成。

细节见 `docs/SIGNING.md`。

## 8. 决策记录

1. **为什么不用 `MenuBarExtra`**：无法可靠地程序化关闭面板、无法区分左右键、`.window` 样式尺寸控制困难。`NSStatusItem + NSPopover` 是成熟做法，SwiftUI 仍负责全部内容。
2. **为什么不用 SwiftUI `Settings` 场景**：需要从 AppDelegate / 热键 / URL 直接打开并定位到某个分区，自管 `NSWindow` 最直接；也避免私有 selector。
3. **为什么用 CGEvent 而不是 `CGWarpMouseCursorPosition`**：warp 不产生 HID 事件，不会重置系统闲置计时，Slack 等仍会判定离开。代价是必须有辅助功能权限，因此引导页与状态机都把权限当一等公民。
4. **为什么不进 App Store**：沙盒内拿不到辅助功能权限。`PointerControlling` 协议为将来的“沙盒降级版”（warp + `IOPMAssertionDeclareUserActivity`）留了替换点，但那只能防休眠，不能保持在线状态。
5. **为什么设置用 JSON 文件而非 UserDefaults**：可读、可导入导出、可备份、可在测试中用临时目录完整验证。
6. **为什么零依赖**：Sparkle 之类的更新框架以后可以加，但首版用“检查更新”跳转 GitHub Releases 足够，避免公证时处理第三方框架签名。
7. **为什么支持到 macOS 11**：Apple Silicon 首发即搭载 macOS 11，要覆盖它能运行的所有系统。代价是放弃 `@Observable`、`NavigationSplitView`、grouped `Form` 等新 API，改用 `ObservableObject` 与自绘的设置布局；换来的是所有系统走同一条代码路径，在新系统上验证过的界面在旧系统上也一样。

## 9. 兼容 macOS 11

| 环节 | 做法 |
| --- | --- |
| 构建 | Xcode 27 最低只能部署到 macOS 12，本地构建会被悄悄抬到 12（Xcode 16 / 26 最低到 10.13）。CI 与发布用 `scripts/select-xcode.sh` 挑选 SDK 声明能部署到 macOS 11 的最新 Xcode，并以 `STRICT_MIN_OS=1` 构建：产物最低版本不是 11.0 就失败 |
| 运行时 | macOS 11 没有 Swift 并发运行时：部署到 11 时二进制经 `@rpath` 引用它，`build-app.sh` 把工具链里的向后部署版本放进 `Contents/Frameworks`；rpath 顺序为 `/usr/lib/swift` 在前，macOS 12+ 仍用系统自带的那份 |
| API 可用性 | 编译器按部署目标检查。本地 Xcode 27 构建会按 12 检查，所以 `scripts/check-min-os.sh`（`make check-min-os`）绕过构建系统，直接用 swiftc 按 macOS 11 对全部模块与测试做类型检查 |
| SF Symbols | 编译器查不出符号在旧系统上是否存在。`SymbolAvailabilityTests` 用系统自带的 SF Symbols 版本表逐个检查源码里的符号：要么 macOS 11 就有，要么在 `Symbols.fallbacks` 登记了替代品并经 `Symbols.name` 使用 |
| 登录启动 | macOS 13+ `SMAppService`；11–12 用户级 LaunchAgent，升级系统后自动迁移 |
| 验证 | `scripts/verify-app.sh` 检查产物并实际启动。macOS 11–13 上的界面无法在 CI 实测，依赖单一代码路径与上述静态检查；macOS 12+ 可在 Apple Silicon 的虚拟机里手动验收 |
