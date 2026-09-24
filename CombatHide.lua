--[[----------------------------------------------------------------------------
    RXPCombatHide —— 进入战斗时把 RestedXP 的窗口变淡或隐藏，脱战后平滑恢复。

    显隐复用 RXPGuides 自己的总开关 addon.settings.profile.showEnabled
    （对应官方 SettingsPanel.lua ToggleActive）。RXP 的显示判断都读它，
    翻一个字段就能覆盖全部窗口，不必逐个框架去猜它的脾气。

    逻辑与视觉分离：showEnabled / isHidden 立即切换 —— RXP 的任务自动化、
    地图更新、步骤推进每帧都在读它们，不能停在中间态；alpha 则独立做动画。

    战斗中降到哪个 alpha 由档位决定：
        完全隐藏 0.00 ／ 几乎透明 0.12 ／ 半透明 0.40 ／ 稍微透明 0.70
    脱战一律回到 1.00。

    命令（大小写与空格都不敏感，/rxpch、/rxpcombathide 是等价别名）：
        /rxphide            状态与当前档位（什么都不带就是它）
        /rxphide mode       换一档透明度
        /rxphide speed      换一档淡入淡出快慢
        /rxphide on|off     启用 / 停用
        /rxphide test|show  手动模拟进战斗 / 脱战
        /rxphide reset      把窗口状态对齐回 RXP 自己的设置
        /rxphide tips|debug 开关登录提示 / 详细日志
        /rxphide help       全部命令
    另有简写：alpha=mode、state=status、fix=reset、?=help。

    设置只存在 SavedVariables 里，改完即写，不依赖任何界面文件。
----------------------------------------------------------------------------]]

-- 单文件插件：整个功能就在这一个 .lua 里，没有别的文件依赖它。
local ADDON_NAME = ...
ADDON_NAME = ADDON_NAME or "RXPCombatHide"

local VERSION = "4.3.0"

-- ---------------------------------------------------------------- 档位与节奏

local MODES = {
    {name = "完全隐藏", alpha = 0.00, color = "ffff5555",
     desc = "战斗中完全看不见窗口，和以前一样。"},
    {name = "几乎透明", alpha = 0.12, color = "ffffa726",
     desc = "只剩一点影子，能瞄一眼当前步骤。"},
    {name = "半透明",   alpha = 0.40, color = "ffffeb3b",
     desc = "看得清，但明显退到背景里。"},
    {name = "稍微透明", alpha = 0.70, color = "ff8bc34a",
     desc = "基本正常显示，只是不抢视线。"},
}
local modeIndex = 1

local SPEEDS = {
    {name = "快",   fadeOut = 0.08, fadeIn = 0.30},
    {name = "标准", fadeOut = 0.18, fadeIn = 0.45},
    {name = "慢",   fadeOut = 0.35, fadeIn = 0.80},
}
local speedIndex = 2

local function CurrentMode() return MODES[modeIndex] end
local function ModeIsFullHide() return CurrentMode().alpha <= 0 end

local FADE_OUT, FADE_IN, MIN_FADE = 0.18, 0.45, 0.10

local function ApplySpeed(i)
    local s = SPEEDS[i]
    if not s then return end
    speedIndex, FADE_OUT, FADE_IN = i, s.fadeOut, s.fadeIn
end

-- ---------------------------------------------------------------- 存档
--[[ 存档可能被游戏在文件执行之后才挂进来，届时 _G 里的 table 会被整体替换。
     所以 DB 不缓存引用，每次读写前重新绑定；设置也等本插件的 ADDON_LOADED 再读。 --]]

-- minimap 字段是面板时期留给小地图按钮的，面板撤除后已无人读取，不再保留。
-- （老存档里若还留着它，不影响任何逻辑。）
local DEFAULTS = {enabled = true, debug = false, tips = true}
local DB

local function SyncDB()
    local db = _G.RXPCombatHideDB
    if type(db) ~= "table" then
        db = {}
        _G.RXPCombatHideDB = db
    end
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    DB = db
    return db
end

-- 文件执行时就必须拿到一张可写的表：下面注册命令、读初始值都要用
SyncDB()

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff54a4fb[RXP 战斗中隐藏]|r " .. tostring(msg))
end

