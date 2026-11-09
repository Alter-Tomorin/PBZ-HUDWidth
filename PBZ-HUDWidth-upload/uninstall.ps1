# PBZ_HUDWidth 卸载脚本
# 只移除本 Mod，不动 UE4SS 本体和其他 Mod
# 用法：powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
# 需要手动指定游戏目录时加 -GameDir "你的 PBZ 目录"

param([string]$GameDir = "")

$ErrorActionPreference = "Stop"

# ---------- 自动寻找游戏目录 ----------
function Find-GameDir {
    $cands = @(
        "C:\Program Files (x86)\Steam\steamapps\common\PBZ",
        "D:\Steam\steamapps\common\PBZ",
        "E:\Steam\steamapps\common\PBZ",
        "C:\SteamLibrary\steamapps\common\PBZ",
        "D:\SteamLibrary\steamapps\common\PBZ",
        "E:\SteamLibrary\steamapps\common\PBZ",
        "F:\SteamLibrary\steamapps\common\PBZ"
    )
    foreach ($vdf in @("C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf",
                       "D:\Steam\steamapps\libraryfolders.vdf",
                       "E:\Steam\steamapps\libraryfolders.vdf")) {
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $p = $m.Groups[1].Value.Replace('\\', '\')
                $cands += (Join-Path $p "steamapps\common\PBZ")
            }
        }
    }
    foreach ($c in $cands) {
        if (Test-Path (Join-Path $c "platform\steam\PBZ.exe")) { return $c }
    }
    return ""
}

if ([string]::IsNullOrWhiteSpace($GameDir)) { $GameDir = Find-GameDir }
if ([string]::IsNullOrWhiteSpace($GameDir)) {
    throw "没能自动找到游戏目录。请带 -GameDir 参数重新运行本脚本，指定你的 PBZ 目录。"
}

$modName = "PBZ_HUDWidth"
$modsDir = Join-Path $GameDir "platform\steam\ue4ss\Mods"
$dstMod  = Join-Path $modsDir $modName
$ts      = Get-Date -Format "yyyyMMdd-HHmmss"

function Read-ModList([string]$path) {
    $raw = [System.IO.File]::ReadAllText($path)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $obj = ConvertFrom-Json $raw
    if ($obj -is [System.Array]) { return @($obj) }
    if ($obj.PSObject.Properties.Name -contains "value") { return @($obj.value) }
    return @($obj)
}

function Write-ModList([string]$path, $list) {
    $items = @($list)
    if ($items.Count -eq 0) {
        [System.IO.File]::WriteAllText($path, "[]", (New-Object System.Text.UTF8Encoding($false)))
        return
    }
    $json = $items | ConvertTo-Json -Depth 5
    if (-not $json.TrimStart().StartsWith("[")) {
        $json = "[" + [Environment]::NewLine + $json + [Environment]::NewLine + "]"
    }
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# 1. 从 mods.json 里移除
$jsonPath = Join-Path $modsDir "mods.json"
if (Test-Path $jsonPath) {
    Copy-Item $jsonPath "$jsonPath.bak-$ts" -Force
    $kept = @()
    foreach ($m in (Read-ModList $jsonPath)) {
        if ($m.mod_name -ne $modName) { $kept += $m }
    }
    Write-ModList $jsonPath $kept
    Write-Output ("[1/3] mods.json 已移除条目（备份: mods.json.bak-$ts）")
} else {
    Write-Output "[1/3] 未找到 mods.json，跳过"
}

# 2. 从 mods.txt 里移除
$txtPath = Join-Path $modsDir "mods.txt"
if (Test-Path $txtPath) {
    Copy-Item $txtPath "$txtPath.bak-$ts" -Force
    $lines = [System.IO.File]::ReadAllLines($txtPath) |
             Where-Object { $_ -notmatch "^\s*$modName\s*:" }
    [System.IO.File]::WriteAllLines($txtPath, $lines)
    Write-Output ("[2/3] mods.txt 已移除条目（备份: mods.txt.bak-$ts）")
} else {
    Write-Output "[2/3] 未找到 mods.txt，跳过"
}

# 3. 删除 Mod 目录
if (Test-Path $dstMod) {
    Remove-Item $dstMod -Recurse -Force
    Write-Output "[3/3] 已删除 $dstMod"
} else {
    Write-Output "[3/3] Mod 目录不存在，跳过"
}

Write-Output ""
Write-Output "卸载完成。游戏内的条会恢复原版（重启游戏即可）。"
