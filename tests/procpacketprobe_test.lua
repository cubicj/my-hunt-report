local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local FLOW = {
    playing = "app.cQuestPlaying.enter()",
    resultInfo = "app.cGUIQuestResultInfo.execute()",
}

local PROC = {
    packetFlayer = "app.cEnemyBadConditionSkillStabbing.receiveActivatePacket(app.net_packet.cEmSkillActivateStabbing)",
    packetRyuki = "app.cEnemyBadConditionSkillRyuki.receiveActivatePacket(app.net_packet.cEmSkillActivateRyuki)",
    toggle = "app.cEmModuleConditions.mcUpdater.onReceivePacket(app.net_packet.cEmToggleCondition)",
    blast = "app.cEnemyBadConditionBlast.onActivate",
    flayer = "app.cEnemyBadConditionSkillStabbing.onActivate",
    elementConvert = "app.cEnemyBadConditionSkillRyuki.onActivate",
    setParam = "app.cEnemyStockDamage.cBadConditionDamageInfo.setParam(System.Single, app.TARGET_ACCESS_KEY, System.Boolean)",
    external = "app.cEnemyStockDamage.stockExternalDamage(System.Single, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean)",
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
    local originalThread = thread
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
        hooks.storage = {}
        thread = { get_hook_storage = function() return hooks.storage end }
        local probe = assert(loadfile("reframework/autorun/MyHuntReport/ProcPacketProbe.lua"))()
        probe.install()
        callback({ probe = probe, hooks = hooks })
    end)
    Game.hook, Game.singleton, Game.masterHunter, Game.callStatic = hook, singleton, masterHunter, callStatic
    sdk.to_managed_object, sdk.to_valuetype, sdk.to_float = toManaged, toValue, toFloat
    thread = originalThread
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

local function withProcProbe(callback)
    withProbe(function(c)
        Log.setDeveloperMode(true)
        Game.callStatic = function(typeName, signature, key)
            if typeName == "app.TargetAccessKeyUtil" and signature == "getHunterCharacter(app.TARGET_ACCESS_KEY)" then
                if key.Category == 0 and key.UniqueIndex == 0 then
                    return { get_GameObject = function() return { get_Name = function() return "MasterPlayer" end } end }
                end
                if key.Category == 0 then
                    return { get_GameObject = function() return { get_Name = function() return "Player_Replica_" .. key.UniqueIndex end } end }
                end
                return nil
            end
        end
        callback(c)
    end)
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
        for _, signature in pairs(PROC) do assert(c.hooks[signature], signature) end
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

function T.packetReceiversLogFieldsCountAndBracket()
    withProcProbe(function(c)
        c.hooks[PROC.packetFlayer].pre({ [3] = { UniqueIndex = 7, Damage = 60.0, AttackerNetID = 3, GuiState = 1 } })
        assert(c.probe.activeBracket() == "packet:flayer")
        c.hooks[PROC.packetFlayer].post(nil)
        assert(c.probe.activeBracket() == nil)
        c.hooks[PROC.packetRyuki].pre({ [3] = { UniqueIndex = 7, Damage = 42.5, AttackerNetID = 1 } })
        assert(c.probe.activeBracket() == "packet:elementConvert")
        c.hooks[PROC.packetRyuki].post(nil)
        local counters = c.probe.counters()
        assert(counters.packetFlayer == 1 and counters.packetRyuki == 1, stubs.encode(counters))
        local lines = ppLines()
        assert(lines[1] == "[MyHuntReport] pp packet flayer em=7 damage=60.0 attackerNet=3 gui=1", lines[1])
        assert(lines[2] == "[MyHuntReport] pp packet elementConvert em=7 damage=42.5 attackerNet=1 gui=-", lines[2])
    end)
end

function T.packetPostPopsEvenWhenDeveloperModeTurnedOff()
    withProcProbe(function(c)
        c.hooks[PROC.packetFlayer].pre({ [3] = {} })
        assert(c.probe.activeBracket() == "packet:flayer")
        Log.setDeveloperMode(false)
        c.hooks[PROC.packetFlayer].post(nil)
        Log.setDeveloperMode(true)
        assert(c.probe.activeBracket() == nil)
        c.hooks[PROC.packetFlayer].post(nil)
        assert(c.probe.activeBracket() == nil)
    end)
end

