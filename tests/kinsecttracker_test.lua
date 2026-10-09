local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local T = {}

local MODULE_PATH = "reframework/autorun/MyHuntReport/KinsectTracker.lua"

local function lines(prefix)
    local found = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] kinsect " .. prefix, 1, true) then found[#found + 1] = line end
    end
    return found
end

local function has(line, text)
    return line ~= nil and line:find(text, 1, true) ~= nil
end

local function classed(name, guide)
    return {
        _ActionGuideID = guide,
        get_type_definition = function() return { get_name = function() return name end } end,
    }
end

local function kinsect(c, address)
    return {
        get_address = function() return address end,
        _ActionController = { get_CurrentAction = function()
            if c.kinsectFails then error("no current action") end
            return c.kinsectAction
        end },
    }
end

local function hunter(c)
    return {
        get_WeaponType = function()
            if c.weaponFails then error("no weapon type") end
            return c.weapon
        end,
        get_WeaponHandling = function()
            return { call = function(_, name)
                if name == "get_Insect" then return c.handlingInsect end
                return nil
            end }
        end,
        call = function(_, name)
            if name == "get_Wp10Insect" then return c.mainInsect end
            if name == "get_BaseActionController" then
                return { get_CurrentAction = function() return c.base end }
            end
            if name == "get_SubActionController" then
                return { get_CurrentAction = function() return c.sub end }
            end
            return nil
        end,
    }
end

local function withTracker(developerMode, callback)
    local saved = {
        masterHunter = Game.masterHunter, uptime = Game.uptime, componentOf = Game.componentOf,
    }
    local c = { weapon = 10, now = 10.0, masterReads = 0, uptimeReads = 0 }
    c.mainInsect = kinsect(c, 0x500)
    c.handlingInsect = c.mainInsect
    c.objectFor = { main = { component = c.mainInsect } }
    c.hunter = hunter(c)
    c.step = function(base, sub, action)
        c.base, c.sub, c.kinsectAction = base, sub, action
        c.tracker.update()
    end
    c.trigger = function(object)
        return c.tracker.triggerFor(object or c.objectFor.main)
    end
    local ok, err = pcall(function()
        Log.setDeveloperMode(developerMode)
        Log.resetCounts()
        stubs.reset()
        Game.masterHunter = function()
            c.masterReads = c.masterReads + 1
            return c.hunter
        end
        Game.uptime = function()
            c.uptimeReads = c.uptimeReads + 1
            return c.now
        end
        Game.componentOf = function(object, typeName)
            if typeName ~= "app.Wp10Insect" or object == nil then return nil end
            return object.component
        end
        c.tracker = dofile(MODULE_PATH)
        callback(c)
    end)
    Game.masterHunter = saved.masterHunter
    Game.uptime = saved.uptime
    Game.componentOf = saved.componentOf
    Log.setDeveloperMode(false)
    if not ok then error(err, 0) end
end

local IDLE = classed("cIdle")

function T.attackBaseExcludesNonAttackAndIdleStates()
    local tracker = dofile(MODULE_PATH)
    assert(tracker.isAttackBase("cBatonMoveAttack") == true)
    assert(tracker.isAttackBase("cDodgeFront") == false)
    assert(tracker.isAttackBase("cMove") == false)
    assert(tracker.isAttackBase("cIdle") == false)
    assert(tracker.isAttackBase("cMoveStop") == false)
    assert(tracker.isAttackBase("cDownFaceDownToMove") == false)
    assert(tracker.isAttackBase(nil) == false)
end

function T.firstObservedActionHasNoTrigger()
    withTracker(false, function(c)
        c.step(classed("cBatonMoveAttack", 1), classed("cNothing"), classed("cPassMoveAttackLeft"))
        local className = c.trigger()
        assert(className == nil)
    end)
end

function T.baseAttackAtTheStartIsTheTriggerAfterTheHunterMovesOn()
    withTracker(false, function(c)
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cBatonMoveAttack", 11), classed("cNothing"), classed("cPassMoveAttackLeft"))
        c.step(classed("cBatonMoveAttack2", 21), classed("cNothing"), classed("cPassMoveAttackLeft"))
        local className, guideId = c.trigger()
        assert(className == "cBatonMoveAttack" and guideId == 11)
        c.step(classed("cBatonMoveAttack2", 21), classed("cNothing"), classed("cPassMoveAttackSuperFront"))
        className, guideId = c.trigger()
        assert(className == "cBatonMoveAttack2" and guideId == 21)
    end)
