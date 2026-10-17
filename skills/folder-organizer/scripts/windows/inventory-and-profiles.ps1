# folder-organizer · Windows 脚本 1/2：文件清单 + 目录画像
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File inventory-and-profiles.ps1 -Target "D:\OldDisk"
# 产出（写入 <Target>\_organizer\）：
#   inventory.csv     FullName,DirectoryName,Name,Extension,Length,CreationTimeUtc,LastWriteTimeUtc,Attributes
#   dir-profiles.csv  RelativePath,Depth,FileCount,SizeMB,Extensions,YearSpan,SubDirs,NameSamples,Protected
#   errors.csv        遍历错误（单个失败不终止整体）
# 本脚本只读，绝不移动/删除/重命名任何用户文件。平台细则见 references/windows.md。
# 本文件为 UTF-8 with BOM，请勿用会去掉 BOM 的方式改写（Windows PowerShell 5.1 会乱码）。

param(
    [Parameter(Mandatory = $true)]
    [string]$Target
)

if (-not (Test-Path -LiteralPath $Target)) { throw "目标目录不存在：$Target" }
$Target = [IO.Path]::GetFullPath($Target).TrimEnd('\')
$Workspace = Join-Path $Target '_organizer'
[IO.Directory]::CreateDirectory($Workspace) | Out-Null

$errors = New-Object System.Collections.Generic.List[object]

# ---- 1. 文件清单（单次遍历，画像直接复用内存结果） ----
$walkErr = $null
$files = @(Get-ChildItem -LiteralPath $Target -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable walkErr |
    Where-Object {
        $_.FullName -notlike "$Target\_organizer*" -and
        $_.FullName -notlike "$Target\_quarantine*"
    })
foreach ($e in @($walkErr)) { $errors.Add([PSCustomObject]@{ Phase = 'walk'; Item = ''; Error = $e.Exception.Message }) }

$files |
    Select-Object FullName, DirectoryName, Name, Extension, Length,
        CreationTimeUtc, LastWriteTimeUtc, Attributes |
    Export-Csv -LiteralPath "$Workspace\inventory.csv" -NoTypeInformation -Encoding UTF8

# ---- 2. 目录画像 ----
$dirErr = $null
$allDirs = @(Get-ChildItem -LiteralPath $Target -Recurse -Directory -Force -ErrorAction SilentlyContinue -ErrorVariable dirErr |
    Where-Object {
        $_.FullName -notlike "$Target\_organizer*" -and
        $_.FullName -notlike "$Target\_quarantine*"
    })
foreach ($e in @($dirErr)) { $errors.Add([PSCustomObject]@{ Phase = 'dirs'; Item = ''; Error = $e.Exception.Message }) }

$filesByDir   = @{}
foreach ($g in ($files | Group-Object -Property DirectoryName))   { $filesByDir[$g.Name]   = $g.Group }
$dirsByParent = @{}
foreach ($g in ($allDirs | Group-Object -Property { $_.Parent.FullName })) { $dirsByParent[$g.Name] = $g.Group }

$protectedNames = @('node_modules', '.venv', 'venv', 'vendor', 'dist', 'build', 'target', '.next', '.nuxt', 'coverage', '.git')

function New-DirProfile([string]$dirFullName, [string]$relPath, [int]$depth) {
    $df = @($filesByDir[$dirFullName]);   if ($df.Count -eq 1 -and $null -eq $df[0])   { $df = @() }
    $sub = @($dirsByParent[$dirFullName]); if ($sub.Count -eq 1 -and $null -eq $sub[0]) { $sub = @() }
    $years = @($df | ForEach-Object { $_.LastWriteTimeUtc.Year } | Sort-Object -Unique)
    $leaf = Split-Path -Leaf $relPath
    [PSCustomObject]@{
        RelativePath = $relPath
        Depth        = $depth
        FileCount    = $df.Count
        SizeMB       = [math]::Round((($df | Measure-Object Length -Sum).Sum) / 1MB, 2)
        Extensions   = (($df | Group-Object Extension | Sort-Object Count -Descending |
                        Select-Object -First 6 | ForEach-Object {
                            '{0}x{1}' -f ($_.Name -replace '^\.?$', '(无扩展名)'), $_.Count
                        }) -join ' ')
        YearSpan     = if ($years.Count -gt 0) { '{0}-{1}' -f $years[0], $years[-1] } else { '' }
        SubDirs      = ($sub | Sort-Object Name | Select-Object -First 12 -ExpandProperty Name) -join ' | '
        NameSamples  = ($df | Sort-Object Name | Select-Object -First 15 -ExpandProperty Name) -join ' | '
        Protected    = if ($protectedNames -contains $leaf) { 'TRUE' } else { '' }
    }
}

$dirProfiles = New-Object System.Collections.Generic.List[object]
$dirProfiles.Add((New-DirProfile $Target '.' 0))   # 根目录 Depth=0，NameSamples 即散落在根下的文件
foreach ($d in $allDirs) {
    $rel = $d.FullName.Substring($Target.Length + 1)
    $depth = ([regex]::Matches($d.FullName.Substring($Target.Length), '\\')).Count
    $dirProfiles.Add((New-DirProfile $d.FullName $rel $depth))
}

# 依赖/构建目录内部不出画像行（标记目录本身保留一行并标 Protected，见 SKILL.md 第 7/9 节）
$deepProtected = '\\(node_modules|\.venv|venv|vendor|dist|build|target|\.next|\.nuxt|coverage|\.git)\\'
$dirProfiles |
    Where-Object { $_.RelativePath -notmatch $deepProtected } |
    Sort-Object RelativePath |
    Export-Csv -LiteralPath "$Workspace\dir-profiles.csv" -NoTypeInformation -Encoding UTF8

if ($errors.Count -gt 0) {
    $errors | Export-Csv -LiteralPath "$Workspace\errors.csv" -NoTypeInformation -Encoding UTF8
}

Write-Output ("inventory: {0} files" -f $files.Count)
Write-Output ("dirs profiled: {0} (before deep-protected filter)" -f $dirProfiles.Count)
Write-Output ("walk errors: {0}" -f $errors.Count)
Write-Output "outputs: $Workspace\inventory.csv ; $Workspace\dir-profiles.csv"
