local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local FLOW = {
    playing = "app.cQuestPlaying.enter()",
    clear = "app.cQuestClear.enter()",
    failed = "app.cQuestFailed.enter()",
    result = "app.cQuestResult.enter()",
    resultInfo = "app.cGUIQuestResultInfo.execute()",
}

local function raising()
    return setmetatable({}, { __index = function(_, key) error("touched " .. tostring(key)) end })
end

local function gpLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] gp ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function withProbe(callback)
    local hook, uptime, singleton, masterHunter, callStatic = Game.hook, Game.uptime, Game.singleton, Game.masterHunter, Game.callStatic
    local toManaged = sdk.to_managed_object
    local originalThread = thread
    local hooks = {}
    local ok, err = pcall(function()
        Log.setDeveloperMode(false)
        Log.resetCounts()
        Game.hook = function(typeName, signature, pre, post)
            hooks[typeName .. "." .. signature] = { pre = pre, post = post }
            return true
        end
        Game.uptime = function() return 42.5 end
        Game.callStatic = function(typeName, signature)
            if typeName == "via.Application" and signature == "get_UpTimeSecond" then return 42.5 end
        end
        Game.singleton = function() return nil end
        Game.masterHunter = function() return nil end
        sdk.to_managed_object = function(value) return value end
        thread = { get_hook_storage = function() return hooks.storage or {} end }
        hooks.storage = {}
        local probe = assert(loadfile("reframework/autorun/MyHuntReport/GuestProbe.lua"))()
        probe.install()
        callback({ probe = probe, hooks = hooks })
    end)
    Game.hook, Game.uptime, Game.singleton, Game.masterHunter, Game.callStatic = hook, uptime, singleton, masterHunter, callStatic
    sdk.to_managed_object = toManaged
    thread = originalThread
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
        counters.own = 3
        local line = c.probe.summaryLine(counters)
        assert(line:sub(1, 12) == "summary own=", line)
        assert(line:find("own=3", 1, true), line)
        local first = c.probe.COUNTER_ORDER[1]
        local last = c.probe.COUNTER_ORDER[#c.probe.COUNTER_ORDER]
        assert(line:find(first .. "=", 1, true) < line:find(last .. "=", 1, true), line)
    end)
end

function T.installsFlowHooksAndStaysSilentWhenDeveloperModeOff()
    withProbe(function(c)
        for _, signature in pairs(FLOW) do assert(c.hooks[signature], signature) end
        for _, entry in pairs(c.hooks) do
            if type(entry) == "table" and entry.pre then entry.pre(raising()) end
            if type(entry) == "table" and entry.post then entry.post(raising()) end
        end
        c.probe.update()
        assert(#gpLines() == 0)
        for _, name in ipairs(c.probe.COUNTER_ORDER) do assert(c.probe.counters()[name] == 0, name) end
    end)
end

function T.flowHooksLogWhenDeveloperModeOn()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        c.hooks[FLOW.playing].pre({})
        c.hooks[FLOW.clear].pre({})
        local lines = gpLines()
        assert(#lines == 4, #lines)
        assert(lines[1]:find("gp flow playing t=42.5", 1, true), lines[1])
        assert(lines[2]:find("gp state playing=unresolved", 1, true), lines[2])
        assert(lines[3]:find("gp master name=unresolved", 1, true), lines[3])
        assert(lines[4]:find("gp flow clear t=42.5", 1, true), lines[4])
    end)
end

function T.resultInfoPostReadsFieldsAndPrintsSummary()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        local info = {
            get_QuestEndType = function() return 2 end,
            get_QuestFailedType = function() return 0 end,
            get_ClearTime = function() return 138840 end,
            get_JoinMemberNum = function() return 4 end,
            get_QuestLevel = function() return 5 end,
            ["<IsLateJoin>k__BackingField"] = true,
        }
        c.hooks[FLOW.resultInfo].pre({ [2] = info })
        c.hooks[FLOW.resultInfo].post(nil)
        local lines = gpLines()
        assert(lines[1]:find("gp result endType=2 failedType=0 clearTimeMs=138840 joinMemberNum=4 lateJoin=true questLevel=5", 1, true), lines[1])
        assert(lines[2]:find("gp summary own=0", 1, true), lines[2])
    end)
end

function T.questStartResetsCounters()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        c.probe.counters().own = 5
        c.hooks[FLOW.playing].pre({})
        assert(c.probe.counters().own == 0)
    end)
end