end

function T.insectSubActionWinsOverAMovingBase()
    withTracker(false, function(c)
        c.step(classed("cMove"), classed("cNothing"), IDLE)
        c.step(classed("cMove"), classed("cInsectAttack", 77), classed("cAttack"))
        local className, guideId = c.trigger()
        assert(className == "cInsectAttack" and guideId == 77)
    end)
end

function T.markShotChainKeepsItsTrigger()
    withTracker(false, function(c)
        c.step(classed("cGunShot", -1726610048), classed("cNothing"), IDLE)
        c.step(classed("cGunShot", -1726610048), classed("cNothing"), classed("cAutoAttack"))
        assert(c.trigger() == "cGunShot")
        c.step(classed("cBatonMoveAttack", 11), classed("cNothing"), classed("cHit"))
        c.step(classed("cBatonMoveAttack", 11), classed("cNothing"), classed("cWander"))
        c.step(classed("cBatonMoveAttack2", 21), classed("cNothing"), classed("cAutoAttack"))
        local className, guideId = c.trigger()
        assert(className == "cGunShot" and guideId == -1726610048)
    end)
end

function T.launchPreStateHandsItsTriggerToTheAttack()
    withTracker(false, function(c)
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cAimAttackHit", 81), classed("cNothing"), classed("cAimAttackPre"))
        c.step(classed("cAimAttackHitToRun", 82), classed("cNothing"), classed("cAimAttack"))
        local className, guideId = c.trigger()
        assert(className == "cAimAttackHit" and guideId == 81)
    end)
end

function T.nonAttackBaseFallsBackToTheLastAttack()
    withTracker(false, function(c)
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), IDLE)
        c.step(classed("cMoveStop"), classed("cNothing"), IDLE)
        c.step(classed("cIdle"), classed("cNothing"), classed("cAttack"))
        local className, guideId = c.trigger()
        assert(className == "cBatonFSlash" and guideId == 31)
    end)
end

function T.nonAttackBaseWithoutALastAttackHasNoTrigger()
    withTracker(false, function(c)
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cDownFaceDownToMove"), classed("cNothing"), classed("cAttack"))
        assert(c.trigger() == nil)
    end)
end

function T.unreadableHunterActionLeavesTheTriggerUnknown()
    withTracker(true, function(c)
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), IDLE)
        c.step(nil, classed("cNothing"), classed("cAttack"))
        assert(c.trigger() == nil)
        c.step(classed("cMove"), nil, classed("cAutoAttack"))
        assert(c.trigger() == nil)
        c.step(classed("cMove"), classed("cNothing"), classed("cHit"))
        assert(c.trigger() == nil)
        local act = lines("act ")
        assert(has(act[2], "base=?/? sub=cNothing/-1 seen=true rule=unreadable trigger=?/?"))
        assert(has(act[3], "base=cMove/-1 sub=?/? seen=true rule=unreadable trigger=?/?"))
        assert(has(act[4], "rule=inherit trigger=?/?"))
        local hit = lines("hit ")
        assert(has(hit[1], "rule=unreadable trigger=?/? hitBase=? result=fallback:unknownTrigger"))
    end)
end

function T.developerModeTurnedOnMidRecordPrintsAnUnknownAge()
    withTracker(false, function(c)
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        Log.setDeveloperMode(true)
        assert(c.trigger() == "cBatonFSlash")
        assert(has(lines("hit ")[1], "kact=cPassBringDown open=cPassBringDown age=? rule=base"))
        c.kinsectFails = true
        c.tracker.update()
        assert(has(lines("act ")[1], "from=cPassBringDown to=? dur=? spans=0"))
    end)
end

