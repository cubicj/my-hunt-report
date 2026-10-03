local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local FLOW = {
    playing = "app.cQuestPlaying.enter()",
    resultInfo = "app.cGUIQuestResultInfo.execute()",
}

local HOOKS = {
    detail = "app.cEnemyStockDamage.stockDamageDetail(app.HitInfo)",
    external = "app.cEnemyStockDamage.stockExternalDamage(System.Single, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean, System.Boolean)",
    scar = "app.cEnemyStockDamage.stockExternalDamageScar(System.Int32, System.Single, System.Boolean, System.Boolean, System.Nullable`1<app.TARGET_ACCESS_KEY>, System.Boolean)",
    hitMark = "app.cEnemyStockDamage.mcEnemyHitMarkManager.playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)",
}

local function raising()
    return setmetatable({}, { __index = function(_, key) error("touched " .. tostring(key)) end })
end

local function wbLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] wb ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function enemy(index, health, maxHealth)
    local state = { health = health, maxHealth = maxHealth or health, scarStates = {} }
    local em = {
        get_UniqueIndex = function() return index end,
        Scar = { _ScarParts = { Get = function(_, scar)
            local value = state.scarStates[scar]
            if value == nil then error("no scar " .. tostring(scar)) end
            return { get_State = function() return value end }
        end } },
    }
    local character = {
        get_HealthMgr = function()
            return {
                get_Health = function() return state.health end,
                get_MaxHealth = function() return state.maxHealth end,
            }
        end,
    }
    local owner = { name = "Em" .. tostring(index), em = em, character = character }
    local stock = { get_Context = function() return { get_Em = function() return em end } end }
    return { owner = owner, em = em, stock = stock, state = state, index = index }
end

local function withProbe(callback)
    local hook, masterHunter, callStatic = Game.hook, Game.masterHunter, Game.callStatic
    local componentOf, enemyContext, isMaster, uptime = Game.componentOf, Game.enemyContext, Game.isMasterGameObject, Game.uptime
    local toManaged, toValue, toFloat, toInt64 = sdk.to_managed_object, sdk.to_valuetype, sdk.to_float, sdk.to_int64
    local originalThread = thread
    local hooks = {}
    local c = { hooks = hooks, now = 100.0 }
    local ok, err = pcall(function()
        Log.setDeveloperMode(false)
        Log.resetCounts()
        stubs.reset()
        Game.hook = function(typeName, signature, pre, post)
            hooks[typeName .. "." .. signature] = { pre = pre, post = post }
            return true
        end
        Game.masterHunter = function() return nil end
        Game.callStatic = function() return nil end
        Game.componentOf = function(gameObject) return gameObject and gameObject.character or nil end
        Game.enemyContext = function(gameObject) return gameObject and gameObject.em or nil end
        Game.isMasterGameObject = function(gameObject) return gameObject ~= nil and gameObject.name == "MasterPlayer" end
        Game.uptime = function() return c.now end
        sdk.to_managed_object = function(value) return value end
        sdk.to_valuetype = function(value) return value end
        sdk.to_float = function(value)
            if type(value) ~= "number" then error("not a float") end
            return value
        end
        sdk.to_int64 = function(value)
            if type(value) ~= "number" then error("not an integer") end
            return value
        end
        hooks.storage = {}
        thread = { get_hook_storage = function() return hooks.storage end }
        c.probe = assert(loadfile("reframework/autorun/MyHuntReport/WoundProbe.lua"))()
        c.probe.install()
        callback(c)
    end)
    Game.hook, Game.masterHunter, Game.callStatic = hook, masterHunter, callStatic
    Game.componentOf, Game.enemyContext, Game.isMasterGameObject, Game.uptime = componentOf, enemyContext, isMaster, uptime
    sdk.to_managed_object, sdk.to_valuetype, sdk.to_float, sdk.to_int64 = toManaged, toValue, toFloat, toInt64
    thread = originalThread
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

local function withDeveloperProbe(callback)
    withProbe(function(c)
        Log.setDeveloperMode(true)
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
        counters.scar = 2
        local line = c.probe.summaryLine(counters)
        assert(line == "summary external=0 scar=2 windows=0 hpChanges=0 hitsInWindow=0", line)
    end)
end

