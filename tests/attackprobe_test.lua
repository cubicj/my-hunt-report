local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local ON_HIT = "app.cHunterAttackPower.calcOnHitAttackPower(app.HitInfo, System.Single, app.HunterCharacter, System.Boolean, System.Boolean, System.Boolean)"
local HIT_INFO = "app.cEnemyStockDamage.stockDamageDetail(app.HitInfo)"
local CALC = "app.cEnemyStockDamage.calcStockDamage(app.cEnemyStockDamage.cCalcDamage, app.cEnemyStockDamage.cPreCalcDamage, app.cEnemyStockDamage.cDamageRate, System.Boolean)"

local function atkLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] atk ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

local function withProbe(callback)
    local hook, masterHunter, isMasterGameObject, uptime = Game.hook, Game.masterHunter, Game.isMasterGameObject, Game.uptime
    local originalSdk = sdk
    local c = { hooks = {}, names = {}, now = 100.0, reads = 0, lookups = 0, conversions = 0, values = {}, masterObject = { name = "MasterPlayer" } }
    c.power = {
        call = function(self, signature)
            c.reads = c.reads + 1
            local value = c.values[signature]
            if value == "error" then error("boom") end
            return value
        end,
    }
    c.master = {
        get_address = function() return 0x1000 end,
        get_HunterStatus = function() return { get_AttackPower = function() return c.power end } end,
    }
    c.other = { get_address = function() return 0x2000 end }
    local ok, err = pcall(function()
        stubs.reset()
        Log.setDeveloperMode(true)
        Log.resetCounts()
        Game.hook = function(typeName, signature, pre, post)
            local label = typeName .. "." .. signature
            c.names[#c.names + 1] = label
            c.hooks[label] = { pre = pre, post = post }
            return true
        end
        Game.masterHunter = function()
            c.lookups = c.lookups + 1
            return c.master
        end
        Game.isMasterGameObject = function(object)
            c.lookups = c.lookups + 1
            return object == c.masterObject
        end
        Game.uptime = function() return c.now end
        sdk = setmetatable({
            to_managed_object = function(value)
                c.conversions = c.conversions + 1
                return value
            end,
            to_float = function(value)
                c.conversions = c.conversions + 1
                return value
            end,
            to_int64 = function(value)
                c.conversions = c.conversions + 1
                return value
            end,
            to_valuetype = function(pointer)
                c.conversions = c.conversions + 1
                return { get_field = function() return pointer end }
            end,
        }, { __index = originalSdk })
        c.probe = assert(loadfile("reframework/autorun/MyHuntReport/AttackProbe.lua"))()
        callback(c)
    end)
    Game.hook, Game.masterHunter, Game.isMasterGameObject, Game.uptime = hook, masterHunter, isMasterGameObject, uptime
    sdk = originalSdk
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

local function setPower(c, weapon, current, add, rate, timer)
    c.values["get_WeaponAttackPower()"] = weapon
    c.values["get_CurrentAttackPower()"] = current
    c.values["get_CurrentAttackAdd()"] = add
    c.values["get_CurrentAttackRate()"] = rate
    c.values["get_AttackUpTimer()"] = timer
end

local function hitInfo(owner, attackData)
    return {
        getActualAttackOwner = function() return owner end,
        get_AttackData = function() return attackData end,
    }
end

local function onHit(c, hunter, base, ret, b1, b2, b3)
    c.hooks[ON_HIT].pre({ nil, c.power, {}, base, hunter, b1, b2, b3 })
    c.hooks[ON_HIT].post(ret)
end

local function hit(c, owner, attackData, preCalc)
    c.hooks[HIT_INFO].pre({ nil, {}, hitInfo(owner, attackData) })
    c.hooks[CALC].pre({ nil, {}, {}, preCalc, {} })
end

function T.installRegistersTheThreeHooksOnce()
    withProbe(function(c)
        c.probe.install()
        c.probe.install()
        assert(#c.names == 3, #c.names)
        assert(c.names[1] == ON_HIT and c.names[2] == HIT_INFO and c.names[3] == CALC, table.concat(c.names, " | "))
        assert(c.hooks[ON_HIT].pre ~= nil and c.hooks[ON_HIT].post ~= nil)
        assert(c.hooks[HIT_INFO].pre ~= nil and c.hooks[HIT_INFO].post == nil)
        assert(c.hooks[CALC].pre ~= nil and c.hooks[CALC].post == nil)
    end)
end

function T.updateLogsOneLinePerChangedFieldAndNothingWhenUnchanged()
    withProbe(function(c)
        setPower(c, 220.0, 235.0, 15.0, 1.0, 0.0)
        c.probe.update()
        local first = atkLines()
        assert(#first == 4, #first)
        assert(first[1]:find("atk change weapon nil -> 220.0 at 100.0", 1, true), first[1])
        assert(first[2]:find("atk change current nil -> 235.0 at 100.0", 1, true), first[2])
        assert(first[3]:find("atk change add nil -> 15.0 at 100.0", 1, true), first[3])
        assert(first[4]:find("atk change rate nil -> 1.0 at 100.0", 1, true), first[4])
        c.probe.update()
        assert(#atkLines() == 4)
        c.now = 101.0
        c.values["get_CurrentAttackPower()"] = 245.0
        c.values["get_AttackUpTimer()"] = 59.0
        c.probe.update()
        local lines = atkLines()
        assert(#lines == 5, #lines)
        assert(lines[5]:find("atk change current 235.0 -> 245.0 at 101.0", 1, true), lines[5])
    end)
end

function T.updateLogsANanReadingOnceAndAFailedReadAsQuestionMark()
    withProbe(function(c)
        setPower(c, 220.0, 235.0, 15.0, 1.0, 0.0)
        c.probe.update()
        c.values["get_CurrentAttackRate()"] = 0 / 0
        c.values["get_CurrentAttackAdd()"] = "error"
        c.probe.update()
        c.probe.update()
        c.probe.update()
        local lines = atkLines()
        assert(#lines == 6, #lines)
        assert(lines[5]:find("atk change add 15.0 -> ? at 100.0", 1, true), lines[5])
        assert(lines[6]:find("atk change rate 1.0 -> ", 1, true), lines[6])
    end)
end

function T.updatePrintsQuestionMarksWithoutAMasterHunter()
    withProbe(function(c)
        c.master = nil
        c.probe.update()
        local lines = atkLines()
        assert(#lines == 4, #lines)
        assert(lines[1]:find("atk change weapon nil -> ? at 100.0", 1, true), lines[1])
        assert(c.reads == 0, c.reads)
    end)
end

function T.masterHitLogsOneLineWithTheOnHitValues()
    withProbe(function(c)
        c.probe.install()
        setPower(c, 220.0, 235.0, 15.0, 1.0, 42.5)
        c.now = 250.25
        onHit(c, c.master, 235.0, 247.5, 1, 0, 1)
        hit(c, c.masterObject, { _OriginalAttackAdjust = 30.0, _CriticaType = 1, _IsNoCritical = false },
            { Attack = 92.8, FixAttack = 0.0, AbsoluteAttack = 0.0, ActionType = 1 })
        local lines = atkLines()
        assert(#lines == 1, #lines)
        assert(lines[1]:find("atk hit at 250.25 mv=30.0 crit=1 nocrit=false action=1 preAttack=92.8 fix=0.0 abs=0.0 "
            .. "weapon=220.0 current=235.0 add=15.0 rate=1.0 upTimer=42.5 onhit=247.5 onhitBase=235.0 onhitFlags=TFT onhitCalls=1", 1, true), lines[1])
    end)
end

function T.hitWithoutAnOnHitCallPrintsNilOnHitValues()
    withProbe(function(c)
        c.probe.install()
        setPower(c, 220.0, 235.0, 15.0, 1.0, 0.0)
        hit(c, c.masterObject, { _OriginalAttackAdjust = 30.0, _CriticaType = 0, _IsNoCritical = true },
            { Attack = 70.5, FixAttack = 0.0, AbsoluteAttack = 0.0, ActionType = 2 })
        local lines = atkLines()
        assert(#lines == 1, #lines)
        assert(lines[1]:find("crit=0 nocrit=true action=2 preAttack=70.5", 1, true), lines[1])
        assert(lines[1]:find("onhit=nil onhitBase=nil onhitFlags=nil onhitCalls=0", 1, true), lines[1])
    end)
end

function T.onHitCallsAreCountedAndResetByTheHitLine()
    withProbe(function(c)
        c.probe.install()
        setPower(c, 220.0, 235.0, 15.0, 1.0, 0.0)
        onHit(c, c.master, 235.0, 240.0, 0, 0, 0)
        onHit(c, c.master, 235.0, 247.5, 1, 1, 0)
        onHit(c, c.other, 300.0, 999.0, 1, 1, 1)
        local attackData = { _OriginalAttackAdjust = 30.0, _CriticaType = 0, _IsNoCritical = false }
        local preCalc = { Attack = 70.5, FixAttack = 0.0, AbsoluteAttack = 0.0, ActionType = 1 }
        hit(c, c.masterObject, attackData, preCalc)
        hit(c, c.masterObject, attackData, preCalc)
        local lines = atkLines()
        assert(#lines == 2, #lines)
        assert(lines[1]:find("onhit=247.5 onhitBase=235.0 onhitFlags=TTF onhitCalls=2", 1, true), lines[1])
        assert(lines[2]:find("onhit=nil onhitBase=nil onhitFlags=nil onhitCalls=0", 1, true), lines[2])
    end)
end

function T.nonMasterHitsAndHitsWithoutAttackDataProduceNoLine()
    withProbe(function(c)
        c.probe.install()
        setPower(c, 220.0, 235.0, 15.0, 1.0, 0.0)
        local preCalc = { Attack = 70.5, FixAttack = 0.0, AbsoluteAttack = 0.0, ActionType = 1 }
        hit(c, { name = "Otomo_00" }, { _OriginalAttackAdjust = 10.0, _CriticaType = 0, _IsNoCritical = false }, preCalc)
        hit(c, c.masterObject, nil, preCalc)
        c.hooks[CALC].pre({ nil, {}, {}, preCalc, {} })
        assert(#atkLines() == 0, #atkLines())
    end)
end

function T.aNonMasterHitClearsAnEarlierPendingMasterHit()
    withProbe(function(c)
        c.probe.install()
        setPower(c, 220.0, 235.0, 15.0, 1.0, 0.0)
        local attackData = { _OriginalAttackAdjust = 30.0, _CriticaType = 0, _IsNoCritical = false }
        c.hooks[HIT_INFO].pre({ nil, {}, hitInfo(c.masterObject, attackData) })
        c.hooks[HIT_INFO].pre({ nil, {}, hitInfo({ name = "Otomo_00" }, attackData) })
        c.hooks[CALC].pre({ nil, {}, {}, { Attack = 5.0 }, {} })
        assert(#atkLines() == 0, #atkLines())
    end)
end

function T.failedFieldReadsPrintQuestionMarks()
    withProbe(function(c)
        c.probe.install()
        setPower(c, 220.0, "error", 15.0, 1.0, "error")
        local failing = setmetatable({}, { __index = function() error("boom") end })
        hit(c, c.masterObject, failing, failing)
        local lines = atkLines()
        assert(#lines == 1, #lines)
        assert(lines[1]:find("mv=? crit=? nocrit=? action=? preAttack=? fix=? abs=? weapon=220.0 current=? add=15.0 rate=1.0 upTimer=?", 1, true), lines[1])
    end)
end

function T.everythingIsSilentAndReadsNothingWithDeveloperModeOff()
    withProbe(function(c)
        c.probe.install()
        Log.setDeveloperMode(false)
        setPower(c, 220.0, 235.0, 15.0, 1.0, 0.0)
        c.probe.update()
        onHit(c, c.master, 235.0, 247.5, 1, 0, 1)
        hit(c, c.masterObject, { _OriginalAttackAdjust = 30.0, _CriticaType = 0, _IsNoCritical = false },
            { Attack = 70.5, FixAttack = 0.0, AbsoluteAttack = 0.0, ActionType = 1 })
        assert(c.reads == 0, c.reads)
        assert(c.lookups == 0, c.lookups)
        assert(c.conversions == 0, c.conversions)
        Log.setDeveloperMode(true)
        assert(#atkLines() == 0)
        c.hooks[CALC].pre({ nil, {}, {}, { Attack = 70.5 }, {} })
        assert(#atkLines() == 0, "no pending hit may survive the Developer Mode off period")
    end)
end

function T.aPendingHitDoesNotSurviveADeveloperModeOffPeriod()
    withProbe(function(c)
        c.probe.install()
        setPower(c, 220.0, 235.0, 15.0, 1.0, 0.0)
        local attackData = { _OriginalAttackAdjust = 30.0, _CriticaType = 0, _IsNoCritical = false }
        c.hooks[HIT_INFO].pre({ nil, {}, hitInfo(c.masterObject, attackData) })
        Log.setDeveloperMode(false)
        c.probe.update()
        Log.setDeveloperMode(true)
        c.hooks[CALC].pre({ nil, {}, {}, { Attack = 70.5, FixAttack = 0.0, AbsoluteAttack = 0.0, ActionType = 1 }, {} })
        assert(#atkLines() == 0, #atkLines())
    end)
end

function T.onHitValuesDoNotSurviveADeveloperModeOffPeriod()
    withProbe(function(c)
        c.probe.install()
        setPower(c, 220.0, 235.0, 15.0, 1.0, 0.0)
        onHit(c, c.master, 235.0, 247.5, 1, 0, 1)
        c.hooks[ON_HIT].pre({ nil, c.power, {}, 235.0, c.master, 1, 1, 1 })
        Log.setDeveloperMode(false)
        c.hooks[ON_HIT].post(999.0)
        Log.setDeveloperMode(true)
        hit(c, c.masterObject, { _OriginalAttackAdjust = 30.0, _CriticaType = 0, _IsNoCritical = false },
            { Attack = 70.5, FixAttack = 0.0, AbsoluteAttack = 0.0, ActionType = 1 })
        local lines = atkLines()
        assert(#lines == 1, #lines)
        assert(lines[1]:find("onhit=nil onhitBase=nil onhitFlags=nil onhitCalls=0", 1, true), lines[1])
    end)
end

return T
