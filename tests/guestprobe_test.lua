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

local HIT = {
    detail = "app.cEnemyStockDamage.stockDamageDetail(app.HitInfo)",
    net = "app.cEnemyStockDamage.stockDamageNet(app.net_packet.cEmDamage)",
    calc = "app.cEnemyStockDamage.calcStockDamage(app.cEnemyStockDamage.cCalcDamage, app.cEnemyStockDamage.cPreCalcDamage, app.cEnemyStockDamage.cDamageRate, System.Boolean)",
    mark = "app.cEnemyStockDamage.mcEnemyHitMarkManager.playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)",
    toPacket = "app.cEnemyStockDamage.cPreCalcDamage.toPacket(app.cEnemyContextHolder)",
    receive = "app.EnemyCharacter.receivePacket_Damage(app.net_packet.cEmDamage)",
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
        for _, signature in pairs(HIT) do assert(c.hooks[signature], signature) end
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

local function hitFixture(c)
    local masterObject = { get_address = function() return 100 end, get_Name = function() return "MasterPlayer" end }
    local replicaObject = { get_address = function() return 200 end, get_Name = function() return "Player_Replica_32" end }
    local em = {
        get_IsBoss = function() return true end,
        get_UniqueIndex = function() return 3 end,
        Parts = { _ParamParts = { _MeatArray = { _DataArray = { [1] = { getActionMeat = function() return 45.0 end } } } } },
        Scar = { _ScarParts = { Get = function() return { get_State = function() return 2 end } end } },
    }
    local enemyObject = { get_address = function() return 300 end }
    Game.masterHunter = function() return { get_GameObject = function() return masterObject end } end
    Game.isMasterGameObject = function(object) return object == masterObject end
    Game.enemyContext = function(object) if object == enemyObject then return em end end
    Game.enemyIsDead = function() return false end
    local function hitInfo(owner, address)
        return {
            getActualAttackOwner = function() return owner end,
            get_DamageOwner = function() return enemyObject end,
            get_address = function() return address end,
        }
    end
    local preCalc = {
        Attack = 120.5, FixAttack = 0.0, AttackAttr = 1, AttrValue = 30.0, ActionType = 1,
        Common = { Attacker = { Category = 0, UniqueIndex = 1 }, ScarIndex = 0, PartsIndex = 2, MeatIndex = { _Value = 1 } },
    }
    local stock = { get_Context = function() return { get_Em = function() return em end } end }
    local packet = { UniqueIndex = 3, AttackerIndex = 1, Attack = 120.5, FixAttack = 0.0, AttackAttr = 1, AttrValue = 30.0, ActionType = 1, PartsIndex = 2, ScarIndex = 0, AttackCond = 3, CondValue = 10.0, SkillAdditionalDamage = 0.0 }
    return { master = masterObject, replica = replicaObject, hitInfo = hitInfo, preCalc = preCalc, stock = stock, packet = packet }
end

local function withHitProbe(callback)
    local isMaster, enemyContext, enemyIsDead = Game.isMasterGameObject, Game.enemyContext, Game.enemyIsDead
    local toValue, toFloat = sdk.to_valuetype, sdk.to_float
    withProbe(function(c)
        local ok, err = pcall(function()
            sdk.to_valuetype = function(pointer) return { get_field = function() return pointer end } end
            sdk.to_float = function(value) return value end
            Log.setDeveloperMode(true)
            callback(c, hitFixture(c))
        end)
        Game.isMasterGameObject, Game.enemyContext, Game.enemyIsDead = isMaster, enemyContext, enemyIsDead
        sdk.to_valuetype, sdk.to_float = toValue, toFloat
        if not ok then error(err, 0) end
    end)
end

function T.classifyOwnerSeparatesMasterReplicaAndOthers()
    withProbe(function(c)
        assert(c.probe.classifyOwner("MasterPlayer", true) == "own")
        assert(c.probe.classifyOwner("Player_Replica_32", false) == "replica")
        assert(c.probe.classifyOwner("Otomo_00", false) == "other")
        assert(c.probe.classifyOwner(nil, false) == "other")
    end)
end

function T.ownHitFlowsDetailCalcMarkAndCounts()
    withHitProbe(function(c, f)
        c.hooks[HIT.detail].pre({ [3] = f.hitInfo(f.master, 555) })
        c.hooks[HIT.calc].pre({ [2] = f.stock, [4] = f.preCalc, [5] = {} })
        c.hooks[HIT.mark].pre({ [3] = { FinalDamage = 88.0 }, [4] = f.hitInfo(f.master, 555) })
        local counters = c.probe.counters()
        assert(counters.own == 1 and counters.replica == 0 and counters.calcNet == 0, stubs.encode(counters))
        assert(counters.calcInsideNetWithOwnPending == 0 and counters.markAddrMismatch == 0)
        local lines = gpLines()
        assert(lines[1]:find("gp own detail em=3 addr=555", 1, true), lines[1])
        assert(lines[2]:find("gp calc em=3 net=false ownPending=true attacker=0/1 attack=120.5 fix=0.0 attr=1/30.0 scar=0 parts=2", 1, true), lines[2])
        assert(lines[3]:find("gp mark em=3 net=false addrMatch=true final=88.0", 1, true), lines[3])
    end)
end

function T.replicaDetailCountsWithoutPending()
    withHitProbe(function(c, f)
        c.hooks[HIT.detail].pre({ [3] = f.hitInfo(f.replica, 556) })
        c.hooks[HIT.calc].pre({ [2] = f.stock, [4] = f.preCalc, [5] = {} })
        local counters = c.probe.counters()
        assert(counters.replica == 1 and counters.own == 0)
        assert(gpLines()[1]:find("gp calc em=3 net=false ownPending=false", 1, true), gpLines()[1])
    end)
end

function T.netBracketMarksCalcAndDetectsOwnPendingContamination()
    withHitProbe(function(c, f)
        c.hooks[HIT.detail].pre({ [3] = f.hitInfo(f.master, 557) })
        c.hooks[HIT.net].pre({ [3] = f.packet })
        assert(c.probe.netDepth() == 1)
        c.hooks[HIT.calc].pre({ [2] = f.stock, [4] = f.preCalc, [5] = {} })
        c.hooks[HIT.mark].pre({ [3] = { FinalDamage = 50.0 }, [4] = f.hitInfo(f.replica, 999) })
        c.hooks[HIT.net].post(nil)
        assert(c.probe.netDepth() == 0)
        local counters = c.probe.counters()
        assert(counters.netDamage == 1 and counters.calcNet == 1 and counters.calcInsideNetWithOwnPending == 1, stubs.encode(counters))
        assert(counters.markNet == 1 and counters.markAddrMismatch == 1)
        local lines = gpLines()
        assert(lines[2]:find("gp net damage em=3 attacker=1 attack=120.5 fix=0.0 attr=1/30.0 act=1 parts=2 scar=0 cond=3/10.0 add=0.0", 1, true), lines[2])
        assert(lines[3]:find("gp calc em=3 net=true ownPending=true", 1, true), lines[3])
        assert(lines[4]:find("gp mark em=3 net=true addrMatch=false final=50.0", 1, true), lines[4])
    end)
end

function T.toPacketPostLogsPacketFieldsAndCounts()
    withHitProbe(function(c, f)
        c.hooks[HIT.toPacket].post(f.packet)
        assert(c.probe.counters().toPacket == 1)
        assert(gpLines()[1]:find("gp toPacket em=3 attacker=1 attack=120.5 fix=0.0 attr=1/30.0 scar=0 parts=2", 1, true), gpLines()[1])
    end)
end

function T.receiveDamageCountsAndLogsFirstTwenty()
    withHitProbe(function(c, f)
        for _ = 1, 25 do c.hooks[HIT.receive].pre({ [3] = f.packet }) end
        assert(c.probe.counters().receiveDamage == 25)
        assert(#gpLines() == 20, #gpLines())
        assert(gpLines()[1]:find("gp receive damage em=3 attacker=1", 1, true), gpLines()[1])
    end)
end

function T.ownDetailLinesStopAtBudgetButCountersContinue()
    withHitProbe(function(c, f)
        for index = 1, 405 do c.hooks[HIT.detail].pre({ [3] = f.hitInfo(f.master, index) }) end
        assert(c.probe.counters().own == 405)
        assert(#gpLines() == 400, #gpLines())
    end)
end

function T.deadAndWoundFailuresCount()
    withHitProbe(function(c, f)
        Game.enemyIsDead = function() return true end
        c.hooks[HIT.detail].pre({ [3] = f.hitInfo(f.master, 558) })
        assert(c.probe.counters().deadOwn == 1)
        local broken = { Attack = 1.0, Common = { Attacker = { Category = 0, UniqueIndex = 1 }, ScarIndex = 0, PartsIndex = 2, MeatIndex = { _Value = 9 } } }
        local stock = { get_Context = function() return { get_Em = function() return { get_UniqueIndex = function() return 3 end, Parts = { _ParamParts = { _MeatArray = { _DataArray = {} } } }, Scar = { _ScarParts = { Get = function() error("no scar") end } } } end } end }
        c.hooks[HIT.calc].pre({ [2] = stock, [4] = broken, [5] = {} })
        assert(c.probe.counters().woundReadFail == 1 and c.probe.counters().meatReadFail == 1, stubs.encode(c.probe.counters()))
    end)
end

function T.detailUnreadableOwnerPreservesCountersAndPending()
    withHitProbe(function(c, f)
        c.hooks[HIT.detail].pre({ [3] = f.hitInfo(f.master, 559) })
        local before = stubs.encode(c.probe.counters())
        local lineCount = #stubs.logLines
        local hitInfo = f.hitInfo(f.master, 560)
        hitInfo.getActualAttackOwner = function() error("owner failed") end
        c.hooks[HIT.detail].pre({ [3] = hitInfo })
        assert(#stubs.logLines == lineCount + 1)
        assert(stubs.logLines[#stubs.logLines] == "[MyHuntReport] gp detail unreadable step=owner")
        assert(stubs.encode(c.probe.counters()) == before)
        assert(c.probe.netDepth() == 0)
        c.hooks[HIT.mark].pre({ [3] = { FinalDamage = 88.0 }, [4] = f.hitInfo(f.master, 559) })
        assert(gpLines()[3]:find("addrMatch=true", 1, true), gpLines()[3])
    end)
end

function T.calcUnreadableContextPreservesCountersAndPending()
    withHitProbe(function(c, f)
        c.hooks[HIT.detail].pre({ [3] = f.hitInfo(f.master, 561) })
        c.hooks[HIT.net].pre({ [3] = f.packet })
        local before = stubs.encode(c.probe.counters())
        local lineCount = #stubs.logLines
        local stock = { get_Context = function() error("context failed") end }
        c.hooks[HIT.calc].pre({ [2] = stock, [4] = f.preCalc })
        assert(#stubs.logLines == lineCount + 1)
        assert(stubs.logLines[#stubs.logLines] == "[MyHuntReport] gp calc unreadable step=context")
        assert(stubs.encode(c.probe.counters()) == before)
        assert(c.probe.netDepth() == 1)
        c.hooks[HIT.net].post(nil)
        c.hooks[HIT.mark].pre({ [3] = { FinalDamage = 88.0 }, [4] = f.hitInfo(f.master, 561) })
        assert(gpLines()[4]:find("addrMatch=true", 1, true), gpLines()[4])
    end)
end

function T.markUnreadableTargetPreservesCountersAndPending()
    withHitProbe(function(c, f)
        c.hooks[HIT.detail].pre({ [3] = f.hitInfo(f.master, 562) })
        c.hooks[HIT.net].pre({ [3] = f.packet })
        local before = stubs.encode(c.probe.counters())
        local lineCount = #stubs.logLines
        local hitInfo = f.hitInfo(f.master, 562)
        hitInfo.get_DamageOwner = function() error("target failed") end
        c.hooks[HIT.mark].pre({ [3] = { FinalDamage = 88.0 }, [4] = hitInfo })
        assert(#stubs.logLines == lineCount + 1)
        assert(stubs.logLines[#stubs.logLines] == "[MyHuntReport] gp mark unreadable step=target")
        assert(stubs.encode(c.probe.counters()) == before)
        assert(c.probe.netDepth() == 1)
        c.hooks[HIT.net].post(nil)
        c.hooks[HIT.mark].pre({ [3] = { FinalDamage = 88.0 }, [4] = f.hitInfo(f.master, 562) })
        assert(gpLines()[4]:find("addrMatch=true", 1, true), gpLines()[4])
    end)
end

function T.detailAddressReadFailuresStayUnreadableWithProductionHelpers()
    local function failAddress() error("address failed") end
    local function missingAddress() return nil end
    local function masterAddress() return 100 end
    for _, scenario in ipairs({
        { ownerAddress = failAddress, masterAddress = masterAddress, expectedMaster = 100 },
        { ownerAddress = missingAddress, masterAddress = masterAddress, expectedMaster = 100 },
        { ownerAddress = masterAddress, masterAddress = failAddress },
        { ownerAddress = masterAddress, masterAddress = missingAddress },
    }) do
        withProbe(function(c)
            Log.setDeveloperMode(true)
            Game.masterHunter = function()
                return { get_GameObject = function() return { get_address = scenario.masterAddress } end }
            end
            local owner = {
                get_address = scenario.ownerAddress,
                get_Name = function() return "Player_Replica_32" end,
            }
            assert(Game.masterAddress() == scenario.expectedMaster)
            assert(Game.isMasterGameObject(owner) == false)
            local before = stubs.encode(c.probe.counters())
            local lineCount = #stubs.logLines
            c.hooks[HIT.detail].pre({ [3] = { getActualAttackOwner = function() return owner end } })
            assert(#stubs.logLines == lineCount + 1, "missing unreadable owner diagnostic")
            assert(stubs.logLines[#stubs.logLines] == "[MyHuntReport] gp detail unreadable step=owner")
            assert(stubs.encode(c.probe.counters()) == before)
            assert(c.probe.netDepth() == 0)
        end)
    end
end

function T.receiveDecodeFailuresPreserveSuccessfulLineBudget()
    withHitProbe(function(c, f)
        local toManaged = sdk.to_managed_object
        sdk.to_managed_object = function() error("packet decode failed") end
        for _ = 1, 20 do c.hooks[HIT.receive].pre({ [3] = f.packet }) end
        assert(c.probe.counters().receiveDamage == 20)
        local unreadableLines = gpLines()
        assert(#unreadableLines == 5, #unreadableLines)
        assert(unreadableLines[1] == "[MyHuntReport] gp receive unreadable step=packet")
        sdk.to_managed_object = toManaged
        for _ = 1, 25 do c.hooks[HIT.receive].pre({ [3] = f.packet }) end
        assert(c.probe.counters().receiveDamage == 45)
        local lines = gpLines()
        assert(#lines == 25, "expected 5 unreadable diagnostics and 20 readable receipts, got " .. #lines)
        for index = 6, 25 do
            assert(lines[index]:find("gp receive damage em=3 attacker=1", 1, true), lines[index])
        end
    end)
end

return T
