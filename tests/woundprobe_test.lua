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

return T
