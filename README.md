<div align="center">

<img src="assets/app_icon.png" alt="VOID" width="112" />

# VOID

**A powerful, cross-platform AI assistant & LLM client for mobile and desktop.**

Connect to any model, give it a workspace to get real work done, and keep your data strictly on your own device.

<p>
  <a href="https://github.com/Keshav974-afk/VOID/releases/latest"><img src="https://img.shields.io/github/v/release/Keshav974-afk/VOID?style=flat-square&amp;label=release" alt="Latest release" /></a>
  <a href="https://github.com/Keshav974-afk/VOID/releases"><img src="https://img.shields.io/github/downloads/Keshav974-afk/VOID/total?style=flat-square" alt="Downloads" /></a>
  <a href="https://github.com/Keshav974-afk/VOID/stargazers"><img src="https://img.shields.io/github/stars/Keshav974-afk/VOID?style=flat-square" alt="Stars" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Keshav974-afk/VOID?style=flat-square" alt="License" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&amp;logo=flutter&amp;logoColor=white" alt="Built with Flutter" /></a>
</p>

[Releases](https://github.com/Keshav974-afk/VOID/releases) · [Download](#-download) · [Features](#-features) · [Report an Issue](https://github.com/Keshav974-afk/VOID/issues)

**English** · [简体中文](README_ZH_CN.md)

</div>

## 💡 Overview

**VOID** is a privacy-first, cross-platform LLM client built with Flutter for Android, Windows, macOS, Linux, and iOS. Connect your own API keys or supported subscriptions, and switch seamlessly between OpenAI, Gemini, Claude, DeepSeek, OpenRouter, and any OpenAI-compatible service without leaving the app.

VOID goes far beyond standard chat:
- **Workspaces & Code Execution**: Models can read, create, and edit files, inspect diffs, and execute commands in an app-managed local workspace, a native desktop shell, or an isolated Linux sandbox on your phone.
- **In-App Previews & Tools**: Live HTML/JS app preview with built-in loopback server, PDF viewer, interactive web browser with DevTools and incognito mode, image and media gallery, and live file tree navigation.
- **Model Context Protocol (MCP)**: Native support for MCP servers (stdio, SSE, Streamable HTTP) allowing models to interact with custom tools, databases, and APIs.
- **True Privacy**: Conversations, credentials, settings, and workspace files remain completely local on your device with optional encrypted WebDAV and S3 backups.

---

## 📸 Screenshots

<p align="center">
  <img src="docx/screenshot_1.png" alt="Chat with Markdown, tables and math" width="200" />
  <img src="docx/screenshot_2.png" alt="Agent working in a workspace" width="200" />
  <img src="docx/screenshot_3.png" alt="Terminal in the Linux sandbox" width="200" />
  <img src="docx/screenshot_4.png" alt="Web search with citations" width="200" />
</p>

---

## 🚀 Download

Pre-built binaries are available on the [GitHub Releases](https://github.com/Keshav974-afk/VOID/releases) page:

| Platform | Format | Package / Architecture | Requirements |
| --- | --- | --- | --- |
| **Windows** | Setup Installer (`.exe`) & Portable ZIP | x86_64 (`VOID.exe`) | Windows 10 or 11 |
| **Android** | Release APK | `arm64-v8a`, `armeabi-v7a`, `x86_64` | Android 7.0 (API 24)+ |
| **macOS** | DMG / App Bundle | Universal (Apple Silicon & Intel) | macOS 12.0+ |
| **Linux** | AppImage, DEB, tar.gz | x86_64 | Standard desktop Linux |
| **iOS / iPadOS** | Unsigned IPA / Xcode build | 64-bit ARM | iOS 15.0+ |

---

## 🧭 Getting Started

1. **Add a Model Provider**: Open **Settings → Providers**, enter your API key for a preset provider (OpenAI, Gemini, Claude, DeepSeek, OpenRouter, SiliconFlow, Grok, etc.) or add a custom OpenAI-compatible endpoint.
2. **Start a Conversation**: Choose your model from the chatbar. Toggle reasoning strength, online web search, MCP servers, or device tools directly from the input bar.
3. **Bind a Workspace**: Go to **Settings → Workspace & environment** to create a workspace, then attach it to a conversation so the agent can read and edit code, compile projects, and run terminal commands.

---

## ✨ Features

### 🧠 Models & Providers
- **Native Protocol Integration**: Direct streaming with OpenAI Chat Completions & Responses API, Google Gemini & Vertex AI, Anthropic Claude, and OpenAI-compatible gateways.
- **Popular Presets**: Built-in configurations for OpenAI, Gemini, Claude, DeepSeek, OpenRouter, SiliconFlow, Alibaba Cloud (Qwen), Zhipu AI, xAI (Grok), ByteDance, and local Ollama/LM Studio servers.
- **Reasoning Controls**: Fine-grained thinking effort toggle (Off, Low, Medium, High, Max) and custom token budgets.
- **Provider Load Balancing**: Multi-key management with round-robin, priority, least-used, and automatic error failover.
- **Advanced Request Control**: Custom HTTP headers, request body overrides, proxy routing (HTTP, HTTPS, SOCKS5), and Claude prompt caching.

### 🤖 Agent & Workspaces
- **Workspace Toolset**: Agents have native tool access to `shell`, `read_file`, `view_image`, `write_file`, `edit_file`, `list_dir`, `glob`, and `grep`.
- **Live Diff & Stream Output**: Live terminal output streaming, colorized diff views, and granular permission prompts before modifying files or executing shell commands.
- **Desktop & Mobile Execution**: Desktop commands run natively in your shell. Mobile devices run an isolated Linux sandbox environment (PRoot on Android, iSH on iOS).
- **Embedded Web & HTML Preview**: Preview generated HTML/JS games and web applications directly inside VOID via a secure local loopback server (`http://127.0.0.1:<port>`).
- **In-App Browser & DevTools**: Integrated browser engine with DevTools inspection, incognito browsing, and extension support.
- **Model Context Protocol (MCP)**: Run MCP servers via stdio, SSE, or Streamable HTTP with OAuth sign-in and individual tool toggle controls.

### 🧩 Long-Term Memory & Context
- **Autonomous Memory Pipeline**: In the background, VOID extracts, deduplicates, and retains crucial user facts, identity traits, workflows, and instructions.
- **Custom System Instructions & World Books**: Dynamic prompt injection cards and regex-triggered lorebooks for specialized domain tasks.
- **Context Optimization**: Conversation branch management, context summarization, and per-chat system prompt overrides.

### 🔍 Vision, Voice & Search
- **Web Search Integration**: Multi-engine search with Bing, DuckDuckGo, SearXNG, Brave, Tavily, Jina, Exa, Serper, and more with live citation links.
- **Multimodal Capabilities**: Ingest images, PDFs, Word documents, text, and audio. Dedicated visual OCR processing and image generation.
- **Text-to-Speech & Speech Recognition**: System TTS/STT along with OpenAI Realtime, ElevenLabs, Azure, and offline on-device speech models.

### 🎨 Clean & Aesthetic UI
- **Design System**: Minimalist, tactile iOS-inspired design built with custom Flutter components, subtle hairlines, and smooth motion.
- **Custom Themes & Palettes**: Custom theme designer, built-in palettes, pure dark/black OLED mode, and optional Android dynamic colors.
- **Typography & Formatting**: LaTeX math equations (KaTeX), Mermaid diagrams with export, code syntax highlighting, and custom font support.

### 🔒 Privacy & Local Storage
- **On-Device Database**: Drift/SQLite storage keeps your conversations, tokens, and files strictly on your local disk.
- **Backup & Sync**: Export encrypted backups or sync automatically via WebDAV or S3-compatible cloud storage.

---

## 🔧 Building from Source

### Prerequisites
- Flutter 3.44+ (Dart 3.12+)
- Platform toolchain:
  - **Windows**: Visual Studio with "Desktop development with C++" workload
  - **Android**: Android SDK & NDK
  - **macOS / iOS**: Xcode 15+
  - **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`

```bash
# Clone the repository
git clone https://github.com/Keshav974-afk/VOID.git
cd VOID

# Install Flutter dependencies
flutter pub get

# Run on your connected device or desktop
flutter run
```

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

```bash
# Format code
dart format lib test

# Static analysis
dart analyze --fatal-infos lib test

# Run tests
flutter test
```

- Report bugs and submit feature suggestions via [GitHub Issues](https://github.com/Keshav974-afk/VOID/issues).
- Check [AGENTS.md](AGENTS.md) for architectural guidelines and code conventions.

---

## 🙏 Acknowledgements

- Built on the solid foundation and architecture inspired by [Kelivo](https://github.com/Chevey339/kelivo) and [RikkaHub](https://github.com/re-ovo/rikkahub).
- [iSH](https://github.com/ish-app/ish) and [PRoot](https://github.com/termux/proot) for mobile Linux sandbox environments.
- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) for offline speech recognition.

---

## 📄 License

VOID is open-source software licensed under the [GNU Affero General Public License v3.0](LICENSE).