function T.updateLogsStateOnceWhenDeveloperModeOn()
    withProbe(function(c)
        c.probe.update()
        assert(#gpLines() == 0)
        Log.setDeveloperMode(true)
        c.probe.update()
        c.probe.update()
        local lines = gpLines()
        assert(#lines == 2, #lines)
        assert(lines[1]:find("gp state playing=unresolved elapsed=unresolved hostStarted=unresolved lateJoinStarted=unresolved", 1, true), lines[1])
        assert(lines[2]:find("gp master name=unresolved", 1, true), lines[2])
    end)
end

function T.resultInfoGetterFailuresStillPrintCompleteResultAndSummary()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        local info = raising()
        for _, name in ipairs({ "get_QuestEndType", "get_QuestFailedType", "get_ClearTime", "get_JoinMemberNum", "get_QuestLevel" }) do
            info[name] = function() error("getter failed") end
        end
        c.hooks[FLOW.resultInfo].pre({ [2] = info })
        c.hooks[FLOW.resultInfo].post(nil)
        local lines = gpLines()
        assert(#lines == 2, #lines)
        assert(lines[1] == "[MyHuntReport] gp result endType=? failedType=? clearTimeMs=? joinMemberNum=? lateJoin=? questLevel=?", lines[1])
        assert(lines[2] == "[MyHuntReport] gp " .. c.probe.summaryLine(c.probe.counters()), lines[2])
    end)
end

function T.resultInfoDecoderFailureClearsStaleStateAndPrintsDiagnostics()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        c.hooks[FLOW.resultInfo].pre({ [2] = { ["<IsLateJoin>k__BackingField"] = true } })
        sdk.to_managed_object = function() error("decoder failed") end
        c.hooks[FLOW.resultInfo].pre({ [2] = {} })
        c.hooks[FLOW.resultInfo].post(nil)
        local lines = gpLines()
        assert(#lines == 2, #lines)
        assert(lines[1] == "[MyHuntReport] gp result endType=? failedType=? clearTimeMs=? joinMemberNum=? lateJoin=? questLevel=?", lines[1])
        assert(lines[2] == "[MyHuntReport] gp " .. c.probe.summaryLine(c.probe.counters()), lines[2])
    end)
end

function T.resultInfoMissingObjectStillPrintsDiagnostics()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        sdk.to_managed_object = function() return nil end
        c.hooks[FLOW.resultInfo].pre({ [2] = {} })
        c.hooks[FLOW.resultInfo].post(nil)
        local lines = gpLines()
        assert(#lines == 2, #lines)
        assert(lines[1] == "[MyHuntReport] gp result endType=? failedType=? clearTimeMs=? joinMemberNum=? lateJoin=? questLevel=?", lines[1])
        assert(lines[2] == "[MyHuntReport] gp " .. c.probe.summaryLine(c.probe.counters()), lines[2])
    end)
end

function T.flowClockFailurePrintsUnknownWithoutFallback()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        Game.callStatic = function() return nil, "clock failed" end
        c.hooks[FLOW.playing].pre({})
        local lines = gpLines()
        assert(#lines == 3, #lines)
        assert(lines[1] == "[MyHuntReport] gp flow playing t=?", lines[1])
    end)
end

function T.flowClockExceptionStillPrintsUnknown()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        Game.callStatic = function() error("clock failed") end
        c.hooks[FLOW.clear].pre({})
        local lines = gpLines()
        assert(#lines == 1, #lines)
        assert(lines[1] == "[MyHuntReport] gp flow clear t=?", lines[1])
    end)
end

function T.flowClockRejectsNonnumericValue()
    withProbe(function(c)
        Log.setDeveloperMode(true)
        Game.callStatic = function() return "42.5" end
        c.hooks[FLOW.clear].pre({})
        local lines = gpLines()
        assert(#lines == 1, #lines)
        assert(lines[1] == "[MyHuntReport] gp flow clear t=?", lines[1])
    end)
end

function T.withProbeRestoresThreadAfterSuccessfulCallback()
    local originalThread = thread
    local ok, err = pcall(function()
        withProbe(function() end)
        assert(thread == originalThread, "thread leaked after successful callback")
    end)
    thread = originalThread
    if not ok then error(err, 0) end
end

function T.withProbeRestoresThreadAfterFailedCallback()
    local originalThread = thread
    local ok, err = pcall(function()
        local callbackOk, callbackError = pcall(withProbe, function() error("callback failed") end)
        assert(not callbackOk and tostring(callbackError):find("callback failed", 1, true), tostring(callbackError))
        assert(thread == originalThread, "thread leaked after failed callback")
    end)
    thread = originalThread
    if not ok then error(err, 0) end
end

return T
