-- F9: Blizzard's buffs, debuffs and weapon enchants at the top right, each area
-- moved with Ctrl+Shift; each hand's poison over its weapon, main hand left; F10's
-- borders. The stock buttons redraw themselves every frame (BuffFrame.xml: the
-- buttons' BuffButton_OnUpdate, TemporaryEnchantFrame's BuffFrame_Enchant_OnUpdate,
-- BuffFrame's flash clock). Here the time left is a countdown on the icon (F12),
-- and a button runs its stock redraw only while it flashes (its last
-- BUFF_WARNING_TIME seconds) or holds the tooltip.
local _, F = ...
local db = UnitFramesDB

local function Area(name, label, width, height, x, y)
    local area = CreateFrame("Frame", "UnitFrames" .. name, UIParent)
    area:SetWidth(width); area:SetHeight(height)
    area:SetFrameStrata("LOW")
    if not area:IsUserPlaced() then area:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x, y) end
    F.Movable(area, label)
    area.buttons = {}
    return area
end
local buffs = Area("TopBuffs", "Buffs", 275, 70, -250, -13)
local debuffs = Area("TopDebuffs", "Debuffs", 275, 35, -250, -95)
local enchants = Area("Enchants", "Weapon enchants", 65, 30, -180, -13)
local areas = { buffs, debuffs }

-- The stock clocks: the flash (BuffFrame) and the enchants' redraw, run only
-- while a button is live (flashing or under the cursor).
local frameClock = BuffFrame:GetScript("OnUpdate")
local enchantClock = TemporaryEnchantFrame:GetScript("OnUpdate")
BuffFrame:SetScript("OnUpdate", nil)
TemporaryEnchantFrame:SetScript("OnUpdate", nil)
local live = {}
local function Live(b, on)
    if (live[b] or false) == on then return end
    live[b] = on or nil
    b:SetScript("OnUpdate", on and b.stock or nil)
    if not on then b:SetAlpha(1) end
    BuffFrame:SetScript("OnUpdate", next(live) and frameClock or nil)
    local enchant = live[TempEnchant1] or live[TempEnchant2]
    TemporaryEnchantFrame:SetScript("OnUpdate", enchant and enchantClock or nil)
end

-- When each button starts to flash (its last BUFF_WARNING_TIME seconds); one
-- shared timer wakes at the earliest. It is armed again only when that moment
-- comes sooner, so an aura change makes no new timer or closure (a timer each
-- was 0.5 KB/s of garbage, /lag 2026-11-17). A timer that finds the wake moved
-- later does nothing.
local flashAt, wakeAt, Wake = {}, nil, nil
local function Arm(at)
    if wakeAt and wakeAt <= at then return end
    wakeAt = at
    C_Timer.After(at - GetTime(), Wake)
end
Wake = function()
    local now = GetTime() + 0.01
    if not wakeAt or now < wakeAt then return end
    wakeAt = nil
    for b, at in pairs(flashAt) do
        if at <= now then flashAt[b] = nil; Live(b, true) end
    end
    for _, at in pairs(flashAt) do Arm(at) end
end

-- The countdown from the time left; the button turns live when it starts to flash.
local function Countdown(b, left)
    local hovered = GameTooltip:IsOwned(b) and true or false
    if not left or left <= 0 then
        flashAt[b] = nil
        b.cd:Clear(); b.ends = nil
        return Live(b, hovered)
    end
    local ends = GetTime() + left
    if not b.ends or math.abs(b.ends - ends) > 0.1 then
        b.ends = ends
        b.cd:SetCooldown(GetTime(), left)
        flashAt[b] = left > BUFF_WARNING_TIME and ends - BUFF_WARNING_TIME or nil
        if flashAt[b] then Arm(flashAt[b]) end
    end
    Live(b, hovered or left <= BUFF_WARNING_TIME)
end

