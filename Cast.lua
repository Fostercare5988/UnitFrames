-- The target's cast bar (F3) and your own, moved with Ctrl+Shift (F4).
local _, F = ...
local db = UnitFramesDB

local GOLD, GREY = { 1, 0.8, 0 }, { 0.65, 0.65, 0.65 }
local bar = CreateFrame("StatusBar", "UnitFramesTargetCast", TargetFrame)
bar:SetWidth(140); bar:SetHeight(10)
bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
bar:SetBackdropColor(0.1, 0.1, 0, 0.8)
bar:SetBackdropBorderColor(0, 0, 0, 1)
bar:Hide()
bar.icon = bar:CreateTexture(nil, "ARTWORK")
bar.icon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
bar.icon:SetWidth(14); bar.icon:SetHeight(14)
bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
bar.spark = bar:CreateTexture(nil, "OVERLAY")
bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
bar.spark:SetWidth(20); bar.spark:SetHeight(20)
bar.spark:SetBlendMode("ADD")
bar.spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)
bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontWhite")
bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
bar.text:SetFont(STANDARD_TEXT_FONT, 10, "THINOUTLINE")
-- The bar fills itself from the cast's span (statusbar:SetTimerDuration), so
-- nothing runs per frame during a cast.
local span = C_DurationUtil.CreateDuration()
local endsAt, channel, locked

-- Under the target frame, lower while the target of target shows; once the
-- player has moved it, where it was put.
local function Place()
    if bar:IsUserPlaced() then return end
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOM", TargetFrame, "BOTTOM", -12, TargetofTargetFrame:IsShown() and -24 or -4)
end
TargetofTargetFrame:HookScript("OnShow", Place)
TargetofTargetFrame:HookScript("OnHide", Place)

local function Stop()
    endsAt, channel, locked = nil, nil, nil
    bar:Hide()
end
-- The stop event ends a cast; this one-shot check covers a missed one.
local function EndIfOver()
    if endsAt and GetTime() >= endsAt then Stop() end
end

local function Read()
    if not db.targetCastbar or not UnitExists("target") or UnitIsDeadOrGhost("target") then return Stop() end
    local isChannel = false
    local name, _, texture, start, finish, _, _, notInterruptible = C_Spell.UnitCastingInfo("target")
    if not name then
        name, _, texture, start, finish, _, notInterruptible = C_Spell.UnitChannelInfo("target")
        isChannel = name ~= nil
    end
    if not name or not finish or finish <= GetTime() * 1000 then return Stop() end
    span:SetTimeSpan(start / 1000, finish / 1000)
    if channel ~= isChannel then
        channel = isChannel
        bar:SetTimerDuration(span, Enum.StatusBarInterpolation.Immediate, isChannel
            and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime)
    end
    if endsAt ~= finish / 1000 then
        endsAt = finish / 1000
        C_Timer.After(endsAt - GetTime() + 0.05, EndIfOver)
    end
    local grey = notInterruptible and true or false
    if locked ~= grey then
        locked = grey
        local c = grey and GREY or GOLD
        bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    end
    F.Text(bar.text, name)
    F.Texture(bar.icon, texture)
    Place()
    bar:Show()
end

-- ClassicAPI fires these once per token that points at the caster; only the
-- "target" copy reaches this frame. DELAYED and FAILED never fire for other units.
local EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }
local STOPS = { UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_CHANNEL_STOP = true }
local casts = CreateFrame("Frame")
casts:SetScript("OnEvent", function(_, e) if STOPS[e] then Stop() else Read() end end)
F.apply.targetCastbar = function()
    casts:UnregisterAllEvents()
    if db.targetCastbar then
        casts:RegisterEvent("PLAYER_TARGET_CHANGED")
        for _, e in ipairs(EVENTS) do casts:RegisterUnitEvent(e, "target") end
    end
    Read()
end
F.apply.targetCastbar()
F.Movable(bar, "Target cast bar", function() if not endsAt then bar:Hide() end end)

-- F4: your own cast bar, which the game puts back above the action bars whenever
-- it lays out the screen (FrameXML UIParent.lua, UIPARENT_MANAGED_FRAME_POSITIONS).
-- So its place is saved here (its top left against the screen's), not by the client.
local cast = CastingBarFrame
cast:SetDontSavePosition(true)
local function PlaceCast()
    local p = db.castbar
    if not p then return end
    cast:ClearAllPoints()
    cast:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p[1], p[2])
end
hooksecurefunc("UIParent_ManageFramePositions", PlaceCast)
PlaceCast()
F.Movable(cast, "Cast bar",
    function() if not (cast.casting or cast.channeling or cast.fadeOut) then cast:Hide() end end,
    function() db.castbar = { cast:GetLeft(), cast:GetTop() - UIParent:GetTop() }; PlaceCast() end)
