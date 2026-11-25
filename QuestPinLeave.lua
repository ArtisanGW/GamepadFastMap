-- Why the world map hitches on the controller UI, and the fix.
--
-- With the controller UI on, the game "leaves" every map pin it lets go of: each
-- time the map opens, closes or redraws its quest pins, each released pin runs its
-- OnMouseLeave (forever branch: Blizzard_MapCanvas.lua:409-412, UnregisterPin ->
-- ExitMapPin). A quest pin's leave sends "MapCanvas.QuestPin.OnLeave"
-- (QuestDataProvider.lua:290), and the quest log answers each one by rebuilding
-- itself in full (QuestMapFrame.lua:1267-1270, QuestLogQuests_Update). With 20 quest
-- pins that's 20 rebuilds in one frame: 100 to 300 ms each time the map opens or
-- closes. The rebuild only clears the quest log's highlight of the quest whose pin
-- the cursor was on (calloutQuestID, QuestMapFrame.lua:1954).
--
-- The fix:
--   1. The quest log stops listening to that message, once. Nothing is ever
--      written back into the game's event registry: a callback registered from
--      addon code runs as addon code, and the quest log's rebuild then taints what
--      it writes. Inside the map's close (B on the controller) that got the game's
--      SetPreferredGamepadInteractTarget() blocked (seen 2026-11-24, taintLog 4).
--   2. What the rebuild did is done by hiding a texture: once the cursor is off
--      the quest's pin, the quest log's highlight of it is hidden. The game's own
--      "cursor on a quest pin" is POIButtonHighlightManager (set before a pin's
--      enter message, cleared before its leave: QuestDataProvider.lua:279-289).
--      Checked at each leave, and after each rebuild the game does for its own
--      reasons (a post-hook: hooksecurefunc, which leaves the game's code secure).
-- Turned off (Stop): the quest log listens again only after a reload, as the game
-- set it at load. Putting it back from addon code is what tainted.
local FastMap = _G.GamepadFastMap

local QuestPinLeave = {
    LEAVE = "MapCanvas.QuestPin.OnLeave",
}
FastMap.QuestPinLeave = QuestPinLeave

local running = false
local stoppedListening = false   -- the quest log was unhooked this session
local hookedRebuild = false

local function registry()
    local eventRegistry = _G.EventRegistry
    if type(eventRegistry) == "table" and type(eventRegistry.RegisterCallback) == "function"
        and type(eventRegistry.UnregisterCallback) == "function" then
        return eventRegistry
    end
end

-- The quest the cursor is on (a map pin or the quest log's own icon), or nil.
local function hoveredQuestID()
    local manager = _G.POIButtonHighlightManager
    if type(manager) == "table" and type(manager.GetQuestID) == "function" then return manager:GetQuestID() end
end

-- The quest log still highlights a quest the cursor left: hide that highlight.
function QuestPinLeave.HideStaleHighlight()
    if not running then return end
    local questLog = _G.QuestScrollFrame
    local highlightedQuestID = questLog and questLog.calloutQuestID
    if highlightedQuestID == nil or highlightedQuestID == hoveredQuestID() then return end
    local titleButtons = questLog.titleFramePool
    if type(titleButtons) ~= "table" or type(titleButtons.EnumerateActive) ~= "function" then return end
    for button in titleButtons:EnumerateActive() do
        if button.questID == highlightedQuestID and button.HighlightTexture then button.HighlightTexture:Hide() end
    end
end

function QuestPinLeave.Start()
    if running then return true end
    local eventRegistry = registry()
    local questLog = _G.QuestScrollFrame
    if not (eventRegistry and type(questLog) == "table") then return false end
    if questLog.IsForbidden and questLog:IsForbidden() then return false end
    running = true
    if not stoppedListening then
        eventRegistry:UnregisterCallback(QuestPinLeave.LEAVE, questLog)
        stoppedListening = true
    end
    eventRegistry:RegisterCallback(QuestPinLeave.LEAVE, QuestPinLeave.HideStaleHighlight, QuestPinLeave)
    if not hookedRebuild and type(_G.QuestLogQuests_Update) == "function" then
        hooksecurefunc("QuestLogQuests_Update", QuestPinLeave.HideStaleHighlight)
        hookedRebuild = true
    end
    return true
end

-- Stops hiding highlights. The quest log listens again after the next reload.
function QuestPinLeave.Stop()
    if not running then return end
    running = false
    local eventRegistry = registry()
    if eventRegistry then eventRegistry:UnregisterCallback(QuestPinLeave.LEAVE, QuestPinLeave) end
end

function QuestPinLeave.IsRunning() return running end
-- True when the game's own leave handling only comes back with a reload.
function QuestPinLeave.NeedsReload() return stoppedListening and not running end
