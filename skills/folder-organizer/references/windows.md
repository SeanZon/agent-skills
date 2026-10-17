# Windows 平台细则（PowerShell）

## 执行本 Skill 脚本

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File inventory-and-profiles.ps1 -Target "D:\OldDisk"
powershell -NoProfile -ExecutionPolicy Bypass -File duplicates-fallback.ps1  -Target "D:\OldDisk"
```

本目录 `.ps1` 均为 **UTF-8 with BOM**：内含中文字符串与注释，无 BOM 时 Windows PowerShell 5.1 会按 ANSI 读而乱码。改写时保持 BOM；pwsh（7.x）无此问题，脚本两边兼容。

## PowerShell 5.1 的坑（脚本已处理；手写命令时同样要遵守）

- 枚举、Hash、导出、移动一律 `-LiteralPath`，不要 `-Path`——文件名里的 `[ ] * ?` 会被解释成通配符。
- `New-Item` 没有 `-LiteralPath`（5.1 与 7.x 都没有）——建目录用 `[IO.Directory]::CreateDirectory()`，天然不做通配符解析。
- `@($null).Count` 是 1 不是 0——数组判空用 `Measure-Object` 或显式判 `$null`。
- `Export-Csv -Encoding UTF8` 在 5.1 下带 BOM（Excel 友好；`Import-Csv` 两版本都能读）。

## Reparse Point（Junction / Symlink）

`Get-ChildItem -Recurse` 会穿透 Junction，导致重复扫描、目录环、越出目标目录。枚举后过滤：

```powershell
$_.Attributes -band [IO.FileAttributes]::ReparsePoint
```

## 错误容忍（单个失败不终止整体）

- 单个文件：无权限、被占用、Hash 读取失败、路径过长（>260，除非系统开启长路径支持）——记入 errors*.csv 继续。
- czkawka"发现重复文件"的特殊退出码不算失败（参考 `-W` 参数）。

## Windows 受保护目录（决策规则见 SKILL.md 第 7 节）

- System Volume Information、`$RECYCLE.BIN`、Recovery、Config.Msi——禁止整理。
- desktop.ini / Thumbs.db 属系统文件：语义理解时忽略，不作为整理对象。
