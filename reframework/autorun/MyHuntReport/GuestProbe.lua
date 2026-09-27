local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local GuestProbe = {}

GuestProbe.COUNTER_ORDER = {
    "own", "replica", "other", "toPacket", "netDamage", "calcNet", "calcInsideNetWithOwnPending",
    "markNet", "markAddrMismatch", "deadOwn", "woundReadFail", "meatReadFail",
    "receiveDamage", "receiveCond", "netCond", "extCond", "external", "setParam",
}

local OWN_LINE_BUDGET = 400
local RECEIVE_LINE_BUDGET = 20
local RESULT_KEY = "mhr_gp_result"

local counters = {}
local ownPending = {}
local ownLines = 0
local receiveLines = 0
local stateLogged = false
local installed = false

local function resetCounters()
    for _, name in ipairs(GuestProbe.COUNTER_ORDER) do counters[name] = 0 end
end

local function resetQuestState()
    resetCounters()
    ownPending = {}
    ownLines = 0
    receiveLines = 0
end

resetQuestState()

function GuestProbe.formatValue(value)
    local kind = type(value)
    if kind == "nil" then return "nil" end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        if math.type(value) == "integer" then return tostring(value) end
        return string.format("%.1f", value)
    end
    return tostring(value)
end

local function readValue(read)
    local ok, value = pcall(read)
    if ok then return GuestProbe.formatValue(value) end
    return "?"
end

local function trace(text)
    Log.trace("gp " .. text)
end

local function bump(name)
    counters[name] = (counters[name] or 0) + 1
end

function GuestProbe.summaryLine(values)
    local parts = {}
    for index, name in ipairs(GuestProbe.COUNTER_ORDER) do
        parts[index] = name .. "=" .. tostring(values[name] or 0)
    end
    return "summary " .. table.concat(parts, " ")
end

function GuestProbe.counters()
    return counters
end

function GuestProbe.reset()
    resetQuestState()
    stateLogged = false
end

local function unresolvedOr(read)
    local ok, value = pcall(read)
    if ok and value ~= nil then return GuestProbe.formatValue(value) end
    return "unresolved"
end

local function logState()
    local director = nil
    pcall(function() director = Game.singleton("app.MissionManager"):get_QuestDirector() end)
    local playing = unresolvedOr(function() return Game.singleton("app.MissionManager"):get_IsPlayingQuest() end)
    local elapsed = unresolvedOr(function() return director:get_QuestElapsedTime() end)
    local hostStarted = unresolvedOr(function() return director["<Param>k__BackingField"].IsHostQuestStarted end)
    local lateJoinStarted = unresolvedOr(function() return director["<Param>k__BackingField"].IsLateJoinQuestStarted end)
    trace("state playing=" .. playing .. " elapsed=" .. elapsed .. " hostStarted=" .. hostStarted .. " lateJoinStarted=" .. lateJoinStarted)
    local masterName = unresolvedOr(function() return Game.masterHunter():get_GameObject():get_Name() end)
    trace("master name=" .. masterName)
end

local function onFlow(name)
    return function()
        if not Log.isDeveloperMode() then return end
        if name == "playing" then resetQuestState() end
        local ok, time = pcall(Game.callStatic, "via.Application", "get_UpTimeSecond")
        local timestamp = ok and type(time) == "number" and GuestProbe.formatValue(time) or "?"
        trace("flow " .. name .. " t=" .. timestamp)
        if name == "playing" or name == "result" then logState() end
        if name == "result" then trace(GuestProbe.summaryLine(counters)) end
    end
end

local function onResultInfoPre(args)
    if not Log.isDeveloperMode() then return end
    local storage = thread.get_hook_storage()
    storage[RESULT_KEY] = nil
    local ok, info = pcall(function() return sdk.to_managed_object(args[2]) end)
    if ok then storage[RESULT_KEY] = info end
end

local function onResultInfoPost()
    if not Log.isDeveloperMode() then return end
    local storage = thread.get_hook_storage()
    local info = storage[RESULT_KEY]
    storage[RESULT_KEY] = nil
    trace("result endType=" .. readValue(function() return info:get_QuestEndType() end)
        .. " failedType=" .. readValue(function() return info:get_QuestFailedType() end)
        .. " clearTimeMs=" .. readValue(function() return info:get_ClearTime() end)
        .. " joinMemberNum=" .. readValue(function() return info:get_JoinMemberNum() end)
        .. " lateJoin=" .. readValue(function() return info["<IsLateJoin>k__BackingField"] end)
        .. " questLevel=" .. readValue(function() return info:get_QuestLevel() end))
    trace(GuestProbe.summaryLine(counters))
end

function GuestProbe.update()
    if stateLogged or not Log.isDeveloperMode() then return end
    stateLogged = true
    logState()
end

local function installFlowHooks()
    Game.hook("app.cQuestPlaying", "enter()", onFlow("playing"))
    Game.hook("app.cQuestClear", "enter()", onFlow("clear"))
    Game.hook("app.cQuestFailed", "enter()", onFlow("failed"))
    Game.hook("app.cQuestResult", "enter()", onFlow("result"))
    Game.hook("app.cGUIQuestResultInfo", "execute()", onResultInfoPre, onResultInfoPost)
end

function GuestProbe.install()
    if installed then return end
    installed = true
    installFlowHooks()
end

return GuestProbe
