# PBZ_HUDWidth

《影之刃零》（Phantom Blade Zero）左下角血条 / 杀气条的**固定显示长度** Mod。

启用后两条的长度锁死在你设定的值上，但**上限继续成长、受伤与消耗仍按百分比扣减** —— 不会出现"假血条"。

> 跑在 UE4SS 上的 Lua Mod，纯运行时修改控件属性，**不写存档、不改 pak、不碰游戏数值**。

---

## 特性

- **长度可调**：配置器拖动滑条，游戏内 0.5 秒即时生效，范围 10%–500%
- **上限照常成长**：`MaxHealth` / `MaxKill` 一点不动，只是条不再变长
- **不会假血条**：填充仍由 `ProgressBar.Percent` 驱动，扣血按比例缩短
- **跨存档统一**：`100%` = 一周目满数值无饰品存档的原始条长，新档会被拉齐到同一标准
- **跨分辨率成立**：补偿基于材质里的 0~1 比例，不是像素
- **像素级等长**：勾「锁定两条长度一致」后杀气条与血条实际长度相同
- **一键还原**：点「对齐取消」立刻回到游戏原生状态
- **无按键占用**：发布版游戏内不注册任何快捷键

---

## 前提

游戏已安装 **UE4SS**（能加载 Lua Mod）。本仓库**不分发** UE4SS。

---

## 安装

### 方式一：跑安装脚本（推荐）

右键 `install.ps1` →「使用 PowerShell 运行」。

脚本会：

1. 自动在 Steam 各库中定位游戏目录
2. 把 `PBZ_HUDWidth\` 复制到 `platform\steam\ue4ss\Mods\`
3. 在 `mods.json` 注册并启用（写前自动备份），同时补 `mods.txt`

找不到目录时手动指定：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -GameDir "D:\Steam\steamapps\common\PBZ"
```

### 方式二：手动

1. 把 `PBZ_HUDWidth` 文件夹（**不是仓库根目录**）复制到：

   ```
   <游戏目录>\platform\steam\ue4ss\Mods\PBZ_HUDWidth\
   ```

2. 编辑 `Mods\mods.json`，加一条：

   ```json
   { "mod_name": "PBZ_HUDWidth", "mod_enabled": true }
   ```

漏掉第 2 步 UE4SS 不会加载它，这是最常见的问题。

### 验证安装成功

启动游戏后看 `platform\steam\ue4ss\UE4SS.log`，出现这行即成功：

```
PBZ_HUDWidth 已加载  v27 ...
```

---

## 使用

打开 `PBZ_HUDWidth_Configurator.exe`：

| 操作 | 效果 |
|---|---|
| 点 **「对齐标准」** | 开始对齐：两条拉到标准长度、隐藏灰框 |
| 拖动滑条 / 数值框输入 | 实时生效，无需按键 |
| 勾选 **「锁定两条长度一致」** | 杀气条按**像素**与血条等长（约放大 2.22 倍） |
| 点 **「对齐取消」** | 恢复游戏原生：缩放归位、灰框重新显示 |

- **装好后默认未启用**，什么都不做；点一次「对齐标准」才开始工作
- 状态会写进 `config.lua`，关游戏、重启、换存档都保持
- 灰框（两条共用的那层灰边）默认为隐藏，可在 `config.lua` 里把 `hideFrame` 改成 `false` 恢复

---

## 卸载

删掉 `Mods\PBZ_HUDWidth` 文件夹，并从 `mods.json` 移除对应条目即可，**游戏不需要任何修复**。

Mod 只改运行时的 `RenderTransform` / `Visibility`，不落盘任何游戏数据；删掉后游戏重建 HUD 即为原生外观。

建议删之前先进游戏点一次「对齐取消」。

---

## 常见问题

**Q：为什么灰框没了？**
那层灰边是两条共用的**一张图**，无法同时贴合两条不同长度的条，所以直接隐藏。想恢复把 `config.lua` 的 `hideFrame` 改成 `false`。

**Q：换了存档，条长不对？**
正常会自动对齐。若明显偏长/偏短，把 `config.lua` 里 `hpRatioRef` / `shaRatioRef` / `frameRef` 改成 `0`，重启让它按当前状态重新采样。

**Q：换分辨率会错位吗？**
不会。补偿量是材质里的比例，不是像素。

**Q：游戏更新后失效？**
控件名或材质参数名可能变化。把 `config.lua` 的 `debug` 改成 `true` 重启，游戏内按 **F8** 会把材质参数枚举写到 `output\calib.txt`，按新参数名更新代码即可。详见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)。

更多问题见 **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**。

---

## 原理

游戏把条长写在**材质实例的标量参数**里，而不是控件尺寸 —— 控件 `Image_HpBG.Scale.X` 恒为 43.80，无论上限怎么涨都不动。

| 材质 | 参数 | 满数值时 |
|---|---|---|
| `HPBG_DMI` | `ShowUpRatio` | 0.58479 |
| `SCBG_DMI` | `ShowUpRatio` | 0.26306 |

Mod 读这个比例做除法补偿：

```lua
补偿倍率 = (基准比例 × 百分比) / 材质里的当前比例
组容器.Scale.X *= 补偿倍率
```

游戏把比例改大，我们就除回去，长度恒定；填充仍归 `ProgressBar.Percent` 管。

完整技术细节（含控件树、踩坑记录）见 **[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md)**。

---

## 从源码构建

Lua Mod 部分**不需要编译**，直接用。只有配置器需要打包成 exe：

```powershell
cd configurator
python -m pip install -r requirements.txt
python -m PyInstaller --noconfirm --clean --onefile --windowed `
  --name PBZ_HUDWidth_Configurator main.py
```

产物在 `configurator\dist\PBZ_HUDWidth_Configurator.exe`。

完整步骤（含国内镜像、打包发布 zip）见 **[docs/BUILD.md](docs/BUILD.md)**。

---

## 项目结构

```
PBZ_HUDWidth/                   Lua Mod 本体
  Scripts/main.lua              主体逻辑
  config.lua                    配置（长度 / 开关 / 基准）
  enabled.txt                   UE4SS 识别标记
configurator/
  main.py                       配置器源码（PySide6）
  requirements.txt              构建依赖
tools/pack_release.py           打发布 zip
docs/                           构建 / 原理 / 排错
install.ps1 / uninstall.ps1     安装与卸载
简单的使用说明.txt               四步上手
```

---

## 免责声明

- 仅用于**单机自用**，请勿用于联机或任何绕过反作弊的场景
- 本仓库**不包含**任何游戏本体资产
- 使用第三方 Mod 加载器存在风险，请自行评估；建议先备份 `SaveGames`

---

## License

MIT，见 [LICENSE](LICENSE)。

---

<sub>English: A UE4SS Lua mod for *Phantom Blade Zero* that locks the on-screen length of the health and "Sha Qi" bars while leaving max values, damage scaling and the fill percentage untouched. Requires UE4SS. No game assets are redistributed.</sub>
