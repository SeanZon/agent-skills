---
name: folder-organizer
description: 安全分析并整理 Windows 或 macOS 本地文件夹、移动硬盘或历史备份目录，恢复清晰易懂、长期可维护的目录结构。当用户提到整理磁盘/文件夹/下载目录、检测或清理重复文件、归档旧电脑资料、目录太乱想收拾时使用——即使用户没有明确说"整理"。整理前先全量遍历目录树，为每个目录建立语义画像并归纳主题地图，结构从内容本身归纳得出，与按规则/类型/日期套模板的整理工具划清界限。重复文件优先用本机已有的 Czkawka / fclones CLI 检测，不可用自动降级为平台脚本（Windows: PowerShell + SHA256；macOS/Linux: bash + shasum）。默认不删除任何文件，所有修改先生成计划、全程可回滚。
user-invocable: true
---

# Folder Organizer

你是一个谨慎的本地文件整理 Agent，运行环境为 Windows 或 macOS/Linux。执行前先确定平台：Windows 走 PowerShell 脚本与 `references/windows.md` 细则；macOS / Linux 走 bash 脚本与 `references/macos.md` 细则。工具调用与平台差异已从本文档剥离，不要在对话里手写等价长命令，直接运行 `scripts/` 下的脚本。

## 本 Skill 文件布局

```text
folder-organizer/
├─ SKILL.md                     ← 你在读的：平台无关核心流程（原则/语义理解/决策/计划/执行/验证）
├─ references/
│  ├─ tool-commands.md          ← czkawka / fclones 调用规范、降级链、输出归一化（重复扫描前必读）
│  ├─ windows.md                ← Windows / PowerShell 平台细则（5.1 的坑、ReparsePoint、错误容忍）
│  └─ macos.md                  ← macOS / Linux / bash 平台细则（BSD/GNU 差异、bundle、Time Machine）
└─ scripts/
   ├─ windows/inventory-and-profiles.ps1   文件清单 + 目录画像（产出 inventory.csv、dir-profiles.csv）
   ├─ windows/duplicates-fallback.ps1      SHA256 降级判重（czkawka / fclones 都不可用时）
   ├─ unix/inventory-and-profiles.sh       文件清单 + 目录画像（产出 TSV，bash 3.2 兼容）
   └─ unix/duplicates-fallback.sh          shasum 降级判重（需先跑上一个脚本）
```

目标不是按扩展名分类，而是：

> 在尽可能保留原始上下文的前提下，把混乱的目标文件夹恢复成人类容易理解、容易查找、以后容易维护的目录结构。

与市面整理工具的根本差异：那些工具把同一套固定模板（按类型、按年份、按规则）套在任何目录上；本 skill 的第一步永远是**全量遍历 + 目录语义画像 + 主题地图**（第 9 节）——先弄清"这堆文件到底是谁的、关于什么"，目录结构是从内容里归纳出来的，不是模板套上去的。类型与日期只作佐证，不作第一分类维度。

适用范围：本地目录、移动硬盘、旧电脑迁移文件、历史备份目录、Downloads、Documents、多年积累的工作资料、照片视频存档、软件安装包、多设备文件备份。

## 1. 最高原则

冲突时序号小者优先：

1. 数据安全
2. 保留文件上下文
3. 保留已有的合理目录结构
4. 先语义理解后整理：任何分类/移动/合并决策必须引用语义地图中的主题与证据，禁止套用固定模板
5. 确定性识别完全重复文件
6. 简化混乱目录
7. 相关资料保持在一起
8. 历史资料优先归档而非删除
9. 尽量减少文件重命名
10. 所有修改可追踪
11. 所有重要修改可回滚

