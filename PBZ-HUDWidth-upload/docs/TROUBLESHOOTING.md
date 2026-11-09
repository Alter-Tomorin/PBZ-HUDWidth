# 排错指南

## 先做三件确认

1. **UE4SS 是否装好**：`<游戏>\platform\steam\dwmapi.dll` 和 `ue4ss\` 目录都在
2. **Mod 是否被加载**：`ue4ss\UE4SS.log` 里搜 `PBZ_HUDWidth 已加载`
3. **是否已启用**：配置器顶部那行字应是「已启用：两条对齐到标准长度，灰框已隐藏。」

---

## 症状速查

| 症状 | 最可能的原因 | 处理 |
|---|---|---|
| 装了但什么都没变 | 未点「对齐标准」 | 打开配置器点一次 |
| 日志里没有 `PBZ_HUDWidth 已加载` | 目录层级错 / 没注册 `mods.json` | 见下方「加载失败」 |
| 配置器报「找不到 mod 目录」 | 路径不对 | 点「更改目录」，选到 `Mods\PBZ_HUDWidth` |
| 拖动滑条游戏里没反应 | Mod 未启用 / 游戏未运行 | 先启用；Mod 需要在运行时才能改 HUD |
| 条变长/变短了但立刻弹回 | 另有 mod 或游戏逻辑在改 | 看日志有没有 `drift` |
| 灰框不见了 | 设计如此 | `config.lua` 里 `hideFrame = false` |
| 换存档后长度明显偏 | 基准失效 | 三个 `*Ref` 改 `0`，重启重采样 |
| 游戏更新后失效 | 控件名/参数名变了 | 见下方「游戏更新」 |

---

## 加载失败

**目录层级必须是这样**（`PBZ_HUDWidth` 是第一层，不要再套一层）：

```
Mods\
└─ PBZ_HUDWidth\
   ├─ Scripts\main.lua
   ├─ config.lua
   └─ enabled.txt
```

**必须注册**到 `Mods\mods.json`：

```json
{ "mod_name": "PBZ_HUDWidth", "mod_enabled": true }
```

漏这一步 UE4SS 不会加载它——这是最常见的问题。`install.ps1` 会自动处理。

---

## 打开调试模式

`config.lua`：

```lua
debug = true,
```

重启游戏后注册诊断键：

| 键 | 作用 |
|---|---|
| **F6** | 导出完整控件树 / 当前两条状态到 `output\hud_state.txt` |
| **F7** | 进入/退出「元素识别测试」（F6 切换元素，F9 复位） |
| **F8** | 枚举 5 个材质实例的标量参数到 `output\calib.txt` |
| **F9 / F10** | 长度 −10% / +10% |

发布版 `debug = false` 时**不注册任何按键**。

---

## 看日志

```
<游戏目录>\platform\steam\ue4ss\UE4SS.log
```

搜 `[HUDW]`：

```
[HUDW] PBZ_HUDWidth 已加载  v27 ...          ← 启动指纹
[HUDW] apply| ratio hp=0.66343→0.58479 ...   ← 补偿生效
[HUDW] 采样基准比例 hp=0.58479                ← 基准采样
[HUDW] drift| ...                             ← 值被改回去了
[HUDW] !! ERROR in xxx                        ← 按下某个键时报错
```

> **改完 Lua 一定要「完全退出游戏再启动」。**
> 判断是否真的加载了新代码：看日志里 `Starting Lua mod 'PBZ_HUDWidth'` 的时间，或 `output\build.txt` 的修改时间。
> 本项目实测 `Ctrl+R` 热重载在此游戏上有概率卡死并崩溃，改 `main.lua` 主体请重启。

---

## 游戏更新后失效

控件名或材质参数名可能变化。步骤：

1. `config.lua` 里 `debug = true`，重启游戏
2. 按 **F8** → `output\calib.txt` 里是所有材质实例的标量参数和当前值
3. 找出数值与"条长"相关的那一项（满数值档下 `HPBG_DMI` 的 `ShowUpRatio` 约 0.58）
4. 用新名字替换 `main.lua` 里 `ratioOf(bar, "HPBG_DMI", 1)` 的参数
5. 按 **F6** → `output\hud_state.txt` 里是完整控件树，用来核对控件名是否还叫 `Image_HpBG` 等

---

## 颜色/位置看起来不对

确认 `hideFrame` 的设置：

```lua
hideFrame = true,   -- 隐藏两条共用的灰框
```

灰框是**一张图**横跨两条，没法同时贴合两条不同长度的条，所以默认隐藏。

---

## 卸载后没恢复

正常情况下删掉文件夹、重启游戏就恢复原生——Mod 只改运行时属性，不写存档、不改 pak。

如果当前这局还没恢复：进游戏点一次「对齐取消」。

---

## 收集信息给反馈

出问题时请提供：

1. `UE4SS.log` 里所有含 `[HUDW]` 的行
2. `config.lua` 的当前内容
3. 截图（能看出条的长度）
4. 游戏版本号

有这四样基本能定位。
