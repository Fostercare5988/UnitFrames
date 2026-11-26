-- Blizzard's unit frames: class colours (F1), exact numbers (F2), target of target
-- by event (F5), raid marks (F6), and the stock frames' handles (F13).
local _, F = ...
local db = UnitFramesDB

-- F1: the class colour behind the player's and target's names, on BORDER: above
-- the frames' 50% black square (BACKGROUND), below their art. NPC targets keep
-- the game's reaction colour; party names are written in the colour.
local FILL = "Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground"
local playerFill = PlayerFrame:CreateTexture(nil, "BORDER")
playerFill:SetTexture(FILL)
playerFill:SetWidth(119); playerFill:SetHeight(19)
playerFill:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 106, -22)
local targetFill = TargetFrame:CreateTexture(nil, "BORDER")
targetFill:SetTexture(FILL)
targetFill:SetAllPoints(TargetFrameNameBackground)

local function Fill(texture, unit)
    local _, class = UnitClass(unit)
    local color = db.classColors and UnitIsPlayer(unit) and RAID_CLASS_COLORS[class or ""]
    if color then texture:SetVertexColor(color.r, color.g, color.b, 1) end
    texture:SetShown(color and true or false)
end
local function ColorPlayer() Fill(playerFill, "player") end
local function ColorTarget() Fill(targetFill, "target") end
local function ColorParty()
    for i = 1, MAX_PARTY_MEMBERS do
        local _, class = UnitClass("party" .. i)
        local color = db.classColors and RAID_CLASS_COLORS[class or ""] or NORMAL_FONT_COLOR
        _G["PartyMemberFrame" .. i .. "Name"]:SetTextColor(color.r, color.g, color.b)
    end
end
hooksecurefunc("PlayerFrame_Update", ColorPlayer)
hooksecurefunc("TargetFrame_CheckFaction", ColorTarget)
hooksecurefunc("PartyMemberFrame_UpdateMember", ColorParty)
F.apply.classColors = function() ColorPlayer(); ColorTarget(); ColorParty() end
F.apply.classColors()

-- F2: exact health and mana on the player and target frames (the target's in
-- thousands, with its percent while hurt), the pet's smaller; hidden under "Dead".
TargetHPText:SetAlpha(0)     -- the stock target numbers, shown by its XML on hover
TargetHPPercText:SetAlpha(0)
local texts = CreateFrame("Frame", nil, TargetFrame)
texts:SetAllPoints(TargetFrame)
TargetFrameHealthBar.TextString = texts:CreateFontString(nil, "OVERLAY")
TargetFrameHealthBar.TextString:SetPoint("TOP", TargetFrameHealthBar, "BOTTOM", -2, 23)
TargetFrameManaBar.TextString = texts:CreateFontString(nil, "OVERLAY")
TargetFrameManaBar.TextString:SetPoint("TOP", TargetFrameManaBar, "BOTTOM", -2, 22)
PetFrameHealthBar.TextString:SetPoint("CENTER", PetFrameHealthBar, "CENTER", -2, 0)
PetFrameManaBar.TextString:SetPoint("CENTER", PetFrameManaBar, "CENTER", -2, -2)

local BARS = { [PlayerFrameHealthBar] = "player", [PlayerFrameManaBar] = "player",
    [TargetFrameHealthBar] = "target", [TargetFrameManaBar] = "target",
    [PetFrameHealthBar] = "pet", [PetFrameManaBar] = "pet" }
local HEALTH = { [PlayerFrameHealthBar] = true, [TargetFrameHealthBar] = true, [PetFrameHealthBar] = true }
for bar, unit in pairs(BARS) do
    local fs = bar.TextString
    fs:SetFont(STANDARD_TEXT_FONT, unit == "pet" and 9 or 10, "OUTLINE")
    fs:SetHeight(32)
    if unit == "pet" then fs:SetJustifyH("LEFT") end
end

local function Numbers(bar)
    bar = bar or this
    local unit = BARS[bar]
    if not unit then return end
    local fs = bar.TextString
    local cur, max = bar:GetValue(), select(2, bar:GetMinMaxValues())
    if bar == TargetFrameHealthBar then cur, max = UnitHealth("target"), UnitHealthMax("target") end
    if max == 0 or unit == "target" and (UnitIsDeadOrGhost("target") or UnitHealth("target") <= 0) then
        F.Text(fs, ""); fs:Hide()
        return
    end
    local text
    local percent = math.floor(cur / max * 100)
    if HEALTH[bar] and max <= 100 and cur == percent then
        text = percent .. "%" -- the server gives no exact health for this unit
    elseif bar == TargetFrameHealthBar and cur < max then
        text = AbbreviateNumbers(cur) .. " - " .. percent .. "%"
    else
        text = AbbreviateNumbers(cur)
    end
    bar.lockShow = 1 -- shown without hovering (FrameXML TextStatusBar.lua)
    fs.written = nil -- the stock function wrote its own text just before
    F.Text(fs, text)
    fs:Show()
