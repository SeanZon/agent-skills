# agent-skills

个人的 Agent Skills 合集,适用于任何支持 Agent Skills 的编码助手(Claude Code、ZCode、Codex CLI、Kimi Code 等)。每个 skill 一个目录,放在 `skills/` 下。

## Skills

| Skill | 简介 | 平台 | 状态 |
|---|---|---|---|
| [folder-organizer](skills/folder-organizer/) | 语义化整理本地文件夹、移动硬盘、旧电脑迁移与历史备份目录:全量遍历 + 目录画像 + 主题地图,先理解后整理;重复检测复用 Czkawka / fclones 并可降级 SHA256 脚本;只隔离不删除,全程可回滚 | macOS / Linux / Windows | macOS 实测通过 |

## 安装

```bash
# 安装单个 skill(推荐,装进当前项目 .agents/skills/)
npx skills add https://github.com/SeanZon/agent-skills/tree/main/skills/folder-organizer

# 或手动:git clone 后把 skills/<name> 目录复制到技能目录
#   项目级: .agents/skills/<name>/
#   用户级: ~/.agents/skills/<name>/
#   Claude Code 用户级: ~/.claude/skills/<name>/
git clone https://github.com/SeanZon/agent-skills.git
```

## 仓库结构

```text
agent-skills/
└─ skills/
   └─ folder-organizer/   ← 每个 skill 一个目录:SKILL.md + references/ + scripts/
```

新增 skill 时在 `skills/` 下建同名目录,并在上方表格加一行。

## 这些 skill 的共同原则

- **安全优先**:修改类操作必须先出计划、可回滚;永不直接删除用户文件
- **无硬依赖**:优先复用本机已有工具,缺失时自动降级到自带脚本,不要求安装
- **平台自适应**:macOS / Linux / Windows 各有原生实现,行为与产出字段一致
- **先理解后动手**:决策基于对内容的理解(语义、上下文),不套固定模板

各 skill 的详细说明、已知限制见其目录内 README。