local function Debug(msg)
    if DB.debug then print("|cff888888[RXPCH]|r " .. tostring(msg)) end
end

local function LoadSettings()
    SyncDB()
    local m = tonumber(DB.mode)
    if m and MODES[math.floor(m)] then modeIndex = math.floor(m) end

    local s = tonumber(DB.speed)
    if s and SPEEDS[math.floor(s)] then
        ApplySpeed(math.floor(s))
    elseif tonumber(DB.fadeOut) then
        -- 旧存档只存了时长，反查回档位
        FADE_OUT = tonumber(DB.fadeOut)
        FADE_IN = tonumber(DB.fadeIn) or FADE_IN
        for i, v in ipairs(SPEEDS) do
            if math.abs(v.fadeOut - FADE_OUT) < 0.001 then speedIndex = i end
        end
    end
    Debug(("读回存档：档位 %d，节奏 %d"):format(modeIndex, speedIndex))
end

-- 改动即写，退出时再兜底一次：写入的是 _G 里的实时 table，崩溃也留得下
local function SaveSettings()
    SyncDB()
    DB.mode, DB.speed = modeIndex, speedIndex
    DB.fadeOut, DB.fadeIn = FADE_OUT, FADE_IN
    DB.enabled = (DB.enabled == true)
    DB.debug   = (DB.debug == true)
    DB.tips    = (DB.tips ~= false)
end

-- ---------------------------------------------------------------- 取插件对象
--[[ _G.RXPGuides 只是挂指南注册函数的命名空间（RXPGuides.lua:158-160），
     不是插件对象，里面没有 settings / enabledFrames。真正的对象只能从
     AceAddon 注册表取，且要用 obj.settings 验明正身。 --]]

local function GetRXP()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    if ace then
        local ok, obj = pcall(ace.GetAddon, ace, "RXPGuides", true)
        if ok and type(obj) == "table" and obj.settings then return obj end
    end
    local g = _G.RXPGuides
    if type(g) == "table" and g.settings then return g end
end

local function GetProfile()
    local rxp = GetRXP()
    return rxp and rxp.settings and rxp.settings.profile
end

local function IsReady() return GetProfile() ~= nil end

-- RXP 的配置要等它自己 OnInitialize 跑完才有值，独立插件总是比它早
local function WhenReady(cb, tries, onTimeout)
    tries = tries or 40
    if IsReady() then cb() return end
    if tries <= 0 then
        if onTimeout then onTimeout() end
        return
    end
    C_Timer.After(0.25, function() WhenReady(cb, tries - 1, onTimeout) end)
end

-- 启动快照：存档里能看到这些字段，就证明插件确实加载执行过
local function MarkRXPState()
    local db = SyncDB()
    local rxp = GetRXP()
    db.rxpReady = (rxp ~= nil)
    db.framesAtLoad = 0
    if rxp and type(rxp.enabledFrames) == "table" then
        for _ in pairs(rxp.enabledFrames) do db.framesAtLoad = db.framesAtLoad + 1 end
    end
end

local function MarkLoaded()
    local db = SyncDB()
    db.loadCount = (tonumber(db.loadCount) or 0) + 1
    db.lastVersion = VERSION
    MarkRXPState()
end

-- ---------------------------------------------------------------- 受保护框架
--[[ 合规红线：战斗锁定期间绝不操作受保护（secure）框架。
     部分 RXP 框架是 SecureActionButtonTemplate，此时 IsForbidden() 为真，
     对它 Show/Hide 会污染 UI，严重时玩家连技能都按不出来。
     官方 RXPGuides.lua HideInRaid 同样先判 IsForbidden。
     SetAlpha 不在受保护之列，所以动画层照常工作。 --]]

local function IsFrameOffLimits(frame)
    if type(frame) ~= "table" then return true end
    if frame.IsForbidden and frame:IsForbidden() then return true end
    if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then return true end
    return false
end

local function SafeCall(frame, method, ...)
    if type(frame) ~= "table" or type(frame[method]) ~= "function" then return false end
    if IsFrameOffLimits(frame) then return false end
    return pcall(frame[method], frame, ...)
end

