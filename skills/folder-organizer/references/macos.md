# macOS / Linux 平台细则（bash）

## 执行本 Skill 脚本

```sh
bash inventory-and-profiles.sh /path/to/target
bash duplicates-fallback.sh   /path/to/target   # 需先跑上面那个
```

输出为 **TSV（制表符分隔）**：shell 下做 CSV 转义既繁琐又易错，TSV 与 Windows 版 CSV 字段一一对应。读取用 `awk -F'\t'`。

## bash / awk 版本约束

- 系统自带 bash 是 3.2（无关联数组、无 mapfile）——本 Skill 脚本只用 POSIX + 普通数组，聚合逻辑全部交给 awk；手写命令时同样不要用 bash 4 特性。
- awk 用系统自带（BWK awk）：无 asort / strftime 等 gawk 专有函数，不要用。

## BSD 与 GNU 差异（脚本已自适应；手写命令时注意）

- `stat`：macOS 是 BSD stat（`-f '%z %m %B'`，`%Sm` 配 `-t` 定制时间格式）；Linux / git-bash 是 GNU stat（`-c '%s %Y %W'`）。两套 flag 互不通用，先探测再用。
- `find`：本 Skill 用法两边一致（`-prune` / `-exec {} +`）；不要用 `-regextype` 等 GNU 专有项。
- 排序一律 `LC_ALL=C sort`（字节序），保证采样确定、两次运行结果一致。
- Hash：`shasum -a 256`（macOS 自带）或 `sha256sum`（Linux）；都不需要额外安装。

## 安装来源（仅在用户主动同意时安装）

- fclones：`brew install fclones`（macOS 首选扫描器）
- czkawka：`brew install czkawka`（CLI 名为 czkawka_cli）

## macOS 特有的剪枝与保护

脚本已从清单中排除（系统噪音，不是用户资料）：

- 文件级：`.DS_Store`、`._*`（AppleDouble 资源文件）
- 目录级：`.Spotlight-V100`、`.Trashes`、`.fseventsd`、`.DocumentRevisions-V100`、`.TemporaryItems`

决策规则（见 SKILL.md 第 7 节）需要知道的 macOS 对象：

- **Time Machine**：`Backups.backupdb`、`*.backupbundle`——整体按"备份快照"规则，内部重复标 `DUPLICATE_IN_BACKUP` + `REVIEW`，不自动隔离。
- **应用与图库包（bundle）**：`*.app`、`*.photoslibrary`、`*.musiclibrary`、`*.tvlibrary`、`*.vault`、`*.vmwarevm`——整个 bundle 视为一个逻辑对象，不整理内部内容。
- **系统位置**：`/System`、根级 `/Library`、SIP 保护路径——禁止整理；`~/Library` 默认跳过（应用数据），用户明确要求才碰。
- **权限**：访问 `~/Library/Mail`、Photos 图库等需要终端具备"完全磁盘访问权限"；报权限错误时如实说明并跳过，不要绕过系统保护。

## 文件系统语义

- APFS 默认卷**大小写不敏感**（NTFS 同理）：apply 阶段的 COLLISION 检查必须按"忽略大小写"比较目标路径——`Report.pdf` 与 `report.pdf` 放进同一目录就是冲突。
- 符号链接：Unix 下 `find` 默认不跟随符号链接，目录环与越界天然防护；手写命令不要加 `-L`。

## 已知限制（Unix 脚本）

- 文件名包含换行符的文件不被支持（清单与判重都会错位）——遇到这类目标直接用 fclones / czkawka。
