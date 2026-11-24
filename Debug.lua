-- Development builds only (left out of the release, see .pkgmeta).
-- /gfm debug   says whether the fix runs, whether the quest log listens to quest
--              pin leaves right now, and whether its highlight is still the game's
--              own (not tainted by addon code): hover a quest pin with the
--              controller, move off it, then run it.
local FastMap = _G.GamepadFastMap

local Debug = {}
FastMap.Debug = Debug

-- A turned-off sibling counts as missing, to test the "Get" buttons.
if FastMap.RelatedAddons then FastMap.RelatedAddons.countTurnedOffAsMissing = true end

local function report(text) print("|cff66ccccGamepadFastMap|r " .. text) end

local function questLogListening()
    local eventRegistry, questLog = _G.EventRegistry, _G.QuestScrollFrame
    if type(eventRegistry) ~= "table" or type(questLog) ~= "table" then return nil end
    local callbacks = eventRegistry.GetCallbacksByEvent
        and eventRegistry:GetCallbacksByEvent(2, FastMap.QuestPinLeave.LEAVE)   -- CallbackType.Function (CallbackRegistry.lua:11)
    return type(callbacks) == "table" and callbacks[questLog] ~= nil
end

function Debug.Command()
    local questLog = _G.QuestScrollFrame
    report("fix running: " .. tostring(FastMap.QuestPinLeave.IsRunning()))
    report("quest log listening to leaves: " .. tostring(questLogListening()))
    if type(questLog) == "table" and type(issecurevariable) == "function" then
        local secure, taintedBy = issecurevariable(questLog, "calloutQuestID")
        report("highlight value secure: " .. tostring(secure) .. (taintedBy and (" (tainted by " .. taintedBy .. ")") or ""))
    end
end
