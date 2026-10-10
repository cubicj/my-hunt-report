local SkillExtras = require("MyHuntReport.SkillExtras")

local T = {}

function T.recordOutsideMasterBracketIsIgnored()
    SkillExtras.reset()
    assert(SkillExtras.record("ryukiExplosion", 30) == false)
    SkillExtras.enter(false)
    assert(SkillExtras.record("ryukiExplosion", 30) == false)
    assert(SkillExtras.pendingCount() == 0)
end

function T.recordInsideMasterBracketIsKept()
    SkillExtras.reset()
    SkillExtras.enter(true)
    assert(SkillExtras.record("ryukiExplosion", 30) == true)
    assert(SkillExtras.record("ryukiExplosion", 0/0) == false)
    assert(SkillExtras.record("ryukiExplosion", 0) == false)
    SkillExtras.leave()
    assert(SkillExtras.pendingCount() == 1)
    local list = SkillExtras.take()
    assert(#list == 1 and list[1].kind == "ryukiExplosion" and list[1].damage == 30)
end

function T.takeReturnsSortedAndClears()
    SkillExtras.reset()
    SkillExtras.enter(true)
    SkillExtras.record("testExtra", 30)
    SkillExtras.record("ryukiExplosion", 45)
    SkillExtras.leave()
    local list = SkillExtras.take()
    assert(#list == 2)
    assert(list[1].kind == "ryukiExplosion" and list[1].damage == 45)
    assert(list[2].kind == "testExtra" and list[2].damage == 30)
    assert(SkillExtras.pendingCount() == 0)
    assert(#SkillExtras.take() == 0)
end

function T.takeReturnsAllPendingValues()
    SkillExtras.reset()
    SkillExtras.enter(true)
    SkillExtras.record("testExtra", 100)
    SkillExtras.record("ryukiExplosion", 20)
    SkillExtras.leave()
    local list = SkillExtras.take()
    assert(#list == 2 and list[1].kind == "ryukiExplosion" and list[1].damage == 20)
    assert(list[2].kind == "testExtra" and list[2].damage == 100)
    assert(SkillExtras.pendingCount() == 0)
end

function T.takeLatestValuePerKindWins()
    SkillExtras.reset()
    SkillExtras.enter(true)
    SkillExtras.record("ryukiExplosion", 10)
    SkillExtras.record("ryukiExplosion", 25)
    SkillExtras.leave()
    local list = SkillExtras.take()
    assert(#list == 1 and list[1].damage == 25)
end

function T.resetClearsBracketAndPending()
    SkillExtras.enter(true)
    SkillExtras.record("ryukiExplosion", 10)
    SkillExtras.reset()
    assert(SkillExtras.pendingCount() == 0)
    assert(SkillExtras.record("ryukiExplosion", 10) == false)
end

function T.installRegistersOnlyCalcAndRyukiExplosionHooks()
    local Game = require("MyHuntReport.Game")
    local hook = Game.hook
    local captured = {}
    local ok, err = pcall(function()
        Game.hook = function(typeName, signature)
            assert(typeName == "app.cHunterSkill")
            captured[#captured + 1] = signature
        end
        local extras = assert(loadfile("reframework/autorun/MyHuntReport/SkillExtras.lua"))()
        extras.install()
        assert(#captured == 2)
        assert(captured[1] == "calcSkillAdditionalDamage(app.cEnemyContextHolder, app.HitInfo, app.HunterCharacter)")
        assert(captured[2] == "getSkillRyukiExplosionAddDamage(System.Boolean)")
        extras.install()
        assert(#captured == 2)
    end)
    Game.hook = hook
    if not ok then error(err, 0) end
end

function T.recordBuildsItsDiagnosticOnlyInDeveloperMode()
    local stubs = require("stubs")
    local Log = require("MyHuntReport.Log")
    local developerMode = Log.isDeveloperMode()
    local formatted = 0
    local kind = setmetatable({}, { __tostring = function() formatted = formatted + 1 return "probe" end })
    local ok, err = pcall(function()
        Log.resetCounts()
        SkillExtras.reset()
        SkillExtras.enter(true)
        Log.setDeveloperMode(false)
        assert(SkillExtras.record(kind, 12) == true)
        assert(formatted == 0 and #stubs.logLines == 0 and Log.count("extra:probe") == 0, formatted)
        Log.setDeveloperMode(true)
        assert(SkillExtras.record(kind, 12) == true)
        assert(stubs.logLines[1] == "[MyHuntReport] skill extra probe value=12", stubs.logLines[1])
        assert(Log.count("extra:probe") == 1)
    end)
    SkillExtras.reset()
    Log.setDeveloperMode(developerMode)
    if not ok then error(err, 0) end
end

return T