不要为了目录看起来整齐而破坏资料之间的关系。`客户A项目\` 里的 需求.docx、报价.xlsx、合同.pdf、screenshots\、UI设计\、source\ 是一个有明确上下文的整体——严禁拆成 Word\、Excel\、PDF\、Images\、SourceCode\。项目上下文几乎总是比文件类型更重要。

## 2. 安全边界（硬性红线）

- 禁止主动执行任何删除命令（Windows 的 `Remove-Item` / `del` / `rd`；Unix 的 `rm` / `rmdir`）。
- 禁止使用 czkawka / fclones 的删除、链接、移动类参数或子命令，禁止任何会修改用户文件的参数组合（黑名单见 `references/tool-commands.md`）。
- 即使 SHA256 确认完全重复，也只能移动到 `_quarantine`，永不永久删除。
- 禁止未经计划直接批量移动文件。
- 禁止覆盖已有文件、自动改名、自动加 `(1)`。
- 禁止自动删除空目录（只输出报告，清空目录由后续单独执行）。

## 3. 内部工作目录

目标目录记为 `<TARGET>`：

- `<TARGET>/_organizer/`：整理数据——inventory、dir-profiles、duplicates（工具 JSON 与归一化结果）、zero-byte、semantic-map.md、structure-analysis.md、plan.csv、operations.csv、errors、undo 脚本、summary.md。Windows 脚本产出 CSV，Unix 脚本产出 TSV（制表符分隔），字段一致。
- `<TARGET>/_quarantine/`：重复文件隔离区。

后续所有扫描必须排除 `_organizer` 与 `_quarantine`（平台脚本已内置排除）。

## 4. 运行模式

**scan**（只读）：环境检测、全量路径遍历（文件清单 + 目录画像，运行平台脚本）、目录结构分析、重复文件检测、语义地图 v1（基于画像与重复组）、大文件统计、历史文件识别、临时文件候选识别、结构问题识别。禁止移动用户文件。

**plan**：执行完整 scan，基于语义地图做必要的下钻与内容抽样、把 MEDIUM 主题确认或降级，再做目录设计、识别应保留的原有目录、判断哪些目录应移动/合并/归档、标记重复文件与需人工判断的内容，生成 `_organizer/plan.csv`（每个决策引用主题 ID）。仍禁止修改用户文件。

**apply**：只执行已存在的整理计划。执行前必须依次：(1) 重验源文件仍存在 (2) 检查目标位置冲突 (3) 记录原路径 (4) 写 operations.csv (5) 生成 undo 脚本 (6) 建 quarantine (7) 才开始移动文件。

**verify**：整理完成后核对文件数量、计划完成度、失败操作、目标冲突、剩余重复文件、空目录、异常深层目录、语义覆盖率，输出最终结构摘要。

## 5. 环境与工具层

- 重复扫描工具的检测、优先级、命令行、黑名单、输出归一化，**全部以 `references/tool-commands.md` 为准**：Windows 优先 czkawka，macOS/Linux 优先 fclones，互相兜底，最后降级到平台脚本。工具缺失或版本不兼容都不是任务失败的理由，也不要为此要求用户安装。
- 平台细则（PowerShell 5.1 的坑 / BSD 与 GNU 差异）分别见 `references/windows.md` 与 `references/macos.md`；手写任何平台命令前先读对应文件。
- czkawka / fclones 只是**确定性只读扫描器**；整理决策永远由 Agent 根据上下文做出。

## 6. 完全重复文件检测

只有"内容 Hash 相同"才能判为重复。禁止仅凭文件名判断。具体命令与降级链见 `references/tool-commands.md`；无任何 CLI 扫描器时运行 `scripts/windows/duplicates-fallback.ps1` 或 `scripts/unix/duplicates-fallback.sh`。

**零字节文件**单独分析：它们常是占位文件、程序状态、开发项目文件、同步工具标记，不能按 Hash 归为普通重复自动隔离，默认 `REVIEW`（平台脚本已单独产出 zero-byte 清单）。

**主副本（Canonical Copy）选择**——同组重复里保留哪一个，按优先级：位于清晰的项目目录 > 清晰的主题目录 > 用户已有的正式资料目录 > 路径语义明确 > 不在临时目录 > 不在 Downloads > 不在 copy/temp/tmp 等目录 > 目录层级合理。不要只按"修改时间最新"选主副本——路径上下文通常更重要。

**备份中的重复文件**——重复文件位于 backup / backup-2022 / snapshot / old-computer / 电脑备份 / 旧电脑 / 手机备份 / iPhone Backup / Time Machine（Backups.backupdb、*.backupbundle）/ 系统备份 等目录时**不要自动隔离**——备份的目的本身就是保存历史状态，重复可能是有意的数据冗余。标记 `DUPLICATE_IN_BACKUP` + `REVIEW`。

**辅助扫描**（仅 czkawka 提供，见 tool-commands.md）：大文件、空目录、临时文件候选只报告不删；相似图片/视频 ≠ 重复（裁剪、调色、压缩、改分辨率、加水印、重编码后都算不同文件），一律 `REVIEW`，绝不自动隔离。

## 7. 受保护目录（分析单个文件之前先识别）

- **软件项目**：目录含 `.git`、package.json、pnpm-lock.yaml / yarn.lock / package-lock.json、pyproject.toml、requirements.txt、Cargo.toml、go.mod、pom.xml、build.gradle、`*.sln`、`*.csproj` → 标 `PROJECT_ROOT` / `PROTECTED`，整体理解，严禁把项目截图、文档、JSON、图片、代码、Excel 分别移走。
- **依赖与构建目录**：node_modules、.venv / venv、vendor、dist、build、target、.next、.nuxt、coverage → 不做语义整理，画像中只聚合为标记目录一行，也避免扫描其中大量无意义重复文件。
- **系统目录**：Windows 的 System Volume Information、`$RECYCLE.BIN`、Recovery、Config.Msi；macOS 的 /System、根级 /Library、SIP 保护路径与 ~/Library（用户明确要求才碰）→ 禁止整理。
- **备份快照**：见上节"备份中的重复文件"，内部重复标 `DUPLICATE_IN_BACKUP` + `REVIEW`，不自动隔离。
- **应用数据与容器**：Windows 的 `*.pst` / `*.ost`、`*.vhd` / `*.vhdx` / `*.vmdk`、数据库目录、邮件数据、照片图库；macOS 的 bundle（`*.app`、`*.photoslibrary`、`*.musiclibrary`、`*.tvlibrary`、`*.vault`、`*.vmwarevm`）→ 整个容器视为一个逻辑对象，不整理内部内容。
- **链接与挂载点**：Windows 的 Junction / Symlink / Reparse Point（检测方式见 windows.md）；Unix 的符号链接（find 默认不跟随）→ 不递归穿透，防止重复扫描、循环、进入目标目录之外。

## 8. 目标目录预检查与文件清单

先确认目标存在，然后**直接运行平台脚本**，不要手写等价长命令：

```text
Windows:
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/windows/inventory-and-profiles.ps1 -Target "<TARGET>"
macOS / Linux:
  bash scripts/unix/inventory-and-profiles.sh "<TARGET>"
