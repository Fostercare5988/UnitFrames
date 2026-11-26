-- The UnitFrames page in ClassicAPI's Settings window (AddOn Options, or /ffr).
local _, F = ...
local db = UnitFramesDB
local category

SettingsRegistrar:AddRegistrant(function()
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("UnitFrames")
    for _, row in ipairs(F.PAGE) do
        if type(row) == "string" then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(row))
        else
            local key, name, tip = row[1], row[2], row[3]
            local default = row[4] ~= false
            local setting = Settings.RegisterAddOnSetting(category, "UnitFrames_" .. key, key, db,
                Settings.VarType.Boolean, name, default)
            setting:SetValueChangedCallback(F.apply[key])
            Settings.CreateCheckbox(category, setting, tip)
        end
    end
    Settings.RegisterAddOnCategory(category)
end)

SLASH_UNITFRAMES1 = "/ffr"
SlashCmdList.UNITFRAMES = function()
    if category then Settings.OpenToCategory(category:GetID()) end
end

-- The one public function: Auras calls it after its list changes, since the rows
-- and the top right leave out what it shows.
UnitFrames = { Refresh = function() F.Rows(); F.TopRight() end }
