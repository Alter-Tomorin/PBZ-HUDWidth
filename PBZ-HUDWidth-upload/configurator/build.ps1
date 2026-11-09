# 一键构建配置器 exe
#
# 用法（在 configurator 目录下）：
#   powershell -ExecutionPolicy Bypass -File .\build.ps1
# 国内网络可加 -Mirror：
#   powershell -ExecutionPolicy Bypass -File .\build.ps1 -Mirror

param([switch]$Mirror = $false)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Output "== 1/3 检查 Python =="
$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { throw "找不到 python，请先安装 Python 3.10+ 并加入 PATH" }
python --version

Write-Output ""
Write-Output "== 2/3 安装依赖 =="
if ($Mirror) {
    python -m pip install -i https://mirrors.aliyun.com/pypi/simple --trusted-host mirrors.aliyun.com -r requirements.txt
} else {
    python -m pip install -r requirements.txt
}
if (-not $?) { throw "依赖安装失败" }

Write-Output ""
Write-Output "== 3/3 打包 =="
python -m PyInstaller --noconfirm --clean --onefile --windowed `
    --name PBZ_HUDWidth_Configurator main.py
if (-not $?) { throw "打包失败" }

$exe = Join-Path $PSScriptRoot "dist\PBZ_HUDWidth_Configurator.exe"
if (-not (Test-Path $exe)) { throw "没找到产物：$exe" }

$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Output ""
Write-Output "完成：$exe  ($size MB)"
Write-Output "下一步：回到仓库根目录执行  python tools\pack_release.py"