-- Shown buttons right to left, eight to a line, closing up round hidden ones;
-- once a frame after they change. The enchants are placed by Weapons: only they
-- swap (BuffFrame_Enchant_OnUpdate gives TempEnchant1 the off hand when it has one).
local pending
local function Layout()
    pending = nil
    for _, area in ipairs(areas) do
        local n = 0
        for _, b in ipairs(area.buttons) do
            if b:IsShown() then
                b:ClearAllPoints()
                b:SetPoint("TOPRIGHT", area, "TOPRIGHT", -(n % 8) * 35, -math.floor(n / 8) * 35)
                n = n + 1
            end
        end
    end
end
local function LayoutSoon()
    if not pending then pending = true; C_Timer.After(0, Layout) end
end

local function Setup(b, area)
    local name = b:GetName()
    b:SetParent(area)
    b.stock = b:GetScript("OnUpdate")
    b:SetScript("OnUpdate", nil)
    _G[name .. "Duration"]:SetAlpha(0) -- the stock label; the countdown replaces it
    _G[name .. "Icon"]:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- The stock icon and count are on BACKGROUND (BuffFrame.xml:9-18), the edge's
    -- layer, and one layer draws in no fixed order: the edge hid the icon.
    _G[name .. "Icon"]:SetDrawLayer("ARTWORK")
    _G[name .. "Count"]:SetDrawLayer("OVERLAY")
    b.border = _G[name .. "Border"]
    b.cd = F.Cooldown(b, 12)
    b.cd:SetDrawSwipe(false)
    b.edge = F.Edge(b)
    b:HookScript("OnEnter", function() Live(b, true) end)
    b:HookScript("OnLeave", function() Countdown(b, b.ends and b.ends - GetTime()) end)
    area.buttons[#area.buttons + 1] = b
end

local function Style(b)
    if b.buffFilter == "HARMFUL" then
        b.border:SetAlpha(db.debuffBorders and 1 or 0)
    else
        b.edge:SetVertexColor(0.15, 0.15, 0.15, 1)
        b.edge:SetShown(db.buffBorders)
    end
end

-- After the stock BuffButton_Update (every PLAYER_AURAS_CHANGED): hidden when the
-- aura has no icon or shows elsewhere (SuperWoW GetPlayerBuffID names it), then
-- its countdown. An aura with no icon (a tracking aura such as Find Herbs) would
-- be a bare grey edge; the rows under the frames leave those out too.
-- Per spell ID: its name, or false when its aura has no icon. Read once: the two
-- reads made new strings for every button at every change (0.13 KB/s, /lag
-- 2026-11-18).
local auraName = {}
hooksecurefunc("BuffButton_Update", function()
    local b = this
    if not b.cd then return end
    local index = b.buffIndex
    local id = index >= 0 and GetPlayerBuffID(index)
    local name = id and auraName[id]
    if id and name == nil then
        name = GetPlayerBuffTexture(index) and (GetSpellInfo(id) or "") or false
        auraName[id] = name
    end
    if index >= 0 and (id and not name or not id and not GetPlayerBuffTexture(index)) then b:Hide()
    elseif name and F.Hidden(name, "player", "top") then b:Hide() end
    Countdown(b, b:IsShown() and b.untilCancelled ~= 1 and GetPlayerBuffTimeLeft(index))
    Style(b)
    local shown = b:IsShown() and true or false
    if b.wasShown ~= shown then b.wasShown = shown; LayoutSoon() end
end)
hooksecurefunc("BuffButtons_UpdatePositions", LayoutSoon) -- it re-anchors stock buttons

-- A new duration is an update in UNIT_AURA_DELTA (API.md, updatedAuraInstanceIDs);
-- the stock redraw that caught one each frame is off, so the shown icons read
-- their time again. An aura added or gone waits for the stock update, which
-- renumbers them. UNVERIFIED: that a stun's time (diminishing returns included)
-- arrives after PLAYER_AURAS_CHANGED; the second Cheap Shot showed no time at
-- the top right (2026-11-18).
local times = CreateFrame("Frame")
times:RegisterUnitEvent("UNIT_AURA_DELTA", "player")
times:SetScript("OnEvent", function(_, _, _, info)
    if info.isFullUpdate or info.addedAuraInstanceIDs or info.removedAuraInstanceIDs
        or not info.updatedAuraInstanceIDs then return end
    for _, area in ipairs(areas) do
        for _, b in ipairs(area.buttons) do
            if b:IsShown() and b.untilCancelled ~= 1 then Countdown(b, GetPlayerBuffTimeLeft(b.buffIndex)) end
        end
    end
end)

-- The weapons: the stock redraw once per change (WEAPON_ENCHANT_CHANGED fires on
-- apply, renew, removal and each charge; WEAPON_SLOT_CHANGED on a new weapon).
local poisons, missed, bag = {}, {}, {}
-- GAP: the icon of a temporary enchant (a DLL could give the item that made it).
-- The item of the enchant's name in your bags (the poison itself), else its spell's.
local function PoisonIcon(id)
    if not id or id == 0 then return nil end
    if poisons[id] then return poisons[id] end
    local info = C_Item.GetEnchantInfo(id)
    if not info then return nil end
    if (missed[id] or 0) > GetTime() then return info.spellID and select(3, GetSpellInfo(info.spellID)) end
    missed[id] = GetTime() + 60 -- not in the bags: look again in a minute, not at every charge
    for b = 0, 4 do
        for s = 1, C_Container.GetContainerNumSlots(b) do
            local item = C_Container.GetContainerItemInfo(b, s, bag)
            if item and item.itemName and item.iconFileID and string.find(item.itemName, info.name, 1, true) == 1 then
                poisons[id] = item.iconFileID
                return poisons[id]
            end
        end
    end
    return info.spellID and select(3, GetSpellInfo(info.spellID))
end

local function Weapons()
    BuffFrame_Enchant_OnUpdate(0)
    local _, mainMs, _, mainID, _, offMs, _, offID = C_Item.GetWeaponEnchantInfo()
    for _, b in ipairs(enchants.buttons) do
        local main = b:GetID() == 16
        local ms, id = main and mainMs or offMs, main and mainID or offID
        Countdown(b, b:IsShown() and ms and ms / 1000)
        local poison = b:IsShown() and PoisonIcon(id)
        F.Texture(b.poison, poison or nil)
        b.poison:SetShown(poison and true or false)
        b.border:SetAlpha(0) -- quality belongs to the weapon, drawn by the edge
        local quality = b:IsShown() and db.enchantBorders and GetInventoryItemQuality("player", b:GetID())
        if quality and quality >= 0 then b.edge:SetVertexColor(GetItemQualityColor(quality)) end
        b.edge:SetShown(quality and quality >= 0 and true or false)
        b:ClearAllPoints() -- by the hand it shows, main hand left
        b:SetPoint("TOPRIGHT", enchants, "TOPRIGHT", b:GetID() == 17 and 0 or -35, 0)
    end
end

-- Areas and switches.
local function Shown()
    buffs:SetShown(db.topBuffs)
    debuffs:SetShown(db.topDebuffs)
    enchants:SetShown(db.enchants)
end
function F.TopRight()
    Shown()
    local was = this -- the stock update reads its button from `this`
    for _, area in ipairs(areas) do
        for _, b in ipairs(area.buttons) do this = b; BuffButton_Update() end
    end
    this = was
    Weapons()
end
F.apply.topBuffs, F.apply.topDebuffs, F.apply.enchants, F.apply.enchantBorders =
    F.TopRight, F.TopRight, F.TopRight, F.TopRight

local i = 0
while _G["BuffButton" .. i] do
    local b = _G["BuffButton" .. i]
    Setup(b, b.buffFilter == "HARMFUL" and debuffs or buffs)
    i = i + 1
end
for n = 1, 2 do
    local b = _G["TempEnchant" .. n]
    Setup(b, enchants)
    b.poison = b:CreateTexture(nil, "OVERLAY")
    b.poison:SetAllPoints(_G["TempEnchant" .. n .. "Icon"])
    b.poison:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

local events = CreateFrame("Frame")
events:RegisterEvent("WEAPON_ENCHANT_CHANGED")
events:RegisterEvent("WEAPON_SLOT_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", Weapons)

F.TopRight() -- the switches and every button once at load
