# 🐾 CodePet

[![build](https://github.com/JellyTony/codepet/actions/workflows/ci.yml/badge.svg)](https://github.com/JellyTony/codepet/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platform: macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](https://www.apple.com/macos/)

为 **Claude Code** 打造的原生 macOS 桌面宠物 —— 一只小动物住在屏幕角落,实时反映你的 AI 智能体在干什么。灵感来自 [Codex pets](https://developers.openai.com/codex/app/settings),并且 **多会话感知**。

> [English README](README.md)

---

## 它能做什么

CodePet 浮在所有桌面(Space)之上、始终置顶、停在你选的角落。它把 Claude Code 的实时状态映射成一只会动的小宠物 + 一行进度提示:

| 状态 | 宠物表现 | 触发事件 |
|------|---------|---------|
| **工作中** | 走动、挥手、跳跃,齿轮转动 | `UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`SubagentStop` |
| **需要你** | 停下张望、抖动,冒出 `?` 气泡 | `Notification` |
| **待审查** | 坐下微笑、捧着代码包、冒星星 | `Stop` |
| **出错了** | 颤抖、皱眉、冒汗、`!` 气泡 | 工具报错 / 错误通知 |
| **空闲** | 呼吸、眨眼、飘 `z z z`、挥手打招呼 | `SessionStart` |

### 多会话任务卡片
在五个终端里同时跑 Claude Code 也不会乱:CodePet **独立跟踪每个会话**,在宠物上方叠成一摞白色任务卡片:

- **状态灯**:工作中转圈、需要你时琥珀色脉冲、待审查打勾、失败红色三角。
- **真实任务标题**(你最近发的那条消息)、**项目名**(自动取 git 仓库根目录名)、**实时进度**(当前正在执行的动作,如 `编辑: SessionsPanel.swift`、`运行: bash build.sh`),以及 `42 操作 · 3分钟` 指标。
- **角落宠物显示聚合状态** —— 哪个会话最需要你就显示哪个;菜单栏 🐾 徽标显示有几个会话在等你。
- 文案支持 **简体/繁体中文、日语、English**,切换语言即时生效。

### 卡片快捷回复
把鼠标移到卡片上(或会话在"需要你"状态时),底部出现「回复…」输入框 —— 打字回车,消息直接送进那个会话的终端,**无需切换窗口**。

### Petdex 宠物图库
菜单内一键安装 [petdex.crafter.run](https://petdex.crafter.run) 上的动画宠物,无需终端、无需配置。

---

## 安装

### 方式一:下载安装(推荐,无需编译)

1. 到 [**Releases**](https://github.com/JellyTony/codepet/releases/latest) 下载 `CodePet-macos.zip` 并解压。
2. 双击 **「Install CodePet.command」**。
   - 若 macOS 拦截:**右键点它 → 打开 → 打开**。
3. 它会把 CodePet 装到 `/Applications`、清除下载隔离、接好 Claude Code 的 hooks、安装技能并启动。菜单栏出现 🐾 即可。

**要求**:macOS 13+,以及 [Node.js](https://nodejs.org)(hooks 需要)。本应用开源且为 ad-hoc 签名(未做公证),所以安装脚本会替你清除 Gatekeeper 隔离。

### 方式二:从源码构建

```bash
git clone https://github.com/JellyTony/codepet.git
cd codepet
bash install.sh
```

`install.sh` 会编译 `CodePet.app`、把 hooks 幂等地写进 `~/.claude/settings.json`、安装 `/codepet-hatch` 与 `/codepet-petdex` 技能并启动。需要 Xcode 命令行工具(`xcode-select --install`)。

---

## 使用

- **点击宠物**:展开/收起任务卡片;**拖动宠物**:换位置;**拖右下角 ⤢**:缩放。
- **点击卡片**:把该会话的终端切到前台(自动识别 iTerm2 / Terminal / VS Code / Warp / Ghostty…);**右键卡片**:在访达中显示、复制会话 ID、查看最近工具。
- **卡片快捷回复**:悬停卡片 → 在「回复…」里打字回车 → 直接发进该会话终端。*(首次会弹出 macOS「自动化」授权,点允许即可。)*
- **从 Petdex 安装宠物**:菜单栏 **🐾 → Pet → 从 Petdex 安装** → 选一只(或「输入名称安装…」装任意一只)。
- **菜单栏 🐾**:显示会话、切换宠物形象、选择角落、切换**语言**、预览状态。徽标显示有几个会话需要你。
- **孵化自定义宠物**:`node tools/hatch.js "Pixel" --form cat --color "#A385EB"`,或直接让 Claude 执行 **`/codepet-hatch`**。

### 关于权限
- 「点击卡片切终端」和「卡片快捷回复」通过 AppleScript 控制终端,需要 **系统设置 → 隐私与安全性 → 自动化** 里允许 CodePet。首次使用会自动弹窗。
- hooks 通过本机回环 HTTP(`127.0.0.1`)与 App 通信,不对外开放,并由共享令牌保护。

---

## 卸载

- 下载版:双击 **「Uninstall CodePet.command」**。
- 源码版:`bash uninstall.sh`。

两者都会移除 hooks 和技能并停止 App,**保留**你已安装的宠物(`~/.codepet`、`~/.petdex`)。

---

## 工作原理(简述)

CodePet 通过 Claude Code 的 **hooks** 感知状态:高频事件(每次工具调用)直接 POST 到 App 在 `127.0.0.1` 上跑的回环 HTTP 服务器(无需每次起 node 进程);`SessionStart` 用一个命令钩子捕获终端身份,以便"点卡片切终端 / 快捷回复"能定位到正确的终端。整个 App 由单条 `swiftc` 编译(AppKit + SwiftUI/Canvas),**无任何第三方依赖**。

更多架构与贡献说明见 [English README](README.md) 和 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE) © 2026 JellyTony。CodePet 为独立项目,与 Anthropic、OpenAI 无关。