function T.installsHooksAndStaysSilentWhenDeveloperModeOff()
    withProbe(function(c)
        for _, signature in pairs(FLOW) do assert(c.hooks[signature], signature) end
        for _, signature in pairs(HOOKS) do assert(c.hooks[signature], signature) end
        for _, entry in pairs(c.hooks) do
            if entry.pre then entry.pre(raising()) end
            if entry.post then entry.post(raising()) end
        end
        c.probe.update()
        assert(#wbLines() == 0)
        for _, name in ipairs(c.probe.COUNTER_ORDER) do assert(c.probe.counters()[name] == 0, name) end
    end)
end

function T.questStartLogsWeaponAndResetsState()
    withDeveloperProbe(function(c)
        Game.masterHunter = function() return { get_WeaponType = function() return 3 end } end
        local target = enemy(7, 1000.0)
        c.hooks[HOOKS.detail].pre({ [3] = { get_DamageOwner = function() return target.owner end } })
        assert(c.probe.owner(7) == target.owner)
        c.probe.counters().scar = 5
        c.hooks[FLOW.playing].pre({})
        assert(c.probe.counters().scar == 0)
        assert(c.probe.owner(7) == nil)
        local lines = wbLines()
        assert(#lines == 1, #lines)
        assert(lines[1] == "[MyHuntReport] wb state weapon=3", lines[1])
    end)
    withDeveloperProbe(function(c)
        c.hooks[FLOW.playing].pre({})
        assert(wbLines()[1] == "[MyHuntReport] wb state weapon=?", wbLines()[1])
    end)
end

function T.questStartResetsCountersEvenWhenDeveloperModeOff()
    withProbe(function(c)
        c.probe.counters().scar = 5
        c.hooks[FLOW.playing].pre(raising())
        assert(c.probe.counters().scar == 0)
        assert(#wbLines() == 0)
    end)
end

function T.resultInfoPostPrintsSummary()
    withDeveloperProbe(function(c)
        c.probe.counters().external = 3
        c.hooks[FLOW.resultInfo].post(nil)
        local lines = wbLines()
        assert(#lines == 1, #lines)
        assert(lines[1] == "[MyHuntReport] wb summary external=3 scar=0 windows=0 hpChanges=0 hitsInWindow=0", lines[1])
    end)
end

function T.ownerCacheIgnoresUnreadableHits()
    withDeveloperProbe(function(c)
        c.hooks[HOOKS.detail].pre({})
        c.hooks[HOOKS.detail].pre({ [3] = raising() })
        c.hooks[HOOKS.detail].pre({ [3] = { get_DamageOwner = function() return nil end } })
        assert(#wbLines() == 0)
        local target = enemy(9, 500.0)
        c.hooks[HOOKS.detail].pre({ [3] = { get_DamageOwner = function() return target.owner end } })
        assert(c.probe.owner(9) == target.owner)
    end)
end

local function masterHunterWith(baseAction, subAction)
    return {
        get_WeaponType = function() return 3 end,
        get_GameObject = function() return { get_address = function() return 4096 end } end,
        call = function(_, getter)
            local action = getter == "get_BaseActionController" and baseAction or subAction
            return { get_CurrentAction = function() return action end }
        end,
    }
end

local function action(className, guideId)
    return {
        get_type_definition = function() return { get_name = function() return className end } end,
        _ActionGuideID = guideId,
    }
end

local function nullableKey(hasValue, category, uniqueIndex)
    return { _HasValue = hasValue, _Value = { Category = category, UniqueIndex = uniqueIndex } }
end

local function withKeyResolver(c)
    Game.callStatic = function(typeName, signature, key)
        if typeName == "app.TargetAccessKeyUtil" and signature == "getHunterCharacter(app.TARGET_ACCESS_KEY)" then
            if key.Category == 0 and key.UniqueIndex == 0 then
                return { get_GameObject = function() return { name = "MasterPlayer", get_address = function() return 4096 end } end }
            end
            if key.Category == 0 then
                return { get_GameObject = function() return { name = "Player_Replica_" .. key.UniqueIndex, get_address = function() return 8192 end } end }
            end
        end
        return nil
    end
end

local function primed(c, index, health)
    local target = enemy(index, health)
    c.hooks[HOOKS.detail].pre({ [3] = { get_DamageOwner = function() return target.owner end } })
    return target
end

function T.int32ArgDecodesMaskedNegatives()
    withProbe(function(c)
        assert(c.probe.int32(12) == 12)
        assert(c.probe.int32(0xFFFFFFFF) == -1)
        assert(c.probe.int32(0x1FFFFFFFF) == -1)
        assert(c.probe.int32(nil) == nil)
    end)
end

function T.externalPreLogsLineOpensWatchAndPostLogsHp()
    withDeveloperProbe(function(c)
        withKeyResolver(c)
        Game.masterHunter = function() return masterHunterWith(action("cFocusStrike", 9328), nil) end
        local target = primed(c, 7, 1000.0)
        c.now = 12.25
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 142.5, [5] = nullableKey(true, 0, 0) })
        local lines = wbLines()
        assert(lines[1] == "[MyHuntReport] wb external t=12.25 em=7 value=142.5 hasKey=true key=0/0 master=true hp=1000.0/1000.0 base=cFocusStrike/9328 sub=nil", lines[1])
        local watch = c.probe.watch(7)
        assert(watch and watch.label == "external:142.5" and watch.startedAt == 12.25 and watch.openHealth == 1000.0 and watch.lastHealth == 1000.0, stubs.encode(watch))
        assert(c.probe.counters().external == 1 and c.probe.counters().windows == 1)
        target.state.health = 857.5
        c.hooks[HOOKS.external].post(nil)
        assert(wbLines()[2] == "[MyHuntReport] wb external-post em=7 hp=857.5", wbLines()[2])
        assert(c.hooks.storage.wb == nil)
    end)
end

function T.externalPostIsSilentWithoutPreMark()
    withDeveloperProbe(function(c)
        c.hooks[HOOKS.external].post(nil)
        c.hooks[HOOKS.scar].post(nil)
        assert(#wbLines() == 0)
    end)
    withProbe(function(c)
        local target = primed(c, 7, 1000.0)
        Log.setDeveloperMode(true)
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 30.0, [5] = nullableKey(false, 0, 0) })
        Log.setDeveloperMode(false)
        c.hooks[HOOKS.external].post(nil)
        assert(#wbLines() == 1, #wbLines())
        assert(c.hooks.storage.wb == nil)
    end)
end

function T.externalPrePrintsQuestionMarksForUnreadableFields()
    withDeveloperProbe(function(c)
        c.now = 1.0
        c.hooks[HOOKS.external].pre({ [2] = raising(), [3] = raising(), [5] = raising() })
        assert(wbLines()[1] == "[MyHuntReport] wb external t=1.00 em=nil value=? hasKey=? key=?/? master=? hp=nil/nil base=nil/nil sub=nil", wbLines()[1])
        assert(c.probe.counters().external == 1 and c.probe.counters().windows == 0)
        sdk.to_valuetype = function() error("decode") end
        c.hooks[HOOKS.external].pre({ [3] = 1.0, [5] = {} })
        assert(wbLines()[2] == "[MyHuntReport] wb external t=1.00 em=nil value=1.0 hasKey=? key=? master=? hp=nil/nil base=nil/nil sub=nil", wbLines()[2])
    end)
end

function T.masterResolutionCoversReplicaMissingKeyAndNonHunter()
    withDeveloperProbe(function(c)
        withKeyResolver(c)
        Game.masterHunter = function() return masterHunterWith(nil, nil) end
        local target = primed(c, 7, 1000.0)
        c.now = 2.0
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 10.0, [5] = nullableKey(true, 0, 2) })
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 10.0, [5] = nullableKey(false, 0, 0) })
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 10.0, [5] = nullableKey(true, 2, 0) })
        local lines = wbLines()
        assert(lines[1]:find(" hasKey=true key=0/2 master=false ", 1, true), lines[1])
        assert(lines[2]:find(" hasKey=false key=0/0 master=? ", 1, true), lines[2])
        assert(lines[3]:find(" hasKey=true key=2/0 master=false ", 1, true), lines[3])
        Game.callStatic = function() return nil end
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 10.0, [5] = nullableKey(true, 0, 0) })
        assert(wbLines()[4]:find(" master=? ", 1, true), wbLines()[4])
        withKeyResolver(c)
        Game.masterHunter = function() return nil end
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 10.0, [5] = nullableKey(true, 0, 0) })
        assert(wbLines()[5]:find(" master=? ", 1, true), wbLines()[5])
    end)
