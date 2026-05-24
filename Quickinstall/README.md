# AITermux Quickinstall

此目录用于放置“一键覆盖安装”相关脚本与模板。

## 用法

首次安装（从 GitHub 克隆到默认目录）：

```bash
git clone https://github.com/jiangshanyao2200-hue/longgu-termux-kit-step2.git ~/AItermux
cd ~/AItermux
bash install.sh
```

已存在 `~/AItermux` 时，直接覆盖部署：

```bash
cd ~/AItermux
bash install.sh
```

也可以从子目录运行（等价）：

```bash
cd ~/AItermux/Quickinstall
bash install.sh
```

## 可选参数

```bash
bash install.sh --dry-run
bash install.sh --quiet
```

## 说明

- `deploy/termux/`：覆盖到 Termux 启动链路文件（`motd.sh` / `login` / `etc/motd.sh` / `etc/termux-login.sh` / `tx11start`）与配置（`termux.properties`）；安装时还会把 `~/.termux/shell` 设为 `$PREFIX/bin/zsh`，确保 `motd` 菜单结束后进入正常 zsh。
- `deploy/aitermux/`：安装启动器、bootstrap，以及保留给 zsh 的占位片段；Launcher 菜单本体已经回收到 `motd.sh`。
- `deploy/startboot/`：开屏动画脚本池；所有可执行 `*.sh` 都会进入随机播放池。
- `deploy/aitermux/bin/`：安装到 `~/AItermux/bin/`，包含 `codexurl`、`codexDNS`、`aitermux-cli-install` 等 AITermux 本地工具。

安装器职责边界：

- 安装阶段部署 AITermux 外壳层，并通过 bootstrap 按需拉取 `projectling / projectying` 源码。
- 安装阶段不主动安装 `codex / gemini / claude`
- 缺失运行时的自动补装，只在用户点击对应 Launcher 入口时触发

前提：

- 需要已安装 `zsh`；安装器会校验 `$PREFIX/bin/zsh`，缺失时直接报错，避免菜单结束后落到 bash。
- `projectying / projectling` 走独立仓库路线；默认仓库为 `projectying-termux` / `projectling-termux`，可用 `AITERMUX_PROJECTYING_REPO`、`AITERMUX_PROJECTLING_REPO` 覆盖。
- `codex / gemini / claude` 缺失时会在点击对应入口时由 bootstrap 自动安装 npm CLI 和 Termux 包装层。也可以手动执行 `aitermux-cli-install codex|gemini|claude|update-aitermux|update-projects|all`。

## 启动菜单（登录后）

安装完成后，重新打开 Termux（或新建 session）会先播放随机 `startboot` 动画，再落到 `motd` 里的交互式 `TERMUX LAUNCHER` 菜单：

- `↑↓`：上下选择
- `1` / `2` / `3` ...：也可以直接在输入框输入序号
- `Enter`：启动当前选中项
- `Esc`：跳过菜单，直接进入 shell
- `PROJECT凌设置`：进入 `motd` 系统配置项

入口仍然是：

- `1`：启动 `PROJECT 萤`（`~/AItermux/projectying/run.sh`）
- `2`：启动 `CODEX`（`codex`）
- `3`：启动 `Gemini`（`gemini`）
- `4`：启动 `Claude Code`（`claude`）
- `启动 Xfce 图形界面`（`tx11start`）
- `PROJECT凌设置`

启动项会在当前 `motd` 页面下方继续执行；程序退出后，再落到正常 zsh。

`PROJECT凌设置` 打开的系统配置菜单当前支持：

- `PROJECT凌设置`：直接进入 `projectling` 的统一设置页
- `启动项管理`：添加、移除、重命名或改路径；自定义项持久化在 `~/AItermux/.state/motd/launchers.tsv`
- `检测 AITermux 更新` / `检测 PROJECT萤 更新` / `检测 PROJECT凌 更新`：检查远端仓库是否有新提交，有则 fast-forward 拉取源码
- 更新检查会写入 `~/AItermux/.state/bootstrap/*.state`，并在 `motd` 底部显示精简进度；同一组件重复触发时会加锁，避免多窗口同时更新同一仓库。
- `PROJECT萤` 更新只拉取源码；如果源码有变化，下一次启动 `PROJECT萤` 时由 `projectying/run.sh` 自动执行 `cargo build --release`。

