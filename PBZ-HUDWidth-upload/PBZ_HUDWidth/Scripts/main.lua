--[[
    PBZ_HUDWidth  |  影之刃零 左下角血条 / 杀气条 固定显示长度

    原理：条长由这几张底图的 RenderTransform.Scale.X 决定（不是布局宽度）。
          Mod 每 500ms 把它们钉回目标值，填充仍由 ProgressBar.Percent 驱动，
          所以上限继续成长、扣血按百分比显示，不会出现假血条。

    百分比语义：100% = 首次运行时的游戏原始长度（自动采样并写回配置）
                与血量上限、屏幕分辨率无关

    快捷键：
      F4  把当前长度保存为永久值（写入 config.lua，删除 live.lua）
      F5  重读 config.lua 并立即应用
      F9  缩短 10%      F10 加长 10%
      F6  把当前状态写到 output\hud_state.txt（排查用）
--]]

local MOD_NAME = "PBZ_HUDWidth"
local BUILD = "v27 2026-11-09 16:50"
local HEADER   = "================================================================"

------------------------------------------------------------------
-- 1. 基础工具
------------------------------------------------------------------

local function safeCall(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

local function isValid(o)
    if o == nil or type(o) ~= "userdata" then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

local function wname(w)
    local ok, n = pcall(function() return w:GetFName():ToString() end)
    if ok and type(n) == "string" then return n end
    return "?"
end

local function num(v, fmt)
    if type(v) == "number" then return string.format(fmt or "%.2f", v) end
    return "?"
end

local function stamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

------------------------------------------------------------------
-- 2. 路径
------------------------------------------------------------------

local SCRIPT_DIR = ""
do
    local ok, info = pcall(function()
        if type(debug) ~= "table" or type(debug.getinfo) ~= "function" then return nil end
        return debug.getinfo(1, "S")
    end)
    if ok and info and type(info.source) == "string" then
        local src = info.source:gsub("^@", "")
        local d = src:match("^(.*)[/\\][^/\\]+$")
        if d then SCRIPT_DIR = d end
    end
end

-- 工程目录（开发期用；分发给别人时这份不存在，会自动退化到 Mod 自身目录）
local WORKSPACE_DIR = "D:/Game/.workbuddy/PBZ_mod/PBZ_HUDWidth/"

local function modDir()
    if SCRIPT_DIR ~= "" then return SCRIPT_DIR .. "\\..\\" end
    return ""
end

local CONFIG_CANDIDATES = {
    WORKSPACE_DIR .. "config.lua",
    modDir() .. "config.lua",
    "Mods/" .. MOD_NAME .. "/config.lua",
}

local LIVE_CANDIDATES = {
    modDir() .. "live.lua",
    WORKSPACE_DIR .. "live.lua",
    "Mods/" .. MOD_NAME .. "/live.lua",
}

local OUTPUT_CANDIDATES = {
    "D:/Game/.workbuddy/PBZ_mod/output/",
    modDir(),
    "",
}

local function readFile(path)
    local f = safeCall(io.open, path, "r")
    if f == nil then return nil end
    local ok, content = pcall(function()
        local c = f:read("*a")
        f:close()
        return c
    end)
    if ok and type(content) == "string" then return content end
    return nil
end

local function readFirst(paths)
    for _, p in ipairs(paths) do
        local c = readFile(p)
        if c ~= nil and #c > 0 then return c, p end
    end
    return nil, nil
end

local resolvedOut = nil
local function writeOut(fileName, text)
    local order = {}
    if resolvedOut then table.insert(order, resolvedOut) end
    for _, b in ipairs(OUTPUT_CANDIDATES) do table.insert(order, b) end
    for _, base in ipairs(order) do
        local f = safeCall(io.open, base .. fileName, "w")
        if f then
            local ok = pcall(function() f:write(text); f:close() end)
            if ok then
                resolvedOut = base
                return base .. fileName
            end
        end
    end
    return nil
end

------------------------------------------------------------------
-- 3. 配置
------------------------------------------------------------------

local cfg = {
    hpPercent   = 100,
    shaPercent  = 100,
    lockSame    = false,
    refLength   = 0,
    refEndX     = 0,
    shaPixelRatio = 0.461,
    enabled     = false,
    debug       = false,
    hpRatioRef  = 0.58479,
    shaRatioRef = 0.26306,
    frameRef    = 43.80,
    hideFrame   = true,
    unit        = "percent",
    hpPixels    = 775,
    shaPixels   = 387,
    pxPerUnit   = 17.7,
    interval_ms = 150,
}

local function applyTable(t)
    if type(t) ~= "table" then return false end
    for _, k in ipairs({ "hpPercent", "shaPercent", "refLength", "refEndX", "interval_ms",
                         "hpPixels", "shaPixels", "pxPerUnit", "hpRatioRef", "shaRatioRef", "frameRef" }) do
        local v = tonumber(t[k])
        if v ~= nil then cfg[k] = v end
    end
    if type(t.lockSame) == "boolean" then cfg.lockSame = t.lockSame end
    if type(t.hideFrame) == "boolean" then cfg.hideFrame = t.hideFrame end
    if type(t.enabled) == "boolean" then cfg.enabled = t.enabled end
    if type(t.debug) == "boolean" then cfg.debug = t.debug end
    if t.unit ~= nil then cfg.unit = tostring(t.unit) end
    return true
end

local CONFIG_PATH = nil

local function loadConfig()
    local text, path = readFirst(CONFIG_CANDIDATES)
    if text == nil then
        print("[HUDW] 找不到 config.lua，用内置默认值")
        return false
    end
    CONFIG_PATH = path
    local chunk = safeCall(load, text)
    if chunk == nil then
        print("[HUDW] config.lua 语法有误: " .. tostring(path))
        return false
    end
    local ok, t = pcall(chunk)
    if not ok then
        print("[HUDW] config.lua 执行失败: " .. tostring(t))
        return false
    end
    applyTable(t)
    print(string.format("[HUDW] config: hp=%s%% sha=%s%% ref=%s",
        num(cfg.hpPercent, "%.0f"), num(cfg.shaPercent, "%.0f"), num(cfg.refLength)))
    return true
end

local function saveConfig()
    local text, path = readFirst(CONFIG_CANDIDATES)
    if text == nil then return false end
    local hp = cfg.hpPercent
    local sha = cfg.lockSame and hp or cfg.shaPercent
    text = text:gsub("hpPercent(%s*)=(%s*)[%d%.]+", "hpPercent%1=%2" .. string.format("%.1f", hp))
    text = text:gsub("shaPercent(%s*)=(%s*)[%d%.]+", "shaPercent%1=%2" .. string.format("%.1f", sha))
    text = text:gsub("refLength(%s*)=(%s*)[%d%.]+", "refLength%1=%2" .. string.format("%.2f", cfg.refLength or 0))
    text = text:gsub("refEndX(%s*)=(%s*)[%d%.]+", "refEndX%1=%2" .. string.format("%.2f", cfg.refEndX or 0))
    text = text:gsub("hpRatioRef(%s*)=(%s*)[%d%.]+", "hpRatioRef%1=%2" .. string.format("%.5f", tonumber(cfg.hpRatioRef) or 0))
    text = text:gsub("shaRatioRef(%s*)=(%s*)[%d%.]+", "shaRatioRef%1=%2" .. string.format("%.5f", tonumber(cfg.shaRatioRef) or 0))
    text = text:gsub("frameRef(%s*)=(%s*)[%d%.]+", "frameRef%1=%2" .. string.format("%.2f", tonumber(cfg.frameRef) or 0))
    text = text:gsub("(enabled)(%s*)=(%s*)(%a+)", "enabled%2=%3" .. tostring(cfg.enabled == true))
    local f = safeCall(io.open, path, "w")
    if f == nil then return false end
    pcall(function() f:write(text); f:close() end)
    print(string.format("[HUDW] 已保存 hp=%.1f%% sha=%.1f%% ref=%.2f", hp, sha, cfg.refLength or 0))
    return true
end

------------------------------------------------------------------
-- 4. live.lua 监听（配置器实时推送）
------------------------------------------------------------------

local live = { active = false, hpPercent = nil, shaPercent = nil, lockSame = nil, enabled = nil }
local lastLiveText = ""

local function pollLive()
    local text = readFirst(LIVE_CANDIDATES)
    if text == nil then
        if live.active then
            live.active = false
            lastLiveText = ""
            print("[HUDW] live.lua 已移除，回到 config 值")
        end
        return false
    end
    if text == lastLiveText then return false end
    lastLiveText = text

    local chunk = safeCall(load, text)
    if chunk == nil then return false end
    local ok, t = pcall(chunk)
    if not ok or type(t) ~= "table" then return false end

    live.hpPercent = tonumber(t.hpPercent)
    live.shaPercent = tonumber(t.shaPercent)
    if type(t.lockSame) == "boolean" then live.lockSame = t.lockSame else live.lockSame = nil end

    -- 总开关：配置器按「对齐标准 / 对齐取消」时下发
    if type(t.enabled) == "boolean" then
        cfg.enabled = t.enabled
        if cfg.enabled then
            local hp, sha, lock = effective()
            cfg.hpPercent = hp
            cfg.shaPercent = sha
            cfg.lockSame = lock
        end
        saveConfig()
        print("[HUDW] live: enabled=" .. tostring(cfg.enabled))
    end
    live.active = true
    print(string.format("[HUDW] live: hp=%s sha=%s",
        num(live.hpPercent, "%.1f"), num(live.shaPercent, "%.1f")))
    return true
end

local function effective()
    local lock = live.lockSame
    if lock == nil then lock = cfg.lockSame end
    local hp = live.hpPercent or cfg.hpPercent
    local sha = live.shaPercent or cfg.shaPercent
    if lock then sha = hp end
    return hp, sha, lock
end

------------------------------------------------------------------
-- 5. HUD 定位
------------------------------------------------------------------

local function findChildByName(w, name, depth)
    if not isValid(w) then return nil end
    if wname(w) == name then return w end
    depth = depth or 0
    if depth > 14 then return nil end

    local ok, cnt = pcall(function() return w:GetChildrenCount() end)
    if ok and type(cnt) == "number" and cnt > 0 then
        for i = 0, cnt - 1 do
            local found = findChildByName(safeCall(function() return w:GetChildAt(i) end), name, depth + 1)
            if found then return found end
        end
    end
    local wt = safeCall(function() return w.WidgetTree end)
    if isValid(wt) then
        local root = safeCall(function() return wt.RootWidget end)
        if isValid(root) and root ~= w then
            return findChildByName(root, name, depth + 1)
        end
    end
    return nil
end

-- 收集所有存活的条根节点（切场景后可能有新旧两份，全部处理）
local function collectBarRoots()
    local roots, seen = {}, {}

    local function push(w)
        if not isValid(w) then return end
        local key = safeCall(function() return w:GetFullName() end)
        if type(key) ~= "string" or seen[key] then return end
        seen[key] = true
        table.insert(roots, w)
    end

    -- 主路径：直接扫全部 UserWidget，按名字前缀取实例。
    -- 不再依赖 W_FrontEndHUDLayout_C -> playerhud 这条固定路径（加载存档后会失效）
    local uws = safeCall(FindAllOf, "UserWidget")
    if type(uws) == "table" then
        for _, u in pairs(uws) do
            if isValid(u) then
                local sn = wname(u)
                if sn:sub(1, 14) == "WB_PlayerHPBar" and sn:sub(-2) ~= "_C" then
                    local bw = safeCall(function() return u.WidgetTree end)
                    local br = bw and safeCall(function() return bw.RootWidget end)
                    if isValid(br) then push(br) end
                end
            end
        end
    end

    -- 回退：老路径
    if #roots == 0 then
        local layouts = safeCall(FindAllOf, "W_FrontEndHUDLayout_C")
        if type(layouts) == "table" then
            for _, layout in pairs(layouts) do
                if isValid(layout) then
                    local wt = safeCall(function() return layout.WidgetTree end)
                    local rt = wt and safeCall(function() return wt.RootWidget end)
                    local hud = rt and findChildByName(rt, "playerhud")
                    if isValid(hud) then
                        local cnt = safeCall(function() return hud:GetChildrenCount() end) or 0
                        for i = 0, cnt - 1 do
                            local w = safeCall(function() return hud:GetChildAt(i) end)
                            if isValid(w) and wname(w):sub(1, 14) == "WB_PlayerHPBar" then
                                local bw = safeCall(function() return w.WidgetTree end)
                                local br = bw and safeCall(function() return bw.RootWidget end)
                                if isValid(br) then push(br) end
                            end
                        end
                    end
                end
            end
        end
    end
    return roots
end

------------------------------------------------------------------
-- 6. 应用
------------------------------------------------------------------

local FRAME     = "Image_OverallBG"
local HP_BG     = "Image_HpBG"
local SHA_BG    = "Image_ShaChiBarBG"
local SHA_GLOW  = "Image_ShaChiBarRedGlow"
local HP_BAR    = "AnimHPBar_1"
local SHA_BAR   = "AnimBreakmeterBar"
local END_GLOWS = { "NS_UI_ShaChiBar_Full_001", "NS_UI_ShaChiBar_Full_002" }

-- 杀气条原始像素长度 / 血条原始像素长度（实测 408/885）
local DEFAULT_PIXEL_RATIO = 1.0

local function sampleRef()
    if (cfg.refLength or 0) > 0 and (cfg.refEndX or 0) > 0 then return true end
    local roots = collectBarRoots()
    local root = roots[1]
    if root == nil then return false end

    if (cfg.refLength or 0) <= 0 then
        local w = findChildByName(root, HP_BG)
        local v = w and safeCall(function() return w.RenderTransform.Scale.X end)
        if type(v) == "number" and v > 0 then cfg.refLength = v end
    end
    if (cfg.refEndX or 0) <= 0 then
        local w = findChildByName(root, END_GLOWS[1])
        local v = w and safeCall(function() return w.RenderTransform.Translation.X end)
        if type(v) == "number" and v > 0 then cfg.refEndX = v end
    end
    if (cfg.refLength or 0) > 0 then
        print(string.format("[HUDW] 采样基准 refLength=%.2f refEndX=%.2f",
            cfg.refLength or 0, cfg.refEndX or 0))
        saveConfig()
        return true
    end
    return false
end

local function setScaleX(w, x, y)
    local cur = safeCall(function() return w.RenderTransform.Scale.X end)
    if type(cur) == "number" and math.abs(cur - x) < 0.005 then return false end
    return pcall(function() w:SetRenderScale({ X = x, Y = y or 1.0 }) end)
end

local function setContainerX(w, factor)
    local cur = safeCall(function() return w.RenderTransform.Scale.X end)
    if type(cur) == "number" and math.abs(cur - factor) < 0.005 then return false end
    pcall(function() w:SetRenderTransformPivot({ X = 0, Y = 0.5 }) end)
    return pcall(function() w:SetRenderScale({ X = factor, Y = 1.0 }) end)
end

local function setEndX(w, x)
    local cur = safeCall(function() return w.RenderTransform.Translation.X end)
    if type(cur) == "number" and math.abs(cur - x) < 0.5 then return false end
    local cy = safeCall(function() return w.RenderTransform.Translation.Y end)
    if type(cy) ~= "number" then cy = 0 end
    return pcall(function() w:SetRenderTranslation({ X = x, Y = cy }) end)
end

-- 计算目标值：锁定 = 像素长度对齐（杀气按 1/pixelRatio 放大）
local function targets()
    local hpPct, shaPct, lock = effective()
    if type(hpPct) ~= "number" or hpPct <= 0 then return nil end
    if hpPct > 1000 then hpPct = 1000 end
    if shaPct > 1000 then shaPct = 1000 end

    local R = tonumber(cfg.refLength) or 43.8
    if R <= 0 then R = 43.8 end
    local ppu = tonumber(cfg.pxPerUnit) or 17.7
    if ppu <= 0 then ppu = 17.7 end

    local hpUnits, shaUnits
    if tostring(cfg.unit) == "pixel" then
        hpUnits = (tonumber(cfg.hpPixels) or 775) / ppu
        shaUnits = (tonumber(cfg.shaPixels) or 387) / ppu
    else
        hpUnits = R * hpPct / 100
        shaUnits = R * shaPct / 100
    end

    if lock then
        -- 像素等长：两条渲染长度都正比于"目标比例"，
        -- 要让杀气画得和血条一样长，需要 shaTarget = hpTarget × (hpRef / shaRef)
        local hr = tonumber(cfg.hpRatioRef) or 0.58479
        local sr = tonumber(cfg.shaRatioRef) or 0.26306
        if sr > 0.0001 then
            shaUnits = hpUnits * (hr / sr)
        else
            shaUnits = hpUnits
        end
    end
    if hpUnits < 0.4 then hpUnits = 0.4 end
    if shaUnits < 0.4 then shaUnits = 0.4 end

    return {
        hpX = hpUnits,
        shaX = shaUnits,
        hpFactor = hpUnits / R,
        shaFactor = shaUnits / R,
        lock = lock,
    }
end

local function parentOf(w)
    if not isValid(w) then return nil end
    local sl = safeCall(function() return w.Slot end)
    if sl == nil then return nil end
    return safeCall(function() return sl.Parent end)
end

local function widgetOf(root)
    local wt = safeCall(function() return root:GetOuter() end)
    if wt == nil then return nil end
    local uw = safeCall(function() return wt:GetOuter() end)
    if isValid(uw) then return uw end
    return nil
end

local function setX(w, f)
    if not isValid(w) then return false end
    if type(f) ~= "number" or f <= 0.001 then return false end
    local cur = safeCall(function() return w.RenderTransform.Scale.X end)
    if type(cur) == "number" and math.abs(cur - f) < 0.002 then return false end
    local cy = safeCall(function() return w.RenderTransform.Scale.Y end)
    if type(cy) ~= "number" or cy <= 0.001 then cy = 1.0 end
    return pcall(function() w:SetRenderScale({ X = f, Y = cy }) end)
end

-- 读某个材质实例第 idx 个标量参数的当前值（这条读取路径已验证可靠）
local function ratioOf(bar, prop, idx)
    if not isValid(bar) then return nil end
    local dmi = safeCall(function() return bar[prop] end)
    if not isValid(dmi) then return nil end
    local arr = safeCall(function() return dmi.ScalarParameterValues end)
    if arr == nil then return nil end
    local e = safeCall(function() return arr[idx or 1] end)
    if e == nil then return nil end
    local v = safeCall(function() return e.ParameterValue end)
    if type(v) == "number" and v > 0.0001 then return v end
    return nil
end

local function applyTo(root, t)
    local changed = 0
    local function hit(v) if v then changed = changed + 1 end end

    local bar = widgetOf(root)
    if not isValid(bar) then bar = root end

    local R = tonumber(cfg.refLength) or 43.8
    if R <= 0 then R = 43.8 end

    local rHp  = ratioOf(bar, "HPBG_DMI", 1)
    local rSha = ratioOf(bar, "SCBG_DMI", 1)
    if rHp == nil or rSha == nil then return 0 end

    -- 首次读到就记为基准（此时应为"参考长度"状态）
    if (tonumber(cfg.hpRatioRef) or 0) <= 0 then
        cfg.hpRatioRef = rHp
        saveConfig()
        print(string.format("[HUDW] 采样基准比例 hp=%.5f", rHp))
    end
    if (tonumber(cfg.shaRatioRef) or 0) <= 0 then
        cfg.shaRatioRef = rSha
        saveConfig()
        print(string.format("[HUDW] 采样基准比例 sha=%.5f", rSha))
    end

    -- 目标比例 = 基准比例 × 百分比；实际比例由游戏给，两者相除就是补偿倍率
    local fHp  = (cfg.hpRatioRef  * t.hpX  / R) / rHp
    local fSha = (cfg.shaRatioRef * t.shaX / R) / rSha

    -- 顶层复位，避免与旧版本叠加
    local top = widgetOf(root)
    if isValid(top) then
        local curTop = safeCall(function() return top.RenderTransform.Scale.X end)
        if type(curTop) == "number" and math.abs(curTop - 1.0) > 0.01 then
            hit(pcall(function() top:SetRenderScale({ X = 1.0, Y = 1.0 }) end))
        end
    end

    local hpBg  = findChildByName(root, HP_BG)
    local shaBg = findChildByName(root, SHA_BG)
    local hpGroup  = parentOf(hpBg)
    local shaGroup = parentOf(shaBg)
    if isValid(hpGroup)  then hit(setX(hpGroup, fHp))  end
    if isValid(shaGroup) then hit(setX(shaGroup, fSha)) end

    -- 共用底板：默认直接隐藏（hideFrame = true）
    local frame = findChildByName(root, FRAME)
    if isValid(frame) then
        if cfg.hideFrame ~= false then
            local vis = safeCall(function() return frame:GetVisibility() end)
            if vis ~= 1 then
                local okHide = pcall(function() frame:SetVisibility(1) end)   -- 1 = Collapsed
                if okHide then
                    changed = changed + 1
                else
                    -- 隐藏失败就退化成缩到最小，保证视觉上消失
                    local cy = safeCall(function() return frame.RenderTransform.Scale.Y end)
                    if type(cy) ~= "number" then cy = 1.2 end
                    pcall(function() frame:SetRenderScale({ X = 0.0001, Y = cy }) end)
                end
            end
        else
            local gF = safeCall(function() return frame.RenderTransform.Scale.X end)
            if (tonumber(cfg.frameRef) or 0) <= 0 then
                if type(gF) == "number" and gF > 1.0 then
                    cfg.frameRef = gF
                    saveConfig()
                    print(string.format("[HUDW] 采样基准比例 frame=%.2f", gF))
                end
            end
            if (tonumber(cfg.frameRef) or 0) > 1.0 then
                hit(setX(frame, cfg.frameRef * fHp))
            end
        end
    end

    if changed > 0 then
        print(string.format("[HUDW] apply| ratio hp=%.5f→%.5f sha=%.5f→%.5f  f=%.3f/%.3f",
            rHp, cfg.hpRatioRef * t.hpX / R, rSha, cfg.shaRatioRef * t.shaX / R, fHp, fSha))
    end
    return changed
end

local applied = false

-- 取消对齐：把缩放归 1、灰框恢复显示，回到游戏原生
local function restoreVanilla()
    local roots = collectBarRoots()
    for _, root in ipairs(roots) do
        for _, nm in ipairs({ HP_BG, SHA_BG }) do
            local w = findChildByName(root, nm)
            local grp = parentOf(w)
            if isValid(grp) then pcall(function() grp:SetRenderScale({ X = 1.0, Y = 1.0 }) end) end
        end
        local frame = findChildByName(root, FRAME)
        if isValid(frame) then pcall(function() frame:SetVisibility(0) end) end
        local top = widgetOf(root)
        if isValid(top) then pcall(function() top:SetRenderScale({ X = 1.0, Y = 1.0 }) end) end
    end
    print("[HUDW] 已取消对齐，恢复游戏原生")
end

local function applyAll(silent)
    if cfg.enabled ~= true then
        if applied then
            applied = false
            pcall(restoreVanilla)
        end
        return 0
    end
    applied = true

    if (cfg.refLength or 0) <= 0 then
        if not sampleRef() then return 0 end
    end
    local t = targets()
    if t == nil then return 0 end

    local roots = collectBarRoots()
    if #roots == 0 then return 0 end

    local changed = 0
    for _, root in ipairs(roots) do
        changed = changed + applyTo(root, t)
    end

    if changed > 0 and not silent then
        print(string.format("[HUDW] apply hp=%.1f%%  shaFactor=%.2f  (S.X=%.2f/%.2f)  roots=%d  changed=%d",
            t.hpFactor * 100, t.shaFactor, t.hpX, t.shaX, #roots, changed))
    end
    return changed
end

-- 取两条的关键数值：轨道缩放 / 填充百分比 / 填充容器缩放
local function barSnapshot(root)
    local r = {}
    local defs = {
        { tag = "HP",  bg = HP_BG,  cont = HP_BAR  },
        { tag = "SHA", bg = SHA_BG, cont = SHA_BAR },
    }
    for _, d in ipairs(defs) do
        local bgw = findChildByName(root, d.bg)
        local cw  = findChildByName(root, d.cont)
        local pb  = cw and findChildByName(cw, "RealBar")
        r[d.tag] = {
            bgX   = bgw and safeCall(function() return bgw.RenderTransform.Scale.X end),
            contX = cw and safeCall(function() return cw.RenderTransform.Scale.X end),
            pct   = pb and safeCall(function() return pb.Percent end),
        }
    end
    return r
end

local function snapText(s)
    local function f(v, fmt) if type(v) == "number" then return string.format(fmt, v) end return "?" end
    return string.format("HP[轨道=%s 填充=%s 容器=%s]  SHA[轨道=%s 填充=%s 容器=%s]",
        f(s.HP.bgX, "%.2f"), f(s.HP.pct, "%.3f"), f(s.HP.contX, "%.3f"),
        f(s.SHA.bgX, "%.2f"), f(s.SHA.pct, "%.3f"), f(s.SHA.contX, "%.3f"))
end

-- 漂移检测：游戏改回去时会打日志，方便定位
local tickCount = 0
local function checkDrift()
    local roots = collectBarRoots()
    if #roots == 0 then
        local n = 0
        local uws = safeCall(FindAllOf, "UserWidget")
        if type(uws) == "table" then
            for _, u in pairs(uws) do
                if isValid(u) and wname(u):sub(1, 14) == "WB_PlayerHPBar" then n = n + 1 end
            end
        end
        print(string.format("[HUDW] drift: 找不到血条根节点（候选 UserWidget=%d）", n))
        return
    end
    local t = targets()
    if t == nil then return end

    for idx, root in ipairs(roots) do
        local s = barSnapshot(root)
        local bad = {}
        if type(s.HP.bgX) == "number" and math.abs(s.HP.bgX - t.hpX) > 0.3 then
            table.insert(bad, string.format("血条轨道 %.2f→应为 %.2f", s.HP.bgX, t.hpX))
        end
        if type(s.HP.contX) == "number" and math.abs(s.HP.contX - t.hpFactor) > 0.03 then
            table.insert(bad, string.format("血条容器 %.3f→应为 %.3f", s.HP.contX, t.hpFactor))
        end
        if type(s.SHA.bgX) == "number" and math.abs(s.SHA.bgX - t.shaX) > 0.3 then
            table.insert(bad, string.format("杀气轨道 %.2f→应为 %.2f", s.SHA.bgX, t.shaX))
        end
        if type(s.SHA.contX) == "number" and math.abs(s.SHA.contX - t.shaFactor) > 0.03 then
            table.insert(bad, string.format("杀气容器 %.3f→应为 %.3f", s.SHA.contX, t.shaFactor))
        end
        if #bad > 0 then
            print(string.format("[HUDW] drift| roots=%d #[%d] %s", #roots, idx, table.concat(bad, "  |  ")))
        end
    end
    if #roots > 1 then
        print(string.format("[HUDW] drift| 注意：同时存在 %d 个 HUD 实例", #roots))
    end
end

------------------------------------------------------------------
-- 6b. 元素识别测试（F7 进入/退出，F6 切换下一个，F9 全部复位）
--     用 F 键而非数字键：数字键在这个 UE4SS 版本上注册不上
------------------------------------------------------------------

local TEST_TARGETS = {
    { name = "Image_OverallBG",           kind = "img" },
    { name = "Image_HpBG",                kind = "img" },
    { name = "AnimHPBar_1",               kind = "box" },
    { name = "Image_ShaChiBarBG",         kind = "img" },
    { name = "Image_ShaChiBarRedGlow",    kind = "img" },
    { name = "AnimBreakmeterBar",         kind = "box" },
    { name = "NS_UI_ShaChiBar_Break_001", kind = "end" },
    { name = "NS_UI_ShaChiBar_Full_001",  kind = "end" },
    { name = "NS_UI_ShaChiBar_Full_002",  kind = "end" },
}

local testMode = false
local testIndex = 0
local TEST_FACTOR = 0.4

local function applyElement(root, t, f)
    local w = findChildByName(root, t.name)
    if w == nil then return false end
    if t.kind == "img" then
        local sy = safeCall(function() return w.RenderTransform.Scale.Y end)
        if type(sy) ~= "number" then sy = 1.0 end
        return pcall(function() w:SetRenderScale({ X = cfg.refLength * f, Y = sy }) end)
    elseif t.kind == "box" then
        if f ~= 1.0 then pcall(function() w:SetRenderTransformPivot({ X = 0, Y = 0.5 }) end) end
        return pcall(function() w:SetRenderScale({ X = f, Y = 1.0 }) end)
    else
        local cy = safeCall(function() return w.RenderTransform.Translation.Y end)
        if type(cy) ~= "number" then cy = 0 end
        return pcall(function() w:SetRenderTranslation({ X = cfg.refEndX * f, Y = cy }) end)
    end
end

local function testApplyIndex(idx, f)
    local t = TEST_TARGETS[idx]
    if t == nil then return false end
    local ok = false
    for _, root in ipairs(collectBarRoots()) do
        if applyElement(root, t, f) then ok = true end
    end
    return ok
end

local function testResetAll()
    for i = 1, #TEST_TARGETS do testApplyIndex(i, 1.0) end
    testIndex = 0
end

local function toggleTestMode()
    testMode = not testMode
    if testMode then
        if (cfg.refLength or 0) <= 0 then sampleRef() end
        testResetAll()
        print("[HUDW] ===== 识别测试开启 =====  F6 = 下一个元素  F9 = 全部复位  F7 = 退出")
        for i, t in ipairs(TEST_TARGETS) do
            print(string.format("[HUDW] test #%d = %s", i, t.name))
        end
    else
        testResetAll()
        print("[HUDW] ===== 识别测试关闭，恢复常规应用 =====")
        applyAll()
    end
end

-- F6：当前元素复位，切到下一个并缩到 40%
local function nextTestElement()
    if not testMode then
        toggleTestMode()
        if not testMode then return end
    end
    if testIndex > 0 then testApplyIndex(testIndex, 1.0) end
    testIndex = testIndex % #TEST_TARGETS + 1
    local ok = testApplyIndex(testIndex, TEST_FACTOR)
    local t = TEST_TARGETS[testIndex]
    print(string.format("[HUDW] test #%d = %s -> %.0f%% %s", testIndex, t.name,
        TEST_FACTOR * 100, ok and "" or "(未找到该控件)"))
end

local function resetTest()
    if not testMode then print("[HUDW] 未在测试模式"); return end
    testResetAll()
    print("[HUDW] test 全部复位 100%")
end

-- 材质参数探针：按数组下标枚举 5 个 DMI 的标量参数，并尝试多种方式取参数名
local DMI_LIST = { "HPBar_DMI", "HPBG_DMI", "SCBG_DMI", "BG_DMI", "MID_RedGlow" }

local function tryName(e)
    local a = safeCall(function() return e.ParameterName end)
    if a ~= nil then
        local s1 = safeCall(function() return a:ToString() end)
        if type(s1) == "string" and #s1 > 0 and not s1:find("TrivialObject", 1, true) then return s1 end
    end
    local pi = safeCall(function() return e.ParameterInfo end)
    if pi ~= nil then
        local nm = safeCall(function() return pi.Name end)
        if nm ~= nil then
            local s2 = safeCall(function() return nm:ToString() end)
            if type(s2) == "string" and #s2 > 0 then return s2 end
            local s3 = safeCall(function() return tostring(nm) end)
            if type(s3) == "string" and #s3 > 0 and not s3:find("TrivialObject", 1, true) then return s3 end
        end
    end
    return "?"
end

local function dumpCalib()
    local out = { "== 材质参数枚举  " .. stamp() .. " ==", "" }
    local function flush()
        writeOut("calib.txt", table.concat(out, "\n") .. "\n")
        for _, line in ipairs(out) do print("[HUDW] calib| " .. line) end
        print("[HUDW] calib -> calib.txt")
    end

    local roots = collectBarRoots()
    if #roots == 0 then
        out[#out + 1] = "找不到血条根节点"
        flush()
        return
    end
    local bar = widgetOf(roots[1])
    if not isValid(bar) then
        out[#out + 1] = "取不到血条控件"
        flush()
        return
    end
    out[#out + 1] = "控件: " .. wname(bar)

    for _, pn in ipairs(DMI_LIST) do
        out[#out + 1] = ""
        local dmi = safeCall(function() return bar[pn] end)
        if not isValid(dmi) then
            out[#out + 1] = string.format("[%s] 取不到", pn)
        else
            out[#out + 1] = string.format("[%s]  %s", pn, wname(dmi))
            local arr = safeCall(function() return dmi.ScalarParameterValues end)
            local n = 0
            if arr ~= nil then
                n = safeCall(function() return arr:GetArrayNum() end) or 0
            end
            if type(n) ~= "number" then n = 0 end
            out[#out + 1] = string.format("    标量参数 %d 个", n)
            for i = 1, n do
                local e = safeCall(function() return arr[i] end)
                if e ~= nil then
                    local v = safeCall(function() return e.ParameterValue end)
                    out[#out + 1] = string.format("    [%d] %-30s = %s", i, tryName(e),
                        type(v) == "number" and string.format("%.5f", v) or tostring(v))
                end
            end
        end
    end
    flush()
end

------------------------------------------------------------------
-- 7. 状态导出
------------------------------------------------------------------

local function dumpDeep(w, out, depth)
    if not isValid(w) or depth > 6 then return end
    local sx = safeCall(function() return w.RenderTransform.Scale.X end)
    local tx = safeCall(function() return w.RenderTransform.Translation.X end)
    local d  = safeCall(function() return w:GetDesiredSize() end)
    local dx = d and safeCall(function() return d.X end)
    table.insert(out, string.format("%s%s S=%-8s T=%-8s W=%s",
        string.rep("  ", depth), wname(w),
        type(sx) == "number" and string.format("%.3f", sx) or "?",
        type(tx) == "number" and string.format("%.1f", tx) or "?",
        type(dx) == "number" and string.format("%.0f", dx) or "?"))
    local cnt = safeCall(function() return w:GetChildrenCount() end) or 0
    for i = 0, cnt - 1 do
        dumpDeep(safeCall(function() return w:GetChildAt(i) end), out, depth + 1)
    end
    local wt = safeCall(function() return w.WidgetTree end)
    if isValid(wt) then
        local r = safeCall(function() return wt.RootWidget end)
        if isValid(r) and r ~= w then dumpDeep(r, out, depth + 1) end
    end
end

local function dumpState()
    local out = { HEADER, "HUD 状态  " .. stamp(), HEADER }
    local hpPct, shaPct, lock = effective()
    table.insert(out, string.format("percent   hp=%.1f%%  sha=%.1f%%  lock=%s",
        hpPct or 0, shaPct or 0, tostring(lock)))
    table.insert(out, string.format("ref       refLength=%.2f  refEndX=%.2f",
        cfg.refLength or 0, cfg.refEndX or 0))
    table.insert(out, string.format("live      active=%s", tostring(live.active)))

    local roots = collectBarRoots()
    table.insert(out, "")
    table.insert(out, string.format("根节点数量: %d", #roots))

    if #roots == 0 then
        table.insert(out, "找不到血条控件")
    else
        for i, root in ipairs(roots) do
            local fn = safeCall(function() return root:GetFullName() end) or "?"
            table.insert(out, "")
            table.insert(out, string.format("---- [%d] %s", i, fn))
            local snap = barSnapshot(root)
            table.insert(out, "     " .. snapText(snap))

            -- 几何：底宽 x 缩放 = 渲染宽，两个存档如果底宽不同，长度就会不同
            local function geo(nm)
                local w = findChildByName(root, nm)
                if w == nil then return nm .. " 未找到" end
                local d = safeCall(function() return w:GetDesiredSize() end)
                local dx = d and safeCall(function() return d.X end)
                local dy = d and safeCall(function() return d.Y end)
                local sx = safeCall(function() return w.RenderTransform.Scale.X end)
                local sy = safeCall(function() return w.RenderTransform.Scale.Y end)
                local rw = (type(dx) == "number" and type(sx) == "number") and dx * sx or nil
                return string.format("%s desired=%.1fx%.1f scale=%.2fx%.2f 渲染宽=%.0f",
                    nm, tonumber(dx) or -1, tonumber(dy) or -1,
                    tonumber(sx) or -1, tonumber(sy) or -1, tonumber(rw) or -1)
            end
            table.insert(out, "  几何: " .. geo(HP_BG))
            table.insert(out, "  几何: " .. geo(SHA_BG))
            table.insert(out, "  几何: " .. geo(FRAME))
            table.insert(out, "  几何: " .. geo(HP_BAR))

            -- 往上走几层，看整体有没有被缩放（HUD 布局的缩放会等比影响所有元素）
            do
                local node = root
                for d = 0, 4 do
                    if node == nil then break end
                    local ds = safeCall(function() return node:GetDesiredSize() end)
                    local dx = ds and safeCall(function() return ds.X end)
                    local dy = ds and safeCall(function() return ds.Y end)
                    local scx = safeCall(function() return node.RenderTransform.Scale.X end)
                    table.insert(out, string.format("  链[%d] %-22s desired=%.0fx%.0f scaleX=%.3f",
                        d, wname(node), tonumber(dx) or -1, tonumber(dy) or -1, tonumber(scx) or -1))
                    node = safeCall(function() return node:GetOuter() end)
                end
            end

            table.insert(out, "  ---- 子树全量 ----")
            local deep = {}
            dumpDeep(root, deep, 0)
            for _, line in ipairs(deep) do table.insert(out, "  " .. line) end

            local names = { FRAME, HP_BG, SHA_BG, SHA_GLOW, HP_BAR, SHA_BAR, END_GLOWS[1], END_GLOWS[2] }
            for _, nm in ipairs(names) do
                local w = findChildByName(root, nm)
                if w then
                    local sx = safeCall(function() return w.RenderTransform.Scale.X end)
                    local tx = safeCall(function() return w.RenderTransform.Translation.X end)
                    table.insert(out, string.format("  %-24s S.X=%-9s T.X=%s",
                        nm, num(sx), num(tx, "%.1f")))
                else
                    table.insert(out, string.format("  %-24s 未找到", nm))
                end
            end
        end
    end

    local path = writeOut("hud_state.txt", table.concat(out, "\n") .. "\n")
    print("[HUDW] state -> " .. tostring(path))
    for _, line in ipairs(out) do
        if line ~= "" then print("[HUDW] S| " .. line) end
    end
    if roots[1] then
        print(string.format("[HUDW] state| roots=%d  %s", #roots, snapText(barSnapshot(roots[1]))))
    end
    if #roots > 1 then
        for i = 2, #roots do
            print(string.format("[HUDW] state| #%d %s", i, snapText(barSnapshot(roots[i]))))
        end
    end
end

------------------------------------------------------------------
-- 8. 快捷键
------------------------------------------------------------------

local function bump(delta)
    local hp = effective() or 100
    hp = hp + delta
    if hp < 10 then hp = 10 end
    if hp > 1000 then hp = 1000 end
    -- 游戏内微调时脱离配置器的临时值，否则 live.lua 会一直压过 config
    live.hpPercent = nil
    live.shaPercent = nil
    cfg.hpPercent = hp
    if cfg.lockSame then cfg.shaPercent = hp end
    applyAll()
    print(string.format("[HUDW] hpPercent -> %.0f%%", hp))
end

local function commit()
    local hp, sha = effective()
    cfg.hpPercent = hp
    cfg.shaPercent = sha
    saveConfig()
    for _, p in ipairs(LIVE_CANDIDATES) do pcall(os.remove, p) end
    live.active = false
    lastLiveText = ""
    print("[HUDW] 已固化到 config.lua，live.lua 已清除")
end

local function resolveKey(spec)
    if type(spec) == "table" then
        for _, n in ipairs(spec) do
            local k = safeCall(function() return Key[n] end)
            if k ~= nil then return k, tostring(n) end
        end
        return nil
    end
    return safeCall(function() return Key[spec] end), tostring(spec)
end

local BINDINGS = {
    { key = { "F4" },  label = "固化保存",   action = commit },
    { key = { "F5" },  label = "重读配置",   action = function() loadConfig(); applyAll() end },
    { key = { "F6" },  label = "下一个测试元素", action = function()
        if testMode then nextTestElement() else dumpState() end
    end },
    { key = { "F7" },  label = "识别测试开关", action = toggleTestMode },
    { key = { "F8" },  label = "校准探针",   action = dumpCalib },
    { key = { "F9" },  label = "缩短10%/测试复位", action = function()
        if testMode then resetTest() else bump(-10) end
    end },
    { key = { "F10" }, label = "加长 10%",   action = function() bump(10) end },
}

local bound = 0
local ENABLE_DEBUG_KEYS = (cfg.debug == true)
for _, b in ipairs(ENABLE_DEBUG_KEYS and BINDINGS or {}) do
    local key, how = resolveKey(b.key)
    local usable = (key ~= nil)
    if usable then print("[HUDW] 绑定 " .. b.label .. " <- " .. tostring(how)) end
    if usable then
        local ok = pcall(RegisterKeyBind, key, {}, function()
            local okRun, err = pcall(b.action)
            if not okRun then print("[HUDW] !! " .. b.label .. " 出错: " .. tostring(err)) end
        end)
        if ok then bound = bound + 1 end
    end
end

------------------------------------------------------------------
-- 9. 启动
------------------------------------------------------------------

loadConfig()
writeOut("probe.txt", "ok " .. stamp() .. "\n")
writeOut("build.txt", table.concat({
    "BUILD   = " .. BUILD,
    "加载时间 = " .. stamp(),
    string.format("配置     hp=%.1f%% sha=%.1f%% lock=%s ref=%.2f",
        tonumber(cfg.hpPercent) or -1, tonumber(cfg.shaPercent) or -1,
        tostring(cfg.lockSame), tonumber(cfg.refLength) or 0),
    string.format("快捷键   %d/%d", bound, #BINDINGS),
}, "\n") .. "\n")
print(table.concat({
    HEADER,
    "PBZ_HUDWidth 已加载  " .. BUILD .. "  " .. stamp(),
    string.format("快捷键 %d/%d", bound, #BINDINGS),
    "F4 固化   F5 重读   F9/F10 微调   F6 导出状态",
    HEADER,
}, "\n"))

-- 每个 tick 先读一次"游戏当前给的值"，判断它有没有把我们的写入覆盖掉
local hitCount, hitTotal, lastSeen, lastWant = 0, 0, nil, nil

local lastG = { hp = 0, sha = 0 }
local noRoot = 0

local lastFull = "?"

local function gx(w)
    if not isValid(w) then return nil end
    return safeCall(function() return w.RenderTransform.Scale.X end)
end

local function preSample()
    local roots = collectBarRoots()
    if #roots == 0 then noRoot = noRoot + 1; return end
    local root  = roots[1]
    local hpBg  = findChildByName(root, HP_BG)
    local shaBg = findChildByName(root, SHA_BG)
    local frame = findChildByName(root, FRAME)
    local cont  = findChildByName(root, HP_BAR)
    local glow  = findChildByName(root, END_GLOWS[1])

    if hpBg then
        local v = gx(hpBg); if type(v) == "number" then lastG.hp = v end
    end
    if shaBg then
        local v = gx(shaBg); if type(v) == "number" then lastG.sha = v end
    end

    -- 读出"我们写入之前"的样子：游戏在这一 tick 里改成了什么
    local hpGrp  = parentOf(hpBg)
    local shaGrp = parentOf(shaBg)
    local gt = nil
    if glow then gt = safeCall(function() return glow.RenderTransform.Translation.X end) end

    lastFull = string.format(
        "img=%.2f/%.2f grp=%s/%s frame=%s cont=%s glowT=%s",
        lastG.hp, lastG.sha,
        type(gx(hpGrp))  == "number" and string.format("%.3f", gx(hpGrp))  or "?",
        type(gx(shaGrp)) == "number" and string.format("%.3f", gx(shaGrp)) or "?",
        type(gx(frame))  == "number" and string.format("%.2f", gx(frame))  or "?",
        type(gx(cont))   == "number" and string.format("%.3f", gx(cont))   or "?",
        type(gt) == "number" and string.format("%.1f", gt) or "?")
end

local function startTicker()
    local ms = tonumber(cfg.interval_ms) or 150
    safeCall(LoopAsync, ms, function()
        pcall(function()
            pollLive()
            if testMode then return end
            tickCount = tickCount + 1

            preSample()
            applyAll(true)

            if cfg.debug == true and tickCount % 20 == 0 then
                local t = targets()
                print(string.format("[HUDW] tick| %s  目标=%.2f/%.2f  无根=%d",
                    lastFull, t and t.hpX or -1, t and t.shaX or -1, noRoot))
                noRoot = 0
            end
        end)
        return false
    end)
end

startTicker()