end

function T.scarPreLogsScarStateAndPostLogsStateAndHp()
    withDeveloperProbe(function(c)
        withKeyResolver(c)
        Game.masterHunter = function() return masterHunterWith(action("cFocusStrike", 9328), action("cSubAction", 1)) end
        local target = primed(c, 7, 1000.0)
        target.state.scarStates[12] = 1
        c.now = 20.0
        c.hooks[HOOKS.scar].pre({ [2] = target.stock, [3] = 12, [4] = 475.0, [7] = nullableKey(true, 0, 0) })
        local lines = wbLines()
        assert(lines[1] == "[MyHuntReport] wb scar t=20.00 em=7 scar=12 value=475.0 hasKey=true key=0/0 master=true state=1 hp=1000.0/1000.0 base=cFocusStrike/9328 sub=cSubAction", lines[1])
        local watch = c.probe.watch(7)
        assert(watch and watch.label == "scar:475.0", stubs.encode(watch))
        assert(c.probe.counters().scar == 1 and c.probe.counters().windows == 1)
        target.state.scarStates[12] = 2
        target.state.health = 525.0
        c.hooks[HOOKS.scar].post(nil)
        assert(wbLines()[2] == "[MyHuntReport] wb scar-post em=7 scar=12 state=2 hp=525.0", wbLines()[2])
        assert(c.hooks.storage.wb == nil)
    end)
    withDeveloperProbe(function(c)
        c.now = 3.0
        c.hooks[HOOKS.scar].pre({ [2] = raising(), [3] = raising(), [4] = raising(), [7] = raising() })
        assert(wbLines()[1] == "[MyHuntReport] wb scar t=3.00 em=nil scar=? value=? hasKey=? key=?/? master=? state=? hp=nil/nil base=nil/nil sub=nil", wbLines()[1])
        c.hooks[HOOKS.scar].post(nil)
        assert(wbLines()[2] == "[MyHuntReport] wb scar-post em=nil scar=? state=? hp=nil", wbLines()[2])
    end)