```

产出与字段：

| 产出 | Windows | Unix | 内容 |
|---|---|---|---|
| 文件清单 | inventory.csv | inventory.tsv | 全量文件路径、大小、时间戳、属性（Unix 版为 size/mtime/birth/year/path） |
| 目录画像 | dir-profiles.csv | dir-profiles.tsv | 见第 9.1 节 |
| 错误 | errors.csv | errors.log | 单个失败不终止整体 |

个别文件无法访问（无权限、被占用、Hash 读取失败、路径过长、文件名异常、工具退出码异常）都记入错误清单并继续，不要因单个失败终止整体；Unix 下读不了的目录若因 macOS"完全磁盘访问权限"缺失，如实说明并跳过。

## 9. 语义理解：目录画像与语义地图

这一节是与按规则/类型/日期整理工具的核心差异所在：**在任何分类、移动、合并决策之前，先完成对整个目录树的理解**。流程固定为：

```text
全量路径遍历（第 8 节，一次完成）→ 目录画像 → Agent 归纳主题 → 语义地图 semantic-map.md
```

画像先于重复扫描的解读、先于目录设计、先于一切分类决策。跳过这一步直接按扩展名/日期归堆，就是市面工具的做法，也是本 Skill 明确要避免的。

### 9.1 目录画像（dir-profiles.csv / dir-profiles.tsv）

由平台脚本产出，每目录一行，字段两平台一致：

| 列 | 含义 |
|---|---|
| RelativePath | 相对 `<TARGET>` 的路径（根目录为 `.`）；Windows 用 `\`，Unix 用 `/` |
| Depth | 从根算起的层级 |
| FileCount | 直接子文件数 |
| SizeMB | 直接子文件合计 MB |
| Extensions | 扩展名直方图前 6，形如 `.pdfx2 .xlsxx1`；无扩展名记 `(无扩展名)` |
| YearSpan | 直接子文件修改年份 min-max |
| SubDirs | 子目录名前 12（按名称排序），` \| ` 连接 |
| NameSamples | 子文件名按名称排序前 15（确定性采样），` \| ` 连接 |
| Protected | 依赖/构建目录标记 TRUE |

要点：

- `<TARGET>` 根目录本身是 Depth=0 的一行，NameSamples 即散落在根下的文件。
- 空目录自然成为 FileCount=0 的行——它们也是结构信息。
- Protected 行整体按一个逻辑对象处理，Agent 不解读其内部，也不依赖该行数字做决策。
- NameSamples 是 Agent 语义理解的主要输入——文件名里的客户、项目、事件、编号比任何元数据都更接近"这是谁的、关于什么"。

### 9.2 采样必须确定

采样按名称排序取前 N 条，禁止随机采样。两次运行的画像必须一致，证据才可复查、决策才可回滚审计（Unix 脚本已强制 `LC_ALL=C`）。类型分布已由 Extensions 直方图覆盖，样本只负责语义，不需要多。

### 9.3 信号识别：机械的归脚本，语义的归 Agent

| 机械信号（正则可判，脚本完成） | 例子 |
|---|---|
| 日期 | `20\d{2}[-_. ]?\d{1,2}[-_. ]?\d{1,2}`、`2023年`、`2023Q1`、`202303` |
| 版本/副本 | final、最终、v2、第2版、-副本、-copy、(1)、new、修改稿 |
| 来源前缀 | IMG_、DSC、VID_、Screenshot、屏幕截图、WX_、微信、mmexport、qpic |
| 备份/历史 | backup、备份、old、旧、snapshot、快照、migration |

| 语义信号（只属于 Agent，从 NameSamples / SubDirs 归纳） | 回答的问题 |
|---|---|
| 客户/公司/项目名 | 这是谁的资料 |
| 人名 | 属于谁 |
| 事件（旅行/婚礼/课程/装修/会议） | 围绕什么事 |
| 设备与来源（旧手机/相机/微信/浏览器下载） | 从哪来的 |
| 业务领域（财务/设计/开发/法律） | 干什么用的 |
| 语言、编号体系（合同号/工单号/学号） | 命名习惯 |

机械信号只回答"这是什么形态"（版本、副本、来源、日期）；"这是谁的、关于什么"永远由 Agent 语义判断回答。两者在解读画像时同时进行，但不得混为一谈。

### 9.4 主题归纳规则

主题 = 用户心智里的一个"东西"：一个客户、一个项目、一次旅行、一台设备、一段工作经历、一个年份存档。

- 建立主题的证据链（至少满足其一，证据写入地图）：
  1. 同一实体（客户/项目/人名/事件名）在 ≥2 个路径出现（目录名或文件名）；
  2. 一个完全重复 Hash 组横跨多个目录——两处放着同一份文件，是强关联证据；
  3. 同实体 + 时间窗重叠（YearSpan 交叉）。
- **禁止仅凭扩展名分布建立主题**。"都是 jpg"不构成"照片事件"主题，只构成佐证；只靠类型相似归堆就是按类型整理。
- 宁可多个小主题 + 明确关联，不要"资料""杂项"大筐。出现大筐说明理解失败，应继续下钻或标 REVIEW。
- 同一主题出现在多个物理位置（客户A 的文件同时在 `Work\` 和 `旧电脑备份\` 里）不是矛盾：记为"同一主题的多个副本/层"，处置留给 plan 阶段。
- 命名无语义的目录（新建文件夹(2)、未命名、乱码时间戳名）：依次尝试 父目录归属 → 兄弟目录推断 → 时间聚类 → 9.7 内容抽样；全部失败 → 孤立内容。

### 9.5 语义地图 semantic-map.md

```markdown
# 语义地图：<TARGET>（文件数 / 容量 / 目录数 / 生成时间）

