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

-- The game's event registry as it behaves (CallbackRegistry.lua, forever branch):
-- one callback per owner and event, called as func(owner, ...); one removed while
-- the event runs is skipped if not reached yet. callbackOrder: "game first" or
-- "addon first", the order the quest log and the addon hear an event in.
local function newEventRegistry(callbackOrder)
    local registry = { callbacks = {} }
    function registry:RegisterCallback(event, func, owner)
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
    game = { rebuilds = 0, frames = {} }
    _G.EventRegistry = newEventRegistry(options.order)
    -- The quest log as the game makes it (QuestMapFrame.lua:1247-1270).
    local questLog = {}
    function questLog:OnMapCanvasPinEnter(_, questID) self.calloutQuestID = questID; game.rebuilds = game.rebuilds + 1 end
    function questLog:OnMapCanvasPinLeave() self.calloutQuestID = nil; game.rebuilds = game.rebuilds + 1 end
    function questLog:IsForbidden() return false end
    _G.QuestScrollFrame = questLog
    _G.EventRegistry:RegisterCallback(ENTER, questLog.OnMapCanvasPinEnter, questLog)
    _G.EventRegistry:RegisterCallback(LEAVE, questLog.OnMapCanvasPinLeave, questLog)

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

    for _, file in ipairs({ "GamepadFastMap.lua", "QuestPinLeave.lua", "Popup.lua", "RelatedAddons.lua" }) do
        assert(loadfile(file))("GamepadFastMap")
    end
    game.fire = function(event, ...)
        for _, frame in ipairs(game.frames) do if frame.events[event] and frame.script then frame.script(frame, event, ...) end end
    end
    game.fire("ADDON_LOADED", "GamepadFastMap")
    game.fire("PLAYER_LOGIN")
end

-- The map lets go of its quest pins: each one's leave (Blizzard_MapCanvas.lua:409-412).
local function releasePins(count)
    for _ = 1, count do _G.EventRegistry:TriggerEvent(LEAVE) end
end
local function enterPin(questID) _G.EventRegistry:TriggerEvent(ENTER, {}, questID) end

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
    test("cursor leaves a quest pin (" .. order .. "): the highlight is cleared", function()
        boot({ order = order })
        enterPin(42)
        expectEqual(_G.QuestScrollFrame.calloutQuestID, 42, "highlight on the hovered quest")
        _G.EventRegistry:TriggerEvent(LEAVE)
        expectEqual(_G.QuestScrollFrame.calloutQuestID, nil, "highlight cleared")
    end)

    test("map closes on a hovered quest pin (" .. order .. "): at most 2 rebuilds, not 20", function()
        boot({ order = order })
        enterPin(42)
        local rebuilds = rebuildsDuring(function() releasePins(20) end)
        assert(rebuilds >= 1 and rebuilds <= 2, "rebuilds: " .. rebuilds)
        expectEqual(_G.QuestScrollFrame.calloutQuestID, nil, "highlight cleared")
        expectEqual(rebuildsDuring(function() releasePins(20) end), 0, "rebuilds on the next open")
    end)
end

test("turned off: the quest log hears every leave again, as the game set it", function()
    boot()
    _G.GamepadFastMapDB.enabled = false
    game.settingChanged.GamepadFastMap_enabled()
    expectEqual(rebuildsDuring(function() releasePins(20) end), 20, "rebuilds")
    _G.GamepadFastMapDB.enabled = true
    game.settingChanged.GamepadFastMap_enabled()
    expectEqual(rebuildsDuring(function() releasePins(20) end), 0, "rebuilds once back on")
end)

test("no quest log: nothing breaks, the fix waits off", function()
    boot()
    _G.GamepadFastMap.QuestPinLeave.Stop()
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
