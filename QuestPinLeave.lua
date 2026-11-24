-- Why the world map hitches on the controller UI, and the fix.
--
-- With the controller UI on, the game "leaves" every map pin it lets go of: each
-- time the map opens, closes or redraws its quest pins, each released pin runs its
-- OnMouseLeave (forever branch: Blizzard_MapCanvas.lua:409-412, UnregisterPin ->
-- ExitMapPin). A quest pin's leave sends "MapCanvas.QuestPin.OnLeave"
-- (QuestDataProvider.lua:290), and the quest log answers each one by rebuilding
-- itself in full (QuestMapFrame.lua:1267-1270, QuestLogQuests_Update). With 20 quest
-- pins that's 20 rebuilds in one frame: 100 to 300 ms each time the map opens or
-- closes. The rebuild only clears the quest log's highlight of the quest under the
-- cursor (calloutQuestID, QuestMapFrame.lua:1954), so it's only needed after the
-- cursor was on a quest pin.
--
-- The fix: the quest log listens to that message only while the cursor is on a
-- quest pin. Its own function stays the one that runs, from the game's own event
-- registry: this file only says when it's listening.
--   Cursor enters a quest pin ("MapCanvas.QuestPin.OnEnter"): listening again.
--   A leave once the highlight is cleared: not listening any more, so the next
--   released pins rebuild nothing.
-- Turned off (Stop), the quest log listens all the time again, as the game set it.
local FastMap = _G.GamepadFastMap

local QuestPinLeave = {
    ENTER = "MapCanvas.QuestPin.OnEnter",
    LEAVE = "MapCanvas.QuestPin.OnLeave",
}
FastMap.QuestPinLeave = QuestPinLeave

local running = false
local questLog         -- the game's quest list (QuestScrollFrame)
local questLogLeave    -- its answer to a leave, as the game registered it

local function registry()
    local eventRegistry = _G.EventRegistry
    if type(eventRegistry) == "table" and type(eventRegistry.RegisterCallback) == "function"
        and type(eventRegistry.UnregisterCallback) == "function" then
        return eventRegistry
    end
end

local function listen(eventRegistry)
    eventRegistry:RegisterCallback(QuestPinLeave.LEAVE, questLogLeave, questLog)
end

local function stopListening(eventRegistry)
    eventRegistry:UnregisterCallback(QuestPinLeave.LEAVE, questLog)
end

-- The cursor is on a quest pin: its leave must clear the highlight.
local function onEnter()
    local eventRegistry = registry()
    if running and eventRegistry then listen(eventRegistry) end
end

-- A leave. The quest log may hear it before or after us: while its highlight is
-- still set, it hasn't yet, so it keeps listening for this one.
local function onLeave()
    local eventRegistry = registry()
    if running and eventRegistry and questLog.calloutQuestID == nil then stopListening(eventRegistry) end
end

function QuestPinLeave.Start()
    if running then return true end
    local eventRegistry = registry()
    local scrollFrame = _G.QuestScrollFrame
    if not (eventRegistry and type(scrollFrame) == "table") then return false end
    if scrollFrame.IsForbidden and scrollFrame:IsForbidden() then return false end
    local leave = scrollFrame.OnMapCanvasPinLeave
    if type(leave) ~= "function" then return false end
    questLog, questLogLeave = scrollFrame, leave
    running = true
    eventRegistry:RegisterCallback(QuestPinLeave.ENTER, onEnter, QuestPinLeave)
    eventRegistry:RegisterCallback(QuestPinLeave.LEAVE, onLeave, QuestPinLeave)
    -- The cursor may be on a pin right now: then its leave is still needed.
    if questLog.calloutQuestID == nil then stopListening(eventRegistry) end
    return true
end

function QuestPinLeave.Stop()
    if not running then return end
    running = false
    local eventRegistry = registry()
    if not eventRegistry then return end
    eventRegistry:UnregisterCallback(QuestPinLeave.ENTER, QuestPinLeave)
    eventRegistry:UnregisterCallback(QuestPinLeave.LEAVE, QuestPinLeave)
    listen(eventRegistry)
end

function QuestPinLeave.IsRunning() return running end