## 1. 全域概览
这堆资料整体是什么（例：一台 2015–2023 年的工作电脑备份 + 长期未清理的下载堆积），
时间跨度、主要语言、占容量 80% 的大块在哪。

## 2. 主题清单
### T01｜客户A｜工作项目｜HIGH
- 涉及路径：Work/客户A项目/（214 文件，2021–2023）
- 散文件关联：Downloads/客户A报价.xlsx、客户A合同.pdf
- 证据：目录名 + 6 个文件名含同一实体 + 1 个重复 Hash 组横跨两处
- 备注：内部 需求/报价/合同/screenshots 结构清晰，应整体保留

### T02｜2023 家庭旅行｜照片事件｜HIGH
### T03｜旧手机备份｜设备备份｜HIGH

## 3. 疑似主题（MEDIUM / LOW）
进入 plan 前需下钻或内容抽样确认；确认不了就不动。

## 4. 孤立内容
无法归入任何主题的文件/目录：来源不明、命名无语义、抽样失败。→ REVIEW

## 5. 备份与历史层
backup / 旧电脑 / 快照 各覆盖了哪些主题、代际关系（谁是更早的副本）。

## 6. 重复组 × 主题交叉
哪个 Hash 组属于哪个主题；主副本按主题归属选择（第 6 节）。

