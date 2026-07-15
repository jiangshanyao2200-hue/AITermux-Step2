# AITermux

AITermux 是面向 Android + Termux 的启动链、开屏动画、motd 菜单和 AI 工具安装器。这个仓库是 longgu termux kit2 的主安装仓。

## 状态

AITermux 当前可以用于 Android + Termux 环境下的实验性测试、研究验证和个人折腾。它仍不是稳定产品，不建议作为生产环境或长期日常依赖。

我们会尽最大努力降低它的使用门槛，但它仍然会保持较高难度。使用者需要理解 Termux、zsh、文件权限、Git、npm、API Key、模型代理，以及终端工具执行带来的系统风险。

## 适用范围

- Android + Termux
- AITermux 启动链、开屏动画、motd 菜单和 zsh 接入
- Project萤、Project凌、Codex、Gemini、Claude Code 的按需安装与启动
- Termux 环境里的 AI 工作流、上下文工程和多工具协作测试

AITermux 不是通用桌面程序，不承诺支持 Linux 桌面、Windows、macOS 或普通 Android shell。

## 当前链路

`projectling` 和 `projectying` 不内置在 AITermux 发布包里，走独立仓库发布与更新。Quickinstall 只保留启动链、启动器和安装器，并通过 bootstrap 按需拉取这两个源码仓。

安装阶段会同步 Termux 启动链、动画、菜单和样式层，并检查/拉取 `projectling / projectying`。`codex / gemini / claude` 不会在安装阶段主动安装，只会在用户点击对应 Launcher 入口时按需补装。

默认独立仓库：

```bash
export AITERMUX_PROJECTYING_REPO='https://github.com/jiangshanyao2200-hue/ProjectYing.git'
export AITERMUX_PROJECTLING_REPO='https://github.com/jiangshanyao2200-hue/ProjectLing.git'
```

## 快速开始

```bash
git clone https://github.com/jiangshanyao2200-hue/AITermux-Step2.git ~/AItermux
cd ~/AItermux
bash install.sh
```

前提：需要已安装 `zsh`。安装脚本会校验 `$PREFIX/bin/zsh`，并把 `~/.termux/shell` 链到它，保证 `motd` 菜单结束后回到正常 zsh。

## 登录后菜单

重新打开 Termux 或新建 session 后，会先播放随机开屏动画，然后显示 `TERMUX LAUNCHER` 菜单。

- `↑↓`：上下选择
- `1` / `2` / `3` ...：输入序号直达启动项
- `Enter`：启动当前选中项
- `Esc`：跳过菜单，直接进入 shell
- `PROJECT凌设置`：进入启动项、动画速度、Project凌 设置和更新检测

内置入口：

- `PROJECT 萤`
- `CODEX`
- `Gemini`
- `Claude Code`
- `Xfce 图形界面`
- `PROJECT凌设置`

启动项会在当前 `motd` 页面下方继续执行；程序退出后，再落到正常 zsh。若入口缺失，会先尝试自动补装；补装失败会写日志并返回菜单或 shell，不会把启动链卡死。

## 按需安装

`aitermux-bootstrap` 当前处理五类组件：

- `projectying`：缺失时从 `ProjectYing` clone，更新走 `git pull --ff-only`
- `projectling`：缺失时从 `ProjectLing` clone；旧仓库地址会在更新时安全迁移
- `codex`：通过 npm 全局安装 `@openai/codex`，并补齐 `@openai/codex-linux-arm64` / `@openai/codex-linux-x64` 原生组件；验证命令、入口文件和 native vendor binary
- `gemini`：通过 npm 全局安装 `@google/gemini-cli`，写入 Termux 包装器，并用 `gemini --version` 验证
- `claude`：安装 `@anthropic-ai/claude-code`，必要时补装 Alpine proot 与 `@anthropic-ai/claude-code-linux-arm64-musl`，并用 `claude --version` 验证

更新链路会把组件状态写到 `~/AItermux/.state/bootstrap/`。AITermux 更新后会自动重新部署启动链；ProjectYing 更新后不会在更新菜单里立即构建，而是在下次启动时检测源码变化并自动执行 release 构建。

也可以手动执行：

```bash
aitermux-cli-install codex
aitermux-cli-install gemini
aitermux-cli-install claude
aitermux-cli-install update-projectling
aitermux-cli-install update-aitermux
aitermux-cli-install update-projects
```

`update-projectling` 完成后重新打开 zsh 会话即可加载新 Hook；若当前 ProjectLing 提供 `projectling_reload`，也可以直接热重载。

GitHub 推送凭据可用本机登录助手保存：

```bash
aitermux-github-login
```

它会明文读取本机输入的 token，并通过 GitHub CLI 配置 `git push` 凭据，避免把 key 写进仓库、脚本或命令历史。建议使用 classic token，并勾选 `repo`、`read:org`、`gist`。

## 目录边界

- `Quickinstall/`：一键覆盖部署脚本与模板
- `install.sh`：根目录安装入口
- `bin/aitermux-bootstrap`：运行时缺失依赖补装器
- `bin/aitermux-github-login`：GitHub CLI 登录助手，用于保存本机 push 凭据
- `bin/aitermux`：AITermux 启动器
- `startboot/`：本机动画脚本池
- `projectling/aidebug/`：Project凌 的本机调试日志目录，默认不随仓库发布
- `backups/`：安装/更新备份目录，默认只保留最近 5 个 `upgrade-*`

## 使用前确认

- 只在 AITermux / Termux 链路内使用。
- 发布仓库不包含 API Key、用户记忆、聊天上下文、运行日志、构建产物和本机角色状态。
- WebSearch、工具执行、终端协作、手机自动化等能力需要用户自己配置并理解风险。
- 不建议普通用户在不了解 Termux 文件结构、权限和模型 API 风险的情况下直接使用。
