# bartrans

按 `menubar-translator-prd.md` 实现的菜单栏翻译工具，纯 Swift + SwiftUI/AppKit，无第三方依赖。

## 构建 & 运行

```bash
./build_app.sh
open .build/release/bartrans.app
```

首次启动只会出现在菜单栏（无 Dock 图标），点击图标弹出翻译面板。

也可以用 `swift run` 直接跑调试版本（不经过 app 打包，Keychain/沙盒行为等同）。

## 功能一览

- 菜单栏图标点击弹出翻译面板；点击"历史"在同一面板内翻转（flip）到历史记录，而不是叠加新窗口
- 输入自动识别中/英文并决定翻译方向，也可手动切换强制方向
- 引擎可选「系统离线」（`Translation` 框架）或「LLM」
- LLM 支持 **Anthropic** 或任意 **OpenAI 兼容** 接口（OpenAI 官方 / Azure OpenAI / DeepSeek / Ollama、LM Studio 本地代理等），Base URL、模型名、API Key 均可在设置里配置，Key 存 Keychain
- 品牌图形（菜单栏图标 + 面板 Logo）用 SwiftUI 矢量图形实时绘制，无外部美术资源（`Views/BarTransLogo.swift`）

## 与 PRD 的已知差异

- **最低系统版本**：PRD 写的是 macOS 13，但 `Translation` 框架（系统离线翻译）实际要求 **macOS 15+**，`SMAppService` 才是 13+。已按 15+ 实现，`Info.plist` 的 `LSMinimumSystemVersion` 设为 15.0；低于该版本时系统引擎会给出友好错误提示而不是崩溃。
- **系统翻译调用方式**：`Translation` 框架的编程式 API 必须挂在存活的 SwiftUI 视图上（`.translationTask`），因此用了一个不可见的桥接 view（`SystemTranslationBridgeView`）把它包装成协议里要求的普通 async 函数，对 `TranslationEngine` 协议的调用方是透明的。
- **回车 vs Shift+回车**：SwiftUI 原生 `TextEditor` 无法区分这两种按键，实现里用了一个包装 `NSTextView` 的 `SubmitTextView` 来做（`Views/SubmitTextView.swift`）。
- **LLM provider**：PRD 原本只要求 Anthropic，现已扩展为可插拔的 Anthropic / OpenAI 兼容双 provider（`Engines/LLMEngine.swift`）。

## 待验证（需要真实 GUI 环境）

- 点击菜单栏图标 → 弹出面板 → 剪贴板自动填充 → 翻译 → 复制，完整走一遍
- 历史记录的翻转动画、返回后状态是否正确保留
- 系统离线引擎需要在「系统设置 → 翻译」里下载中英语言包后才能工作
- LLM 引擎分别测试 Anthropic 和 OpenAI 兼容两种 provider
- 登录启动开关（`SMAppService`）需要实际登出登入或重启验证