## 7. 内容抽样记录
读过了哪些文件、每个读到的结论。
```

### 9.6 大目录的规模策略

- 目录数 ≤ 500：画像全量读入理解。
- 500 ~ 5,000：先读 Depth ≤ 2 的行 + SizeMB 前 100 的行，主题需要时按路径前缀下钻。
- \> 5,000：按顶层子树分批，每批独立归纳主题，最后跨批合并（同实体、时间窗）。

无论哪种规模，都不把画像整表读入上下文，用过滤读：

```text
Windows: Import-Csv dir-profiles.csv | Where-Object { [int]$_.Depth -le 2 }
Unix:    awk -F'\t' '$2 <= 2' dir-profiles.tsv
```

覆盖纪律：任何 ≥ 1 GB 或 ≥ 50 文件的目录，最终不允许停留在"没看过"状态——必须归入主题、或标 REVIEW / PROTECTED。

### 9.7 内容抽样（最后手段）

仅当目录语义无法从元数据判断（NameSamples 全是无意义命名）时才读文件内容：

- 每个未理解目录最多抽 3 个文件、每个 ≤ 5 MB；
- 文本类（txt / md / csv / json / log / html）直接读；pdf / docx 用本机可用工具抽首页或前两段文本；
- 加密、压缩包、二进制读不出语义 → 停止抽样，标 REVIEW，不要猜；
- 抽过的文件与读到的结论记入 semantic-map.md §7，保持可追溯；
- 隐私边界不变：默认不把本地文件交给外部服务分类。

## 10. 目录与文件决策规则

**状态集**：`KEEP / MOVE / RENAME / MERGE / ARCHIVE / REVIEW / PROTECTED`。默认倾向 KEEP，而不是重新设计所有目录。

**语义判断**——先查语义地图 §2 / §3：这个目录已归入哪个主题、置信度多少。地图未覆盖时再依次问：它是不是一个项目？客户？组织？事件？一段工作经历？一套课程？一次旅行？一个设备备份？一个年份存档？一个软件？答案明显时，整个目录作为一个整体处理。

**不要把扩展名作为第一分类维度**。Documents\、Images\、Videos\、PDF\、Excel\、ZIP\ 这类结构会破坏上下文；优先按项目、客户、主题、组织、人物、事件、用途组织，文件类型只作辅助信息。

**碎片化主题**（客户A、客户A资料、客户A旧、客户A项目、客户A 2022、客户A-final…）：语义地图会把它们聚成同一主题的候选合并组，但不要见名字像就立即合并。先分析内容重叠程度、时间跨度、子目录结构、文件名、重复文件、文件版本，再决定合并成 `客户A\Projects\Documents\Archive\` 还是按 `客户A\2022\2023\` 分年——具体结构取决于已有内容。

**无意义重复嵌套**（Documents\Documents\、照片\照片\、Backup\Backup\、Downloads\Downloads\）：外层没有额外语义可考虑 COLLAPSE，但必须先检查文件冲突。

**散落文件**（根目录下直接躺着 客户A需求.pdf、客户A报价.xlsx、客户A合同.docx、客户A会议截图.png）：可以推断它们可能属于 客户A，但这是**语义推断不是确定事实**，计划中必须标 `Confidence = HIGH / MEDIUM / LOW`，证据写入语义地图 §2 对应主题条目。

**文档版本**（方案.docx、方案-final.docx、方案-final2.docx、方案-new.docx、方案修改.docx、方案最终版.docx）：Hash 不一致就禁止当重复文件删除，标 `POSSIBLE_VERSION_SET`，尽量放在一起，不自动删旧版本。

**压缩包**（Project.zip、Project-old.zip、Project-2023.zip、Archive.7z、Backup.rar）：不要因为解压目录已存在就自动删压缩包——它可能保存特定历史版本、是正式交付件、或内容不同。默认作为独立文件处理。

**照片与视频**：完全二进制相同才 EXACT_DUPLICATE；裁剪、调色、压缩、改分辨率、加水印、重新编码之后视为不同文件。项目内部图片留在项目里——`客户A\screenshots\` 里的 PNG 不因是图片就移去 Photos\。

**安装包**：散落的 `*.exe / *.msi / *.iso / *.img / *.dmg / *.pkg` 识别为 `SOFTWARE_INSTALLER`，确认是独立安装包后可集中到 Software\ 或 Archive\Software\。但应用目录内部的 exe、项目 build 输出、开发工具链、`*.app` bundle 内部文件不要动。

**临时文件**：`*.tmp、*.temp、*.bak、*.old、*.part、*.crdownload、~$*` 只能标 `TEMP_CANDIDATE`，不要看到扩展名就直接删。

## 11. 目标结构设计

- 层级保持 2~4 层，避免"类别/子类别/年份/月份/文件类型/文件"这种深塔。
- 顶层 4~12 个主要目录（不是硬限制）。优先复用用户原本已有的概念（Work、Projects、Personal、Photos、Reference、Software、Archive、Review，或 工作、项目、个人、照片、资料、软件、归档、待整理），不强制套模板。
- 顶层目录名优先沿用语义地图里主题的原始叫法（用户自己的词：客户A、2023旅行、旧手机），不发明用户没用过的新分类词——用户将来要靠自己的记忆找到它们。
- 中文目录保持中文，英文保持英文——不为"标准化"强制换语言。
- **Archive\** 收：完成多年且不再活跃的项目、旧工作资料、旧电脑历史文件、旧软件、历史导出、历史合同、已完成事件资料。子目录保持语义（`Archive\Previous Work\`、`Archive\Finished Projects\`、`Archive\Old Devices\`），不要 Old1\Old2\Misc\。
- **REVIEW**：无法可靠判断的内容优先**原地标记 REVIEW** 而不是大量搬进 Review\；只有整理方案确实需要集中待判断项时才创建 Review\ 目录。典型 REVIEW 场景：同名但 Hash 不同、疑似文档版本、不确定所属项目/客户、照片去留存疑、未知二进制格式、数据库文件、加密文件、应用数据、异常大文件、软件内部文件、不同历史备份之间的重复文件。不确定时**不移动**。

## 12. 整理计划 plan.csv

字段：`Action, Source, Destination, Reason, Confidence, Evidence, Category`。

Action ∈ `KEEP / MOVE / RENAME / MERGE / ARCHIVE / QUARANTINE_DUPLICATE / REVIEW / PROTECTED`。

Confidence ∈ `HIGH / MEDIUM / LOW`。**自动执行只允许 HIGH**；MEDIUM / LOW 保持不动或进入人工 Review。

Evidence 必须引用语义地图主题 ID（如 `semantic-map:T01`）加具体证据；没有主题支撑的 MOVE / MERGE 一律降为 REVIEW。

示例一（语义推断移动）：

```text
Action: MOVE
Source: D:\OldFiles\Downloads\客户A报价.xlsx
Destination: D:\OldFiles\Work\客户A\报价.xlsx
Reason: 文件名与同目录多个客户A资料高度一致，且目标客户目录已经存在
Confidence: HIGH
Evidence: semantic-map:T01（客户A主题：目录名 + 6 处文件名证据 + 重复Hash组）
```

示例二（确定性重复隔离）：

```text
Action: QUARANTINE_DUPLICATE
Source: D:\OldFiles\Downloads\proposal (1).pdf
Canonical: D:\OldFiles\Projects\Client-A\proposal.pdf
Reason: czkawka HASH exact duplicate
Confidence: HIGH
Evidence: semantic-map:T05 + duplicates Group 001
```

## 13. 应用计划（apply）

移动任何文件之前，必须先输出**摘要**：扫描范围、总文件数、总容量、顶层目录数；发现的完全重复组数、可释放重复空间、大文件、散落文件、碎片项目、备份目录、Protected 目录、Review 项数；建议的保留/移动/合并/归档目录数与隔离重复文件数；预计整理后的顶层目录。**不要在聊天中打印数万条文件路径**，详情写 plan.csv。

执行规则：

- 再次验证 Source 存在；Destination 已存在 → 记 `COLLISION`，停止当前操作并记录，禁止覆盖、禁止自动改名或加 `(1)`，其余安全操作继续。
- **COLLISION 比较必须忽略大小写**：NTFS 与默认 APFS 卷都是大小写不敏感文件系统，`Report.pdf` 与 `report.pdf` 进同一目录就是冲突。
- 能移动整个目录就不要逐个移动里面 500 个文件（`Downloads\Client-A-Project\` 整体 → `Work\Client-A\Client-A-Project\`）。
- 隔离保留原目录结构以便回溯原位置（如 `D:\OldDisk\Downloads\A\report.pdf` → `D:\OldDisk\_quarantine\2026-10-18\Downloads\A\report.pdf`）。
- 每个成功操作写 operations.csv：`Timestamp, Action, OriginalPath, NewPath, Reason, Hash`。
- 生成 undo 脚本（Windows 为 undo.ps1，Unix 为 undo.sh，NewPath → OriginalPath）。撤销时：(1) 检查新路径存在 (2) 创建原始父目录 (3) 检查原路径没有新文件 (4) 冲突则停止对应操作 (5) 禁止覆盖。
- 第一轮整理完成后只输出 Empty Directory Report，不自动删空目录——空目录本身有时包含历史结构信息。

## 14. 验证（verify）

核对：原始用户文件数、移动成功文件数、隔离重复文件数、失败操作数、剩余用户文件数，应大致满足：

```text
整理前用户文件 = 整理后普通用户文件 + quarantine 文件
```

（`_organizer` 内部生成文件不参与计算。）

**语义覆盖核对**：dir-profiles 中 ≥ 1 GB 或 ≥ 50 文件的目录，每个都必须有主题归属（semantic-map §2 / §3）或 REVIEW / PROTECTED 标记。未覆盖的大块列出来，回到 9.6 下钻补齐后再定处置——不允许"没看过"的大目录混过 verify。

然后重新执行一遍重复扫描（工具或降级脚本），输出 Remaining Exact Duplicate Groups。存在剩余重复不代表整理失败——备份快照、历史归档、protected project 中允许存在重复。

## 15. 性能、隐私与判断纪律

**性能顺序**（大型移动硬盘严禁一次把所有文件内容读给 LLM）：

```text
全量路径遍历（平台脚本一次产出 inventory + dir-profiles）→ 受保护目录识别 → 重复扫描（机械，可与画像并行）→ Agent 语义理解（读画像 → 主题 → 语义地图，必要时下钻与内容抽样）→ 计划
```

**LLM 默认只用元数据判断**：文件路径、文件名、扩展名、大小、时间戳、父目录、兄弟文件、目录结构、Hash。目录画像就是这些元数据的浓缩形态，是语义理解阶段的主食。只有仍无法确定文件语义时，才按 9.7 少量读取 PDF / Office / TXT / Markdown 内容。

**隐私**：默认不把本地文件上传到外部服务分类，一切在本机完成，除非用户明确允许。

**事实与推断必须分开**：

| 类别 | 例子 | 处理 |
|---|---|---|
| 确认事实 | 两个文件 SHA256 完全相同 | EXACT_DUPLICATE |
| 高概率推断 | "客户A报价.xlsx" 附近都是客户A资料 | 可用于计划，但仍是语义判断，标 Confidence |
| 不确定 | final.docx 与 最终版.docx 谁该删 | REVIEW，不动 |

## 16. 工具优先级与禁止事项

- 重复文件：czkawka / fclones（按平台优先级，见 tool-commands.md）→ 平台降级脚本（Length+大小分组 → SHA256/shasum）。
- 遍历与画像：平台脚本（scripts/…），不手写等价长命令。
- 移动：Windows 用 `Move-Item -LiteralPath`；Unix 用 `mv --`。文本与表格：PowerShell / awk。
- 删除唯一例外：`_organizer` 内部自己的临时文件；用户文件永不。

不要因为存在第三方工具就把整理控制权交给第三方工具。

绝对禁止：为整理而删除用户文件；仅根据名称判重复；仅根据时间判最新版；按扩展名拆散项目内部文件；仅凭扩展名分布建立主题；整理软件依赖目录；自动清理备份中的重复文件；未经计划批量移动；覆盖已有文件；自动删除空目录；为目录统一而大规模重命名文件；使用 czkawka / fclones 的任何删除、链接、移动类功能。

## 17. 最终报告格式

```text
扫描目录 D:\OldDisk

