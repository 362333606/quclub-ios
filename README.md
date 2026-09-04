# 球域AI iOS 壳工程

WKWebView 单页壳，承载 https://qyai001.cn。bundleId `cn.qyai001.qiuyu`，Team `KD737T5M5W`。

## 结构
- `project.yml` — xcodegen 工程定义（CI 里生成 .xcodeproj，本地无 Mac 不需要）
- `QiuYuAI/` — 源码：AppDelegate / SceneDelegate / ViewController(WKWebView) / Info.plist / entitlements / Assets
- `ExportOptions.plist` — app-store-connect 导出配置
- `.github/workflows/build-ios.yml` — macOS runner 打包 + 上传 TestFlight

## 壳能力
- 登录态/缓存持久化（WKWebsiteDataStore default）
- 支付收银台 H5（拉卡拉/汇付）壳内完成
- 微信/支付宝 scheme 拉起 App，失败留原地
- 断网/加载失败遮罩 + 重试，顶部进度条，边缘右滑返回

## GitHub 仓库 Secrets（6 个）

| Secret | 内容 | 来源 |
|---|---|---|
| `APPLE_P12_BASE64` | apple_distribution.p12 的 base64 | `base64 -w0 证书/apple_distribution.p12` |
| `APPSTORE_PROFILE_BASE64` | App Store profile 的 base64 | 建 profile 后导出 |
| `ASC_API_KEY_P8` | AuthKey_api.p8 文件**原文**（非base64） | 证书/AuthKey_api.p8 |
| `ASC_KEY_ID` | `8889JD3CN2` | — |
| `ASC_ISSUER_ID` | `80b9a5de-f65f-47c1-804d-9e83856f5190` | — |

## 触发打包
Actions 页手动 Run workflow（或推 `v*` tag）。约 15 分钟出包：
1. TestFlight 自动收到新 build（内部测试免审）
2. Artifacts 里同时留了 ipa 备份（可取回走超级签）

## Profile 名约定
`QiuYu AppStore 20260903`（project.yml / ExportOptions.plist / workflow 三处引用需一致）

## 合规红线（提审前）
App 内禁词：命中率/盈利/下注/投注/赔率/带单/稳赚/内幕。截图必须先过瑞奇合规审查。
