local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Session = require("MyHuntReport.Session")
local Palico = require("MyHuntReport.Palico")

local T = {}

local HOOKS = {
    detail = "app.cEnemyStockDamage.stockDamageDetail(app.HitInfo)",
    hitMark = "app.cEnemyStockDamage.mcEnemyHitMarkManager.playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)",
}

local function gameObject(name, address, mine)
    local object = {
        get_Name = function() return name end,
        get_address = function() return address end,
    }
    if mine ~= nil then
        object.otomo = { get_IsMasterMyOtomo = function() return mine end }
    end
    return object
end

local function enemy(isBoss, dead)
    return { dead = dead == true, em = { get_IsBoss = function() return isBoss end } }
end

local function hitInfo(address, attacker, target, attackObjName)
    return {
        get_address = function() return address end,
        getActualAttackOwner = function() return attacker end,
        get_DamageOwner = function() return target end,
        get_AttackObj = function() return { get_Name = function() return attackObjName end } end,
    }
end

local function palicoLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] palico ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function withPalico(callback)
    local hook, componentOf, enemyContext, enemyIsDead, callStatic =
        Game.hook, Game.componentOf, Game.enemyContext, Game.enemyIsDead, Game.callStatic
    local toManaged = sdk.to_managed_object
    local developerMode = Log.isDeveloperMode()
    local c = { characters = {}, resolved = {} }
    local ok, err = pcall(function()
        Log.setDeveloperMode(false)
        Log.resetCounts()
        stubs.reset()
        Session.reset(0)
        Palico.reset()
        Game.componentOf = function(object, typeName)
            if object and typeName == "app.OtomoCharacter" then return object.otomo end
            return nil
        end
        Game.enemyContext = function(object) return object and object.em or nil end
        Game.enemyIsDead = function(object) return object.dead == true end
        Game.callStatic = function(typeName, signature, key)
            assert(typeName == "app.TargetAccessKeyUtil" and signature == "getCharacter(app.TARGET_ACCESS_KEY)")
            c.resolved[#c.resolved + 1] = key
            local found = c.characters[key]
            if not found then return nil end
            return { get_GameObject = function() return found end }
        end
        sdk.to_managed_object = function(value) return value end
        function c.hit(info, final)
            Palico.handleStockDamageDetail(info)
            Palico.handleHitMark({ FinalDamage = final }, info)
        end
        callback(c)
    end)
    Game.hook, Game.componentOf, Game.enemyContext, Game.enemyIsDead, Game.callStatic =
        hook, componentOf, enemyContext, enemyIsDead, callStatic
    sdk.to_managed_object = toManaged
    Log.setDeveloperMode(developerMode)
    Log.resetCounts()
    Session.reset(0)
    Palico.reset()
    if not ok then error(err, 0) end
end

function T.isOwnObjectRequiresAnExactTrueFromTheOwnershipGetter()
    withPalico(function()
        local mine, otomo = Palico.isOwnObject(gameObject("Otomo_00", 1, true))
        assert(mine == true and otomo ~= nil)
        mine, otomo = Palico.isOwnObject(gameObject("Otomo_46", 2, false))
        assert(mine == false and otomo ~= nil)
        mine, otomo = Palico.isOwnObject(gameObject("MasterPlayer", 3))
        assert(mine == false and otomo == nil)
        mine, otomo = Palico.isOwnObject(nil)
        assert(mine == false and otomo == nil)
        for _, value in ipairs({ "nil", 1, "true" }) do
            local object = gameObject("Otomo_00", 4, true)
            object.otomo.get_IsMasterMyOtomo = function()
                if value == "nil" then return nil end
                return value
            end
            assert(Palico.isOwnObject(object) == false, tostring(value))
        end
        local raising = gameObject("Otomo_00", 5, true)
        raising.otomo.get_IsMasterMyOtomo = function() error("no getter") end
        mine, otomo = Palico.isOwnObject(raising)
        assert(mine == false and otomo ~= nil)
    end)
end

function T.isOwnKeyResolvesOnlyOtomoKeysToTheOwnPalico()
    withPalico(function(c)
        local ownKey, otherKey, lostKey = { Category = 2, UniqueIndex = 0 }, { Category = 2, UniqueIndex = 1 }, { Category = 2, UniqueIndex = 9 }
        c.characters[ownKey] = gameObject("Otomo_00", 1, true)
        c.characters[otherKey] = gameObject("Otomo_46", 2, false)
        assert(Palico.isOwnKey(ownKey) == true)
        assert(Palico.isOwnKey(otherKey) == false)
        assert(Palico.isOwnKey(lostKey) == false)
        assert(#c.resolved == 3)
        for _, key in ipairs({ { Category = 0, UniqueIndex = 0 }, { Category = 4, UniqueIndex = 0 }, { UniqueIndex = 0 }, {} }) do
            assert(Palico.isOwnKey(key) == false)
        end
        assert(Palico.isOwnKey(nil) == false)
        assert(#c.resolved == 3, "only category 2 keys reach the resolver")
        local broken = { Category = 2, UniqueIndex = 3 }
        c.characters[broken] = setmetatable({}, { __index = function() error("no object") end })
        Game.callStatic = function() return { get_GameObject = function() error("no object") end } end
        assert(Palico.isOwnKey(broken) == false)
    end)
end

function T.ownPalicoHitsOnALivingBossAreCounted()
    withPalico(function(c)
        local mine = gameObject("Otomo_00", 1, true)
        c.hit(hitInfo(100, mine, enemy(true), "Otomo_00"), 32.4)
        c.hit(hitInfo(101, mine, enemy(true), "Sh200_007"), 30.9)
        local totals = Session.palicoTotals()
        assert(totals.hits == 2 and math.abs(totals.direct - 63.3) < 1e-9)
        assert(Session.hitCount() == 0 and Session.hasData() == false)
    end)
end

function T.everythingElseIsNotCounted()
    withPalico(function(c)
        local mine = gameObject("Otomo_00", 1, true)
        local other = gameObject("Otomo_46", 2, false)
        local master = gameObject("MasterPlayer", 3)
        c.hit(hitInfo(100, other, enemy(true), "Otomo_46"), 24.9)
        c.hit(hitInfo(101, master, enemy(true), "Wp07Shell"), 150)
        c.hit(hitInfo(102, mine, enemy(false), "Otomo_00"), 20)
        c.hit(hitInfo(103, mine, enemy(true, true), "Otomo_00"), 20)
        c.hit(hitInfo(104, mine, enemy(true), "Sh200_004"), 0)
        c.hit(hitInfo(105, mine, enemy(true), "Otomo_00"), "broken")
        c.hit(hitInfo(106, mine, { em = { get_IsBoss = function() error("no boss flag") end } }, "Otomo_00"), 20)
        c.hit(hitInfo(107, mine, nil, "Otomo_00"), 20)
        c.hit(hitInfo(nil, mine, enemy(true), "Otomo_00"), 20)
        Palico.handleStockDamageDetail(nil)
        Palico.handleHitMark({ FinalDamage = 20 }, nil)
        Palico.handleHitMark({ FinalDamage = 20 }, hitInfo(108, mine, enemy(true), "Otomo_00"))
        local raising = hitInfo(109, mine, enemy(true), "Otomo_00")
        raising.getActualAttackOwner = function() error("no owner") end
        c.hit(raising, 20)
        local totals = Session.palicoTotals()
        assert(totals.hits == 0 and totals.direct == 0)
    end)
end

function T.aMarkIsCountedOncePerDetailCall()
    withPalico(function()
        local mine = gameObject("Otomo_00", 1, true)
        local info = hitInfo(100, mine, enemy(true), "Otomo_00")
        Palico.handleStockDamageDetail(info)
        Palico.handleHitMark({ FinalDamage = 10 }, info)
        Palico.handleHitMark({ FinalDamage = 10 }, info)
        assert(Session.palicoTotals().hits == 1)
        Palico.handleStockDamageDetail(info)
        Palico.reset()
        Palico.handleHitMark({ FinalDamage = 10 }, info)
        assert(Session.palicoTotals().hits == 1)
    end)
end

function T.aReusedHitInfoAddressNeverCarriesAnEarlierOwnership()
    withPalico(function()
        local mine = gameObject("Otomo_00", 1, true)
        local other = gameObject("Otomo_46", 2, false)
        local rejected = {
            hitInfo(100, other, enemy(true), "Otomo_46"),
            hitInfo(100, gameObject("MasterPlayer", 3), enemy(true), "Wp07Shell"),
            hitInfo(100, mine, enemy(false), "Otomo_00"),
            hitInfo(100, mine, enemy(true, true), "Otomo_00"),
            hitInfo(100, mine, enemy(true), "Otomo_00"),
        }
        rejected[5].getActualAttackOwner = function() error("no owner") end
        for _, info in ipairs(rejected) do
            Palico.handleStockDamageDetail(hitInfo(100, mine, enemy(true), "Otomo_00"))
            Palico.handleStockDamageDetail(info)
            Palico.handleHitMark({ FinalDamage = 25 }, info)
        end
        local totals = Session.palicoTotals()
        assert(totals.hits == 0 and totals.direct == 0)
    end)
end

function T.diagnosticsAppearOnlyInDeveloperMode()
    withPalico(function(c)
        local mine = gameObject("Otomo_00", 1, true)
        local other = gameObject("Otomo_46", 2, false)
        c.hit(hitInfo(100, mine, enemy(true), "Otomo_00"), 32.4)
        Palico.logSummary(Session.snapshot())
        assert(#palicoLines() == 0)
        Log.setDeveloperMode(true)
        c.hit(hitInfo(101, mine, enemy(true), "Sh200_007"), 30.9)
        c.hit(hitInfo(102, other, enemy(true), "Otomo_46"), 24.9)
        c.hit(hitInfo(103, other, enemy(true), "Otomo_46"), 24.9)
        c.hit(hitInfo(104, mine, enemy(true), "Otomo_00"), 13.5)
        local lines = palicoLines()
        assert(#lines == 4, #lines)
        assert(lines[1] == "[MyHuntReport] palico seen name=Otomo_00 mine=true", lines[1])
        assert(lines[2] == "[MyHuntReport] palico hit #2 dmg=30.9 obj=Sh200_007 total=63.3", lines[2])
        assert(lines[3] == "[MyHuntReport] palico seen name=Otomo_46 mine=false", lines[3])
        assert(lines[4] == "[MyHuntReport] palico hit #3 dmg=13.5 obj=Otomo_00 total=76.8", lines[4])
        Palico.reset()
        stubs.logLines = {}
        c.hit(hitInfo(105, other, enemy(true), "Otomo_46"), 24.9)
        assert(palicoLines()[1] == "[MyHuntReport] palico seen name=Otomo_46 mine=false")
    end)
end

function T.summaryLineReportsTheSnapshotPalicoBlock()
    withPalico(function(c)
        Log.setDeveloperMode(true)
        Palico.logSummary(Session.snapshot())
        assert(palicoLines()[1] == "[MyHuntReport] palico summary hits=0 direct=0.0 blast=0.0 poison=0.0 own=0.0 share=0.0000", palicoLines()[1])
        stubs.logLines = {}
        Palico.logSummary({
            damage = { total = 900 },
            palico = { hits = 3, direct = 60, blast = 25, poison = 15, damage = 100, share = 0.1 },
        })
        assert(palicoLines()[1] == "[MyHuntReport] palico summary hits=3 direct=60.0 blast=25.0 poison=15.0 own=900.0 share=0.1000", palicoLines()[1])
        stubs.logLines = {}
        Palico.logSummary(nil)
        assert(palicoLines()[1]:find("hits=0 direct=0.0", 1, true))
    end)
end

function T.installHooksTheDetailAndHitMarkMethodsOnce()
    withPalico(function()
        local hooks, count = {}, 0
        Game.hook = function(typeName, signature, pre, post)
            count = count + 1
            hooks[typeName .. "." .. signature] = { pre = pre, post = post }
            return true
        end
        local module = assert(loadfile("reframework/autorun/MyHuntReport/Palico.lua"))()
        module.install()
        module.install()
        assert(count == 2 and hooks[HOOKS.detail].pre and hooks[HOOKS.hitMark].pre)
        assert(hooks[HOOKS.detail].post == nil and hooks[HOOKS.hitMark].post == nil)
        local mine = gameObject("Otomo_00", 1, true)
        local info = hitInfo(100, mine, enemy(true), "Otomo_00")
        local untouched = setmetatable({}, { __index = function() error("read without a pending hit") end })
        hooks[HOOKS.hitMark].pre(untouched)
        hooks[HOOKS.detail].pre({ nil, nil, info })
        hooks[HOOKS.hitMark].pre({ nil, nil, { FinalDamage = 21.5 }, info })
        assert(Session.palicoTotals().hits == 1 and Session.palicoTotals().direct == 21.5)
    end)
end

return T
