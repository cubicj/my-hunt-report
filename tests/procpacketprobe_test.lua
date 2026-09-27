local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local FLOW = {
    playing = "app.cQuestPlaying.enter()",
    resultInfo = "app.cGUIQuestResultInfo.execute()",
}

local function raising()
    return setmetatable({}, { __index = function(_, key) error("touched " .. tostring(key)) end })
end

local function ppLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] pp ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function withProbe(callback)
    local hook, singleton, masterHunter, callStatic = Game.hook, Game.singleton, Game.masterHunter, Game.callStatic
    local toManaged, toValue, toFloat = sdk.to_managed_object, sdk.to_valuetype, sdk.to_float
    local hooks = {}
    local ok, err = pcall(function()
        Log.setDeveloperMode(false)
        Log.resetCounts()
        stubs.reset()
        Game.hook = function(typeName, signature, pre, post)
            hooks[typeName .. "." .. signature] = { pre = pre, post = post }
            return true
        end
        Game.singleton = function() return nil end
        Game.masterHunter = function() return nil end
        Game.callStatic = function() return nil end
        sdk.to_managed_object = function(value) return value end
        sdk.to_valuetype = function(value) return value end
        sdk.to_float = function(value) return value end
        local probe = assert(loadfile("reframework/autorun/MyHuntReport/ProcPacketProbe.lua"))()
        probe.install()
        callback({ probe = probe, hooks = hooks })
    end)
    Game.hook, Game.singleton, Game.masterHunter, Game.callStatic = hook, singleton, masterHunter, callStatic
    sdk.to_managed_object, sdk.to_valuetype, sdk.to_float = toManaged, toValue, toFloat
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

function T.formatValueRoundsFloatsAndNamesNil()
    withProbe(function(c)
        assert(c.probe.formatValue(nil) == "nil")
        assert(c.probe.formatValue(true) == "true")
        assert(c.probe.formatValue(7) == "7")
        assert(c.probe.formatValue(12.34) == "12.3")
        assert(c.probe.formatValue("x") == "x")
    end)
end

function T.summaryLineListsCountersInFixedOrder()
    withProbe(function(c)
        local counters = {}
        for _, name in ipairs(c.probe.COUNTER_ORDER) do counters[name] = 0 end
        counters.packetFlayer = 2
        local line = c.probe.summaryLine(counters)
        assert(line == "summary packetFlayer=2 packetRyuki=0 toggle=0 activateBlast=0 activateFlayer=0 activateRyuki=0 activateInsidePacket=0 setParamInsidePacket=0 externalInsidePacket=0", line)
    end)
end

function T.installsFlowHooksAndStaysSilentWhenDeveloperModeOff()
    withProbe(function(c)
        for _, signature in pairs(FLOW) do assert(c.hooks[signature], signature) end
        for _, entry in pairs(c.hooks) do
            if entry.pre then entry.pre(raising()) end
            if entry.post then entry.post(raising()) end
        end
        assert(#ppLines() == 0)
        for _, name in ipairs(c.probe.COUNTER_ORDER) do assert(c.probe.counters()[name] == 0, name) end
        assert(c.probe.activeBracket() == nil)
    end)
end

function T.questStartLogsStateAndResetsCounters()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        c.probe.counters().toggle = 5
        c.hooks[FLOW.playing].pre({})
        assert(c.probe.counters().toggle == 0)
        local lines = ppLines()
        assert(#lines == 1, #lines)
        assert(lines[1] == "[MyHuntReport] pp state lateJoinStarted=unresolved hostStarted=unresolved master=unresolved", lines[1])
    end)
    withProbe(function(c)
        Log.setDeveloperMode(true)
        local param = { IsLateJoinQuestStarted = true, IsHostQuestStarted = false }
        Game.singleton = function(name)
            if name == "app.MissionManager" then
                return { get_QuestDirector = function() return { ["<Param>k__BackingField"] = param } end }
            end
        end
        Game.masterHunter = function()
            return { get_GameObject = function() return { get_Name = function() return "MasterPlayer" end } end }
        end
        c.hooks[FLOW.playing].pre({})
        assert(ppLines()[1] == "[MyHuntReport] pp state lateJoinStarted=true hostStarted=false master=MasterPlayer", ppLines()[1])
    end)
end

function T.questStartResetsCountersEvenWhenDeveloperModeOff()
    withProbe(function(c)
        c.probe.counters().toggle = 5
        c.hooks[FLOW.playing].pre(raising())
        assert(c.probe.counters().toggle == 0)
        assert(#ppLines() == 0)
    end)
end

function T.resultInfoPostPrintsSummary()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        c.probe.counters().activateBlast = 3
        c.hooks[FLOW.resultInfo].post(nil)
        local lines = ppLines()
        assert(#lines == 1, #lines)
        assert(lines[1]:find("pp summary packetFlayer=0 packetRyuki=0 toggle=0 activateBlast=3 ", 1, true), lines[1])
    end)
end

return T
