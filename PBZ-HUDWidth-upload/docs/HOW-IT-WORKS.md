# 原理与实现

这份文档记录「为什么这样做」，以及开发过程中踩过的坑。如果你要改这个 Mod，建议先读完。

---

## 一、问题：条为什么会长

玩家血量上限从 850 成长到 5500，左下角血条在视觉上跟着变长。目标是**锁死视觉长度**，但保留：

- 上限数值继续成长（战斗数值不变）
- 受伤 / 消耗时按 `当前/最大` 的百分比扣减
- 不出现"假血条"

"假血条"的定义：轨道长度固定，但填充仍按**绝对数值**映射像素，于是上限翻倍后扣 50 点血在画面上看不出变化。

---

## 二、错误的方向（都试过）

### 1. 改 `SizeBox.WidthOverride`

最初的假设是"外层轨道是个 SizeBox，把宽度写死就行"。

**不成立**：`WB_PlayerHPBar` 整条祖先链上**一个 SizeBox 都没有**。整棵树是：

```
W_FrontEndHUDLayout_C → playerhud → WB_PlayerHPBar_82
├ Image_OverallBG          共用灰框
├ Image_HpBG               血条底图
├ AnimHPBar_1              血条填充容器
├ Image_ShaChiBarBG        杀气底图
└ AnimBreakmeterBar        杀气填充容器
```

父面板全是 `Overlay`，`OverlaySlot` 不提供尺寸控制。

### 2. 改 `CanvasPanelSlot.Size`

**不存在**。整条链上没有任何 `CanvasPanelSlot`。

### 3. 改 `RenderTransform.Scale.X`

`Image_HpBG` 的 `Scale.X` 实测恒为 **43.80**，无论上限怎么变都不动。改它确实能让条变短（缩放画布），但游戏改的是别的东西，所以压不住成长。

### 4. 改 `GetDesiredSize` / 布局宽度

所有控件的 `GetDesiredSize()` 都是 `32×32`（默认白刷子的尺寸），与实际渲染长度无关。`GetCachedGeometry()` 在此游戏返回 `nil`。

### 5. Hook `UpdateMaxHealth` / 逐帧轮询覆盖

轮询能改到值，但游戏每帧重写，`被改回 20/20 次`。而且找不到"该写什么"——因为长度根本不在这层。

---

## 三、真正的机制：材质标量参数

用「戴 +上限饰品前后，把血条子树 52 个节点的 `Scale.X` / `Translation.X` / `DesiredSize` 全量 diff」的方法验证：

**控件几何一个数都没变**，但画面上条确实变长了。

于是转向材质实例，按**数组下标**枚举 `.ScalarParameterValues[i].ParameterValue`（`ParameterName` 直读是 `nil`，得走 `ParameterInfo.Name`）：

| 材质 | 参数 | 不戴饰品 | 戴 +上限饰品 |
|---|---|---|---|
| `HPBG_DMI` | `ShowUpRatio` | 0.58479 | 0.66343 |
| `BG_DMI` | `1stBarRatio` | 0.58979 | 0.66843 |
| `BG_DMI` | `2ndBarRatio`（杀气） | 0.26806 | 0.26806 |
| `SCBG_DMI` | `ShowUpRatio` | 0.26306 | 0.26306 |

**这就是长度源**：条不是被"撑大"的，是被材质**画长**的。控件只是画布。

---

## 四、解法：除法补偿

```
实际比例 r = 材质里的 ShowUpRatio          -- 游戏写，我们只读
目标比例   = 基准比例 × 百分比
补偿倍率   = 目标比例 / r
组容器.Scale.X = 补偿倍率
```

游戏把 r 从 0.585 改成 0.663，我们算出 `0.585/0.663 = 0.882`，把组容器缩 0.882 倍，净效果长度不变。

### 为什么用「比例」而不是「像素」

`ShowUpRatio` 是 0~1 的无量纲比例，与分辨率、HUD 缩放、DPI 完全无关。同一个值在 1080p 和 4K 上占屏幕的比例一致。

如果改用像素锚点，就得标定 `pxPerUnit`，换分辨率就错位。

### 为什么不会假血条

填充仍然由 `ProgressBar.Percent`（`AnimBar` / `RealBar`）驱动，我们只动**外层容器的横向缩放**。`当前值/最大值` 的逻辑一行没碰。

### 100% 的语义

