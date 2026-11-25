-- Development builds only (left out of the release, see .pkgmeta).
-- /gpfm debug pins: the in-game half of tests/ingame_pin_close.sh, which closes
-- the map with the cursor on a quest pin, again and again, at different moments
-- (the same instant as the hover, a few frames after, just after leaving it).
-- Hard to do by hand with a controller; the script does it with the mouse and
-- the map key.
--
-- While it runs, each time the map is open a magenta square sits on one quest
-- pin, so the script can find it on a screenshot. Nothing here touches the
-- game's map or quest log: it only reads them, and listens.
-- Each map close is one round, logged with:
--   hovered      the cursor was on a quest pin when the map closed
--   frames       frames between that pin's enter and the close (0 = same frame)
--   stale        quest log titles still highlighted for a quest the cursor left
--   secure       whether the quest log's highlight value is still the game's own
-- and every action the game refused (ADDON_ACTION_BLOCKED / FORBIDDEN) is kept
-- with its addon and function: the crash this checks was
-- SetPreferredGamepadInteractTarget() blocked as the map closed on a hovered pin.
-- It ends after ROUNDS closes (or SECONDS) with a reload box; the reload saves
-- GamepadFastMapDB.debugPinClose, which the script reads.
local FastMap = _G.GamepadFastMap
local Debug = FastMap.Debug

local PinClose = {
    ROUNDS = 30,
    SECONDS = 300,
    MARKER_SIZE = 14,
    ENTER = "MapCanvas.QuestPin.OnEnter",
    LEAVE = "MapCanvas.QuestPin.OnLeave",
}
Debug.PinClose = PinClose

local function say(text) print("|cff88ccffgpfm debug|r " .. text) end

local test           -- the run in progress, or nil
local frameNumber = 0
local hoveredQuestID, enterFrame
local markedPin
local marker, timerText
local hookedMap = false
local eventFrame = CreateFrame("Frame")

