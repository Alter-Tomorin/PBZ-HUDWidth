# PBZ_HUDWidth 安装脚本
# 用法：右键“使用 PowerShell 运行”，或：
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# 如果自动找不到游戏目录，手动指定：
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 -GameDir "D:\Steam\steamapps\common\PBZ"

param([string]$GameDir = "")

$ErrorActionPreference = "Stop"

# ---------- 自动寻找游戏目录（Steam 库） ----------
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
$srcMod  = Join-Path $PSScriptRoot $modName
$modsDir = Join-Path $GameDir "platform\steam\ue4ss\Mods"
$dstMod  = Join-Path $modsDir $modName
$ts      = Get-Date -Format "yyyyMMdd-HHmmss"

# PS 5.1 的 ConvertFrom-Json / ConvertTo-Json 对顶层数组会套一层 {value, Count}，
# 这里统一解包，避免把 mods.json 写坏。
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

if (-not (Test-Path $modsDir)) { throw "找不到 Mods 目录，UE4SS 可能没装好: $modsDir" }
if (-not (Test-Path $srcMod))  { throw "找不到源目录: $srcMod" }

# 1. 复制 Mod 本体
if (Test-Path $dstMod) { Remove-Item $dstMod -Recurse -Force }
Copy-Item -Path $srcMod -Destination $dstMod -Recurse -Force
Write-Output "[1/3] 已复制 -> $dstMod"

# 2. 注册到 mods.json（新版 UE4SS 的主清单）
$jsonPath = Join-Path $modsDir "mods.json"
if (Test-Path $jsonPath) {
    Copy-Item $jsonPath "$jsonPath.bak-$ts" -Force
    $list = Read-ModList $jsonPath
    $found = $false
    foreach ($m in $list) {
        if ($m.mod_name -eq $modName) { $found = $true; $m.mod_enabled = $true }
    }
    if (-not $found) {
        $list = @($list) + [pscustomobject]@{ mod_name = $modName; mod_enabled = $true }
    }
    Write-ModList $jsonPath $list
    Write-Output ("[2/3] mods.json 已注册，当前条目数 " + @($list).Count + "（备份: mods.json.bak-$ts）")
} else {
    Write-Output "[2/3] 未找到 mods.json，跳过"
}

# 3. 同步到 mods.txt（旧版清单，双写更稳）
$txtPath = Join-Path $modsDir "mods.txt"
if (Test-Path $txtPath) {
    Copy-Item $txtPath "$txtPath.bak-$ts" -Force
    $raw = [System.IO.File]::ReadAllText($txtPath)
    if ($raw -notmatch "(?m)^$modName\s*:") {
        if (-not $raw.EndsWith("`r`n")) { $raw = $raw.TrimEnd() + "`r`n" }
        $raw = $raw + "$modName : 1`r`n"
        [System.IO.File]::WriteAllText($txtPath, $raw, (New-Object System.Text.UTF8Encoding($false)))
        Write-Output "[3/3] mods.txt 已追加（备份: mods.txt.bak-$ts）"
    } else {
        Write-Output "[3/3] mods.txt 已存在条目，跳过"
    }
}

Write-Output ""
Write-Output "安装完成，文件清单："
Get-ChildItem -Recurse $dstMod | ForEach-Object { Write-Output ("  " + $_.FullName) }
Write-Output ""
Write-Output "下一步：打开 PBZ_HUDWidth_Configurator.exe，点「对齐标准」。"