-- 返回 shown, isSecure。shown 为假 = 用户没开这个功能，必须整个跳过
local function FeatureEnabled(frame)
    if type(frame) ~= "table" then return false, false end
    if type(frame.IsFeatureEnabled) ~= "function" then return true, false end
    local ok, shown, isSecure = pcall(frame.IsFeatureEnabled, frame)
    if not ok then return false, false end
    return shown, isSecure == true
end

--[[ 显示时必须逐个查询"功能是否启用"。官方 ToggleActive 的写法是
         if not (isSecure and InCombatLockdown()) and shown then SetShown(...) end
     无脑 Show 会把用户没开的窗口（活动物品、活动目标等）一起放出来。 --]]
local function SetFramesShown(show)
    local rxp = GetRXP()
    if not rxp then return end

    if not show then
        SafeCall(rxp.RXPFrame, "Hide")
        if type(rxp.enabledFrames) == "table" then
            for _, frame in pairs(rxp.enabledFrames) do SafeCall(frame, "Hide") end
        end
        return
    end

    local inLock = InCombatLockdown()
    if type(rxp.enabledFrames) == "table" then
        for _, frame in pairs(rxp.enabledFrames) do
            local shown, isSecure = FeatureEnabled(frame)
            if shown and not (isSecure and inLock) then SafeCall(frame, "Show") end
        end
    end

    local p = GetProfile()
    if not (p and p.hideGuideWindow) then SafeCall(rxp.RXPFrame, "Show") end
end

-- ---------------------------------------------------------------- 动画引擎

local fadeFrom, fadeTarget, fadeElapsed, fading = 1, 1, 0, false
local fadeRects, rectKey = {}, ""
local fadeDriver = CreateFrame("Frame")

-- 时长按 alpha 跨度缩放；跨度太小时保底，否则几帧就走完，看着像瞬切
local function TravelTime(from, to)
    local span = math.abs(to - from)
    if span < 0.001 then return 0 end
    local t = ((to < from) and FADE_OUT or FADE_IN) * span
    return (t < MIN_FADE) and MIN_FADE or t
end

local function Ease(t) return 1 - (1 - t) * (1 - t) end

--[[ 收集可淡化的"绘制区域"。
     alpha 只认 SetAlpha / SetIgnoreParentAlpha：RXP 的箭头框架平时是
     SetIgnoreParentAlpha(true)，父框架再怎么透明它都照常显示，
     所以必须把 ignoreParentAlpha 一并归零，否则"完全隐藏"档位会漏出箭头。 --]]
