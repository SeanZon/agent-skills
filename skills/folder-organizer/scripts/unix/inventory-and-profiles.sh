#!/bin/bash
# folder-organizer · Unix 脚本 1/2：文件清单 + 目录画像（macOS / Linux / git-bash 通用，bash 3.2 兼容）
# 用法：  ./inventory-and-profiles.sh /path/to/target
# 产出（写入 <target>/_organizer/）：
#   inventory.tsv     size, mtime(epoch), birth(epoch 或 "-"), year, path —— 制表符分隔
#   dir-profiles.tsv  RelativePath, Depth, FileCount, SizeMB, Extensions, YearSpan, SubDirs, NameSamples, Protected
#   errors.log        遍历错误（单个失败不终止整体）
# 字段含义与 Windows 版 CSV 一致，只是分隔符为 TAB（避开 shell 下的 CSV 转义）。
# 本脚本只读，绝不移动/删除/重命名任何用户文件。平台细则见 references/macos.md。
# 已知限制：文件名包含换行符的文件不被支持（用 fclones / czkawka 代替本脚本）。

set -u

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "usage: $0 <target-dir>" >&2; exit 2; }
[ -d "$TARGET" ] || { echo "target not found: $TARGET" >&2; exit 2; }
TARGET=$(cd "$TARGET" && pwd) || exit 2
[ "$TARGET" = "/" ] && { echo "refuse to organize filesystem root" >&2; exit 2; }
WS="$TARGET/_organizer"
TMP="$WS/tmp"
mkdir -p "$WS" "$TMP" || exit 1

TAB=$(printf '\t')
export LC_ALL=C   # 排序按字节序：保证采样确定性、两次运行结果一致

# 剪枝目录：整理工作区 + macOS 系统噪音（Linux/git-bash 下通常不存在，条件无害）
# 注意末尾必须带 -prune：只匹配不剪枝的话 find 仍会递归进去
PRUNE=( \( -name '_organizer' -o -name '_quarantine' -o -name '.Spotlight-V100' \
           -o -name '.Trashes' -o -name '.fseventsd' -o -name '.DocumentRevisions-V100' \
           -o -name '.TemporaryItems' -o -name 'Backups.backupdb' \) -prune )

# ---- 1. inventory.tsv：size, mtime, birth, year, path ----
# BSD stat（macOS）与 GNU stat（Linux / git-bash）自适应；year 字段两者分别为 4 位年份 / 完整日期，下游 awk 统一取前 4 位
: > "$WS/inventory.tsv"
: > "$WS/errors.log"
if stat -f '%m' / >/dev/null 2>&1; then
  find "$TARGET" "${PRUNE[@]}" -o \( -type f ! -name '.DS_Store' ! -name '._*' \
    -exec stat -f "%z${TAB}%m${TAB}%B${TAB}%Sm${TAB}%N" -t '%Y' {} + \
    >> "$WS/inventory.tsv" 2>> "$WS/errors.log" \)
else
  find "$TARGET" "${PRUNE[@]}" -o \( -type f ! -name '.DS_Store' ! -name '._*' \
    -exec stat -c "%s${TAB}%Y${TAB}%W${TAB}%y${TAB}%n" {} + \
    >> "$WS/inventory.tsv" 2>> "$WS/errors.log" \)
fi

