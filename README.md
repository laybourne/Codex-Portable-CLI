# Codex-Portable-CLI

> **面向 Windows 的便携式 OpenAI Codex CLI 智能代理套件与一键启动运行环境**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%2F%2011%20(x64)-brightgreen.svg)]()
[![OpenAI Codex](https://img.shields.io/badge/OpenAI-Codex%20CLI-orange.svg)](https://github.com/openai/codex)
[![Windows Terminal](https://img.shields.io/badge/Integrated-Windows%20Terminal-blueviolet.svg)](https://github.com/microsoft/terminal)

> [!IMPORTANT]
> 本仓库公开提供代理节点配置，节点可能随时失效。Codex 登录凭据与会话保存在 `Data/`，该目录已被 Git 忽略。请勿把个人私密凭据提交到公开仓库。

---

## 📖 项目全景介绍

### 痛点与背景
OpenAI 推出的 **Codex CLI** 是一款革命性的命令行智能编程助手。然而在受限网络环境下，开发者在 Windows 上使用 Codex 经常面临诸多痛点：
1. **网络连接困难**：直接访问 OpenAI API 受到限制，网络经常出现 `Falling back from WebSockets ... tls handshake eof` 或连接重置。
2. **协议不兼容**：Codex 底层深度依赖 HTTP/HTTPS CONNECT 代理隧道，而许多现代化的高速抗封锁协议（如 Hysteria、Juicity 等）默认仅提供 SOCKS5 端口，需要繁琐的转换。
3. **系统环境污染**：传统配置需在 Windows 全局修改 `HTTP_PROXY` 与系统环境变量，极易与日常其它网络应用冲突。
4. **升级与维护困难**：官方二进制迭代频繁，手动下载、替换、重配路径效率低下。

### 解决方案
**Codex-Portable-CLI** 提供了一套**便携化、十核冗余**的 Windows 解决方案。它将 10 种业界主流的低延迟代理核心、动态 HTTP 桥接调度器、便携版 Windows Terminal 以及官方一键升级机制整合成一个绿色独立的目录体系。开发者可直接尝试公开节点，也可配置自己的代理节点，然后通过启动脚本进入 OpenAI Codex 交互终端。

---

## ✨ 核心技术架构与亮点

```
                      +------------------------------------------+
                      |         启动入口 (.cmd 脚本 / 1~10)       |
                      +------------------------------------------+
                                           |
                    (可选) 倒计时自动触发各核心 IP 更新 (ip_Update)
                                           |
                                           v
                      +------------------------------------------+
                      |       App/codex_proxy.ps1 (核心调度器)    |
                      +------------------------------------------+
                        |  - 端口占用探测与冲突预防
                        |  - 自动启动选定代理核心 (Hidden 模式)
                        |  - (若需要) 启动 sing-box 动态 HTTP 桥接
                        |  - api.openai.com 真实 TLS 握手预检探测
                        |  - 注入便携环境变量: CODEX_HOME / PATH / PROXY
                                           |
                                           v
    +-----------------------------------------------------------------------------+
    |                         运行会话 (Windows Terminal)                          |
    |  +---------------------------+       +-----------------------------------+  |
    |  |  OpenAI Codex CLI 会话     | <===> | 本地代理端口 (127.0.0.1:<Port>)     |  |
    |  +---------------------------+       +-----------------------------------+  |
    |               |                                         |                   |
    |               v                                         v                   |
    |     [本地隔离数据目录 Data/codex]                 [远程 OpenAI 服务器]        |
    |   (auth.json, sessions, history)                                            |
    +-----------------------------------------------------------------------------+
```

### 1. 🌐 十核驱动，多通道冗余保障
内置集成了 10 款主流代理核心，涵盖混合分流、现代 UDP/QUIC 隧道、SOCKS5 流量混淆等多种协议形态。当某一类协议受到 ISP 限制或 QoS 干扰时，可随时无缝切换到备用核心。

### 2. 🌉 自动化动态 HTTP-to-SOCKS 协议桥
针对仅提供 SOCKS5 监听的现代协议（如 Hysteria、Hysteria2、Juicity、Mieru、NaiveProxy、ShadowQUIC），内置调度器会自动在后台拉起轻量级 `sing-box` 作为**无感知 HTTP 代理桥**，在本地动态随机端口上完成转换，完美迎合 Codex 对 HTTP 代理的严格要求。

### 3. 🛡️ 智能预检：OpenAI TLS 真实握手探测
传统代理启动后，常常因为远端节点失效而在 Codex 输入后报 `tls handshake eof` 错误。本项目内置 **`Wait-ProxyTls` 预检机制**：
- 在启动 Codex 前，调度器会主动向 `api.openai.com:443` 发起真实的 HTTP CONNECT 隧道请求与 TLS 握手。
- 握手成功后才拉起 Codex；握手失败则给出明确提示并阻止启动，绝不浪费开发者的排查时间。

### 4. ⚡ 端口冲突主动防御
启动前自动扫描目标端口（如 1080、7890、1081 等）。若发现端口已被系统中其他第三方软件占用，会立即输出占用的程序名称及 PID，防止启动冲突与静默失败。

### 5. 🧳 便携数据隔离
- **环境隔离**：通过定向挂载 `$env:CODEX_HOME = "Data/codex"`，所有用户登录凭据（`auth.json`）、会话上下文、插件和日志均集中存放在 `Data/` 目录中，不修改也不污染用户系统的 `%USERPROFILE%`。
- **安全开源**：公开节点配置已纳入仓库；`Data/` 仍在 `.gitignore` 中排除。提交前请检查 `git status`，不要把个人凭据复制进受跟踪文件。

### 6. 🔄 直连官方 GitHub Releases 的全自动更新
配套 `update.cmd`（`App/update.ps1`），利用 `curl.exe` 直连 GitHub：
- 自动查询并下载 `openai/codex` 官方最新 `x86_64-pc-windows-msvc` 包。
- 自动查询并更新 `microsoft/terminal` 便携版。
- 具备更新备份与故障自动回滚机制。

---

## 📂 10 大核心引擎与启动脚本一览

| 编号 | 启动脚本 | 核心引擎 | 协议类型 | 本地端口 | 协议桥接 | 适用场景与优势 |
| :---: | :--- | :--- | :--- | :---: | :---: | :--- |
| **1** | `1.clash.meta.cmd` | Clash.Meta (Mihomo) | 多协议混合规则分流 | 7890 | 直连 | 规则分流丰富，日常首选 |
| **2** | `2.Xray.cmd` | Xray-core | VLESS / VMess / Trojan | 1081 | 直连 | 经典成熟协议，多节点备份 |
| **3** | `3.hysteria.cmd` | Hysteria 1 | 基于 QUIC 的暴力 UDP 加速 | 1080 | 自动桥接 | 恶劣弱网环境优化，对抗丢包 |
| **4** | `4.singbox.cmd` | sing-box | 现代通用网络核心 | 1080 | 直连 | 占用资源低，响应迅捷 |
| **5** | `5.naiveproxy.cmd` | NaiveProxy | Chromium 网络栈流量 | 1080 | 自动桥接 | 流量特征高度伪装，抗封锁极佳 |
| **6** | `6.hysteria2.cmd` | Hysteria 2 | 现代化高速 UDP 隧道协议 | 1080 | 自动桥接 | 新一代协议，极速并发吞吐 |
| **7** | `7.juicity.cmd` | Juicity | 极简高效 QUIC 隧道 | 1080 | 自动桥接 | 协议结构轻巧，握手开销低 |
| **8** | `8.mieru.cmd` | Mieru | SOCKS5 / TCP 混淆传输 | 3080 | 自动桥接 | 高度抗探测，特殊阻断环境备选 |
| **9** | `9.shadowquic.cmd` | ShadowQUIC | QUIC 协议伪装与混淆 | 4080 | 自动桥接 | 特征混淆度高 |
| **10** | `10.Quick.cmd` | Quick | 高速分流定制核心 | 7890 | 直连 | 极速轻量备用通道 |

---

## 🚀 详细使用指南

### 1. 环境准备
- **操作系统**：Windows 10 / Windows 11 (64 位)
- **网络条件**：能正常访问 GitHub（用于执行 `update.cmd` 获取官方 Codex 组件）
- **权限说明**：普通用户权限即可运行；若某些代理核心需要创建 TUN 虚拟网卡，建议右键“以管理员身份运行”。

### 2. 克隆与部署项目
```bash
git clone https://github.com/laybourne/Codex-Portable-CLI.git
cd Codex-Portable-CLI
```

### 3. 第一步：拉取官方组件（必须执行）
由于官方 `codex.exe`（300MB+）体积过大，超出 GitHub 仓库规范，本项目不直接包含该二进制文件。

1. 双击运行根目录下的 **`update.cmd`**。
2. 脚本将自动连接 GitHub Releases，下载官方最新版：
   - **OpenAI Codex CLI**（解压至 `App/bin/` 及 `App/codex-resources/`）
   - **Windows Terminal**（解压至 `WindowsTerminal/`）
3. 看到 `[DONE] Update check completed successfully.` 提示即表示初始化成功！

> [!TIP]
> 以后任何时候只要官方 Codex 或 Windows Terminal 发布新版本，重新双击运行 `update.cmd` 即可无痛原地升级。

### 4. 第二步：选择通道并启动

仓库已包含公开节点配置，可直接选择通道启动。若节点失效，可使用 `ip_Update` 脚本更新，或编辑所选核心目录下的 `config.json`、`config.yaml`、`client.yaml` 配置自己的节点。`*.example` 是无凭据模板；仅在实际配置缺失时，`setup-configs.cmd` 或启动脚本才会复制它。

选择通道启动：
在项目根目录中，根据您的网络偏好双击对应的启动脚本（如 **`1.clash.meta.cmd`** 或 **`6.hysteria2.cmd`**）：

1. **节点更新提示**：
   ```text
   是否执行IP更新？IP更新从服务端更新IP对接节点。
   默认 7 秒内不选择直接启动，1~6 选择更新对应 ip 节点。
   ```
   - **直接回车或等待 7 秒**：直接使用当前配置启动。
   - **输入数字（如 1、2）**：将自动触发 `ip_Update` 脚本在线拉取最新的备用节点配置，随后自动启动。
2. **启动自动化流转**：
   - 自动清理历史残留进程。
   - 启动后台代理引擎及必要的本地协议桥。
   - 预检 `api.openai.com` 的 TLS 握手状态。
   - 唤起内置便携版 **Windows Terminal**，自动进入 OpenAI Codex 交互界面！

### 5. 第三步：登录与使用 OpenAI Codex
初次在 Windows Terminal 中运行 Codex 时：
1. 终端会提示进行登录认证（输入 API Key 或完成浏览器 OAuth 授权）。
2. 授权凭证保存在本地的 **`Data/codex/auth.json`** 中；请按敏感文件保管，不要上传或分享。
3. 认证成功后即可直接进行自然语言编程、代码审查、终端命令自动化生成等所有 Codex 核心功能。

### 6. 第四步：结束使用与进程清理
使用完成后，无需手动一个个在任务管理器中查杀进程：
- 直接双击根目录下的 **`停止代理.cmd`**。
- 程序将自动扫描并精准关闭本机由本项目产生的所有后台代理进程（如 clash、xray、sing-box 等），恢复系统最初的网络状态。

---

## 🛠️ 进阶配置与自定义

### 自定义您自己的私人代理节点
如果您拥有自己的自建节点或订阅，可编辑对应核心的配置文件。仓库中的配置已被 Git 跟踪；请勿将私人节点凭据提交到公开仓库。
- **Clash.Meta**：编辑 `clash.meta/config.yaml`
- **Xray**：编辑 `Xray/config.json`
- **sing-box**：编辑 `singbox/config.json`
- **Hysteria 2**：编辑 `hysteria2/config.json`
- **NaiveProxy**：编辑 `naiveproxy/config.json`

修改完成后，无需额外配置，双击对应的 `.cmd` 启动脚本即可生效。

### 本地数据的备份与多机器迁移
Codex 登录信息、聊天记录和会话缓存存储于 `Data/` 目录中：
- **完整备份**：只需备份 `Data/codex/` 文件夹即可完整保留所有设置与登录态。
- **跨机器使用**：将整套目录拷贝至 U 盘或移动硬盘，在任何 Windows 设备上双击即可直接免登录使用。
- **重置环境**：若需彻底重置登录态，清空 `Data/codex/` 目录即可。

### 高级命令行调用
除了通过根目录的 `.cmd` 双击运行外，您还可以通过 PowerShell 脚本进行参数化自定义启动：

```powershell
# 指定使用 6 号核心 (Hysteria2) 并直接在当前控制台中运行（不拉起 Windows Terminal）
powershell.exe -ExecutionPolicy Bypass -File App/codex_proxy.ps1 -Core 6 -InConsole
```

---

## 📁 完整目录结构说明

```text
Codex-Portable-CLI/
├── 1.clash.meta.cmd            # [快捷入口] Clash.Meta 核心一键启动
├── 2.Xray.cmd                  # [快捷入口] Xray 核心一键启动
├── 3.hysteria.cmd              # [快捷入口] Hysteria 1 核心一键启动
├── 4.singbox.cmd               # [快捷入口] sing-box 核心一键启动
├── 5.naiveproxy.cmd            # [快捷入口] NaiveProxy 核心一键启动
├── 6.hysteria2.cmd             # [快捷入口] Hysteria 2 核心一键启动
├── 7.juicity.cmd               # [快捷入口] Juicity 核心一键启动
├── 8.mieru.cmd                 # [快捷入口] Mieru 核心一键启动
├── 9.shadowquic.cmd            # [快捷入口] ShadowQUIC 核心一键启动
├── 10.Quick.cmd                # [快捷入口] Quick 核心一键启动
├── update.cmd                  # [核心运维] 官方 Codex & Windows Terminal 一键更新
├── 停止代理.cmd                # [核心运维] 一键安全关闭所有后台代理守护进程
├── wget.exe                    # 节点更新批处理底层下载工具
├── .gitignore                  # Git 忽略运行数据与超大包
├── setup-configs.cmd           # 实际配置缺失时从模板创建配置
├── LICENSE                     # MIT 开源协议
├── README.md                   # 详细使用说明文档
│
├── App/                        # 调度与更新主逻辑
│   ├── codex_proxy.ps1         # 核心调度器（端口校验/TLS探测/协议桥/环境挂载）
│   ├── update.ps1              # 官方组件更新器（下载/校验/解压/回滚）
│   ├── stop_all_proxies.ps1    # 代理进程精准清理逻辑
│   ├── codex-package.json      # Codex 版本描述清单
│   └── bin/                    # [本地生成/Git已忽略] Codex 官方二进制存放目录
│
├── Data/                       # [本地私有/Git已忽略] 便携数据隔离目录
│   ├── codex/                  # Codex 运行时主目录 (auth.json, sessions, history)
│   ├── proxies/                # 代理运行时状态
│   └── logs/                   # 日志文件
│
├── WindowsTerminal/            # 便携版 Windows 终端运行环境
│   ├── WindowsTerminal.exe     # 终端主程序
│   └── settings/               # 终端配置文件
│
└── <各个代理核心目录>/          # 10 款核心程序与配置
    ├── clash.meta/             # Clash.Meta 内核、规则集与配置文件
    ├── Xray/                   # Xray-core、wintun.dll 与配置文件
    ├── singbox/                # sing-box 内核及通用路由规则库
    ├── hysteria2/              # Hysteria2 可执行程序与配置文件
    └── ...各核心下的 ip_Update/ # 各自独立的在线节点更新脚本
```

---

## ❓ 常见问题排查 (FAQ)

### Q1: 运行启动脚本时提示 `未找到 App/bin/codex.exe`？
**解答**：因为 GitHub 不存储超大二进制文件，克隆项目后**必须先双击运行 `update.cmd`**。它会自动拉取官方最新版 Codex 并安装就绪。

### Q2: 提示 `端口 1080/7890 已被外部程序占用`？
**解答**：说明您电脑上已运行了其他代理软件（如 Clash Verge、v2rayN 等）并占用了相同端口。
- **方案 A**：先退出冲突的第三方代理软件，再重新启动脚本。
- **方案 B**：改用本项目中其他端口不冲突的核心（例如使用端口为 1081 的 `2.Xray.cmd`）。

### Q3: 提示 `本地端口已经启动，但无法通过该节点完成 OpenAI TLS 握手`？
**解答**：这说明本地代理虽然成功启动，但该节点无法与 OpenAI 服务器（`api.openai.com:443`）建立有效连接。
- 启动脚本时输入数字 `1` 尝试更新在线备用节点。
- 或者直接换用其他编号的核心（例如由 1 号切至 6 号或 4 号）。
- 检查自己的网络是否有 UDP 拦截；若 UDP 被封锁，建议优先使用基于 TCP 的 `1.clash.meta.cmd`、`2.Xray.cmd` 或 `5.naiveproxy.cmd`。

### Q4: 如何彻底关闭后台代理？
**解答**：双击运行根目录下的 **`停止代理.cmd`** 即可。调度器会精准识别并杀死由本项目工作目录拉起的所有后台进程，不会误杀系统中的其他进程。

---

## 🔒 隐私与安全性保障

- **100% 本地托管**：本套件不架设任何中间收集服务器，所有请求直接由您的本地核心对接 OpenAI 官方。
- **零全局污染**：不修改 Windows 注册表，不强行修改系统全局网络代理。代理参数仅注入当前 Codex 会话的进程环境变量中。
- **凭据隔离**：Codex 登录数据存放在 `Data/`，该目录被 Git 忽略。代理节点配置是公开文件；提交前请复查文件变更，避免加入私人凭据。

---

## ⚖️ 免责声明 (Disclaimer)

1. 本项目作为开源自动化工具与脚本集合，仅供技术研究、网络协议交流与开发者学习使用。
2. 使用本项目时请务必遵守当地法律法规以及服务提供商的相关服务条款。
3. "OpenAI" 及 "Codex" 为 OpenAI, Inc. 的商标与产品，本项目为第三方开源封装集成套件，与 OpenAI 官方无任何商业从属关系。

---

## 📄 授权协议

本项目采用 [MIT License](LICENSE) 开源授权协议。