如果入口缺失，选中后按 Enter 时才会触发安装：

- 点击 `PROJECT 萤`：如果本地缺少，会从 `projectying-termux` clone；已有本地目录则不会覆盖
- 打开 `PROJECT凌设置`：如果本地缺少 `projectling`，会从 `projectling-termux` clone
- 点击 `CODEX`：自动安装官方 `@openai/codex`，并补齐 `@openai/codex-linux-arm64` / `@openai/codex-linux-x64` 原生组件；验证命令、入口文件和 native vendor binary，不再把缺少 optional dependency 误判为安装成功
- 点击 `Gemini`：自动安装 `@google/gemini-cli`，并写入 `~/.local/bin/gemini`。Termux Android 下会跳过安装脚本，避免 `keytar/node-pty` 触发无效的 Android NDK 编译报错；安装后用 `gemini --version` 做启动验证。
- 点击 `Claude Code`：自动安装官方 `@anthropic-ai/claude-code`；Termux Android 没有官方原生 target 时，会补装 Alpine proot 与 `@anthropic-ai/claude-code-linux-arm64-musl`，并写入 `~/.local/bin/claude`。安装后用 `claude --version` 做启动验证，只有可运行才写入 ok 状态。

自动安装会在后台执行，`motd` 菜单底部状态行会显示当前组件、最近安装日志、完成或失败摘要；已安装的入口会直接启动，不再重复安装。

`projectying` 是 Rust 源码项目，不走 npm。源码拉取或更新后，`run.sh` 会在首次打开或源码变更时自动执行 `cargo build --release`。

安装失败不会阻塞进入菜单；错误会写进 `~/AItermux/projectling/aidebug/logs/startup.log`，后续按退避策略重试。

日志不会无限增长：motd、zshrc、bootstrap、projectling 会按大小保留最近尾部日志，并按天数清理 `projectling/aidebug/tmp` 和 ProjectLing terminal 临时输出；`notes/`、`backup/`、`legacy/` 默认不会自动删除。

## 运行时可调参数（开屏动画）

默认策略：尽量全屏渲染，但用较低负载参数减少卡顿；动画结束后固定落到一帧静态赛博欢迎头，不再额外 flicker。

- 轻量模式（必要时再开）：`AITERMUX_MOTD_LIGHT=1`（会把画布限制为 `70x24`）
- 自定义画布上限：`AITERMUX_MOTD_MAX_COLS=70`、`AITERMUX_MOTD_MAX_ROWS=24`（仅当 `AITERMUX_MOTD_LIGHT=1` 或手动设置时生效）
- 速度相关示例（偏快）：`AITERMUX_MOTD_FPS=12`、`AITERMUX_MOTD_DURATION=1.1`、`AITERMUX_MOTD_HOLD=0`、`AITERMUX_MOTD_SPEED=1.2`
- 速度相关示例（偏稳）：`AITERMUX_MOTD_FPS=12`、`AITERMUX_MOTD_DURATION=1.7`、`AITERMUX_MOTD_HOLD=0.4`、`AITERMUX_MOTD_SPEED=1.0`
- 超时兜底：`AITERMUX_MOTD_TIMEOUT=4`（支持 `4`/`4s`/`200ms`/`1m` 等；`0` 表示不超时）
- 关闭颜色：`AITERMUX_MOTD_COLOR=0`（欢迎头和菜单都会退回无彩色）

## startboot 约定

- `startboot/` 里所有带执行权限的 `*.sh` 都会被随机抽取。
- 脚本报错、超时或异常退出时，`motd` 会直接跳过，继续进入 Launcher。
- 如果你只想放素材、说明或辅助文件，不要给它们可执行权限，也不要命名成 `*.sh`。

## 安装可视化与回滚

- 每次安装会创建备份目录：`~/AItermux/backups/upgrade-YYYYMMDD-HHMMSS/`
- 安装过程会输出每一步，并同时写入备份目录的 `install.log` 与 `~/AItermux/projectling/aidebug/logs/install.log`
- 安装/更新会自动清理旧安装残留，并只保留最近 5 个 `upgrade-*` 备份目录；可用 `AITERMUX_BACKUP_KEEP` 调整保留数量。
- 回滚脚本：`rollback.sh`（把备份文件复制回原路径）