end

function T.secondCallOnSameEnemyReplacesTheWatch()
    withDeveloperProbe(function(c)
        local target = primed(c, 7, 1000.0)
        c.now = 5.0
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 142.5, [5] = nullableKey(false, 0, 0) })
        c.hooks[HOOKS.external].post(nil)
        target.state.health = 900.0
        c.now = 5.2
        c.hooks[HOOKS.scar].pre({ [2] = target.stock, [3] = 12, [4] = 475.0, [7] = nullableKey(false, 0, 0) })
        c.hooks[HOOKS.scar].post(nil)
        local watch = c.probe.watch(7)
        assert(watch.label == "scar:475.0" and watch.startedAt == 5.2 and watch.openHealth == 900.0, stubs.encode(watch))
        assert(c.probe.counters().windows == 2)
    end)
end

function T.healthReadsAreIndependent()
    withDeveloperProbe(function(c)
        local target = enemy(7, 1000.0)
        target.owner.character.get_HealthMgr = function()
            return {
                get_Health = function() return 1000.0 end,
                get_MaxHealth = function() error("unreadable max health") end,
            }
        end
        c.hooks[HOOKS.detail].pre({ [3] = { get_DamageOwner = function() return target.owner end } })
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 10.0, [5] = nullableKey(false, 0, 0) })
        assert(wbLines()[1]:find(" hp=1000.0/nil ", 1, true), wbLines()[1])
    end)
end

local function openExternal(c, target, value, now)
    c.now = now
    c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = value, [5] = nullableKey(false, 0, 0) })
    c.hooks[HOOKS.external].post(nil)
end