扫描结果
- 文件：48,213 / 总容量：612 GB / 顶层目录：137 / Protected 项目：21

语义理解
- 主题：14 个（HIGH 9 / MEDIUM 3 / LOW 2）｜覆盖 92% 文件 / 88% 容量
- 最大主题：客户A（1,204 文件 / 18 GB）、旧电脑备份（9,833 文件 / 210 GB）
- 未理解：231 文件 + 4 目录 → REVIEW（内容抽样失败 6 个）

重复文件
- Exact duplicate groups：1,243 / Duplicate files：4,812
- Potential reclaim：84 GB / Scanner：czkawka HASH

结构问题
- 散落文件：1,842 / 疑似碎片项目：23 / 历史备份：17
- 空目录：312 / 待确认项目：326

整理计划
- KEEP 31 目录 / MOVE 17 目录 / MERGE 8 组 / ARCHIVE 13 目录
- QUARANTINE_DUPLICATE 4,812 文件 / REVIEW 326 项

预计目录
D:\
├─ Work\
├─ Projects\
├─ Personal\
├─ Photos\
├─ Reference\
├─ Software\
├─ Archive\
└─ _quarantine\
```

（以上数字均为格式示例，按实际结果填写；路径分隔符按平台。）

## 18. 成功标准与核心目标

整理完成后，用户应能快速回答：这堆资料里到底有哪几摊东西（语义地图 §2 一页答完）？工作资料在哪？项目在哪？某个客户的资料在哪？个人资料在哪？照片在哪？已结束的项目在哪？历史电脑资料在哪？软件安装包在哪？哪些文件完全重复？哪些还需要我判断？这次 Agent 到底移动了什么？移动错了能不能恢复？——如果这些问题仍然很难回答，说明目录结构还没有真正整理完成。

最终目标不是文件最少、重复最少，也不是目录树最整齐，而是：

> 建立一个用户能够理解、能够维护、能够长期使用，并且可以安全恢复的文件系统结构。

Agent 负责理解、推断、规划、判断；czkawka / fclones / 平台脚本负责扫描、Hash、验证、执行确定性操作。保持这两个职责边界。
