<div align="center">

<img src="assets/app_icon.png" alt="VOID" width="112" />

# VOID

**强大、开源的跨平台 AI 助手与 LLM 客户端，覆盖手机与桌面。**

一个应用接入所有主流模型，赋予 AI 执行任务的工作区，数据始终留在自己的设备上。

<p>
  <a href="https://github.com/Keshav974-afk/VOID/releases/latest"><img src="https://img.shields.io/github/v/release/Keshav974-afk/VOID?style=flat-square&amp;label=release" alt="Latest release" /></a>
  <a href="https://github.com/Keshav974-afk/VOID/releases"><img src="https://img.shields.io/github/downloads/Keshav974-afk/VOID/total?style=flat-square" alt="Downloads" /></a>
  <a href="https://github.com/Keshav974-afk/VOID/stargazers"><img src="https://img.shields.io/github/stars/Keshav974-afk/VOID?style=flat-square" alt="Stars" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Keshav974-afk/VOID?style=flat-square" alt="License" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&amp;logo=flutter&amp;logoColor=white" alt="Built with Flutter" /></a>
</p>

[Releases](https://github.com/Keshav974-afk/VOID/releases) · [下载](#-下载) · [功能特性](#-功能特性) · [反馈问题](https://github.com/Keshav974-afk/VOID/issues)

[English](README.md) · **简体中文**

</div>

## 💡 简介

**VOID** 是基于 Flutter 构建的隐私优先跨平台 AI 客户端，支持 Android、Windows、macOS、Linux 与 iOS。你可以填入自己的 API Key，或直接连接已支持的服务，在同一款简洁的应用中畅享 OpenAI、Gemini、Claude、DeepSeek、OpenRouter 及任何 OpenAI 兼容模型。

VOID 远不仅是聊天工具：
- **工作区与代码执行**：模型可以读写文件、查看代码 Diff，并在本地工作区、桌面原生 Shell 或移动端隔离的 Linux 沙盒中执行终端命令。
- **内置预览与渲染**：支持带有本地回环服务器的 HTML/JS 网页预览、PDF 查看器、支持扩展与 DevTools 的内置 Chromium 浏览器引擎、多媒体展示与代码高亮。
- **Model Context Protocol (MCP)**：原生接入 MCP 服务器（stdio、SSE、Streamable HTTP），使模型能够与各种外部工具、本地数据库和 API 联动。
- **隐私至上**：会话记录、密钥设置与工作区文件全部保存在本地，支持通过 WebDAV 或 S3 兼容对象存储加密备份。

---

## 📸 应用截图

<p align="center">
  <img src="docx/screenshot_1.png" alt="Chat with Markdown, tables and math" width="200" />
  <img src="docx/screenshot_2.png" alt="Agent working in a workspace" width="200" />
  <img src="docx/screenshot_3.png" alt="Terminal in the Linux sandbox" width="200" />
  <img src="docx/screenshot_4.png" alt="Web search with citations" width="200" />
</p>

---

## 🚀 下载

预编译安装包可在 [GitHub Releases](https://github.com/Keshav974-afk/VOID/releases) 获取：

| 平台 | 格式 | 架构 / 安装包 | 最低要求 |
| --- | --- | --- | --- |
| **Windows** | 安装程序 (`.exe`) & 便携包 (`.zip`) | x86_64 (`VOID.exe`) | Windows 10 或 11 |
| **Android** | 安装包 (`.apk`) | `arm64-v8a`, `armeabi-v7a`, `x86_64` | Android 7.0+ |
| **macOS** | DMG 镜像 / App Bundle | Universal (Apple Silicon & Intel) | macOS 12.0+ |
| **Linux** | AppImage, DEB, tar.gz | x86_64 | 主流桌面发行版 |
| **iOS / iPadOS** | IPA / Xcode 源码构建 | 64-bit ARM | iOS 15.0+ |

---

## 🧭 快速开始

1. **配置模型服务商**：前往 **设置 → 服务商**，输入 OpenAI、Gemini、Claude、DeepSeek、OpenRouter、SiliconFlow、Grok 等服务商的 API Key，或添加自定义端点。
2. **开始对话**：在底部输入栏直接切换模型、调节思考深度（Reasoning Level）、启用联网搜索或挂载设备工具。
3. **绑定工作区**：在 **设置 → 工作区与环境** 中创建或关联目录，为对话绑定后即可让 AI 编写代码、编辑文件与运行命令。

---

## ✨ 功能特性

### 🧠 模型与服务商
- **原生协议流式接入**：深度支持 OpenAI Chat Completions、Responses API、Google Gemini、Vertex AI、Anthropic Claude 及标准兼容接口。
- **开箱即用预设**：内置 OpenAI、Gemini、Claude、DeepSeek、OpenRouter、SiliconFlow、通义千问 (Qwen)、智谱 AI、xAI (Grok)、字节豆包以及本地 Ollama / LM Studio。
- **思考力度调节**：支持关闭、Low、Medium、High、Max 思考级别与自定义 Token 预算。
- **多 Key 轮换与负载均衡**：支持轮询、优先级、最少使用与故障自动重试。

### 🤖 智能体与工作区
- **全套工作区工具**：内置 `shell`、`read_file`、`view_image`、`write_file`、`edit_file`、`list_dir`、`glob` 和 `grep`。
- **实时 Diff 与终端流**：清晰的语法高亮与行级 Diff，敏感指令与文件修改前支持交互式权限确认。
- **双端执行架构**：桌面端原生 Shell 运行；移动端采用隔离的 PRoot (Android) 与 iSH (iOS) 沙盒。
- **本地 HTML 游戏与网页实时预览**：通过内置安全本地服务器加载 HTML5/Canvas/JS 应用。
- **内置浏览器与 DevTools**：提供独立 Chromium 浏览器引擎，支持无痕模式、扩展及控制台调试。

### 🔒 隐私与本地存储
- **纯本地数据库**：基于 Drift / SQLite，会话与私密数据不经过任何第三方服务器。
- **云端同步与备份**：支持 WebDAV 与 S3 兼容存储的一键加密同步与导入导出。

---

## 🔧 从源码构建

```bash
# 克隆仓库
git clone https://github.com/Keshav974-afk/VOID.git
cd VOID

# 安装 Flutter 依赖
flutter pub get

# 运行应用
flutter run
```

---

## 📄 开源许可

VOID 采用 [GNU Affero General Public License v3.0](LICENSE) 开源协议。