三个基准写死在 `config.lua`：

```lua
hpRatioRef  = 0.58479   -- 一周目满数值、无饰品时的血条比例
shaRatioRef = 0.26306
frameRef    = 43.80
```

于是**任何存档的 100% 都对齐到"满数值档"的原始长度**：新档比例小（如 0.18），补偿倍率约 3.2，条被拉长到同一屏幕占比。

基准为 `0` 时才会自动采样（留给游戏更新后美术改动的情况）。

---

## 五、关键实现细节

### 控件查找不能依赖固定路径

早期实现：

```lua
FindAllOf("W_FrontEndHUDLayout_C")
  → WidgetTree.RootWidget
  → findChildByName(root, "playerhud")   -- 深度上限 6
```

加载存档 / 换装后 HUD 会重建，层级变深，`findChildByName` 在第 6 层放弃返回 `nil`，整条链静默断掉——不报错、不刷屏，只是什么都不做。

现在改成扫全部 `UserWidget`，按名字前缀 `WB_PlayerHPBar` 匹配，深度上限 14，按 `GetFullName()` 去重，兼容多份实例。

### 结构体参数用 Lua table 传

UE4SS 里 `FVector2D` 构造器不可用，但可以直接传 table：

```lua
w:SetRenderScale({ X = 1.2, Y = 1.0 })
w:SetRenderTransformPivot({ X = 0, Y = 0.5 })
w:SetRenderTranslation({ X = 430.4, Y = 0 })
```

### 读结构体字段会导致进程级崩溃

`GetDesiredSize()` 的返回值、`slot.Size`、`RenderTransform.Scale` 这类**结构体字段读取**走裸指针，越界即访问违例。`pcall` 拦不住——那是进程崩溃，不是 Lua 错误。

本项目的表现：遍历**敌人血条**（已失效但 `IsValid()` 仍返回真）时读取几何，直接 Fatal Error。所以：

- 诊断代码只针对**玩家**这一条链
- 崩溃定位靠「每步一行日志」，看最后一行停在哪
- 玩家链本身是健康的，10 层祖先遍历不会崩

### 不要每 tick 自乘

错误写法：

```lua
local g = frame.RenderTransform.Scale.X   -- 读到的是上一轮写进去的值
setX(frame, g * f)                        -- 指数衰减
```

`f = 0.881`、150ms 一次，3 秒 20 次后 `0.881²⁰ ≈ 0.08`，灰框直接消失。

正确写法：固定基准 × 倍率（绝对值）。

### 灰框为什么被隐藏

`Image_OverallBG` 是两条**共用的同一张图**（`Scale.Y = 1.2`，横跨两行）。一张图只有一个长度，不可能同时贴合血条和杀气条。

最终选择 `SetVisibility(1)`（Collapsed）直接隐藏。想恢复把 `config.lua` 的 `hideFrame` 改成 `false`。

---

## 六、配置优先级

```
live.lua  >  config.lua  >  DEFAULT_CFG
```

`live.lua` 由配置器实时写入，每 200ms 轮询一次；`config.lua` 是持久化值，点「对齐标准」/「对齐取消」或游戏内固化时写回。

**踩过的坑**：`bump()`（游戏内微调）只改了 `cfg`，没清 `live` 的值，于是 `live` 永远压过它——表现为"按了键没反应"。现在微调时会主动清空 live 的临时值。

---

## 七、配置持久化

`saveConfig()` 用 **`gsub` 替换已有数字**来保留注释，这带来一个约束：

> **新增字段必须同时在 `config.lua` 模板里存在，否则永远写不进去。**

早期加 `hpRatioRef` 时只改了默认值表，没加模板行，导致采样成功但文件里一直是 `0`。

---

## 八、时间线（供参考）

| 阶段 | 结论 |
|---|---|
| 验证 UE4SS | 可注入、Lua 可执行、`FindAllOf` 可用 |
| 定位控件树 | 无 SizeBox、无 CanvasPanelSlot，全是 Overlay |
| 填充逻辑 | `ProgressBar.Percent` 驱动，天然百分比，✅ |
| 长度源 | 控件几何全部不变 → 排除布局/缩放 |
| 材质参数 | `ShowUpRatio` 随上限变化 → **找到** |
| 补偿实现 | 除法归一化，✅ 长度锁死 |
| 假血条验证 | 受伤/消耗仍按比例扣减，✅ |