local function CollectRects()
    local rxp = GetRXP()
    if not rxp then
        fadeRects, rectKey = {}, "none"
        return fadeRects
    end

    local size = 0
    if type(rxp.enabledFrames) == "table" then
        for _ in pairs(rxp.enabledFrames) do size = size + 1 end
    end
    -- 指纹带上主窗口对象：切场景会重建框架，只比数量会留下失效引用
    local key = tostring(rxp.RXPFrame) .. "#" .. size
    if rectKey == key then return fadeRects end

    local list, seen = {}, {}
    local function add(frame)
        if type(frame) == "table" and not seen[frame]
           and (type(frame.SetAlpha) == "function" or type(frame.SetIgnoreParentAlpha) == "function") then
            seen[frame] = true
            list[#list + 1] = frame
        end
    end

    add(rxp.RXPFrame)
    if type(rxp.enabledFrames) == "table" then
        for _, frame in pairs(rxp.enabledFrames) do add(frame) end
    end

    fadeRects, rectKey = list, key
    return list
end

-- 热路径：pcall 有开销，探测一次，可信的框架之后直连
local untrusted = setmetatable({}, {__mode = "k"})

local function SetAllAlpha(a)
    local list = CollectRects()
    for i = 1, #list do
        local frame, state = list[i], untrusted[list[i]]
        if state == nil then
            untrusted[frame] = not (pcall(frame.SetAlpha, frame, a)
                                    and pcall(frame.SetIgnoreParentAlpha, frame, false))
        elseif state == false then
            frame:SetAlpha(a)
            frame:SetIgnoreParentAlpha(false)
        end
    end
end

local function SnapTo(a)
    fading = false
    fadeDriver:SetScript("OnUpdate", nil)
    fadeFrom, fadeTarget, fadeElapsed = a, a, 0
    SetAllAlpha(a)
end

-- 与 OnUpdate 共用同一条曲线，中途反相才不会有偏差
local function GetCurrentAlpha()
    if not fading or fadeFrom == fadeTarget then return fadeTarget end
    local total = TravelTime(fadeFrom, fadeTarget)
    if total <= 0 then return fadeTarget end
    local t = math.min(fadeElapsed / total, 1)
    return fadeFrom + (fadeTarget - fadeFrom) * Ease(t)
end

--[[ setShownFirst：渐变前先 Show 出来。alpha=0 不等于不可见 —— 框架被藏起来时
     这段渐变屏幕上根本看不见，等它自己 Show 的那一帧就是"闪一下"。
     onDone：用于"淡到 0 之后再真正隐藏"，顺序反了同样没有淡出动画。 --]]
local function FadeTo(target, setShownFirst, animate, onDone)
    if setShownFirst and target > 0 then SetFramesShown(true) end

    if animate == false then
        SnapTo(target)
        if onDone then onDone() end
        return
    end

    local from = GetCurrentAlpha()
    if math.abs(from - target) < 0.005 then
        SnapTo(target)
        if onDone then onDone() end
        return
    end

    fadeFrom, fadeTarget, fadeElapsed, fading = from, target, 0, true

    fadeDriver:SetScript("OnUpdate", function(_, dt)
        fadeElapsed = fadeElapsed + dt
        local total = TravelTime(fadeFrom, fadeTarget)
        local t = (total > 0) and math.min(fadeElapsed / total, 1) or 1
        SetAllAlpha(fadeFrom + (fadeTarget - fadeFrom) * Ease(t))
        if t >= 1 then
            fading = false
            fadeDriver:SetScript("OnUpdate", nil)
            SetAllAlpha(fadeTarget)
            if onDone then onDone() end
        end
    end)
end

-- ---------------------------------------------------------------- 核心开关

-- 照搬官方 ToggleActive 的语义，只是把值换成我们要的 show
local function ApplyShow(show)
    local rxp, p = GetRXP(), GetProfile()
    if not rxp or not p then return end

    p.showEnabled = show and true or false
    rxp.showEnabled = p.showEnabled

    local inLock = InCombatLockdown()
    if type(rxp.enabledFrames) == "table" then
        for _, frame in pairs(rxp.enabledFrames) do
            local shown, isSecure = FeatureEnabled(frame)
            if shown and not (isSecure and inLock) then
                SafeCall(frame, "SetShown", show)
            end
        end
    end

    -- 主窗口另由官方的 hideGuideWindow 决定
    SafeCall(rxp.RXPFrame, "SetShown", show and not p.hideGuideWindow or false)

    -- isHidden 是 RXP 的派生状态，跟着官方语义一起更新，别留下脏值
    rxp.isHidden = (not p.showEnabled) or (p.hideGuideWindow == true)
end

local inCombatHide = false
local beforeShowEnabled

--[[ "完全隐藏"档位会把 showEnabled 设成 false，这是我方副作用而非用户意图。
     存进 DB，重载后据此还原；否则光看 showEnabled 分不清是谁关的，会永远不恢复。 --]]
local function RestoreOurShowFlag()
    if not DB.weHid then return end
    DB.weHid = false
    local p = GetProfile()
    if p and p.showEnabled == false then
        p.showEnabled = true
        local rxp = GetRXP()
        if rxp then rxp.showEnabled = true end
    end
end

local function HideFramesAfterFade()
    if ModeIsFullHide() and inCombatHide then
        ApplyShow(false)
        SetFramesShown(false)
        DB.weHid = true
    end
end

local function HideNow(animate)
    RestoreOurShowFlag()
    if not DB.enabled or inCombatHide or not IsReady() then return end

    local p = GetProfile()
    beforeShowEnabled = (p.showEnabled ~= false)
    inCombatHide = true

    if not beforeShowEnabled then
        Debug("用户本就关着界面，跳过")
        return
    end

    if ModeIsFullHide() then
        FadeTo(0, false, animate, HideFramesAfterFade)
    else
        FadeTo(CurrentMode().alpha, false, animate)
    end
    Debug(("进战斗 → %s"):format(CurrentMode().name))
end

local function ShowNow(animate)
    if not inCombatHide then return end

    local want = (beforeShowEnabled ~= false)
    inCombatHide, beforeShowEnabled = false, nil
    if not want or not IsReady() then return end

    -- 三步缺一就闪：恢复官方显隐 → Show 出来（alpha 还是暗的）→ 再渐显到 1
    ApplyShow(true)
    DB.weHid = false
    FadeTo(1, true, animate)
    Debug("脱战 → 恢复显示")
end

-- 切档位；正在战斗中就立刻按新档位生效
local function ApplyMode(i)
    if not MODES[i] then return end
    modeIndex = i
    SaveSettings()

    local m = CurrentMode()
    if not inCombatHide then return m end

    if ModeIsFullHide() then
        FadeTo(0, false, true, HideFramesAfterFade)
    else
        -- 从"完全隐藏"切过来时框架已被藏掉，得先放出来才看得见半透明
        local p = GetProfile()
        if p and not p.showEnabled then ApplyShow(true) end
        FadeTo(m.alpha, true, true)
    end
    return m
end

local function CycleMode()
    local m = ApplyMode(modeIndex % #MODES + 1)
    Print(("透明档 → |c%s%s|r (α=%.2f)"):format(m.color, m.name, m.alpha))
end

local function CycleSpeed()
    ApplySpeed(speedIndex % #SPEEDS + 1)
    SaveSettings()
    Print(("淡出 %.2fs | 淡入 %.2fs"):format(FADE_OUT, FADE_IN))
end

-- 已被误显示的框架不会自己消失，用它把状态重新对齐回"功能是否启用"
local function RealignFrames()
    local rxp, p = GetRXP(), GetProfile()
    if not rxp or not p then return 0 end

    local inLock, fixed = InCombatLockdown(), 0
    if type(rxp.enabledFrames) == "table" then
        for _, frame in pairs(rxp.enabledFrames) do
            local shown, isSecure = FeatureEnabled(frame)
            if not (isSecure and inLock) then
                local want = (shown == true) and (p.showEnabled ~= false)
                local isShown = (frame.IsShown and frame:IsShown()) or false
                if isShown ~= want and SafeCall(frame, "SetShown", want) then
                    fixed = fixed + 1
                end
            end
        end
    end

    local main, wantMain = rxp.RXPFrame, (p.showEnabled ~= false) and not p.hideGuideWindow
    if main then
        local isShown = (main.IsShown and main:IsShown()) or false
        if isShown ~= wantMain and SafeCall(main, "SetShown", wantMain) then
            fixed = fixed + 1
        end
    end
    return fixed
end

-- ---------------------------------------------------------------- 输出

local function Diagnose()
    local rxp, p = GetRXP(), GetProfile()
    local d = {ready = rxp ~= nil, hasProfile = p ~= nil, frames = {}}
    d.showEnabled = p and tostring(p.showEnabled) or "n/a"
    d.isHidden = rxp and tostring(rxp.isHidden) or "n/a"
    d.version = rxp and tostring(rxp.release) or "n/a"
    if rxp and type(rxp.enabledFrames) == "table" then
        for name, frame in pairs(rxp.enabledFrames) do
            local shown = FeatureEnabled(frame)
            d.frames[#d.frames + 1] = ("%s[%s]"):format(name, shown and "开" or "|cffff8888关|r")
        end
        table.sort(d.frames)
    end
    return d
end

local function PrintDiag(d)
    if not d.ready then
        Print("|cffff5555没取到 RXPGuides 插件对象|r —— 它还没初始化完，或者没启用。")
        return
    end
    Print(("RXPGuides v%s | profile %s | showEnabled=%s | isHidden=%s")
        :format(d.version, d.hasProfile and "就绪" or "未就绪", d.showEnabled, d.isHidden))
    if #d.frames > 0 then
        Print("窗口（[开]=你启用了，本插件才会动它）：" .. table.concat(d.frames, "  "))
    end
end

local function PrintStatus()
    local m = CurrentMode()
    Print(("状态 %s | 战斗中 %s | 处理中 %s")
        :format(DB.enabled and "|cff4caf50启用|r" or "|cffff5555停用|r",
                InCombatLockdown() and "是" or "否",
                inCombatHide and "是" or "否"))
    Print(("透明档 |c%s%s|r (α=%.2f) | 淡出 %.2fs / 淡入 %.2fs")
        :format(m.color, m.name, m.alpha, FADE_OUT, FADE_IN))
    Print(("存档 → 档位=%s 淡出=%s 淡入=%s | 已加载 %s 次（v%s）")
        :format(tostring(DB.mode), tostring(DB.fadeOut), tostring(DB.fadeIn),
                tostring(DB.loadCount), tostring(DB.lastVersion)))
end

local HELP_LINES = {
    "|cffffff00/rxphide|r              看当前状态和档位",
    "|cffffff00/rxphide mode|r         换一档透明度（完全隐藏 → 几乎透明 → 半透明 → 稍微透明）",
    "|cffffff00/rxphide speed|r        换一档淡入淡出快慢（快 / 标准 / 慢）",
    "|cffffff00/rxphide on / off|r     启用 / 停用本插件",
    "|cffffff00/rxphide test / show|r  手动模拟进战斗 / 脱战，用来确认效果",
    "|cffffff00/rxphide reset|r        窗口状态错乱时复位回 RXP 自己的设置",
    "|cffffff00/rxphide tips|r         开关登录时那行提示",
    "|cffffff00/rxphide debug|r        开关详细日志（排查问题时再开）",
    "|cffffff00/rxphide help|r         就是你在看的这个",
}

local function PrintHelp()
    Print("===== 命令一览（|cffffff00/rxphide|r 可简写为 |cffffff00/rxpch|r）=====")
    for _, line in ipairs(HELP_LINES) do Print("  " .. line) end
    -- 别名不占篇幅，一句话带过即可
    Print("  另有简写：|cffffff00alpha|r=mode，|cffffff00state|r=status，"
        .. "|cffffff00fix|r=reset，|cffffff00?|r=help")
end

local function PrintBanner()
    local m = CurrentMode()
    Print(("v%s 已就绪 | 战斗中：|c%s%s|r"):format(VERSION, m.color, m.name))
    Print("换档 |cffffff00/rxphide mode|r · 快慢 |cffffff00/rxphide speed|r · "
        .. "全部命令 |cffffff00/rxphide help|r")
    Print("想关掉这条提示：|cffffff00/rxphide tips|r")
end

-- hash_SlashCmdList 要等所有插件加载完才填充，所以查冲突只能放在 PLAYER_LOGIN 之后
local MY_COMMANDS = {"/rxphide", "/rxpch", "/rxpcombathide"}
local MY_GROUP = "RXPCOMBATHIDE"

local function CheckCommandConflict()
    local owner = SLASH_RXPCOMBATHIDE1
    if owner ~= MY_COMMANDS[1] then
        Print(("|cffff5555警告：|r 主命令被占用（现在是 %s），请改用 /rxpch。")
            :format(tostring(owner)))
    end
    if not hash_SlashCmdList then return end

    local mine, taken = SlashCmdList[MY_GROUP], {}
    for _, cmd in ipairs(MY_COMMANDS) do
        local who = hash_SlashCmdList[cmd:upper()]
        if who ~= nil and who ~= mine then taken[#taken + 1] = cmd end
    end
    if #taken > 0 then
        Print(("|cffff5555警告：|r %s 已被别的插件占用"):format(table.concat(taken, "、")))
    end
end

-- ---------------------------------------------------------------- 设置

-- on/off 单独包一层：停用时还要把窗口立刻恢复正常显示，
-- 而不只是写个字段就完事。
local function SetEnabled(on)
    SyncDB()
    DB.enabled = on and true or false
    SaveSettings()
    if not DB.enabled then ShowNow(false) end
end

-- ---------------------------------------------------------------- 命令

local function Normalize(msg)
    return (msg or ""):lower():gsub("%s+", "")
end

local function HandleCommand(msg)
    local cmd = Normalize(msg)

    if cmd == "on" then
        SetEnabled(true)
        Print("|cff4caf50已启用|r")

    elseif cmd == "off" then
        SetEnabled(false)
        Print("|cffff5555已停用|r（战斗中不再处理，窗口已恢复）")

    elseif cmd == "mode" or cmd == "alpha" then
        CycleMode()

    elseif cmd == "speed" then
        CycleSpeed()

    elseif cmd == "test" then
        if inCombatHide then Print("已经在隐藏状态了") return end
        if not IsReady() then PrintDiag(Diagnose()) return end
        HideNow(true)
        Print("已模拟进战斗，|cffffff00/rxphide show|r 恢复")

    elseif cmd == "show" then
        if not inCombatHide then Print("当前没在隐藏状态") return end
        ShowNow(true)

    elseif cmd == "reset" or cmd == "fix" then
        if not IsReady() then PrintDiag(Diagnose()) return end
        local fixed = RealignFrames()
        Print(fixed > 0 and ("已复位 %d 个窗口"):format(fixed) or "窗口状态本来就是对的")

    elseif cmd == "tips" then
        DB.tips = not DB.tips
        SaveSettings()
        Print("登录提示：" .. (DB.tips and "开" or "关"))

    elseif cmd == "debug" then
        DB.debug = not DB.debug
        SaveSettings()
        Print("详细日志：" .. (DB.debug and "开" or "关"))

    elseif cmd == "help" or cmd == "?" or cmd == "commands" then
        PrintHelp()

    elseif cmd == "status" or cmd == "state" then
        PrintStatus()
        PrintDiag(Diagnose())

    else
        -- 无参数（或 options/config/设置）时给出状态，相当于"主界面"
        PrintStatus()
        PrintDiag(Diagnose())
        if cmd == "" or cmd == "options" or cmd == "config" or cmd == "设置" then
            Print("换档用 |cffffff00/rxphide mode|r，全部命令 |cffffff00/rxphide help|r")
        else
            Print("未知命令 " .. cmd .. "　（|cffffff00/rxphide help|r 看全部）")
        end
    end
end

--[[ 命令名注册有个必须守住的约定：SLASH_<组名><槽位> 里的组名必须**全大写**，
     且只有 1..3 三个槽位有效。写成小写（SLASH_rxpcombathide1）不会被采纳，
     玩家一敲回车就会因为 SlashCmdList[nil] 而弹 Lua 错误。 --]]
local function RegisterSlash()
    if SLASH_RXPCOMBATHIDE1 ~= nil and SLASH_RXPCOMBATHIDE1 ~= MY_COMMANDS[1] then
        Debug("主命令被占用，改用备用命令")
    end
    SLASH_RXPCOMBATHIDE1, SLASH_RXPCOMBATHIDE2, SLASH_RXPCOMBATHIDE3 = unpack(MY_COMMANDS)
    SlashCmdList[MY_GROUP] = HandleCommand
end

--[[ /rxp、/rxpg、/rxpguides 已被 RXPGuides 本体占用（SettingsPanel.lua:269-271，
     经 AceConsole 动态注册，源码里搜不到字面量），所以主命令取 /rxphide。
     SlashCmdList 一旦有值，后加载的插件不会覆盖，加载顺序不用操心。 --]]
RegisterSlash()

-- ---------------------------------------------------------------- 事件

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            SyncDB()            -- 此刻存档才 100% 就位，重新绑定后再读
            LoadSettings()
            MarkLoaded()
        elseif arg1 == "RXPGuides" then
            MarkRXPState()
        end

    elseif event == "PLAYER_LOGIN" then
        CheckCommandConflict()
        if DB.tips then PrintBanner() end
        WhenReady(function()
            local fixed = RealignFrames()
            if fixed > 0 then Print(("已复位 %d 个窗口"):format(fixed)) end
            if InCombatLockdown() then HideNow(false) end
        end, 60, function()
            Print("|cffffff00等不到 RXPGuides 就绪|r —— 它可能没启用，本插件不会生效。")
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        inCombatHide, beforeShowEnabled = false, nil
        rectKey = nil                             -- 框架可能已重建，缓存作废
        if InCombatLockdown() then
            -- 战斗中重载/切场景：直接按档位归位，别经过"全亮"的中间态
            WhenReady(function() HideNow(false) end, 20)
        else
            SnapTo(1)
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        HideNow(true)

    elseif event == "PLAYER_REGEN_ENABLED" then
        ShowNow(true)

    elseif event == "PLAYER_LOGOUT" then
        SaveSettings()
    end
end)