SKIP=$(( ${#TARGET} + 2 ))   # 相对路径起始字节位置（跳过 "$TARGET/"）

# ---- 2. 目录清单（含空目录；根目录记为 "."）----
find "$TARGET" "${PRUNE[@]}" -o -type d -print |
  awk -v base="$TARGET" -v OFS="$TAB" \
    '{ if ($0 == base) print "."; else print substr($0, length(base) + 2) }' > "$TMP/dirs.tsv"

# 深度表：dir, depth
awk -F"$TAB" -v OFS="$TAB" '
  { d = $1; dep = (d == ".") ? 0 : 1; while (match(d, /\/[^\/]*$/)) { dep++; d = substr(d, 1, RSTART - 1) }
    print $1, dep }' "$TMP/dirs.tsv" > "$TMP/dirs2.tsv"

# 子目录聚合：每目录子目录名前 12（按名称排序，" | " 连接）
awk -F"$TAB" -v OFS="$TAB" '
  $1 != "." { p = $1; if (sub(/\/[^\/]*$/, "", p) == 0) p = "."
              n = $1; sub(/.*\//, "", n); print p, n }' "$TMP/dirs2.tsv" |
  sort -t"$TAB" -k1,1 -k2,2 |
  awk -F"$TAB" -v OFS="$TAB" '
    { if ($1 != cur) { if (cur != "") print cur, acc; cur = $1; acc = $2; n = 1 }
      else if (n < 12) { acc = acc " | " $2; n++ } }
    END { if (cur != "") print cur, acc }' > "$TMP/subdirj.tsv"

# ---- 3. 每目录统计：dir, depth, filecount, sizemb, yearspan ----
# 同时产出 flat-ext.tsv（dir, ext, count）供直方图排序
awk -F"$TAB" -v OFS="$TAB" -v skip=$SKIP -v tmpdir="$TMP" '
  { size = $1 + 0
    rel = substr($5, skip)
    d = rel; if (sub(/\/[^\/]*$/, "", d) == 0) d = "."
    name = rel; sub(/.*\//, "", name)
    n2 = name; sub(/^\./, "", n2)
    if (match(n2, /\.[^.]+$/)) ext = substr(n2, RSTART, RLENGTH); else ext = "(无扩展名)"
    cnt[d]++; byt[d] += size
    yr = substr($4, 1, 4)
    if (yr ~ /^[0-9][0-9][0-9][0-9]$/) {
      if (!(d in ymin)) { ymin[d] = yr; ymax[d] = yr }
      else { if (yr < ymin[d]) ymin[d] = yr; if (yr > ymax[d]) ymax[d] = yr }
    }
    ecnt[d SUBSEP ext]++
  }
  END {
    for (d in cnt) {
      ys = (d in ymin) ? ymin[d] "-" ymax[d] : ""
      mb = sprintf("%.2f", byt[d] / 1048576)
      dep = (d == ".") ? 0 : 1; tmp = d
      while (match(tmp, /\/[^\/]*$/)) { dep++; tmp = substr(tmp, 1, RSTART - 1) }
      print d, dep, cnt[d], mb, ys
    }
    for (k in ecnt) { split(k, a, SUBSEP); print a[1], a[2], ecnt[k] > (tmpdir "/flat-ext.tsv") }
  }' "$WS/inventory.tsv" > "$TMP/stats.tsv"

# 扩展名直方图：每目录前 6，形如 ".pdfx2 .xlsxx1"
sort -t"$TAB" -k1,1 -k3,3nr "$TMP/flat-ext.tsv" |
  awk -F"$TAB" -v OFS="$TAB" '
    { piece = $2 "x" $3
      if ($1 != cur) { if (cur != "") print cur, acc; cur = $1; acc = piece; n = 1 }
      else if (n < 6) { acc = acc " " piece; n++ } }
    END { if (cur != "") print cur, acc }' > "$TMP/extj.tsv"

# 文件名样本：每目录按名称排序前 15，" | " 连接（确定性采样）
awk -F"$TAB" -v OFS="$TAB" -v skip=$SKIP '
  { rel = substr($5, skip)
    d = rel; if (sub(/\/[^\/]*$/, "", d) == 0) d = "."
    n = rel; sub(/.*\//, "", n)
    print d, n }' "$WS/inventory.tsv" |
  sort -t"$TAB" -k1,1 -k2,2 |
  awk -F"$TAB" -v OFS="$TAB" '
    { if ($1 != cur) { if (cur != "") print cur, acc; cur = $1; acc = $2; n = 1 }
      else if (n < 15) { acc = acc " | " $2; n++ } }
    END { if (cur != "") print cur, acc }' > "$TMP/samplesj.tsv"

# ---- 4. 汇总成 dir-profiles.tsv：主键来自 dirs2（空目录也有行）----
# 依赖/构建目录内部不出画像行（标记目录本身保留一行并标 Protected，见 SKILL.md 第 7/9 节）
awk -F"$TAB" -v OFS="$TAB" -v tmpdir="$TMP" '
  FILENAME == tmpdir "/dirs2.tsv"    { key[$1] = 1; dep[$1] = $2; next }
  FILENAME == tmpdir "/stats.tsv"    { cnt[$1] = $3; mb[$1] = $4; ys[$1] = $5; next }
  FILENAME == tmpdir "/extj.tsv"     { eh[$1] = $2; next }
  FILENAME == tmpdir "/samplesj.tsv" { sm[$1] = $2; next }
  FILENAME == tmpdir "/subdirj.tsv"  { sd[$1] = $2; next }
  END {
    for (d in key) {
      if (d ~ /(^|\/)(node_modules|\.venv|venv|vendor|dist|build|target|\.next|\.nuxt|coverage|\.git)\//) continue
      base = d; sub(/.*\//, "", base)
      prot = ""
      if (base == "node_modules" || base == ".venv" || base == "venv" || base == "vendor" || \
          base == "dist" || base == "build" || base == "target" || base == ".next" || \
          base == ".nuxt" || base == "coverage" || base == ".git") prot = "TRUE"
      print d, dep[d] + 0, cnt[d] + 0, (d in mb) ? mb[d] : "0.00", \
            (d in eh) ? eh[d] : "", (d in ys) ? ys[d] : "", (d in sd) ? sd[d] : "", (d in sm) ? sm[d] : "", prot
    }
  }' "$TMP/dirs2.tsv" "$TMP/stats.tsv" "$TMP/extj.tsv" "$TMP/samplesj.tsv" "$TMP/subdirj.tsv" |
  sort -t"$TAB" -k1,1 > "$WS/dir-profiles.tsv"

rm -f "$TMP/flat-ext.tsv"   # 体积最大的中间文件，其余 tmp 保留备查

FILES=$(wc -l < "$WS/inventory.tsv" | tr -d ' ')
DIRS=$(wc -l < "$TMP/dirs2.tsv" | tr -d ' ')
ERRS=$(wc -l < "$WS/errors.log" | tr -d ' ')
echo "inventory: $FILES files"
echo "dirs profiled: $DIRS"
echo "walk errors: $ERRS"
echo "outputs: $WS/inventory.tsv ; $WS/dir-profiles.tsv"
