# 构建步骤

本项目分两部分：

| 部分 | 是否需要构建 | 产物 |
|---|---|---|
| Lua Mod（`PBZ_HUDWidth/`） | **不需要**，纯 Lua 直接运行 | — |
| 配置器（`configurator/`） | 需要打包成 exe | `PBZ_HUDWidth_Configurator.exe` |

---

## 0. 环境要求

- Windows 10 / 11
- Python **3.10+**（64 位）
- 无需安装 Visual Studio / .NET SDK

检查：

```powershell
python --version
```

---

## 1. 安装依赖

```powershell
cd configurator
python -m pip install -r requirements.txt
```

`requirements.txt` 内容：

```
PySide6-Essentials>=6.5
pyinstaller>=6.0
```

> 只装 `PySide6-Essentials` 而不是完整 `PySide6`，体积小很多，本项目用不到 Qt3D / WebEngine。

### 国内网络

官方源下载 80 MB+ 可能很慢甚至超时，用阿里云镜像：

```powershell
python -m pip install -i https://mirrors.aliyun.com/pypi/simple `
  --trusted-host mirrors.aliyun.com -r requirements.txt
```

---

## 2. 打包配置器

```powershell
cd configurator
python -m PyInstaller --noconfirm --clean --onefile --windowed `
  --name PBZ_HUDWidth_Configurator main.py
```

参数说明：

| 参数 | 作用 |
|---|---|
| `--onefile` | 打成单文件，用户端无需安装 |
| `--windowed` | 不弹黑色控制台窗口 |
| `--clean` | 清掉上一次的缓存 |

产物：`configurator\dist\PBZ_HUDWidth_Configurator.exe`（约 37 MB）

首次启动会解包到临时目录，约 3–5 秒属正常。

### 打包后自检

```powershell
$env:QT_QPA_PLATFORM = "offscreen"
.\dist\PBZ_HUDWidth_Configurator.exe
# 无输出、无崩溃即正常；Ctrl+C 结束
```

或直接双击，确认窗口能出来。

---

## 3. 打包发布 zip

回到仓库根目录：

```powershell
python tools/pack_release.py
```

会生成 `dist/PBZ_HUDWidth_<版本>.zip`，内容：

```
PBZ_HUDWidth_v1.0/
├─ 简单的使用说明.txt
├─ README.md
├─ install.ps1
├─ uninstall.ps1
├─ PBZ_HUDWidth_Configurator.exe
└─ PBZ_HUDWidth/
   ├─ Scripts/main.lua
   ├─ config.lua
   └─ enabled.txt
```

脚本会检查 exe 是否存在；没打包 exe 时会**跳过**并提示先执行第 2 步。

> zip 里故意**不含**仓库的 `.gitignore`、`docs/`、`tools/`，保持用户端干净。

---

## 4. 修改与调试

### 改 Lua

1. 编辑 `PBZ_HUDWidth/Scripts/main.lua`
2. 复制到游戏目录 `Mods\PBZ_HUDWidth\Scripts\`（或直接跑 `install.ps1`）
3. **完全退出游戏再启动**

> 不建议用 UE4SS 的 `Ctrl+R` 热重载：本项目实测在这个游戏上有概率在「卸载全部 mod → 重新加载」阶段卡死并崩溃。只改 `config.lua` 时热重载是安全的，改 `main.lua` 主体请重启。

### 打开调试模式

`config.lua`：

```lua
debug = true,
```

重启后游戏内会注册诊断键（F6 / F7 / F8 / F9 / F10），详见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。

### 看日志

```
<游戏目录>\platform\steam\ue4ss\UE4SS.log
```

搜 `[HUDW]`。加载成功的第一行形如：

```
PBZ_HUDWidth 已加载  v27 ... 2026-11-09 16:50
```

---

## 5. 常见构建问题

**`ModuleNotFoundError: No module named 'tkinter'`**
本项目用 PySide6，不需要 tkinter。如果看到这个错误，说明打的是旧版本代码。

**打出来的 exe 启动即退出**
多为缺少 Qt 平台插件。确认是在 `configurator/` 目录下执行 PyInstaller（它要能找到 PySide6 的插件目录），并加 `--clean` 重打。

**exe 被杀软报毒**
PyInstaller 单文件包的通病（自解压行为）。可选缓解：改用 `--onedir`，或自行签名。不建议为了免杀而牺牲单文件便利。

**中文路径报错**
`install.ps1` 含中文，必须以 **UTF-8 with BOM** 保存，否则 PowerShell 5.1 会按 ANSI 解析并报"字符串缺少终止符"。
