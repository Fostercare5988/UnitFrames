-- F8: your and your target's buffs and debuffs under their frames, 20 px, eight
-- to a line: sweeps, countdowns, stacks, dispel colours (F10's borders). The
-- stock target auras give way.
local _, F = ...
local db = UnitFramesDB

local SIZE, GAP, PER_LINE, MAX = 20, 3, 8, 32
local OVERLAY = "Interface\\Buttons\\UI-Debuff-Overlays"

local function OnEnter()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetUnitAura(this.row.unit, this.index, this.row.filter)
    GameTooltip:Show()
end
local function OnLeave() GameTooltip:Hide() end
local function OnClick() -- right-click cancels a buff of yours
    if this.row.unit == "player" and this.row.filter == "HELPFUL" and this.spellID then
        C_Spell.CancelSpellByID(this.spellID)
    end
end

local function NewButton(row, i)
    local b = CreateFrame("Button", nil, row)
    F.Icon(b, SIZE, 9)
    local x, y = ((i - 1) % PER_LINE) * (SIZE + GAP), -math.floor((i - 1) / PER_LINE) * (SIZE + GAP)
    b:SetPoint("TOP" .. row.side, row, "TOP" .. row.side, row.side == "RIGHT" and -x or x, y)
    b.edge = F.Edge(b)
    b.edge:SetVertexColor(0.15, 0.15, 0.15, 1)
    b.overlay = b:CreateTexture(nil, "OVERLAY")
    b.overlay:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.overlay:SetWidth(SIZE + 2); b.overlay:SetHeight(SIZE + 2)
    b.overlay:SetTexture(OVERLAY)
    b.overlay:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    b.overlay:Hide()
    b.row = row
    b:RegisterForClicks("RightButtonUp")
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b:SetScript("OnClick", OnClick)
    row.buttons[i] = b
    return b
end

-- A row: a named frame (the client saves where the player put it), its buttons
-- made as auras need them.
local function NewRow(name, unit, filter, frame, side, label)
    local row = CreateFrame("Frame", "UnitFrames" .. name, frame)
    row:SetWidth(PER_LINE * (SIZE + GAP) - GAP); row:SetHeight(SIZE)
    row:SetFrameStrata("LOW")
    row.unit, row.filter, row.frame, row.side, row.buttons, row.used = unit, filter, frame, side, {}, 0
    row.key = string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
    F.Movable(row, label)
    return row
end
local rows = {
    NewRow("PlayerBuffs", "player", "HELPFUL", PlayerFrame, "LEFT", "Your buffs"),
    NewRow("PlayerDebuffs", "player", "HARMFUL", PlayerFrame, "LEFT", "Your debuffs"),
    NewRow("TargetBuffs", "target", "HELPFUL", TargetFrame, "RIGHT", "Target buffs"),
    NewRow("TargetDebuffs", "target", "HARMFUL", TargetFrame, "RIGHT", "Target debuffs"),
}

-- F10: buffs a dark edge, debuffs their dispel colour; written when the look changes.
local function Border(b, dispel)
    local look = b.row.filter == "HELPFUL" and (db.buffBorders and "buff" or "off")
        or db.debuffBorders and (dispel or "") or "off"
    if b.look == look then return end
    b.look = look
    b.edge:SetShown(look == "buff")
    b.overlay:SetShown(look ~= "buff" and look ~= "off")
    if look ~= "buff" and look ~= "off" then
        local c = C_UnitAuras.GetAuraDispelTypeColor(look)
        b.overlay:SetVertexColor(c.r, c.g, c.b, 1)
    end
end

-- Under its frame until the player moves it; debuffs under the buffs while
-- there are any (the target's lower: its target of target and cast bar sit there).
local function Place(row)
    if row:IsUserPlaced() then return end
    row:ClearAllPoints()
    local buffs = row.filter == "HARMFUL" and rows[row.unit == "player" and 1 or 3]
    local x, y = row.side == "RIGHT" and -5 or 5, row.side == "RIGHT" and -34 or 12
    if buffs and buffs.used > 0 and buffs:IsShown() and not buffs:IsUserPlaced() then
        local lines = math.ceil(buffs.used / PER_LINE)
        row:SetPoint("TOP" .. row.side, buffs, "TOP" .. row.side, 0, -lines * (SIZE + GAP) - 1)
    else
        row:SetPoint("TOP" .. row.side, row.frame, "BOTTOM" .. row.side, x, y)
    end
end

local slots = {}
-- The unit's auras of the row's kind, in the game's order; one shown elsewhere
-- (a watched aura) takes no button.
local function Fill(row)
    local used = 0
    if db[row.key] and UnitExists(row.unit) then
        local _, n = C_UnitAuras.GetAuraSlots(row.unit, row.filter, nil, nil, slots)
        for i = 1, n do
            if used == MAX then break end
            local name, texture, stacks, dispel, duration, expires, source, _, _, spellID =
                C_UnitAuras.UnitAuraBySlot(row.unit, slots[i])
            if texture and not F.Hidden(name, row.unit, nil, source) then
                used = used + 1
                local b = row.buttons[used] or NewButton(row, used)
                b.index, b.spellID, b.source = i, spellID, source and UnitGUID(source)
                F.Texture(b.icon, texture)
                F.Stacks(b, stacks)
                F.Timing(b, duration, expires)
                Border(b, dispel)
                b:Show()
            end
        end
    end
    for i = used + 1, row.used do row.buttons[i]:Hide() end
    row.used = used
    row:SetShown(db[row.key] and UnitExists(row.unit) and true or false)
end

local function Unit(unit)
    for _, row in ipairs(rows) do if row.unit == unit then Fill(row) end end
    for _, row in ipairs(rows) do if row.unit == unit then Place(row) end end
end

-- Only refreshes or stack changes: each rewrites its own button. A new or lost
-- aura moves the others, so the rows are read again; so is an aura with no button.
local data = {}
local function Refresh(unit, ids)
    for i = 1, #ids do
        local d = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, ids[i], data)
        if not d then return false end
        local row = rows[(unit == "player" and 1 or 3) + (d.isHelpful and 0 or 1)]
        local hit = F.Hidden(d.name, unit, nil, d.sourceUnit)
        for j = 1, hit and 0 or row.used do
            local b = row.buttons[j]
            if b.spellID == d.spellId and b.source == d.sourceGUID then
                F.Stacks(b, d.applications)
                F.Timing(b, d.duration, d.expirationTime)
                hit = true
                break
            end
        end
        if not hit then return false end
    end
    return true
end

-- The stock target auras give way. TargetFrame's UNIT_AURA only draws them
-- (TargetFrame.lua:87-90, TargetDebuffButton_Update), so it is off; the hook
-- hides what a target change and the stock target of target still draw.
TargetFrame:UnregisterEvent("UNIT_AURA")
hooksecurefunc("TargetDebuffButton_Update", function()
    for i = 1, 5 do _G["TargetFrameBuff" .. i]:Hide() end
    for i = 1, 16 do _G["TargetFrameDebuff" .. i]:Hide() end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterUnitEvent("UNIT_AURA_DELTA", "player", "target") -- not the target's raid or plate copies
events:SetScript("OnEvent", function(_, e, unit, info)
    if e == "UNIT_AURA_DELTA" then
        local ids = info.updatedAuraInstanceIDs
        if not (ids and not info.isFullUpdate and not info.addedAuraInstanceIDs
            and not info.removedAuraInstanceIDs and Refresh(unit, ids)) then Unit(unit) end
    elseif e == "PLAYER_TARGET_CHANGED" then
        Unit("target")
    else
        Unit("player"); Unit("target")
    end
end)

function F.Rows() Unit("player"); Unit("target") end
-- A switch: its row; the borders: every button.
for _, row in ipairs(rows) do F.apply[row.key] = F.Rows end
F.apply.buffBorders = function()
    for _, row in ipairs(rows) do for _, b in ipairs(row.buttons) do b.look = nil end end
    F.Rows()
    if F.TopRight then F.TopRight() end
end
F.apply.debuffBorders = F.apply.buffBorders
