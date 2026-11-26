-- F7: energy ticks and the five-second mana rule on your power bar: a bright
-- line runs to the next tick (OnUpdate while it shows: animation, VANILLAFORGE §2)
-- and the bar's bottom edge flashes on each tick. Width 6, the player's values.
local _, F = ...
local db = UnitFramesDB

local bar = PlayerFrameManaBar
local line = CreateFrame("Frame", nil, bar)
line:SetAllPoints(bar)
line:Hide()
local spark = bar:CreateTexture(nil, "ARTWORK")   -- below the OVERLAY power text
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetBlendMode("ADD")
spark:SetVertexColor(1, 1, 1, 0.9)
local glow = bar:CreateTexture(nil, "ARTWORK")
glow:SetTexture("Interface\\Buttons\\WHITE8X8")
glow:SetBlendMode("ADD")
glow:SetVertexColor(1, 1, 1, 0.45)
glow:SetPoint("CENTER", spark, "CENTER", 0, 0)
local core = bar:CreateTexture(nil, "ARTWORK")
core:SetTexture("Interface\\Buttons\\WHITE8X8")
core:SetPoint("CENTER", spark, "CENTER", 0, 0)
local pulse = bar:CreateTexture(nil, "ARTWORK")
pulse:SetTexture("Interface\\Buttons\\WHITE8X8")
pulse:SetBlendMode("ADD")
pulse:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
local parts = { spark, glow, core, pulse }

-- The tick clock: the last tick (start), the period (2 s, or 5 s after mana was
-- spent), and whether a real tick has been seen (synced: until then no flash).
local start, period, blockedUntil, synced = 0, 2, nil, false
local power, last, width, half, scale, lastX, lastAlpha

local function Render()
    local now = GetTime()
    if period == 5 and now >= blockedUntil then start, period = blockedUntil, 2 end
    local elapsed = (now - start) % period
    local x = half + (width - 2 * half) * elapsed / period
    x = math.floor(x * scale + 0.5) / scale -- move only when the screen pixel changes
    if x ~= lastX then lastX = x; spark:SetPoint("CENTER", bar, "LEFT", x, 0) end
    local alpha = synced and period == 2 and elapsed < 0.25 and math.floor((1 - elapsed / 0.25) * 16 + 0.5) / 16 or 0
    if alpha ~= lastAlpha then lastAlpha = alpha; pulse:SetAlpha(alpha) end
end

-- Shown for energy and mana, alive, on a visible bar; laid out when its size changes.
local function Refresh()
    local on = db.energyTicks and bar:IsVisible() and not UnitIsDeadOrGhost("player")
        and (power == 0 or power == 3) and bar:GetWidth() > 0
    if not on then
        line:SetScript("OnUpdate", nil)
        for _, t in ipairs(parts) do t:Hide() end
        return
    end
    if width ~= bar:GetWidth() then
        width = bar:GetWidth()
        local h = bar:GetHeight()
        half = math.min(12, width) / 2
        spark:SetWidth(half * 2); spark:SetHeight(math.min(16, h))
        core:SetWidth(math.min(6, half * 2)); core:SetHeight(math.min(16, h))
        glow:SetWidth(math.min(8, half * 2)); glow:SetHeight(math.min(16, h))
        pulse:SetWidth(width); pulse:SetHeight(math.min(4, h))
        lastX = nil
    end
    scale = bar:GetEffectiveScale()
    for _, t in ipairs(parts) do t:Show() end
    line:Show()
    line:SetScript("OnUpdate", Render)
    Render()
end
F.apply.energyTicks = Refresh
function F.Tick() return start, period end

-- Until a gain shows where the server's tick falls, a 2 s cycle from now, unflashed.
local gain, gainAt, spellGain, spellAt, candidate = 0, nil, 0, nil, nil
local function Reset()
    power, last = UnitPowerType("player"), UnitMana("player")
    gain, gainAt, candidate = 0, nil, nil
    start, period, blockedUntil, synced = GetTime(), 2, nil, false
    Refresh()
end

-- A gain is a tick unless a spell gave it (NamPower SPELL_ENERGIZE_ON_SELF, which
-- can arrive just after the power update: the gain is judged 0.15 s later).
local function Judge()
    local at, amount = gainAt, gain
    if not at then return end -- a reset since
    if spellAt and math.abs(at - spellAt) <= 0.35 then amount = amount - spellGain end
    gain, gainAt, spellGain, spellAt = 0, nil, 0, nil
    if amount <= 0 then return end
    if power == 3 then
        -- 20 a tick, 40 doubled; a smaller last tick fills the bar. Once synced,
        -- an off-phase gain moves the clock only when two come 2 s apart.
        local capped = UnitMana("player") == UnitManaMax("player") and amount <= 44
        local tick = amount >= 20 and amount <= 22 or amount >= 40 and amount <= 44 or capped
        if tick and synced then
            local phase = (at - start) % 2
            if phase >= 0.35 and phase <= 1.65 then
                tick = candidate and at - candidate >= 1.65 and at - candidate <= 2.35
                candidate = at
            else
                candidate = nil
            end
        end
        if tick then start, period, candidate, synced = at, 2, nil, true end
    elseif not blockedUntil or at >= blockedUntil then
        start, period, synced = at, 2, true
    end
    Refresh()
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "UI_SCALE_CHANGED", "SPELL_ENERGIZE_ON_SELF" }) do events:RegisterEvent(e) end
events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
events:SetScript("OnEvent", function(_, e, _, _, _, kind, amount)
    if e == "SPELL_ENERGIZE_ON_SELF" then
        if kind == power and amount and amount > 0 then
            local now = GetTime()
            if not spellAt or now - spellAt > 0.35 then spellGain = 0 end
            spellGain, spellAt = spellGain + amount, now
        end
    elseif e == "UI_SCALE_CHANGED" then
        Refresh()
    elseif e ~= "UNIT_POWER_UPDATE" or UnitPowerType("player") ~= power then
        Reset()
    else
        local value = UnitMana("player")
        local diff = value - last
        last = value
        if diff < 0 and power == 0 then -- mana spent: five seconds without a tick
            start, period = GetTime(), 5
            blockedUntil = start + 5
        elseif diff > 0 then
            if not gainAt then C_Timer.After(0.15, Judge) end
            gain, gainAt = gain + diff, GetTime()
        end
    end
end)
for _, frame in ipairs({ PlayerFrame, bar }) do
    frame:HookScript("OnShow", Refresh)
    frame:HookScript("OnHide", Refresh)
    frame:HookScript("OnSizeChanged", Refresh)
end
Reset()
