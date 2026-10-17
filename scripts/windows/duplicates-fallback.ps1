# folder-organizer · Windows 脚本 2/2：重复检测降级方案（czkawka / fclones 都不可用时）
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File duplicates-fallback.ps1 -Target "D:\OldDisk"
# 产出（写入 <Target>\_organizer\）：
#   duplicates-fallback.csv   Group,Hash,Size,FullName（仅"Length 相同 + SHA256 相同"的组）
#   zero-byte.csv             零字节文件（占位/状态文件，单独报告，不判重）
#   errors-duplicates.csv     读取/Hash 失败（单个失败不终止整体）
# 本脚本只读，绝不移动/删除/重命名任何用户文件。禁止在此脚本上加删除逻辑。
# 本文件为 UTF-8 with BOM，请勿用会去掉 BOM 的方式改写。

param(
    [Parameter(Mandatory = $true)]
    [string]$Target
)

if (-not (Test-Path -LiteralPath $Target)) { throw "目标目录不存在：$Target" }
$Target = [IO.Path]::GetFullPath($Target).TrimEnd('\')
$Workspace = Join-Path $Target '_organizer'
[IO.Directory]::CreateDirectory($Workspace) | Out-Null

$errors = New-Object System.Collections.Generic.List[object]

$walkErr = $null
$files = @(Get-ChildItem -LiteralPath $Target -Recurse -File -Force -ErrorAction SilentlyContinue -ErrorVariable walkErr |
    Where-Object {
        $_.FullName -notlike "$Target\_organizer*" -and
        $_.FullName -notlike "$Target\_quarantine*"
    })
foreach ($e in @($walkErr)) { $errors.Add([PSCustomObject]@{ Phase = 'walk'; Item = ''; Error = $e.Exception.Message }) }

# 零字节文件：占位、程序状态、同步标记，不能按 Hash 归为普通重复
$files | Where-Object { $_.Length -eq 0 } |
    Select-Object FullName, Length, LastWriteTimeUtc |
    Export-Csv -LiteralPath "$Workspace\zero-byte.csv" -NoTypeInformation -Encoding UTF8

# 第一步：按大小分组（大小不同必不重复，避免全量 Hash）
$candidates = @($files | Where-Object { $_.Length -gt 0 } | Group-Object Length |
    Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Group })

# 第二步：仅对候选计算 SHA256
$hashed = foreach ($f in $candidates) {
    try {
        $h = Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256
        [PSCustomObject]@{ Hash = $h.Hash; Size = $f.Length; FullName = $f.FullName }
    } catch {
        $errors.Add([PSCustomObject]@{ Phase = 'hash'; Item = $f.FullName; Error = $_.Exception.Message })
    }
}

# 第三步：Hash 相同 + 大小相同 = EXACT_DUPLICATE；按 Hash 排序保证组号确定性、两次运行一致
$groups = @($hashed | Group-Object Hash | Where-Object { $_.Count -gt 1 } | Sort-Object Name)
$rows = for ($i = 0; $i -lt $groups.Count; $i++) {
    foreach ($f in ($groups[$i].Group | Sort-Object FullName)) {
        [PSCustomObject]@{
            Group    = 'T{0:D3}' -f ($i + 1)
            Hash     = $groups[$i].Name
            Size     = $f.Size
            FullName = $f.FullName
        }
    }
}
$rows = @($rows)
$rows | Export-Csv -LiteralPath "$Workspace\duplicates-fallback.csv" -NoTypeInformation -Encoding UTF8

if ($errors.Count -gt 0) {
    $errors | Export-Csv -LiteralPath "$Workspace\errors-duplicates.csv" -NoTypeInformation -Encoding UTF8
}

Write-Output ("files scanned: {0} / hash candidates: {1}" -f $files.Count, $candidates.Count)
Write-Output ("exact duplicate groups: {0} / files in groups: {1}" -f $groups.Count, ($rows | Measure-Object).Count)
Write-Output "outputs: $Workspace\duplicates-fallback.csv ; $Workspace\zero-byte.csv"
