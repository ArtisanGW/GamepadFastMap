-- GamepadFastMap against a fake game: the game's event registry, its quest log
-- and the Settings API. From GamepadFastMap:  luajit tests/run.lua
-- GFM_TEST="part of a name" runs only the tests whose name holds it.
local failed, passed = 0, 0
local only = os.getenv("GFM_TEST")
local function test(name, testBody)
    if only and not name:find(only, 1, true) then return end
    local ok, err = xpcall(testBody, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. "\n" .. err) end
end
local function expectEqual(actual, expected, message)
    if actual ~= expected then error((message or "") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local ENTER, LEAVE = "MapCanvas.QuestPin.OnEnter", "MapCanvas.QuestPin.OnLeave"
local QUESTS = 20

-- The game's event registry as it behaves (CallbackRegistry.lua, forever branch):
-- one callback per owner and event, called as func(owner, ...); one removed while
-- the event runs is skipped if not reached yet. callbackOrder: "game first" or
-- "addon first", the order the quest log and the addon hear an event in.
-- writesForQuestLog counts registrations of the quest log's callbacks after load:
-- each one would run the quest log's code as addon code (tainted).
local function newEventRegistry(callbackOrder)
    local registry = { callbacks = {}, writesForQuestLog = 0 }
    function registry:RegisterCallback(event, func, owner)
        if owner == _G.QuestScrollFrame and self.loaded then self.writesForQuestLog = self.writesForQuestLog + 1 end
        self.callbacks[event] = self.callbacks[event] or {}
        self.callbacks[event][owner] = func
    end
    function registry:UnregisterCallback(event, owner)
        if self.callbacks[event] then self.callbacks[event][owner] = nil end
    end
    function registry:TriggerEvent(event, ...)
        local callbacks = self.callbacks[event] or {}
        local owners = {}
        for owner in pairs(callbacks) do owners[#owners + 1] = owner end
        table.sort(owners, function(first, second)
            local firstIsGame = first == _G.QuestScrollFrame
            local secondIsGame = second == _G.QuestScrollFrame
            if callbackOrder == "addon first" then return secondIsGame and not firstIsGame end
            return firstIsGame and not secondIsGame
        end)
        for _, owner in ipairs(owners) do
            local func = callbacks[owner]   -- read when reached: removed ones are skipped
            if func then func(owner, ...) end
        end
    end
    return registry
end

local game
local function boot(options)
    options = options or {}
    game = { rebuilds = 0, frames = {}, popups = {} }
    _G.EventRegistry = newEventRegistry(options.order)
    -- The quest log as the game makes it (QuestMapFrame.lua:1247-1270), with one
    -- title button per quest whose highlight shows the quest under the cursor (:1954).
    local questLog = { buttons = {} }
    for questID = 1, QUESTS do questLog.buttons[questID] = { questID = questID, HighlightTexture = {
        shown = false, Hide = function(self) self.shown = false end } } end
    questLog.titleFramePool = { EnumerateActive = function()
        local i = 0
        return function() i = i + 1; return questLog.buttons[i] end
    end }
    function questLog:IsForbidden() return false end
    _G.QuestLogQuests_Update = function()
        game.rebuilds = game.rebuilds + 1
        for _, button in ipairs(questLog.buttons) do button.HighlightTexture.shown = questLog.calloutQuestID == button.questID end
    end
    function questLog:OnMapCanvasPinEnter(_, questID) self.calloutQuestID = questID; _G.QuestLogQuests_Update() end
    function questLog:OnMapCanvasPinLeave() self.calloutQuestID = nil; _G.QuestLogQuests_Update() end
    _G.QuestScrollFrame = questLog
    _G.EventRegistry:RegisterCallback(ENTER, questLog.OnMapCanvasPinEnter, questLog)
    _G.EventRegistry:RegisterCallback(LEAVE, questLog.OnMapCanvasPinLeave, questLog)
    _G.EventRegistry.loaded = true
    -- The game's "cursor on a quest" (POIButtonHighlightManager.lua).
    _G.POIButtonHighlightManager = { GetQuestID = function(self) return self.questID end }
    _G.hooksecurefunc = function(name, hook)
        local original = _G[name]
        _G[name] = function(...) original(...); hook(...) end
    end
    _G.InCombatLockdown = function() return false end

    _G.GamepadFastMapDB = options.saved
    _G.SlashCmdList = {}
    _G.CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(_, script) self.script = script end
        game.frames[#game.frames + 1] = frame
        return frame
    end
    game.settingChanged = {}
    _G.Settings = {
        VarType = { Boolean = "boolean" },
        RegisterVerticalLayoutCategory = function(name)
            return { name = name, GetID = function() return name end }, { AddInitializer = function() end }
        end,
        RegisterAddOnSetting = function(_, variableName, key, table)
            return { variableName = variableName, key = key, table = table }
        end,
        SetOnValueChangedCallback = function(variableName, callback) game.settingChanged[variableName] = callback end,
        CreateCheckbox = function() return {} end,
        RegisterAddOnCategory = function() end,
    }
    _G.C_AddOns = { DoesAddOnExist = function() return true end }

    for _, file in ipairs({ "Code/GamepadFastMap.lua", "Code/QuestPinLeave.lua", "Code/Popup.lua", "Code/RelatedAddons.lua" }) do
        assert(loadfile(file))("GamepadFastMap")
    end
    _G.GamepadFastMap.Popup = { Show = function(popup) game.popups[#game.popups + 1] = popup end }
    game.fire = function(event, ...)
        for _, frame in ipairs(game.frames) do if frame.events[event] and frame.script then frame.script(frame, event, ...) end end
    end
    game.fire("ADDON_LOADED", "GamepadFastMap")
    game.fire("PLAYER_LOGIN")
end

-- A quest pin, as QuestDataProvider.lua:279-290: the highlight manager first, then the message.
local function enterPin(questID)
    _G.POIButtonHighlightManager.questID = questID
    _G.EventRegistry:TriggerEvent(ENTER, {}, questID)
end
local function leavePin()
    _G.POIButtonHighlightManager.questID = nil
    _G.EventRegistry:TriggerEvent(LEAVE)
end
-- The map lets go of its quest pins: each one's leave (Blizzard_MapCanvas.lua:409-412).
local function releasePins(count) for _ = 1, count do leavePin() end end
local function highlighted(questID) return _G.QuestScrollFrame.buttons[questID].HighlightTexture.shown end

local function rebuildsDuring(action)
    local before = game.rebuilds
    action()
    return game.rebuilds - before
end

test("without the addon: one rebuild per released quest pin", function()
    boot({ saved = { enabled = false } })
    expectEqual(rebuildsDuring(function() releasePins(20) end), 20, "rebuilds")
end)

test("map opens or closes: no rebuild for its released quest pins", function()
    boot()
    expectEqual(rebuildsDuring(function() releasePins(20) end), 0, "rebuilds")
end)

for _, order in ipairs({ "game first", "addon first" }) do
    test("cursor leaves a quest pin (" .. order .. "): its highlight goes, with no rebuild", function()
        boot({ order = order })
        enterPin(4)
        expectEqual(highlighted(4), true, "highlight on the hovered quest")
        expectEqual(rebuildsDuring(function() leavePin() end), 0, "rebuilds")
        expectEqual(highlighted(4), false, "highlight gone")
    end)

    test("map closes on a hovered quest pin (" .. order .. "): no rebuild, highlight gone", function()
        boot({ order = order })
        enterPin(4)
        expectEqual(rebuildsDuring(function() releasePins(20) end), 0, "rebuilds")
        expectEqual(highlighted(4), false, "highlight gone")
    end)
end

test("the game rebuilds the quest log later: the left quest stays unhighlighted", function()
    boot()
    enterPin(4)
    leavePin()
    _G.QuestLogQuests_Update()   -- QUEST_LOG_UPDATE and the like
    expectEqual(highlighted(4), false, "still gone")
end)

test("a rebuild while the cursor is on a pin keeps its highlight", function()
    boot()
    enterPin(4)
    _G.QuestLogQuests_Update()
    expectEqual(highlighted(4), true, "highlight kept")
    enterPin(7)
    expectEqual(highlighted(7), true, "the next pin's highlight")
    expectEqual(highlighted(4), false, "the last one's gone")
end)

test("never writes the quest log's own callback into the game's registry", function()
    boot()
    enterPin(4); releasePins(20); enterPin(5); leavePin()
    _G.GamepadFastMapDB.enabled = false
    game.settingChanged.GamepadFastMap_enabled()
    _G.GamepadFastMapDB.enabled = true
    game.settingChanged.GamepadFastMap_enabled()
    expectEqual(_G.EventRegistry.writesForQuestLog, 0, "registrations for the quest log")
end)

test("turned off: a reload is offered to give the quest log its updates back", function()
    boot()
    _G.GamepadFastMapDB.enabled = false
    game.settingChanged.GamepadFastMap_enabled()
    expectEqual(#game.popups, 1, "popups")
    expectEqual(game.popups[1].buttons[1].reload, true, "first button reloads")
    enterPin(4); leavePin()
    expectEqual(highlighted(4), true, "highlight no longer hidden by the addon")
end)

test("off from the start: nothing touched, no popup", function()
    boot({ saved = { enabled = false } })
    expectEqual(#game.popups, 0, "popups")
    enterPin(4)
    expectEqual(rebuildsDuring(function() leavePin() end), 1, "the game's own rebuild")
end)

test("no quest log: nothing breaks, the fix waits off", function()
    boot({ saved = { enabled = false } })
    _G.QuestScrollFrame = nil
    expectEqual(_G.GamepadFastMap.QuestPinLeave.Start(), false, "started")
end)

test("saved keys the addon doesn't use are dropped", function()
    boot({ saved = { enabled = true, old = 1 } })
    expectEqual(_G.GamepadFastMapDB.old, nil, "old key")
    expectEqual(_G.GamepadFastMapDB.enabled, true, "enabled")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