function T.packetUnreadableStillCountsAndOpensBracket()
    withProcProbe(function(c)
        sdk.to_managed_object = function() error("decode") end
        c.hooks[PROC.packetRyuki].pre({ [3] = {} })
        assert(c.probe.counters().packetRyuki == 1)
        assert(c.probe.activeBracket() == "packet:elementConvert")
        assert(ppLines()[1] == "[MyHuntReport] pp packet elementConvert unreadable step=packet", ppLines()[1])
        c.hooks[PROC.packetRyuki].post(nil)
        c.hooks[PROC.packetFlayer].pre({ [3] = raising() })
        assert(ppLines()[2] == "[MyHuntReport] pp packet flayer unreadable step=packet", ppLines()[2])
    end)
    withProcProbe(function(c)
        c.hooks[PROC.packetFlayer].pre({ [3] = raising() })
        assert(ppLines()[1] == "[MyHuntReport] pp packet flayer em=? damage=? attackerNet=? gui=?", ppLines()[1])
    end)
end

function T.toggleReceiverLogsFieldsAndBracket()
    withProcProbe(function(c)
        c.hooks[PROC.toggle].pre({ [3] = { UniqueIndex = 7, Type = 9, ActiveAndCount = 17, Invoker = 3 } })
        assert(c.probe.activeBracket() == "toggle")
        assert(ppLines()[1] == "[MyHuntReport] pp toggle em=7 type=9 active=17 invoker=3", ppLines()[1])
        c.hooks[PROC.toggle].post(nil)
        assert(c.probe.activeBracket() == nil)
        assert(c.probe.counters().toggle == 1)
    end)
end

function T.blastActivationLogsInvokerObjectBracketAndPresetFields()
    withProcProbe(function(c)
        local blast = {
            _Invoker = { Category = 0, UniqueIndex = 0 },
            _Count = 2,
            _IsPlayerCondition = true,
            _PresetParamRef = { _DamageEm = 100.0, _DamageExEm = 120.0 },
        }
        c.hooks[PROC.blast].pre({ [2] = blast })
        assert(ppLines()[1] == "[MyHuntReport] pp activate blast invoker=0/0 obj=MasterPlayer in=none count=2 player=true damageEm=100.0 damageExEm=120.0", ppLines()[1])
        local counters = c.probe.counters()
        assert(counters.activateBlast == 1 and counters.activateInsidePacket == 0, stubs.encode(counters))
        c.hooks[PROC.toggle].pre({ [3] = { UniqueIndex = 7, Type = 9, ActiveAndCount = 1, Invoker = 3 } })
        c.hooks[PROC.blast].pre({ [2] = blast })
        c.hooks[PROC.toggle].post(nil)
        assert(ppLines()[3]:find("pp activate blast invoker=0/0 obj=MasterPlayer in=toggle count=2", 1, true), ppLines()[3])
        assert(c.probe.counters().activateBlast == 2 and c.probe.counters().activateInsidePacket == 1)
    end)
    withProcProbe(function(c)
        c.hooks[PROC.blast].pre({ [2] = { _Invoker = { Category = 1, UniqueIndex = 2253 } } })
        assert(ppLines()[1] == "[MyHuntReport] pp activate blast invoker=1/2253 obj=nil in=none count=nil player=nil damageEm=? damageExEm=?", ppLines()[1])
        c.hooks[PROC.blast].pre({ [2] = raising() })
        assert(ppLines()[2] == "[MyHuntReport] pp activate blast invoker=? obj=? in=none count=? player=? damageEm=? damageExEm=?", ppLines()[2])
        c.hooks[PROC.blast].pre({})
        assert(ppLines()[3] == "[MyHuntReport] pp activate blast unreadable step=this", ppLines()[3])
        assert(c.probe.counters().activateBlast == 3)
    end)
end

function T.skillActivationsInsidePacketLogInvokerAndCount()
    withProcProbe(function(c)
        c.hooks[PROC.packetFlayer].pre({ [3] = { UniqueIndex = 7, Damage = 60.0, AttackerNetID = 3, GuiState = 0 } })
        c.hooks[PROC.flayer].pre({ [2] = { _Invoker = { Category = 0, UniqueIndex = 0 } } })
        c.hooks[PROC.packetFlayer].post(nil)
        c.hooks[PROC.elementConvert].pre({ [2] = { _Invoker = { Category = 0, UniqueIndex = 2 } } })
        local lines = ppLines()
        assert(lines[2] == "[MyHuntReport] pp activate flayer invoker=0/0 obj=MasterPlayer in=packet:flayer", lines[2])
        assert(lines[3] == "[MyHuntReport] pp activate elementConvert invoker=0/2 obj=Player_Replica_2 in=none", lines[3])
        local counters = c.probe.counters()
        assert(counters.activateFlayer == 1 and counters.activateRyuki == 1 and counters.activateInsidePacket == 1, stubs.encode(counters))
        c.hooks[PROC.flayer].pre({ [2] = { _Invoker = nil } })
        assert(ppLines()[4] == "[MyHuntReport] pp activate flayer invoker=nil obj=nil in=none", ppLines()[4])
    end)