local function currentRound() return test and test.rounds[#test.rounds] end

-- The quest pins on the open map, in the map's own visible area.
local function visibleQuestPins()
    local pins = {}
    local map = _G.WorldMapFrame
    local container = map and map.ScrollContainer
    if not (map and container and map.EnumeratePinsByTemplate) then return pins end
    local left, bottom, width, height = container:GetRect()
    if not left then return pins end
    local containerScale = container:GetEffectiveScale()
    for pin in map:EnumeratePinsByTemplate("QuestPinTemplate") do
        local x, y = pin:GetCenter()
        if pin:IsVisible() and x then
            local scale = pin:GetEffectiveScale() / containerScale
            x, y = x * scale, y * scale
            -- Well inside the visible area, so the whole square shows.
            if x > left + 30 and x < left + width - 30 and y > bottom + 30 and y < bottom + height - 30 then
                pins[#pins + 1] = pin
            end
        end
    end
    table.sort(pins, function(first, second) return (first.questID or 0) < (second.questID or 0) end)
    return pins
end

local function placeMarker()
    local round = currentRound()
    if not (round and _G.WorldMapFrame:IsShown()) then marker:Hide(); return end
    if not (markedPin and markedPin:IsVisible()) then
        local pins = visibleQuestPins()
        if #pins == 0 then marker:Hide(); round.noPin = true; return end
        markedPin = pins[(#test.rounds - 1) % #pins + 1]
        round.markedQuestID = markedPin.questID
    end
    local x, y = markedPin:GetCenter()
    local scale = markedPin:GetEffectiveScale() / UIParent:GetEffectiveScale()
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
    marker:Show()
end

local function staleHighlights()
    local questLog = _G.QuestScrollFrame
    local titleButtons = questLog and questLog.titleFramePool
    if not titleButtons then return 0 end
    local count = 0
    for button in titleButtons:EnumerateActive() do
        if button.HighlightTexture and button.HighlightTexture:IsShown() and button.questID ~= hoveredQuestID then
            count = count + 1
        end
    end
    return count
end

local function finish()
    if not test then return end
    local finished = test
    test = nil
    marker:Hide()
    timerText:Hide()
    _G.EventRegistry:UnregisterCallback(PinClose.ENTER, PinClose)
    _G.EventRegistry:UnregisterCallback(PinClose.LEAVE, PinClose)
    eventFrame:UnregisterAllEvents()
    local hovered, sameFrame, stale, tainted = 0, 0, 0, 0
    for _, round in ipairs(finished.rounds) do
        if round.hovered then hovered = hovered + 1 end
        if round.hovered and round.frames and round.frames <= 1 then sameFrame = sameFrame + 1 end
        stale = stale + (round.stale or 0)
        if round.secure == false then tainted = tainted + 1 end
    end
    finished.summary = { closes = #finished.rounds, hovered = hovered, sameFrame = sameFrame,
        blocked = #finished.blocked, stale = stale, tainted = tainted }
    finished.passed = #finished.blocked == 0 and stale == 0 and tainted == 0 and hovered > 0
    FastMap.GetSettings().debugPinClose = finished
    local text = string.format("Map close test %s.\n%d closes, %d on a hovered quest pin (%d in the same frame).\n"
        .. "%d blocked actions, %d stale highlights.\n\nReload to save the results.",
        finished.passed and "passed" or "FAILED", #finished.rounds, hovered, sameFrame, #finished.blocked, stale)
    say(text:gsub("\n", " "))
    FastMap.Popup.Show({ text = text, buttons = { { text = RELOADUI or "Reload", reload = true }, { text = LATER or "Later" } } })
end

local function onMapShown()
    if not test then return end
    markedPin = nil
    table.insert(test.rounds, { openedFrame = frameNumber })
end

local function onMapHidden()
    local round = currentRound()
    if not round or round.closedFrame then return end
    marker:Hide()
    round.closedFrame = frameNumber
    round.hovered = hoveredQuestID ~= nil
    round.frames = enterFrame and (frameNumber - enterFrame) or nil
    local cursorX, cursorY = GetCursorPosition()
    round.cursor = string.format("%d,%d", cursorX, cursorY)
    round.checkNextFrame = true
end

local function hookMap()
    if hookedMap or not _G.WorldMapFrame then return end
    _G.WorldMapFrame:HookScript("OnShow", onMapShown)
    _G.WorldMapFrame:HookScript("OnHide", onMapHidden)
    hookedMap = true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then return hookMap() end
    local addonName, functionName = ...
    table.insert(test.blocked, { event = event, addon = tostring(addonName), func = tostring(functionName),
        round = #test.rounds, frame = frameNumber })
end)

local function onUpdate()
    frameNumber = frameNumber + 1
    if not test then return end
    local round = currentRound()
    if round and round.checkNextFrame then
        round.checkNextFrame = nil
        round.stale = staleHighlights()
        local questLog = _G.QuestScrollFrame
        if questLog then round.secure = issecurevariable(questLog, "calloutQuestID") end
        if #test.rounds >= PinClose.ROUNDS then return finish() end
    end
    placeMarker()
    local secondsLeft = math.ceil(test.startedAt + PinClose.SECONDS - GetTime())
    timerText:SetText(string.format("map close test: %d of %d closes, %d s left",
        round and round.closedFrame and #test.rounds or math.max(0, #test.rounds - 1), PinClose.ROUNDS, math.max(0, secondsLeft)))
    if secondsLeft <= 0 then finish() end
end

function PinClose.Start()
    if not marker then
        marker = CreateFrame("Frame", nil, UIParent)
        marker:SetFrameStrata("TOOLTIP")
        marker:SetSize(PinClose.MARKER_SIZE, PinClose.MARKER_SIZE)
        marker:EnableMouse(false)
        local square = marker:CreateTexture(nil, "OVERLAY")
        square:SetAllPoints()
        square:SetColorTexture(1, 0, 1, 1)
        marker:Hide()
        timerText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        timerText:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -60)
        CreateFrame("Frame"):SetScript("OnUpdate", onUpdate)
    end
    if test then say("map close test started again") end
    hookMap()
    if not hookedMap then eventFrame:RegisterEvent("ADDON_LOADED") end
    test = { date = date("%Y-%m-%d %H:%M:%S"), startedAt = GetTime(), fixRunning = FastMap.QuestPinLeave.IsRunning(),
        rounds = {}, blocked = {} }
    if _G.WorldMapFrame and _G.WorldMapFrame:IsShown() then onMapShown() end
    hoveredQuestID, enterFrame = nil, nil
    _G.EventRegistry:RegisterCallback(PinClose.ENTER, function(_, _, questID)
        hoveredQuestID, enterFrame = questID or true, frameNumber
    end, PinClose)
    _G.EventRegistry:RegisterCallback(PinClose.LEAVE, function()
        -- A leave while the map is still open is the cursor's; the ones the
        -- close sends come after the map is hidden and don't count.
        if _G.WorldMapFrame and _G.WorldMapFrame:IsShown() then hoveredQuestID = nil end
    end, PinClose)
    eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
    eventFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    timerText:Show()
    say(string.format("map close test: %d closes of the map, run by tests/ingame_pin_close.sh", PinClose.ROUNDS))
end
