-- GamepadFastMap: on the controller UI, the world map opens and closes without
-- its hitch. Settings sit in the game's Options > AddOns > Gamepad Fast Map, or /gpfm.
--
-- Files, one job each:
--   GamepadFastMap.lua   saved settings, the settings page, events, /gpfm
--   QuestPinLeave.lua    the fix: the quest log rebuilt once, not once per quest pin
--   Popup.lua            a popup in the game's style
--   RelatedAddons.lua    hints for our other controller addons
local ADDON_NAME = ...

local FastMap = {
    -- enabled: the fix is on. On by default: it's what the addon is for, and the
    -- map looks and works as the game's own either way.
    DEFAULTS = { enabled = true },
}
_G.GamepadFastMap = FastMap

function FastMap.GetSettings()
    if type(GamepadFastMapDB) ~= "table" then GamepadFastMapDB = {} end
    local settings = GamepadFastMapDB
    for key in pairs(settings) do
        if FastMap.DEFAULTS[key] == nil then settings[key] = nil end
    end
    for key, defaultValue in pairs(FastMap.DEFAULTS) do
        if settings[key] == nil then settings[key] = defaultValue end
    end
    return settings
end

-- Starts or stops the fix, as the settings say. Turned off after it ran, the
-- game's own handling comes back with a reload (QuestPinLeave.lua): offered here.
function FastMap.Apply()
    if FastMap.GetSettings().enabled then return FastMap.QuestPinLeave.Start() end
    FastMap.QuestPinLeave.Stop()
    if FastMap.QuestPinLeave.NeedsReload() and FastMap.Popup then
        FastMap.Popup.Show({ text = "Fast map is off.\n\nReload to give the map back its own quest list updates.",
            buttons = { { text = RELOADUI or "Reload", reload = true }, { text = LATER or "Later" } } })
    end
end

-- Settings: Options > AddOns > Gamepad Fast Map

function FastMap.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local settings = FastMap.GetSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Gamepad Fast Map")
    FastMap.category = category

    local variableName = "GamepadFastMap_enabled"
    local setting = Settings.RegisterAddOnSetting(category, variableName, "enabled", settings,
        Settings.VarType.Boolean, "Fast map", FastMap.DEFAULTS.enabled)
    Settings.SetOnValueChangedCallback(variableName, function() FastMap.Apply() end)
    Settings.CreateCheckbox(category, setting,
        "Opens and closes the world map without its hitch on the controller UI.\n\n"
        .. "The game rebuilds the whole quest list once per quest pin each time the map opens or closes. "
        .. "With this on, it doesn't, and the quest list's highlight still goes when the cursor leaves a quest pin. "
        .. "The map looks and works the same.")

    if FastMap.AddRelatedAddonButtons then FastMap.AddRelatedAddonButtons(layout) end   -- RelatedAddons.lua
    Settings.RegisterAddOnCategory(category)
end

function FastMap.Open()
    if FastMap.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(FastMap.category:GetID())
    end
end

-- Events

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        FastMap.GetSettings()
        pcall(FastMap.RegisterSettings)
    elseif event == "PLAYER_LOGIN" then
        -- The game's quest log is built by now.
        FastMap.Apply()
    end
end)

-- /gpfm (or /gamepadfastmap) opens the settings.
SLASH_GAMEPADFASTMAP1 = "/gpfm"
SLASH_GAMEPADFASTMAP2 = "/gamepadfastmap"
SlashCmdList.GAMEPADFASTMAP = function(message)
    local command, arguments = tostring(message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "debug" and FastMap.Debug then return FastMap.Debug.Command(arguments) end
    FastMap.Open()
end