end

function T.damageCallsOutsideBracketReadNothing()
    withProcProbe(function(c)
        c.hooks[PROC.setParam].pre(raising())
        c.hooks[PROC.external].pre(raising())
        assert(#ppLines() == 0)
        local counters = c.probe.counters()
        assert(counters.setParamInsidePacket == 0 and counters.externalInsidePacket == 0)
    end)
end

function T.damageCallsInsideBracketLogValueKeyAndBracket()
    withProcProbe(function(c)
        c.hooks[PROC.packetFlayer].pre({ [3] = { UniqueIndex = 7, Damage = 60.0, AttackerNetID = 3, GuiState = 0 } })
        c.hooks[PROC.setParam].pre({ [3] = 60.0, [4] = { Category = 0, UniqueIndex = 0 } })
        c.hooks[PROC.external].pre({ [3] = 60.0, [5] = { _HasValue = true, _Value = { Category = 0, UniqueIndex = 0 } } })
        c.hooks[PROC.packetFlayer].post(nil)
        local lines = ppLines()
        assert(lines[2] == "[MyHuntReport] pp setParam value=60.0 key=0/0 in=packet:flayer", lines[2])
        assert(lines[3] == "[MyHuntReport] pp external value=60.0 hasKey=true key=0/0 in=packet:flayer", lines[3])
        local counters = c.probe.counters()
        assert(counters.setParamInsidePacket == 1 and counters.externalInsidePacket == 1, stubs.encode(counters))
    end)
    withProcProbe(function(c)
        c.hooks[PROC.toggle].pre({ [3] = {} })
        sdk.to_valuetype = function() error("key failed") end
        c.hooks[PROC.setParam].pre({ [3] = 100.0, [4] = {} })
        c.hooks[PROC.external].pre({ [3] = 1.0, [5] = {} })
        assert(ppLines()[2] == "[MyHuntReport] pp setParam value=100.0 key=? in=toggle", ppLines()[2])
        assert(ppLines()[3] == "[MyHuntReport] pp external value=1.0 hasKey=? key=? in=toggle", ppLines()[3])
        sdk.to_valuetype = function(value) return value end
        c.hooks[PROC.external].pre({ [3] = 1.0, [5] = raising() })
        assert(ppLines()[4] == "[MyHuntReport] pp external value=1.0 hasKey=? key=?/? in=toggle", ppLines()[4])
        c.hooks[PROC.toggle].post(nil)
    end)
end

function T.questStartClearsOpenBrackets()
    withProcProbe(function(c)
        c.hooks[PROC.toggle].pre({ [3] = {} })
        assert(c.probe.activeBracket() == "toggle")
        c.hooks[FLOW.playing].pre({})
        assert(c.probe.activeBracket() == nil)
        c.hooks[PROC.toggle].post(nil)
        assert(c.probe.activeBracket() == nil)
        assert(c.hooks.storage.pushed == nil)
    end)
end

function T.nestedReceivesRestoreTheOuterBracket()
    withProcProbe(function(c)
        c.hooks[PROC.packetFlayer].pre({ [3] = {} })
        local outerStorage = c.hooks.storage
        c.hooks.storage = {}
        c.hooks[PROC.toggle].pre({ [3] = {} })
        assert(c.probe.activeBracket() == "toggle")
        c.hooks[PROC.toggle].post(nil)
        assert(c.hooks.storage.pushed == nil)
        assert(c.probe.activeBracket() == "packet:flayer")
        c.hooks.storage = outerStorage
        c.hooks[PROC.packetFlayer].post(nil)
        assert(c.probe.activeBracket() == nil)
        assert(c.hooks.storage.pushed == nil)
    end)
    withProcProbe(function(c)
        c.hooks[PROC.packetFlayer].pre({ [3] = {} })
        local outerStorage = c.hooks.storage
        c.hooks.storage = {}
        Log.setDeveloperMode(false)
        c.hooks[PROC.toggle].pre(raising())
        assert(c.hooks.storage.pushed == nil)
        c.hooks[PROC.toggle].post(nil)
        assert(c.probe.activeBracket() == "packet:flayer")
        Log.setDeveloperMode(true)
        c.hooks.storage = outerStorage
        c.hooks[PROC.blast].pre({ [2] = { _Invoker = { Category = 0, UniqueIndex = 0 } } })
        local lines = ppLines()
        assert(lines[2]:find("in=packet:flayer", 1, true), lines[2])
        assert(c.probe.counters().activateInsidePacket == 1)
        c.hooks[PROC.packetFlayer].post(nil)
        assert(c.probe.activeBracket() == nil)
        assert(c.hooks.storage.pushed == nil)
    end)
end

return T
