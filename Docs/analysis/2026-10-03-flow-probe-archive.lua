local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local FlowProbe = {}

FlowProbe.HOOKS = {
    { "app.cQuestDirector", "endFlow()" },
    { "app.cQuestDirector", "requestLeaveResult()" },
    { "app.cQuestDirector", "reqCloseQuestFixResult()" },
    { "app.cQuestDirector", "evLoadEnd()" },
    { "app.cQuestDirector", "requestLeaveShowing(System.Boolean)" },
    { "app.cQuestReward", "enter()" },
    { "app.cQuestReward", "setRequestCloseFixResult()" },
    { "app.cQuestPlaying", "exit()" },
    { "app.cQuestSuccessFreePlayTime", "exit()" },
    { "app.cQuestStart", "enter()" },
    { "app.cQuestClearEnd", "enter()" },
    { "app.cQuestFailedEnd", "enter()" },
    { "app.cQuestResult", "enter()" },
    { "app.LifeAreaMusicManager", "enterLifeArea()" },
    { "app.LifeAreaMusicManager", "exitLifeArea()" },
}

FlowProbe.FIELDS = { "cur", "next", "state", "life" }

local installed = false
local previous = {}

local function trace(text)
    Log.trace("flow " .. text)
end

local function describe(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function readOr(read, failed)
    local ok, value = pcall(read)
    if ok then return value end
    return failed
end

local function typeNameOf(object)
    if object == nil then return nil end
    return readOr(function() return object:get_type_definition():get_full_name() end, "?")
end

local function director()
    return readOr(function()
        local manager = Game.singleton("app.MissionManager")
        if not manager then return nil end
        return manager:get_QuestDirector()
    end, nil)
end

function FlowProbe.snapshot()
    local snapshot = { cur = nil, next = nil, state = nil, life = nil }
    local questDirector = director()
    if questDirector then
        local cur = readOr(function() return questDirector._CurFlow end, "?")
        if cur == "?" then
            snapshot.cur, snapshot.state = "?", "?"
        else
            snapshot.cur = typeNameOf(cur)
            if cur ~= nil then snapshot.state = readOr(function() return cur._State end, "?") end
        end
        local nextFlow = readOr(function() return questDirector._NextFlow end, "?")
        snapshot.next = nextFlow == "?" and "?" or typeNameOf(nextFlow)
    end
    local music = Game.singleton("app.LifeAreaMusicManager")
    if music then snapshot.life = readOr(function() return music:get_IsInLifeArea() end, "?") end
    return snapshot
end

function FlowProbe.formatSnapshot(snapshot)
    local parts = {}
    for _, field in ipairs(FlowProbe.FIELDS) do
        parts[#parts + 1] = field .. "=" .. describe(snapshot[field])
    end
    return table.concat(parts, " ")
end

local function onHook(label, readArg)
    return function(args)
        local text = "hook " .. label .. " at " .. tostring(Game.uptime()) .. " " .. FlowProbe.formatSnapshot(FlowProbe.snapshot())
        if readArg then text = text .. " arg=" .. describe(readOr(function() return readArg(args) end, "?")) end
        trace(text)
    end
end

local function boolArg(index)
    return function(args)
        return (sdk.to_int64(args[index]) & 0xFF) ~= 0
    end
end

function FlowProbe.install()
    if installed then return end
    installed = true
    for _, entry in ipairs(FlowProbe.HOOKS) do
        local label = entry[1] .. "." .. entry[2]
        local readArg = entry[2] == "requestLeaveShowing(System.Boolean)" and boolArg(3) or nil
        Game.hook(entry[1], entry[2], onHook(label, readArg))
    end
end

function FlowProbe.update()
    if not Log.isDeveloperMode() then return end
    local snapshot = FlowProbe.snapshot()
    local now = nil
    for _, field in ipairs(FlowProbe.FIELDS) do
        if snapshot[field] ~= previous[field] then
            now = now or tostring(Game.uptime())
            trace("change " .. field .. " " .. describe(previous[field]) .. " -> " .. describe(snapshot[field])
                .. " at " .. now .. " " .. FlowProbe.formatSnapshot(snapshot))
        end
    end
    previous = snapshot
end

function FlowProbe.resetForTests()
    previous = {}
end

return FlowProbe
