# folder-organizer

一个**谨慎的本地文件整理 Agent Skill**:安全分析并整理 Windows / macOS / Linux 的本地文件夹、移动硬盘、旧电脑迁移文件或历史备份目录,把混乱的目录恢复成人类容易理解、容易查找、长期可维护的结构。

适用于任何支持 Agent Skills 的编码助手(Claude Code、ZCode、Codex CLI、Kimi Code 等)。

## 与"整理工具"的根本差异

市面上的整理工具把同一套固定模板(按类型、按年份、按规则)套在任何目录上。本 Skill 的第一步永远是**全量遍历 + 目录语义画像 + 主题地图**——先弄清"这堆文件到底是谁的、关于什么",目录结构是从内容里归纳出来的,不是模板套上去的。

- `客户A项目/` 里的 需求.docx、报价.xlsx、合同.pdf、screenshots/、source/ 是一个有上下文的整体,**严禁**被拆成 Word/、Excel/、PDF/、Images/
- 类型与日期只作佐证,不作第一分类维度
- 主题 = 用户心智里的一个"东西":一个客户、一个项目、一次旅行、一台设备、一段工作经历

## 核心特性

- **四种运行模式**:`scan`(只读分析)→ `plan`(生成 plan.csv,每个决策引用主题证据)→ `apply`(执行,自动生成 undo 脚本)→ `verify`(核对文件守恒与语义覆盖率)
- **语义地图**:目录画像 + Agent 归纳主题,产出 `semantic-map.md`,一页答完"这堆资料里有哪几摊东西"
- **确定性判重**:优先复用本机已装的 Czkawka / fclones CLI(只读扫描),不可用自动降级为平台脚本(Windows: PowerShell + SHA256;Unix: bash + shasum),不需要安装任何东西
- **全平台**:macOS / Linux(bash 3.2 + 系统 awk 实测通过)与 Windows(PowerShell 5.1+)双脚本实现,字段一致

## 安全设计(硬性红线)

- 禁止删除任何用户文件——即使 SHA256 确认完全重复,也只能移入 `_quarantine/` 隔离区
- 所有修改必须先生成计划(`plan.csv`),自动执行只允许 HIGH 置信度
- 全程可回滚:每个操作记录 operations.csv,并生成 undo 脚本
- 软件项目(`.git`/锁文件标识)、依赖目录(node_modules 等)、macOS bundle(`.app`/`.photoslibrary`)、备份快照(Time Machine 等)自动识别并保护
- 默认不把本地文件交给外部服务分类,一切在本机完成

## 安装

```bash
# 方式一:skills CLI(装进当前项目 .agents/skills/)
npx skills add SeanZon/folder-organizer

# 方式二:手动克隆后把整个目录复制到技能目录
#   项目级: .agents/skills/folder-organizer/
#   用户级: ~/.agents/skills/folder-organizer/
#   Claude Code 用户级: ~/.claude/skills/folder-organizer/
git clone https://github.com/SeanZon/folder-organizer.git
```

## 使用

安装后直接对话触发,例如:

> 帮我整理一下 ~/Downloads,目录太乱了
> 这块移动硬盘是旧电脑迁移过来的,帮我梳理清楚结构

Skill 支持显式调用(声明了 `user-invocable`),也会在用户提到整理磁盘/文件夹/下载目录、检测重复文件、归档旧资料时自动触发。

## 仓库结构

```text
├─ SKILL.md                     平台无关核心流程(原则/语义理解/决策/计划/执行/验证)
├─ references/
│  ├─ tool-commands.md          czkawka / fclones 调用规范、降级链、输出归一化
│  ├─ windows.md                Windows / PowerShell 平台细则
│  └─ macos.md                  macOS / Linux / bash 平台细则
└─ scripts/
   ├─ windows/                  inventory-and-profiles.ps1 / duplicates-fallback.ps1
   └─ unix/                     inventory-and-profiles.sh / duplicates-fallback.sh
```

## 依赖

无硬依赖。重复扫描优先用本机已有的 [Czkawka](https://github.com/qarmin/czkawka) 或 [fclones](https://github.com/pkolaczk/fclones)(只读调用),都没有时自动降级为自带脚本;工具缺失不要求安装、不算失败。

## 已知限制

- 文件名包含换行符的文件不被降级脚本支持(此时应使用 fclones / czkawka)
- Unix 脚本在 macOS 自带 bash 3.2 + BWK awk 与 Linux GNU 工具链下均按最小依赖编写;`~/Library` 等应用数据目录默认跳过,需要"完全磁盘访问权限"的路径报错时如实跳过
