-- UnitFrames: Blizzard's player, target and pet frames, their auras and cast
-- bars, energy ticks. Doc headings are ClassicAPI's docs/API.md;
-- "FrameXML" is the client's own code.
if not CLASSIC_API_VERSION then error("UnitFrames needs ClassicAPI.", 0) end

local _, F = ...
UnitFramesDB = UnitFramesDB or {} -- restored first: LoadSavedVariablesFirst
local db = UnitFramesDB

-- The page (Page.lua), in play order: a string is a section header, a row is
-- { key, label, tip, default }. A switch is on unless its row says false; the frames
-- start before the Settings window registers the page, so the defaults are written here too.
F.PAGE = {
    "Frames",
    { "classColors", "Class colours", "Your, your target's and your party's class colour behind their names." },
    { "targetCastbar", "Target cast bar", "Your target's casts under its frame; grey when it cannot be interrupted." },
    { "energyTicks", "Energy ticks", "A line on your power bar that runs to the next energy or mana tick." },
    "Under the frames",
    { "playerBuffs", "Your buffs", "Your buffs under your frame, with the time left." },
    { "playerDebuffs", "Your debuffs", "Your debuffs under your frame, in their dispel colour." },
    { "targetBuffs", "Target buffs", "Your target's buffs under its frame." },
    { "targetDebuffs", "Target debuffs", "Your target's debuffs under its frame." },
    "Top right",
    { "topBuffs", "Buffs", "The game's buff icons at the top right." },
    { "topDebuffs", "Debuffs", "The game's debuff icons at the top right." },
    { "topFromLeft", "Fill from the left", "The top-right buffs and debuffs start at the left and fill to the right. Off: they start at the right.", false },
    { "enchants", "Weapon enchants", "Poisons, oils and stones on your weapons, main hand left." },
    "Borders",
    { "buffBorders", "Buff borders", "A thin dark border round every buff icon." },
    { "debuffBorders", "Debuff borders", "A border in the dispel colour round every debuff icon." },
    { "enchantBorders", "Weapon enchant borders", "A border in the weapon's quality colour." },
}
for _, row in ipairs(F.PAGE) do
    if type(row) == "table" and db[row[1]] == nil then db[row[1]] = row[4] ~= false end
end

-- The Auras addon shows some auras on icons of their own; the rows and the top
-- right leave those out. Its one public function: Auras.Hidden.
function F.Hidden(name, unit, place, source)
    return Auras and Auras.Hidden(name, unit, place, source) or false -- vanillaforge-ignore: K1
end

-- What a switch runs when it changes: F.apply[key]().
F.apply = {}

-- F12: one countdown look on every cooldown; the client counts down (the
-- Cooldown section).
local Up = Enum.NumericRuleFormatRounding.Up
F.Countdown = C_StringUtil.CreateNumericRuleFormatter()
F.Countdown:SetBreakpoints({
    { threshold = 0, step = 0.1, rounding = Up, format = "|cffff4444%.1f|r" },
    { threshold = 5, step = 1, rounding = Up, format = "|cffffff33%d|r" },
    { threshold = 10, step = 1, rounding = Up, format = "|cffffffff%d|r" },
    { threshold = 60, format = "|cffffffff%dm|r", components = { { div = 60, step = 1, rounding = Up } } },
    { threshold = 3600, format = "|cffffffff%dh|r", components = { { div = 3600, step = 1, rounding = Up } } },
    { threshold = 86400, format = "|cffffffff%dd|r", components = { { div = 86400, step = 1, rounding = Up } } },
})

-- A native Cooldown over `parent` that counts down in that look.
function F.Cooldown(parent, size)
    local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
    cd:SetAllPoints(parent)
    cd:SetReverse(true)
    cd:SetDrawBling(false)
    cd:SetCountdownFormatter(F.Countdown)
    cd:GetCountdownFontString():SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    return cd
end

-- An aura icon on `b`: its picture, the sweep and countdown, and the stacks above them.
function F.Icon(b, size, textSize)
    b:SetWidth(size); b:SetHeight(size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.cd = F.Cooldown(b, textSize)
    local over = CreateFrame("Frame", nil, b)
    over:SetAllPoints(b)
    over:SetFrameLevel(b:GetFrameLevel() + 5)
    b.count = over:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
end
function F.Stacks(b, stacks) F.Text(b.count, stacks and stacks > 1 and stacks or "") end

-- The sweep of an aura (or a cooldown) ending at `expires`; restarted only when
-- its timing changes.
function F.Timing(b, duration, expires)
    local start = duration and duration > 0 and expires and expires > GetTime() and expires - duration or nil
    if b.start == start and b.duration == duration then return end
    b.start, b.duration = start, duration
    if start then b.cd:SetCooldown(start, duration) else b.cd:Clear() end
end

-- A 1 px frame behind an icon (BACKGROUND, so the icon covers all but the edge).
function F.Edge(button)
    local edge = button:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
    edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    edge:Hide()
    return edge
end

-- A font string's text and a texture's path, written only when they change.
function F.Text(fs, text)
    if fs.written ~= text then fs.written = text; fs:SetText(text) end
end
function F.Texture(tex, path)
    if tex.path ~= path then tex.path = path; tex:SetTexture(path) end
end

-- F13: Ctrl+Shift shows a handle over each frame placed here; dragging it moves the
-- frame (the handle is the frame's child: it shows only while the frame does). The client saves a named frame the player moved (### frame:SetDontSavePosition);
-- `saved` runs after a drag of a frame the game moves again by itself. `reveal`
-- puts back a frame that was shown only to be moved.
local handles, held = {}, false
local keys = CreateFrame("Frame")
keys:RegisterEvent("MODIFIER_STATE_CHANGED")
keys:SetScript("OnEvent", function()
    -- The left and right reads: the merged state lags this event (ClassicAPI fires
    -- it from the key message, before the client's own state catches up).
    local now = (IsLeftShiftKeyDown() or IsRightShiftKeyDown())
        and (IsLeftControlKeyDown() or IsRightControlKeyDown()) and true or false
    if now == held then return end
    held = now
    for _, h in ipairs(handles) do
        if not h.off then
            if held then
                if h.reveal and not h.frame:IsShown() then h.revealed = true; h.frame:Show() end
                h:Show()
            else
                h:GetScript("OnMouseUp")() -- the keys let go while dragging
                h:Hide()
                if h.revealed then h.revealed = nil; h.reveal(h.frame) end
            end
        end
    end
end)

function F.Movable(frame, label, reveal, saved)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    local h = CreateFrame("Frame", nil, frame)
    h:SetAllPoints(frame)
    h:SetFrameStrata("DIALOG")
    h:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    h:SetBackdropColor(0.2, 0.6, 1, 0.45)
    h:EnableMouse(true)
    h.label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.label:SetPoint("CENTER", h, "CENTER", 0, 0)
    h.label:SetText(label)
    h.frame, h.reveal = frame, reveal
    h:SetScript("OnMouseDown", function() h.moving = true; frame:StartMoving() end)
    h:SetScript("OnMouseUp", function()
        if not h.moving then return end
        h.moving = nil
        frame:StopMovingOrSizing()
        if saved then saved(frame) end
    end)
    h:Hide()
    handles[#handles + 1] = h
    return h
end