end
hooksecurefunc("TextStatusBar_UpdateTextString", Numbers)
-- Death changes no mana value, so both numbers are read again then.
hooksecurefunc("TargetFrame_CheckDead", function() Numbers(TargetFrameHealthBar); Numbers(TargetFrameManaBar) end)

-- F5: the stock target of target redraws itself every frame it shows
-- (TargetFrame.xml OnUpdate: TargetofTarget_OnUpdate, which also runs the target's
-- whole aura update). Here it redraws when what it shows changes: the target picks
-- someone else (UNIT_TARGET), or that unit's health, power, auras, name or
-- portrait change (NamPower's GUID events: "targettarget" gets no unit events).
local tot = TargetofTargetFrame
tot:SetScript("OnUpdate", nil)
local driver = CreateFrame("Frame")
local GUID_EVENTS = { "UNIT_HEALTH_GUID", "UNIT_MANA_GUID", "UNIT_RAGE_GUID", "UNIT_ENERGY_GUID",
    "UNIT_AURA_GUID", "UNIT_NAME_UPDATE_GUID", "UNIT_PORTRAIT_UPDATE_GUID" }
local POWER = { UNIT_MANA_GUID = true, UNIT_RAGE_GUID = true, UNIT_ENERGY_GUID = true }
local shownGUID, listening, targetAlive

local function Listen(on)
    if listening == on then return end
    listening = on
    for _, e in ipairs(GUID_EVENTS) do
        if on then driver:RegisterEvent(e) else driver:UnregisterEvent(e) end
    end
end
-- The unit shown: its name and portrait when it is another unit.
local function ReadUnit()
    local guid = UnitGUID("targettarget")
    CURRENT_TARGETTARGET = UnitName("targettarget")
    if guid and guid ~= shownGUID then
        SetPortraitTexture(tot.portrait, tot.unit)
        tot.name:SetText(GetUnitName(tot.unit))
    end
    shownGUID = guid
    Listen(guid ~= nil and tot:IsShown() and true or false)
end

driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:RegisterUnitEvent("UNIT_TARGET", "target")
driver:RegisterUnitEvent("UNIT_HEALTH", "target")
driver:SetScript("OnEvent", function(_, e, guid)
    if e == "UNIT_TARGET" or e == "GROUP_ROSTER_UPDATE" then
        -- Whether it shows can depend on the group (SHOW_TARGET_OF_TARGET_STATE).
        ReadUnit(); TargetofTarget_Update()
    elseif e == "PLAYER_TARGET_CHANGED" then -- TargetFrame's own handler updates it
        targetAlive = UnitHealth("target") > 0
        ReadUnit()
    elseif e == "UNIT_HEALTH" then -- the stock update hides it while the target is dead
        local alive = UnitHealth("target") > 0
        if alive ~= targetAlive then targetAlive = alive; TargetofTarget_Update() end
    elseif guid == shownGUID then
        if e == "UNIT_HEALTH_GUID" then
            UnitFrameHealthBar_Update(tot.healthbar, tot.unit)
            TargetofTarget_CheckDead()
        elseif POWER[e] then
            UnitFrameManaBar_Update(tot.manabar, tot.unit)
        elseif e == "UNIT_AURA_GUID" then
            RefreshBuffs(tot, 0, tot.unit)
        elseif e == "UNIT_NAME_UPDATE_GUID" then
            tot.name:SetText(GetUnitName(tot.unit))
        else
            SetPortraitTexture(tot.portrait, tot.unit)
        end
    end
end)
-- TargetFrame shows it when a target of target appears; read the unit then.
tot:HookScript("OnShow", ReadUnit)
tot:HookScript("OnHide", function() Listen(false) end)

-- F6: the target's raid mark on its portrait. Solo the server refuses marks;
-- NamPower's SetRaidTarget then sets one only this client sees
-- (NP_EnableLocalSetRaidTarget), and the target frame is redrawn here.
-- UNVERIFIED: whether RAID_TARGET_UPDATE fires for a local mark.
TargetRaidTargetIcon:ClearAllPoints()
TargetRaidTargetIcon:SetPoint("CENTER", TargetPortrait, "CENTER", 0, 0)
TargetRaidTargetIcon:SetWidth(22); TargetRaidTargetIcon:SetHeight(22)
hooksecurefunc("SetRaidTarget", function()
    if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then TargetFrame_UpdateRaidTargetIcon() end
end)

-- F13: the stock frames' handles; the client saves where they were put.
F.Movable(PlayerFrame, "Player")
F.Movable(TargetFrame, "Target")
F.Movable(tot, "Target of target")
