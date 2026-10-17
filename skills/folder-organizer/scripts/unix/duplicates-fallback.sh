#!/bin/bash
# folder-organizer · Unix 脚本 2/2：重复检测降级方案（fclones / czkawka 都不可用时）
# 用法：  ./duplicates-fallback.sh /path/to/target
# 前置：  先运行 inventory-and-profiles.sh（本脚本读取其产出的 inventory.tsv）
# 产出（写入 <target>/_organizer/）：
#   duplicates-fallback.tsv   Group,Hash,Size,FullName（仅"大小相同 + SHA256 相同"的组）
#   zero-byte.tsv             零字节文件（占位/状态文件，单独报告，不判重）
#   errors-duplicates.log     Hash 失败记录（单个失败不终止整体）
# 本脚本只读，绝不移动/删除/重命名任何用户文件。禁止在此脚本上加删除逻辑。
# 已知限制：文件名包含换行符的文件不被支持（用 fclones / czkawka 代替本脚本）。

set -u

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "usage: $0 <target-dir>" >&2; exit 2; }
[ -d "$TARGET" ] || { echo "target not found: $TARGET" >&2; exit 2; }
TARGET=$(cd "$TARGET" && pwd) || exit 2
WS="$TARGET/_organizer"
[ -f "$WS/inventory.tsv" ] || { echo "inventory.tsv not found - run inventory-and-profiles.sh first" >&2; exit 2; }
TMP="$WS/tmp"
mkdir -p "$TMP" || exit 1

TAB=$(printf '\t')
export LC_ALL=C

# 零字节文件：占位、程序状态、同步标记，不能按 Hash 归为普通重复
awk -F"$TAB" '$1 + 0 == 0' "$WS/inventory.tsv" > "$WS/zero-byte.tsv"

# 第一步：找出出现次数 >1 的大小值；第二步：取出这些大小的候选文件
awk -F"$TAB" '{ if ($1 + 0 > 0) sz[$1]++ } END { for (s in sz) if (sz[s] > 1) print s }' "$WS/inventory.tsv" > "$TMP/dupsizes.tsv"
awk -F"$TAB" 'NR == FNR { dup[$1] = 1; next } dup[$1] { print $5 }' "$TMP/dupsizes.tsv" "$WS/inventory.tsv" > "$TMP/candidates.tsv"

# 第三步：仅对候选计算 SHA256（shasum 优先，sha256sum 兜底；NUL 分隔交给 xargs 批量执行）
: > "$TMP/hashes.raw"
: > "$WS/errors-duplicates.log"
if [ -s "$TMP/candidates.tsv" ]; then
  if command -v shasum >/dev/null 2>&1; then
    tr '\n' '\0' < "$TMP/candidates.tsv" | xargs -0 shasum -a 256 >> "$TMP/hashes.raw" 2>> "$WS/errors-duplicates.log"
  elif command -v sha256sum >/dev/null 2>&1; then
    tr '\n' '\0' < "$TMP/candidates.tsv" | xargs -0 sha256sum >> "$TMP/hashes.raw" 2>> "$WS/errors-duplicates.log"
  else
    echo "no sha256 tool found (shasum / sha256sum)" >&2
    exit 3
  fi
fi

# 第四步：SHA256 输出固定为 64 位十六进制 + 两个空格 + 路径
# 先按 Hash 分组、只留成员 >1 的组；再从 inventory 回填大小、编组号（按 Hash 排序，两次运行一致）
sort "$TMP/hashes.raw" |
  awk -v OFS="$TAB" '
    { h = substr($0, 1, 64); p = substr($0, 67)
      if (h != cur) { if (cur != "" && n > 1) for (i = 1; i <= n; i++) print buf[i]
                      cur = h; n = 0 }
      n++; buf[n] = h OFS p }
    END { if (cur != "" && n > 1) for (i = 1; i <= n; i++) print buf[i] }' > "$TMP/groups.tsv"

if [ -s "$TMP/groups.tsv" ]; then
  awk -F"$TAB" -v OFS="$TAB" '
    NR == FNR { sz[$5] = $1; next }
    { if ($1 != cur) { cur = $1; gi++ }
      printf "T%03d", gi
      print "", $1, sz[$2] + 0, $2 }' "$WS/inventory.tsv" "$TMP/groups.tsv" > "$WS/duplicates-fallback.tsv"
else
  : > "$WS/duplicates-fallback.tsv"
fi

DUPG=$(awk -F"$TAB" '{ print $1 }' "$WS/duplicates-fallback.tsv" | sort -u | wc -l | tr -d ' ')
DUPF=$(wc -l < "$WS/duplicates-fallback.tsv" | tr -d ' ')
ZERO=$(wc -l < "$WS/zero-byte.tsv" | tr -d ' ')
echo "exact duplicate groups: $DUPG / files in groups: $DUPF"
echo "zero-byte files: $ZERO"
echo "outputs: $WS/duplicates-fallback.tsv ; $WS/zero-byte.tsv"