function T.updateLogsHpChangesAndClosesTheWindowWithTheDrop()
    withDeveloperProbe(function(c)
        local target = primed(c, 7, 1000.0)
        openExternal(c, target, 142.5, 10.0)
        c.now = 10.016
        c.probe.update()
        assert(#wbLines() == 2, #wbLines())
        target.state.health = 857.5
        c.now = 10.05
        c.probe.update()
        assert(wbLines()[3] == "[MyHuntReport] wb hp t=10.05 em=7 after=external:142.5 dt=0.050 hp=857.5 delta=142.5", wbLines()[3])
        target.state.health = 382.5
        c.now = 10.4
        c.probe.update()
        assert(wbLines()[4] == "[MyHuntReport] wb hp t=10.40 em=7 after=external:142.5 dt=0.400 hp=382.5 delta=475.0", wbLines()[4])
        c.now = 10.99
        c.probe.update()
        assert(#wbLines() == 4 and c.probe.watch(7) ~= nil)
        c.now = 11.0
        c.probe.update()
        assert(wbLines()[5] == "[MyHuntReport] wb watch-end em=7 after=external:142.5 dt=1.000 drop=617.5", wbLines()[5])
        assert(c.probe.watch(7) == nil)
        local counters = c.probe.counters()
        assert(counters.hpChanges == 2 and counters.windows == 1, stubs.encode(counters))
    end)
end

function T.updateHandlesUnreadableHealth()
    withDeveloperProbe(function(c)
        local target = enemy(7, 1000.0)
        c.now = 1.0
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 30.0, [5] = nullableKey(false, 0, 0) })
        c.hooks[HOOKS.external].post(nil)
        assert(c.probe.watch(7).openHealth == nil)
        c.now = 1.5
        c.probe.update()
        assert(#wbLines() == 2, #wbLines())
        c.now = 2.0
        c.probe.update()
        assert(wbLines()[3] == "[MyHuntReport] wb watch-end em=7 after=external:30.0 dt=1.000 drop=nil", wbLines()[3])
        assert(c.probe.counters().hpChanges == 0)
    end)
end

function T.updateStaysSilentWhenDeveloperModeOff()
    withDeveloperProbe(function(c)
        local target = primed(c, 7, 1000.0)
        openExternal(c, target, 142.5, 10.0)
        Log.setDeveloperMode(false)
        target.state.health = 0.0
        c.now = 12.0
        c.probe.update()
        assert(#wbLines() == 2, #wbLines())
        assert(c.probe.watch(7) == nil)
        Log.setDeveloperMode(true)
        c.now = 12.1
        c.probe.update()
        assert(#wbLines() == 2, #wbLines())
        assert(c.probe.counters().hpChanges == 0)
    end)
end

function T.hitInsideWindowLogsFinalAndHp()
    withDeveloperProbe(function(c)
        local target = primed(c, 7, 1000.0)
        local other = primed(c, 8, 800.0)
        openExternal(c, target, 142.5, 10.0)
        c.now = 10.1
        target.state.health = 950.0
        c.hooks[HOOKS.hitMark].pre({ [3] = { FinalDamage = 50.0 }, [4] = { get_DamageOwner = function() return target.owner end } })
        assert(wbLines()[3] == "[MyHuntReport] wb hit t=10.10 em=7 final=50.0 hp=950.0", wbLines()[3])
        c.hooks[HOOKS.hitMark].pre({ [3] = raising(), [4] = { get_DamageOwner = function() return other.owner end } })
        assert(#wbLines() == 3, #wbLines())
        c.hooks[HOOKS.hitMark].pre({ [3] = raising(), [4] = { get_DamageOwner = function() return target.owner end } })
        assert(wbLines()[4] == "[MyHuntReport] wb hit t=10.10 em=7 final=? hp=950.0", wbLines()[4])
        assert(c.probe.counters().hitsInWindow == 2)
    end)
end

function T.hitOutsideAnyWindowReadsNothing()
    withDeveloperProbe(function(c)
        c.hooks[HOOKS.hitMark].pre(raising())
        assert(#wbLines() == 0 and c.probe.counters().hitsInWindow == 0)
    end)
end

function T.hitAfterDeadlineBeforeNextUpdateIsStillCounted()
    withDeveloperProbe(function(c)
        local target = primed(c, 7, 1000.0)
        openExternal(c, target, 142.5, 10.0)
        target.state.health = 900.0
        c.now = 11.05
        c.hooks[HOOKS.hitMark].pre({ [3] = { FinalDamage = 100.0 }, [4] = { get_DamageOwner = function() return target.owner end } })
        assert(wbLines()[3] == "[MyHuntReport] wb hit t=11.05 em=7 final=100.0 hp=900.0", wbLines()[3])
        assert(c.probe.counters().hitsInWindow == 1)
        c.probe.update()
        assert(wbLines()[4] == "[MyHuntReport] wb hp t=11.05 em=7 after=external:142.5 dt=1.050 hp=900.0 delta=100.0", wbLines()[4])
        assert(wbLines()[5] == "[MyHuntReport] wb watch-end em=7 after=external:142.5 dt=1.050 drop=100.0", wbLines()[5])
        assert(c.probe.watch(7) == nil)
    end)
end

function T.updateHandlesThrowingHealthGetter()
    withDeveloperProbe(function(c)
        local target = primed(c, 7, 1000.0)
        target.owner.character.get_HealthMgr = function()
            return {
                get_Health = function() error("unreadable health") end,
                get_MaxHealth = function() return 1000.0 end,
            }
        end
        c.now = 1.0
        c.hooks[HOOKS.external].pre({ [2] = target.stock, [3] = 30.0, [5] = nullableKey(false, 0, 0) })
        c.hooks[HOOKS.external].post(nil)
        assert(wbLines()[1]:find(" hp=nil/1000.0 ", 1, true), wbLines()[1])
        assert(c.probe.watch(7).openHealth == nil)
        c.now = 1.5
        c.probe.update()
        assert(#wbLines() == 2, #wbLines())
        c.now = 2.0
        c.probe.update()
        assert(#wbLines() == 3, #wbLines())
        assert(wbLines()[3] == "[MyHuntReport] wb watch-end em=7 after=external:30.0 dt=1.000 drop=nil", wbLines()[3])
        assert(c.probe.counters().hpChanges == 0)
    end)
end

return T
