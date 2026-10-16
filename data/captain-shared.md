# Captain shared preferences (main-authoritative, read-only in secondmate homes)
<!-- memory tiers: see the stow skill -->

This file is the single source of truth for captain preferences that apply across all firstmate homes (primary and secondmates). The main home (cc-vps) owns the authoritative version; secondmate homes receive it read-only via `bin/fm-remote-inherit-push.sh`.

Local per-home preferences belong in `data/captain.md` (not shared, not synced).

## 沟通

- **和 captain 的沟通一律用中文。**

## 工具与派发

- 配置/工作派发一律走 firstmate 派发路径（fm-spawn → worker，运行时后端按 config/backend 选，如 herdr）。不使用体系外 subagent 工具执行写操作；只读分析类任务可放宽。

## 工作方式

- **向上游提 PR 走 fork-first**：先 fork 到 `WeiYiAcc/<repo>`、推修复分支、自己跑一段时间，确认稳定后再提 PR；不直接往上游推分支。
- **本机已有的能力优先复用**，不要另要一份凭据或把人工步骤抛回给 captain。装新工具时直接接本机既有的网关/密钥体系（例如 gproxy 的稳定名 `default`、secretspec 取 key），而不是让 captain 去跑 `claude setup-token` 之类的交互登录。
- **能自动跑完的就跑到可验证结果**，中途的安装、配置、排障不要逐个回来确认；只有真正需要 captain 决策或授权的才停下问。
- 需要改/删远端资源时 captain 会明确授权（如「我授权」），授权后直接执行；没有授权又做不到时，用可逆办法（归档而非删除）并在结果里说明差异。
- **编译任务一律不用 VPS**（cc-vps、racknerd 都不行——4G/低配跑不动 Rust release build）。编译环境优先级：GitHub Action > Devin Cloud（org-7a24 大概还有半个月过期，抓紧用）> 本机 WSL > desktop/book 的 WSL。派活时 brief 里写明目标环境，不要让 worker 默认在 VPS 上 cargo build。

## 密钥

- **secretspec（sops+age）是唯一密钥真相源，禁明文副本**；客户端 env 引用（codex `env_key`、claude `apiKeyHelper` 等）。**mise track 的配置不得含明文密钥**（会进 mise-setup 仓），先改 `${VAR}` 再 track。

## 工具作用域

- Pi 的 packages **一律装在用户级** `~/.pi/agent/settings.json`，不搬去项目级；某个仓库要启用哪些包，由该仓库自己的 `.pi/settings.json` 或 `pi -e` 决定。firstmate 主 home 的 `~/.pi/agent/settings.json` 是 captain 的配置，不代为删改。
- `pi-subagents` 不装进任何新仓库；`pi-ask-user` 与新 CE 仓库配套，在仓库的 `.pi/settings.json` 里启用。