function T.hitsFromAnotherKinsectOrAStaleActionFallBack()
    withTracker(true, function(c)
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        local other = { component = kinsect(c, 0x900) }
        assert(c.trigger(other) == nil)
        c.kinsectAction = classed("cBack")
        assert(c.trigger() == nil)
        c.kinsectAction = classed("cPassBringDown")
        assert(c.trigger({}) == nil)
        assert(c.trigger({ component = { get_address = function() error("gone") end,
            _ActionController = c.mainInsect._ActionController } }) == nil)
        assert(c.trigger() == "cBatonFSlash")
        local hitLines = lines("hit ")
        assert(#hitLines == 5)
        assert(has(hitLines[1], "result=fallback:otherKinsect"))
        assert(has(hitLines[2], "kact=cBack open=cPassBringDown"))
        assert(has(hitLines[2], "result=fallback:stale"))
        assert(has(hitLines[3], "kact=? open=cPassBringDown"))
        assert(has(hitLines[3], "result=fallback:unreadable"))
        assert(has(hitLines[4], "result=fallback:unreadable"))
        assert(has(hitLines[5], "rule=base trigger=cBatonFSlash/31 hitBase=cBatonFSlash result=trigger"))
    end)
end

function T.replacedKinsectStartsAnUnobservedRecord()
    withTracker(false, function(c)
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        c.mainInsect = kinsect(c, 0x900)
        c.objectFor.main.component = c.mainInsect
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        assert(c.trigger() == nil)
    end)
end

function T.unreadableKinsectDropsTheRecordAndRecoveryIsUnobserved()
    withTracker(true, function(c)
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        c.kinsectFails = true
        c.now = 10.5
        c.tracker.update()
        c.tracker.update()
        c.kinsectFails = false
        c.step(classed("cBatonWSlash", 41), classed("cNothing"), classed("cPassCurveR"))
        assert(c.trigger() == nil)
        local act = lines("act ")
        assert(#act == 4)
        assert(has(act[3], "from=cPassBringDown to=? dur=0.50 spans=0"))
        assert(has(act[4], "from=? to=cPassCurveR dur=? spans=? base=cBatonWSlash/41 sub=cNothing/-1 seen=false rule=unseen trigger=?/?"))
    end)
end

function T.handlingGetterIsTheFallback()
    withTracker(false, function(c)
        c.mainInsect = nil
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        assert(c.trigger() == "cBatonFSlash")
    end)
end

function T.leavingTheGlaiveClearsAndPrintsTheSummary()
    withTracker(true, function(c)
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        assert(c.trigger() == "cBatonFSlash")
        c.weapon = 3
        c.tracker.update()
        c.tracker.update()
        local summary = lines("summary ")
        assert(#summary == 1)
        assert(has(summary[1], "hits=1 trigger=1 noRecord=0 otherKinsect=0 stale=0 unknownTrigger=0 unreadable=0 inherit=0 sub=0 base=1 last=0"))
        c.weapon = 10
        assert(c.trigger() == nil)
        c.weaponFails = true
        c.tracker.update()
        assert(c.trigger() == nil)
    end)
end

function T.spansCountAttackChangesButNotGuideLossOrTheFirstRead()
    withTracker(true, function(c)
        c.step(nil, nil, IDLE)
        c.step(nil, nil, classed("cPassBringDown"))
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        c.step(classed("cBatonFSlash"), classed("cNothing"), classed("cPassBringDown"))
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        c.step(nil, nil, classed("cPassBringDown"))
        c.step(classed("cBatonWSlash", 41), classed("cNothing"), classed("cPassBringDown"))
        c.step(classed("cDodgeFront", 51), classed("cNothing"), classed("cPassCurveR"))
        local act = lines("act ")
        assert(has(act[#act], "from=cPassBringDown to=cPassCurveR dur=0.00 spans=1"))
        assert(has(act[#act], "rule=last trigger=cBatonWSlash/41"))
    end)
end

function T.summaryPrintsEveryTwentyHitsInDeveloperModeOnly()
    withTracker(true, function(c)
        for _ = 1, 20 do c.trigger() end
        assert(#lines("summary ") == 1)
        assert(has(lines("summary ")[1], "hits=20 trigger=0 noRecord=20"))
    end)
end

function T.outsideDeveloperModeNothingIsLoggedAndTheHitDoesNotReadTheHunter()
    withTracker(false, function(c)
        c.step(classed("cIdle"), classed("cNothing"), IDLE)
        c.step(classed("cBatonFSlash", 31), classed("cNothing"), classed("cPassBringDown"))
        local reads = c.masterReads
        for _ = 1, 20 do assert(c.trigger() == "cBatonFSlash") end
        c.weapon = 3
        c.tracker.update()
        assert(c.masterReads == reads + 1)
        assert(c.uptimeReads == 0)
        assert(#stubs.logLines == 0)
    end)
end

return T
