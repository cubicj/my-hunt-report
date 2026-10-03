local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local function flowLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] flow ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function flowObject(name, state)
    local object = { get_type_definition = function() return { get_full_name = function() return name end } end }
    if state ~= nil then object._State = state end
    return object
end

local function withProbe(callback)
    local hook, singleton, uptime = Game.hook, Game.singleton, Game.uptime
    local toInt64 = sdk.to_int64
    local hooks, names = {}, {}
    local c = { hooks = hooks, names = names, now = 100.0, director = nil, life = nil }
    local ok, err = pcall(function()
        stubs.reset()
        Log.setDeveloperMode(true)
        Log.resetCounts()
        Game.hook = function(typeName, signature, pre, post)
            local label = typeName .. "." .. signature
            names[#names + 1] = label
            hooks[label] = { pre = pre, post = post }
            return true
        end
        Game.singleton = function(name)
            if name == "app.MissionManager" and c.director then
                return { get_QuestDirector = function() return c.director end }
            end
            if name == "app.LifeAreaMusicManager" and c.life ~= nil then
                return { get_IsInLifeArea = function() return c.life end }
            end
            return nil
        end
        Game.uptime = function() return c.now end
        sdk.to_int64 = function(value) return value end
        local probe = assert(loadfile("reframework/autorun/MyHuntReport/FlowProbe.lua"))()
        c.probe = probe
        callback(c)
    end)
    Game.hook, Game.singleton, Game.uptime = hook, singleton, uptime
    sdk.to_int64 = toInt64
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

function T.installRegistersEveryCandidateHookOnce()
    withProbe(function(c)
        c.probe.install()
        c.probe.install()
        assert(#c.names == #c.probe.HOOKS, #c.names .. " vs " .. #c.probe.HOOKS)
        for index, entry in ipairs(c.probe.HOOKS) do
            local label = entry[1] .. "." .. entry[2]
            assert(c.names[index] == label, c.names[index] .. " vs " .. label)
            assert(c.hooks[label].pre ~= nil and c.hooks[label].post == nil, label)
        end
        local expected = {
            "app.cQuestDirector.endFlow()",
            "app.cQuestDirector.requestLeaveResult()",
            "app.cQuestDirector.reqCloseQuestFixResult()",
            "app.cQuestDirector.evLoadEnd()",
            "app.cQuestDirector.requestLeaveShowing(System.Boolean)",
            "app.cQuestReward.enter()",
            "app.cQuestReward.setRequestCloseFixResult()",
            "app.cQuestPlaying.exit()",
            "app.cQuestSuccessFreePlayTime.exit()",
            "app.cQuestStart.enter()",
            "app.cQuestClearEnd.enter()",
            "app.cQuestFailedEnd.enter()",
            "app.cQuestResult.enter()",
            "app.LifeAreaMusicManager.enterLifeArea()",
            "app.LifeAreaMusicManager.exitLifeArea()",
        }
        for index, label in ipairs(expected) do
            assert(c.names[index] == label, tostring(c.names[index]) .. " vs " .. label)
        end
        assert(#expected == #c.names)
    end)
end

function T.hookLogsLabelUptimeAndSnapshot()
    withProbe(function(c)
        c.director = { _CurFlow = flowObject("app.cQuestReward"), _NextFlow = flowObject("app.cQuestSceneLoading", 2) }
        c.life = false
        c.probe.install()
        c.now = 2866.5
        c.hooks["app.cQuestDirector.endFlow()"].pre({})
        local lines = flowLines()
        assert(#lines == 1, #lines)
        assert(lines[1]:find("flow hook app.cQuestDirector.endFlow() at 2866.5 cur=app.cQuestReward next=app.cQuestSceneLoading state=nil life=false", 1, true), lines[1])
    end)
end

function T.leaveShowingHookAppendsItsArgument()
    withProbe(function(c)
        c.probe.install()
        c.hooks["app.cQuestDirector.requestLeaveShowing(System.Boolean)"].pre({ [3] = 1 })
        c.hooks["app.cQuestDirector.requestLeaveShowing(System.Boolean)"].pre({ [3] = 0 })
        local lines = flowLines()
        assert(#lines == 2, #lines)
        assert(lines[1]:find(" arg=true", 1, true), lines[1])
        assert(lines[2]:find(" arg=false", 1, true), lines[2])
    end)
end

function T.formatSnapshotPrintsNilForMissingAndQuestionMarkForFailures()
    withProbe(function(c)
        assert(c.probe.formatSnapshot(c.probe.snapshot()) == "cur=nil next=nil state=nil life=nil")
        c.director = {
            _CurFlow = setmetatable({}, { __index = function() error("boom") end }),
            _NextFlow = flowObject("app.cQuestResult", 3),
        }
        assert(c.probe.formatSnapshot(c.probe.snapshot()) == "cur=? next=app.cQuestResult state=? life=nil")
        c.director._CurFlow = flowObject("app.cQuestResult", 3)
        assert(c.probe.formatSnapshot(c.probe.snapshot()) == "cur=app.cQuestResult next=app.cQuestResult state=3 life=nil")
    end)
end

function T.updateLogsOneLinePerChangedFieldAndNothingWhenUnchanged()
    withProbe(function(c)
        c.director = { _CurFlow = flowObject("app.cQuestPlaying"), _NextFlow = nil }
        c.life = true
        c.probe.update()
        local first = flowLines()
        assert(#first == 2, #first)
        assert(first[1]:find("flow change cur nil -> app.cQuestPlaying at 100.0", 1, true), first[1])
        assert(first[2]:find("flow change life nil -> true at 100.0", 1, true), first[2])
        c.probe.update()
        assert(#flowLines() == 2, #flowLines())
        c.now = 101.0
        c.director._CurFlow = flowObject("app.cQuestResult", 1)
        c.director._NextFlow = flowObject("app.cQuestReward")
        c.probe.update()
        local lines = flowLines()
        assert(#lines == 5, #lines)
        assert(lines[3]:find("flow change cur app.cQuestPlaying -> app.cQuestResult at 101.0 cur=app.cQuestResult next=app.cQuestReward state=1 life=true", 1, true), lines[3])
        assert(lines[4]:find("flow change next nil -> app.cQuestReward at 101.0", 1, true), lines[4])
        assert(lines[5]:find("flow change state nil -> 1 at 101.0", 1, true), lines[5])
        c.director._CurFlow._State = 2
        c.probe.update()
        assert(#flowLines() == 6)
        assert(flowLines()[6]:find("flow change state 1 -> 2 at 101.0", 1, true), flowLines()[6])
    end)
end

function T.updateIsSilentAndReadsNothingWithDeveloperModeOff()
    withProbe(function(c)
        Log.setDeveloperMode(false)
        local reads = 0
        c.director = setmetatable({}, { __index = function() reads = reads + 1 return nil end })
        c.probe.update()
        assert(#flowLines() == 0)
        assert(reads == 0, reads)
    end)
end

function T.resetForTestsForgetsThePreviousSnapshot()
    withProbe(function(c)
        c.director = { _CurFlow = flowObject("app.cQuestPlaying") }
        c.probe.update()
        c.probe.resetForTests()
        c.probe.update()
        assert(#flowLines() == 2, #flowLines())
    end)
end

return T
