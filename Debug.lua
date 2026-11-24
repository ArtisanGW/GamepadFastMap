-- Development builds only (left out of the release, see .pkgmeta).
-- /gpfm debug   says whether the fix runs, whether the quest log listens to quest
--              pin leaves right now, and whether its highlight is still the game's
--              own (not tainted by addon code): hover a quest pin with the
--              controller, move off it, then run it.
-- /gpfm debug watch   90 seconds: hover quest pins and close the map, also both
--              at once. Logs each quest pin enter and leave (and an enter that
--              comes while a leave is still being sent), and each change of the
--              quest log's place in the game's event registry: listening or not,
--              and whether that place is still the game's own or tainted (a
--              tainted one makes the quest log's rebuild run as addon code).
--              Saved in GamepadFastMapDB.debugWatch on the reload at the end.
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

-- The quest log's place in the registry's leave list: "off", "secure", or "tainted by X".
local function questLogSlot()
    local eventRegistry, questLog = _G.EventRegistry, _G.QuestScrollFrame
    if type(eventRegistry) ~= "table" or type(questLog) ~= "table" or not eventRegistry.GetCallbacksByEvent then return "unknown" end
    local callbacks = eventRegistry:GetCallbacksByEvent(2, FastMap.QuestPinLeave.LEAVE)
    if type(callbacks) ~= "table" or callbacks[questLog] == nil then return "off" end
    local ok, secure, taintedBy = pcall(issecurevariable, callbacks, questLog)
    if not ok then return "on (can't check)" end
    return secure and "secure" or ("tainted by " .. tostring(taintedBy))
end

local Watch = { SECONDS = 90, LINES_KEPT = 300 }
Debug.Watch = Watch
local watchFrame = CreateFrame("Frame")
local watch   -- the watch in progress, or nil

local function note(text)
    if #watch.lines < Watch.LINES_KEPT then
        table.insert(watch.lines, string.format("%.3f %s", GetTime() - watch.startedAt, text))
    end
end

-- Our own listeners, next to the fix's: what the game sends, and when.
local function onPinEvent(eventName)
    if not watch then return end
    local executing = _G.EventRegistry.executingEvents or {}
    local whileLeave = eventName == "enter" and executing[FastMap.QuestPinLeave.LEAVE] ~= nil
    note(eventName .. (whileLeave and " WHILE A LEAVE IS SENT" or "") .. ", slot " .. questLogSlot())
    if whileLeave then watch.entersDuringLeave = watch.entersDuringLeave + 1 end
    if eventName == "leave" then watch.checkHighlightNextFrame = true end
end

-- What the quest log's own leave wrote: the game's, or tainted (its rebuild ran as addon code).
local function highlightState()
    local secure, taintedBy = issecurevariable(_G.QuestScrollFrame, "calloutQuestID")
    return secure and "secure" or ("tainted by " .. tostring(taintedBy))
end

local function finishWatch()
    watchFrame:SetScript("OnUpdate", nil)
    _G.EventRegistry:UnregisterCallback(FastMap.QuestPinLeave.ENTER, Watch)
    _G.EventRegistry:UnregisterCallback(FastMap.QuestPinLeave.LEAVE, Watch)
    watch.timerText:Hide()
    local summary = string.format("%d enters during a leave. Slot tainted %d times, ends %s. Highlight tainted %d times.",
        watch.entersDuringLeave, watch.taintedTimes, questLogSlot(), watch.highlightTaintedTimes)
    watch.summary = summary
    watch.timerText = nil
    GamepadFastMapDB.debugWatch = watch
    watch = nil
    report("watch done. " .. summary)
    FastMap.Popup.Show({ text = "Watch done.\n" .. summary .. "\n\nReload to save the results.",
        buttons = { { text = RELOADUI or "Reload", reload = true }, { text = LATER or "Later" } } })
end

function Watch.Start()
    if watch then return report("the watch is already running") end
    local timerText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    timerText:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -60)
    watch = { date = date("%Y-%m-%d %H:%M:%S"), startedAt = GetTime(), lines = {}, entersDuringLeave = 0,
        taintedTimes = 0, highlightTaintedTimes = 0, lastHighlight = highlightState(), lastSlot = questLogSlot(), timerText = timerText }
    note("start, slot " .. watch.lastSlot .. ", highlight " .. watch.lastHighlight)
    _G.EventRegistry:RegisterCallback(FastMap.QuestPinLeave.ENTER, function() onPinEvent("enter") end, Watch)
    _G.EventRegistry:RegisterCallback(FastMap.QuestPinLeave.LEAVE, function() onPinEvent("leave") end, Watch)
    watchFrame:SetScript("OnUpdate", function()
        if watch.checkHighlightNextFrame then
            watch.checkHighlightNextFrame = nil
            local highlight = highlightState()
            if highlight ~= watch.lastHighlight then
                note("frame: highlight " .. tostring(watch.lastHighlight) .. " -> " .. highlight)
                if highlight ~= "secure" then watch.highlightTaintedTimes = watch.highlightTaintedTimes + 1 end
                watch.lastHighlight = highlight
            end
        end
        local slot = questLogSlot()
        if slot ~= watch.lastSlot then
            note("frame: slot " .. watch.lastSlot .. " -> " .. slot)
            if slot:find("tainted", 1, true) and not watch.lastSlot:find("tainted", 1, true) then
                watch.taintedTimes = watch.taintedTimes + 1
            end
            watch.lastSlot = slot
        end
        local secondsLeft = math.ceil(watch.startedAt + Watch.SECONDS - GetTime())
        timerText:SetText(string.format("map watch: %d s left", math.max(0, secondsLeft)))
        if secondsLeft <= 0 then finishWatch() end
    end)
    report(string.format("watch for %d s: hover quest pins, close the map, and both at once", Watch.SECONDS))
end

function Debug.Command(arguments)
    if arguments == "watch" then return Watch.Start() end
    local questLog = _G.QuestScrollFrame
    report("fix running: " .. tostring(FastMap.QuestPinLeave.IsRunning()))
    report("quest log listening to leaves: " .. tostring(questLogListening()))
    if type(questLog) == "table" and type(issecurevariable) == "function" then
        local secure, taintedBy = issecurevariable(questLog, "calloutQuestID")
        report("highlight value secure: " .. tostring(secure) .. (taintedBy and (" (tainted by " .. taintedBy .. ")") or ""))
    end
end
