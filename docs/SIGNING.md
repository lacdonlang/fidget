# 签名、公证与分发

Fidget 通过 Developer ID 分发（不走 App Store，原因见架构文档 §8）。

## 1. 准备证书（一次性）

1. 登录 [developer.apple.com](https://developer.apple.com/account/resources/certificates/list)，创建 **Developer ID Application** 证书（需要 Account Holder 身份），或直接在 Xcode → Settings → Accounts → Manage Certificates 里点 “+” → Developer ID Application。
2. 确认钥匙串里能看到：
   ```bash
   security find-identity -v -p codesigning
   # 应出现  "Developer ID Application: 你的名字 (TEAMID)"
   ```
3. 为公证存一份凭据（App 专用密码在 appleid.apple.com 生成）：
   ```bash
   xcrun notarytool store-credentials fidget-notary \
     --apple-id "<Apple ID>" --team-id "<TEAMID>" --password "<App 专用密码>"
   ```

## 2. 命令行发布流程

在仓库根目录建一个不入库的 `.signing.env`，之后所有脚本默认用它签名（环境变量 `CODESIGN_IDENTITY` 仍可临时覆盖）：

```bash
echo 'CODESIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)"' > .signing.env
```

```bash
export CODESIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)"
make app          # swift build -c release → build/Fidget.app（Hardened Runtime + 时间戳签名）
make notarize     # 上传公证并 staple
make dmg          # dist/Fidget-<版本>.dmg（同样签名）
scripts/notarize.sh dist/Fidget-<版本>.dmg   # 可选：DMG 也公证
```

版本号来自 `VERSION` 文件；构建号默认取 git 提交数，可用 `BUILD_NUMBER` 覆盖。

## 3. 在 Xcode 中签名

```bash
make xcodeproj    # 需要 brew install xcodegen
open Fidget.xcodeproj
```

把 `Config/Signing.xcconfig` 改为：

```
DEVELOPMENT_TEAM = <TEAMID>
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = Apple Development
```

之后 Product → Archive → Distribute App → Developer ID → Upload（Xcode 会自动用 Developer ID Application 证书并公证）。
应用目标只包含 `Sources/Fidget/main.swift` 与 asset catalog，其余代码来自本地 Swift Package，编辑任何源码都能即时参与构建。

## 4. 本地开发与 TCC（辅助功能权限）

macOS 用代码签名身份识别应用。**ad-hoc 签名的应用每次重新构建签名都会变，辅助功能授权随之失效**，需要重新勾选。两种办法：

- 开发时也用 `Apple Development` 证书签名：`CODESIGN_IDENTITY="Apple Development: 你的名字 (TEAMID)" make app`，授权在重建后依然有效。
- 或者在 Xcode 中用自动签名运行。

如果授权列表里出现多个 Fidget 或权限“打了勾却不生效”，用下面的命令清理后重新授权：

```bash
tccutil reset Accessibility com.lacdon.fidget
```

同一台机器上存在多份 `Fidget.app`（例如 `build/Fidget.app` 与 Xcode 的 DerivedData）时，`open fidget://…` 可能交给另一份处理。
用 `open -a /绝对路径/Fidget.app "fidget://…"` 指定目标。

## 5. CI

`.github/workflows/ci.yml`：每次 push/PR 构建、测试并产出 ad-hoc 签名的 .app（仅用于验证）。
`.github/workflows/release.yml`：打 `v*` 标签时，如配置了下列 secrets 则签名+公证+DMG 并创建 GitHub Release：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Developer ID Application 证书导出的 .p12，base64 |
| `MACOS_CERTIFICATE_PASSWORD` | .p12 密码 |
| `CODESIGN_IDENTITY` | `Developer ID Application: 名字 (TEAMID)` |
| `NOTARY_APPLE_ID` / `NOTARY_TEAM_ID` / `NOTARY_PASSWORD` | 公证凭据 |

缺少证书时 release 工作流产出临时签名的 DMG 与 zip；缺少公证凭据时跳过公证。.app 与 DMG 都会公证并装订。

## 6. 校验

```bash
codesign -dv --verbose=4 build/Fidget.app          # 查看签名信息
spctl --assess --type execute -vv build/Fidget.app  # Gatekeeper 评估（公证后应为 accepted）
xcrun stapler validate build/Fidget.app
```
