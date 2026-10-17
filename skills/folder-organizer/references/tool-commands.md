# 工具层：重复文件扫描调用规范（czkawka / fclones，跨平台）

重复文件检测只允许两种来源：已安装的 CLI 扫描器（czkawka / fclones）或本 Skill 自带的平台降级脚本。本文件是唯一的工具调用规范；SKILL.md 只保留判定与决策规则。

## 总原则

- czkawka / fclones 永远只是**只读扫描器**。任何会写文件、删文件、建链接的参数/子命令一律禁止（见下文两节黑名单）。
- 参数以 `--help` 实测为准：两工具都在快速迭代，版本间参数不一致，禁止凭记忆猜参数。
- 检测到工具后先跑 `--version` 与对应子命令 `--help` 确认能力，再决定参数；不兼容就降级，降级不是任务失败，也不要求用户安装。
- 输出统一归一化：`Group, Hash, Size, FullName`，再由 Agent 标注 `Protected / SuggestedAction`。
- 辅助扫描（大文件 / 空目录 / 临时文件候选）只有 czkawka 提供；czkawka 不在时这些项跳过，在报告中注明"未执行（工具不可用）"，不要硬凑。

## 检测与优先级

| 平台 | 优先级 |
|---|---|
| Windows | czkawka → fclones → `scripts/windows/duplicates-fallback.ps1` |
| macOS / Linux | fclones → czkawka → `scripts/unix/duplicates-fallback.sh` |

任一工具在任一平台可用即可按各自命令行执行；优先级只是选择顺序，不是硬门槛。

Windows 检测：

```powershell
Get-Command czkawka_cli, czkawka, fclones -ErrorAction SilentlyContinue | Select-Object Name, Source
```

Unix 检测：

```sh
command -v fclones czkawka czkawka_cli || true
```

macOS 安装来源（仅在用户主动同意时）：`brew install fclones`、`brew install czkawka`（CLI 名为 czkawka_cli）。

## czkawka dup

```powershell
$DuplicateJson = Join-Path $Workspace "duplicates-czkawka.json"

& $Czkawka.Source dup `
    -d $Target `
    -e "$Target\_organizer" `
    -e "$Target\_quarantine" `
    -s HASH `
    -u `
    -p $DuplicateJson `
    -W
```

- `-s HASH` 按内容 Hash 判重；`-u` 启用 prehash cache（版本支持时开启，加速复扫）；`-p` 输出格式化 JSON；`-W` 避免"发现重复文件"被当成脚本失败退出码。
- 参数版本不一致时，以 `dup --help` 实测为准调整；仍不兼容就降级（见优先级表）。

黑名单（绝对禁止）：`-D`、`-y` 及任何 `delete` / `remove` / hardlink / move-to-trash 类自动处理参数；czkawka 的输出只作为重复证据，文件处理永远由本 Skill 控制。

## fclones group

代表性形态（以 `fclones group --help` 实测为准，参数名可能随版本变化）：

```sh
fclones group --format json --output "$WS/duplicates-fclones.json" \
  --exclude "$TARGET/_organizer/**" \
  --exclude "$TARGET/_quarantine/**" \
  "$TARGET"
```

- 判重流水线：size → 前缀 → 全量 hash，最终仍以"内容完全相同"为准，与 czkawka `-s HASH` 同级。
- `--exclude` 是 glob 模式，可重复传；路径分隔符与平台一致（macOS/Linux 为 `/`）。
- 版本支持时开启缓存（`--cache`），加速复扫。
- JSON 结构：groups → 每组文件列表 → path/size/hash，按下文规则归一化。

黑名单（绝对禁止）：`fclones remove` / `link` / `reflink` / `move` / `dedupe` 等一切写操作子命令——fclones 的设计用途是"查找后直接处理"，本 Skill 只用它的"查找"；同样禁止任何 `--soft-link` / `--hard-link` / 输出替换类选项。

## 输出归一化

czkawka / fclones 的 JSON 与本 Skill 降级脚本的 CSV/TSV，统一转成：

```text
Group, Hash, Size, FullName, Protected, SuggestedAction
```

Group 编号规则：按 Hash 字典序排序后从 T001 起连续编号；同一目标的两次扫描编号必须一致（证据可复核）。Agent 在此之上按 SKILL.md 第 6/7 节标注 Protected 与 SuggestedAction（KEEP / QUARANTINE_DUPLICATE / DUPLICATE_IN_BACKUP + REVIEW）。

## 大文件 / 空目录 / 临时文件辅助扫描（仅 czkawka）

- `czkawka big`：大文件报告（ISO、旧安装包、视频、虚拟机镜像等），只报告不删。
- `czkawka empty-folders`：空目录报告，第一轮整理不自动删除。
- `czkawka temp`：只标 `TEMP_CANDIDATE`，禁止自动删除。
- `czkawka image` / `czkawka video`：相似 ≠ 重复，一律 `REVIEW`（见 SKILL.md 第 6 节）。
- fclones 无对应子命令；czkawka 不可用时上述辅助项缺失即可，报告中注明。
