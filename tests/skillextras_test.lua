local SkillExtras = require("MyHuntReport.SkillExtras")

local T = {}

function T.recordOutsideMasterBracketIsIgnored()
    SkillExtras.reset()
    assert(SkillExtras.record("violent", 30) == false)
    SkillExtras.enter(false)
    assert(SkillExtras.record("violent", 30) == false)
    assert(SkillExtras.pendingCount() == 0)
end

function T.recordInsideMasterBracketIsKept()
    SkillExtras.reset()
    SkillExtras.enter(true)
    assert(SkillExtras.record("violent", 30) == true)
    assert(SkillExtras.record("violent", 0/0) == false)
    assert(SkillExtras.record("ryukiExplosion", 0) == false)
    SkillExtras.leave()
    assert(SkillExtras.pendingCount() == 1)
    local list = SkillExtras.take()
    assert(#list == 1 and list[1].kind == "violent" and list[1].damage == 30)
end

function T.takeReturnsSortedAndClears()
    SkillExtras.reset()
    SkillExtras.enter(true)
    SkillExtras.record("violent", 30)
    SkillExtras.record("ryukiExplosion", 45)
    SkillExtras.leave()
    local list = SkillExtras.take()
    assert(#list == 2)
    assert(list[1].kind == "ryukiExplosion" and list[1].damage == 45)
    assert(list[2].kind == "violent" and list[2].damage == 30)
    assert(SkillExtras.pendingCount() == 0)
    assert(#SkillExtras.take() == 0)
end

function T.takeReturnsAllPendingValues()
    SkillExtras.reset()
    SkillExtras.enter(true)
    SkillExtras.record("violent", 100)
    SkillExtras.record("ryukiExplosion", 20)
    SkillExtras.leave()
    local list = SkillExtras.take()
    assert(#list == 2 and list[1].kind == "ryukiExplosion" and list[1].damage == 20)
    assert(list[2].kind == "violent" and list[2].damage == 100)
    assert(SkillExtras.pendingCount() == 0)
end

function T.takeLatestValuePerKindWins()
    SkillExtras.reset()
    SkillExtras.enter(true)
    SkillExtras.record("violent", 10)
    SkillExtras.record("violent", 25)
    SkillExtras.leave()
    local list = SkillExtras.take()
    assert(#list == 1 and list[1].damage == 25)
end

function T.resetClearsBracketAndPending()
    SkillExtras.enter(true)
    SkillExtras.record("violent", 10)
    SkillExtras.reset()
    assert(SkillExtras.pendingCount() == 0)
    assert(SkillExtras.record("violent", 10) == false)
end

return T
