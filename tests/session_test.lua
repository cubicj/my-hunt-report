local stubs = require("stubs")
local Session = require("MyHuntReport.Session")

local T = {}

local function hit(overrides)
    local base = {
        monsterId = 1, monsterLabel = { kind = "monster", emId = 26 }, finalDamage = 100, physical = 80, element = 20,
        weight = 10, motionKey = "7:cShellFire", motionLabel = { kind = "motion", className = "cShellFire", guideId = -1 },
        activeSkills = {}, time = 10,
    }
    for key, value in pairs(overrides or {}) do base[key] = value end
    return base
end

function T.snapshotCopiesOptionalQuestLevel()
    Session.reset(0)
    assert(Session.snapshot({ questLevel = 5 }).quest.level == 5)
    assert(Session.snapshot().quest.level == nil)
end

function T.resetClearsEverything()
    Session.reset(5)
    Session.addHit(hit())
    Session.reset(7)
    assert(Session.hitCount() == 0)
    assert(Session.startTime() == 7)
    assert(Session.lastHitTime() == nil)
    assert(Session.hasData() == false)
end

function T.totalsSplitPhysicalElementAndStatus()
    Session.reset(0)
    Session.addHit(hit({ finalDamage = 100, physical = 80, element = 20 }))
    Session.addHit(hit({ finalDamage = 50, physical = 50, element = 0, time = 12 }))
    Session.addProc({ kind = "blast", damage = 100, time = 13 })
    local s = Session.snapshot()
    assert(s.damage.total == 250, "total " .. s.damage.total)
    assert(s.damage.physical == 130 and s.damage.element == 20 and s.damage.status == 100)
    assert(s.damage.hits == 2)
    assert(s.quest.elapsedSeconds == 12)
    assert(s.version == 2)
end

function T.zeroDamageHitsAreIgnored()
    Session.reset(0)
    assert(Session.addHit(hit({ finalDamage = 0 })) == false)
    assert(Session.hitCount() == 0)
end

function T.monstersSortedByDamage()
    Session.reset(0)
    Session.addHit(hit({ monsterId = 1, monsterLabel = { kind = "monster", emId = 1 }, finalDamage = 30 }))
    Session.addHit(hit({ monsterId = 2, monsterLabel = { kind = "monster", emId = 2 }, finalDamage = 70 }))
    Session.addHit(hit({ monsterId = 1, monsterLabel = { kind = "monster", emId = 1 }, finalDamage = 20 }))
    local s = Session.snapshot()
    assert(#s.monsters == 2)
    assert(s.monsters[1].id == 2 and s.monsters[1].damage == 70)
    assert(s.monsters[2].name == "#1" and s.monsters[2].damage == 50)
end

function T.skillSharesUseWeightOverTotalWeight()
    Session.reset(0)
    Session.addHit(hit({ weight = 10, activeSkills = { [29] = true } }))
    Session.addHit(hit({ weight = 30, activeSkills = {} }))
    local s = Session.snapshot({
        equippedSkills = { { id = 29 }, { id = 116 } },
        resolveName = function(label)
            if label.kind == "skill" then
                return label.id == 29 and "Offensive Guard" or "Adrenaline Rush"
            end
            return label.kind
        end,
    })
    assert(#s.skills == 1, "equipped skills without credited weight are hidden")
    assert(s.skills[1].id == 29 and s.skills[1].name == "Offensive Guard")
    assert(math.abs(s.skills[1].share - 0.25) < 1e-9, tostring(s.skills[1].share))
    assert(s.skills[1].weight == 10)
end

function T.skillSharesUseEligibleWeightWhenPresent()
    Session.reset(0)
    Session.addHit(hit({ weight = 10, activeSkills = { [4082] = true, [29] = true }, eligibleSkills = { [4082] = true } }))
    Session.addHit(hit({ weight = 30, activeSkills = {}, eligibleSkills = { [4082] = true } }))
    Session.addHit(hit({ weight = 60, activeSkills = {}, eligibleSkills = {} }))
    local rows = {}
    for _, row in ipairs(Session.snapshot({ equippedSkills = { { id = 29 } }, resolveName = function(label) return tostring(label.id) end }).skills) do
        rows[row.id] = row
    end
    assert(rows[4082] and math.abs(rows[4082].share - 0.25) < 1e-9, tostring(rows[4082] and rows[4082].share))
    assert(rows[29] and math.abs(rows[29].share - 0.1) < 1e-9, tostring(rows[29] and rows[29].share))
    Session.reset(0)
    Session.addHit(hit({ weight = 10, activeSkills = { [4082] = true }, eligibleSkills = {} }))
    local s = Session.snapshot({ resolveName = function(label) return tostring(label.id) end })
    assert(#s.skills == 1 and math.abs(s.skills[1].share - 1) < 1e-9)
end

function T.placeholderSkillNamesAreHidden()
    Session.reset(0)
    Session.addHit(hit({ weight = 10, activeSkills = { [243] = true, [59] = true } }))
    local s = Session.snapshot({ resolveName = function(label)
        if label.kind == "skill" then return label.id == 243 and "------" or "Agitator" end
        return label.kind
    end })
    assert(#s.skills == 1 and s.skills[1].id == 59)
end

function T.creditedMelodyProducesRowWithoutBeingEquipped()
    Session.reset(0)
    Session.addHit(hit({ weight = 10, activeSkills = { [2012] = true } }))
    Session.addHit(hit({ weight = 30, activeSkills = {} }))
    local s = Session.snapshot({
        equippedSkills = { { id = 29 } },
        resolveName = function(label)
            if label.kind == "skill" and label.id == 2012 then return "Attack x1.1" end
            return label.kind
        end,
    })
    assert(#s.skills == 1)
    local row = s.skills[1]
    assert(row.id == 2012 and row.name == "Attack x1.1")
    assert(stubs.encode(row.label) == stubs.encode({ kind = "skill", id = 2012 }))
    assert(row.weight == 10 and math.abs(row.share - 0.25) < 1e-9)
end

function T.skillWithoutWeightIsHidden()
    Session.reset(0)
    Session.addHit(hit({ weight = 0, activeSkills = { [29] = true } }))
    local s = Session.snapshot()
    assert(#s.skills == 0)
end

function T.motionRowsIncludeProcs()
    Session.reset(0)
    Session.addHit(hit({ motionKey = "7:cShellFire", motionLabel = { kind = "motion", className = "cShellFire", guideId = -1 }, finalDamage = 60 }))
    Session.addHit(hit({ motionKey = "7:cSlash", motionLabel = { kind = "motion", className = "cSlash", guideId = -1 }, finalDamage = 20 }))
    Session.addHit(hit({ motionKey = "7:cShellFire", motionLabel = { kind = "motion", className = "cShellFire", guideId = -1 }, finalDamage = 20 }))
    Session.addProc({ kind = "blast", damage = 100, time = 1 })
    local s = Session.snapshot()
    assert(#s.motions == 3)
    assert(s.motions[1].key == "proc:blast" and s.motions[1].damage == 100 and s.motions[1].hits == 1)
    assert(s.motions[2].key == "7:cShellFire" and s.motions[2].hits == 2)
    assert(math.abs(s.motions[2].share - 0.4) < 1e-9)
    assert(#s.procs == 1 and s.procs[1].kind == "blast" and s.procs[1].count == 1)
end

function T.diagnosticsCount()
    Session.reset(0)
    Session.noteWeightFallback()
    Session.noteDroppedPending()
    Session.noteDroppedPending()
    local d = Session.snapshot().diagnostics
    assert(d.weightFallbacks == 1 and d.droppedPending == 2)
    assert(d.uncountedExternal == nil and d.procAttribution == nil)
    assert(Session.noteUncountedExternal == nil)
end

function T.questFieldsComeFromOptions()
    Session.reset(0)
    Session.addHit(hit())
    local s = Session.snapshot({ result = "clear", elapsedSeconds = 754, endedAt = 123, weapon = { type = 7 }, playerCount = 2 })
    assert(s.quest.result == "clear" and s.quest.elapsedSeconds == 754 and s.quest.endedAt == 123)
    assert(s.quest.weapon.type == 7 and s.quest.weapon.name == "#7" and s.quest.playerCount == 2)
    local d = Session.snapshot()
    assert(d.quest.result == "running" and d.quest.endedAt == stubs.now)
end

function T.snapshotIsDetachedFromLaterHits()
    Session.reset(0)
    Session.addHit(hit())
    local s = Session.snapshot()
    Session.addHit(hit())
    assert(s.damage.hits == 1)
end

function T.fixedHitsMoveIntoFixed()
    Session.reset(0)
    Session.addHit(hit({ finalDamage = 40, physical = 40, element = 0, fixed = true }))
    Session.addHit(hit({ finalDamage = 60, physical = 50, element = 10 }))
    local s = Session.snapshot()
    assert(s.damage.fixed == 40 and s.damage.physical == 50 and s.damage.element == 10, "fixed split")
    assert(s.damage.total == 100)
end

function T.critRateHonoursCanCrit()
    Session.reset(0)
    Session.addHit(hit({ canCrit = true, critType = 1 }))
    Session.addHit(hit({ canCrit = true, critType = 0 }))
    Session.addHit(hit({ canCrit = true, critType = 2 }))
    Session.addHit(hit({ canCrit = false, critType = 1 }))
    Session.addHit(hit({}))
    local st = Session.snapshot().stats
    assert(math.abs(st.critRate - 1 / 3) < 1e-9, tostring(st.critRate))
    assert(math.abs(st.negativeCritRate - 1 / 3) < 1e-9, tostring(st.negativeCritRate))
end

function T.critRateIsNilWithoutCrittableHits()
    Session.reset(0)
    Session.addHit(hit({ canCrit = false, critType = 1 }))
    local st = Session.snapshot().stats
    assert(st.critRate == nil and st.negativeCritRate == nil)
end

function T.hitzoneAverageSkipsFixedAndZeroPhysical()
    Session.reset(0)
    Session.addHit(hit({ baseHitzone = 45, physical = 80 }))
    Session.addHit(hit({ baseHitzone = 25, physical = 80 }))
    Session.addHit(hit({ baseHitzone = 99, physical = 80, fixed = true }))
    Session.addHit(hit({ baseHitzone = 99, physical = 0, element = 10 }))
    Session.addHit(hit({ physical = 80 }))
    local st = Session.snapshot().stats
    assert(st.avgHitzone == 35, tostring(st.avgHitzone))
end

function T.attributeAverageUsesDominantAttribute()
    Session.reset(0)
    Session.addHit(hit({ attribute = 1, attributeHitzone = 20, element = 10 }))
    Session.addHit(hit({ attribute = 1, attributeHitzone = 30, element = 10 }))
    Session.addHit(hit({ attribute = 1, attributeHitzone = 30, element = 0 }))
    Session.addHit(hit({ attribute = 1, attributeHitzone = 0, element = 10 }))
    Session.addHit(hit({ attribute = 3, attributeHitzone = 50, element = 10 }))
    Session.addHit(hit({ attribute = 0, attributeHitzone = 30, element = 10 }))
    local st = Session.snapshot().stats
    assert(st.attribute == 1 and st.avgAttributeHitzone == 25, tostring(st.avgAttributeHitzone))
end

function T.attributeIsZeroWithoutElementHits()
    Session.reset(0)
    Session.addHit(hit({}))
    local st = Session.snapshot().stats
    assert(st.attribute == 0 and st.avgAttributeHitzone == nil)
end

function T.skillDamageRowsSortedAndFiltered()
    Session.reset(0)
    Session.addHit(hit({ finalDamage = 100, skillExtras = { { kind = "flare", damage = 10 }, { kind = "violent", damage = 30 } } }))
    Session.addHit(hit({ finalDamage = 100, skillExtras = { { kind = "flare", damage = 15 }, { kind = "darkWave", damage = 0 } } }))
    local rows = Session.snapshot().skillDamage
    assert(#rows == 2, tostring(#rows))
    assert(rows[1].kind == "violent" and rows[1].damage == 30 and math.abs(rows[1].share - 0.15) < 1e-9)
    assert(rows[2].kind == "flare" and rows[2].damage == 25)
end

local function assertSkillProcDamage(kind)
    Session.reset(0)
    Session.addHit(hit())
    assert(Session.addProc({ kind = kind, damage = 160 }) == true)
    local s = Session.snapshot()
    assert(s.damage.total == 260 and s.damage.fixed == 160 and s.damage.status == 0)
    assert(s.damage.physical == 80 and s.damage.element == 20 and s.damage.hits == 1)
    assert(#s.procs == 0 and #s.motions == 1)
    for _, row in ipairs(s.motions) do assert(row.key:sub(1, 5) ~= "proc:") end
    assert(s.motions[1].damage == 100 and s.motions[1].share == 100 / 260)
    assert(stubs.encode(s.skillDamage) == stubs.encode({ { kind = kind, damage = 160, share = 160 / 260 } }))
end

function T.flayerProcAddsFixedSkillDamageWithoutMotionRow()
    assertSkillProcDamage("flayer")
end

function T.elementConvertProcAddsFixedSkillDamageWithoutMotionRow()
    assertSkillProcDamage("elementConvert")
end

function T.blastAndPoisonKeepStatusAndProcRows()
    for _, kind in ipairs({ "blast", "poison" }) do
        Session.reset(0)
        Session.addHit(hit())
        assert(Session.addProc({ kind = kind, damage = 160 }) == true)
        local s = Session.snapshot()
        assert(s.damage.total == 260 and s.damage.fixed == 0 and s.damage.status == 160)
        assert(#s.skillDamage == 0 and #s.procs == 1 and #s.motions == 2)
        assert(s.procs[1].kind == kind and s.procs[1].damage == 160 and s.procs[1].count == 1)
        assert(s.motions[1].key == "proc:" .. kind and s.motions[1].damage == 160)
        assert(s.motions[1].share == 160 / 260 and s.motions[1].hits == 1)
    end
end

function T.skillProcOnlySessionHasDataUntilReset()
    for _, kind in ipairs({ "flayer", "elementConvert" }) do
        Session.reset(0)
        assert(Session.hasData() == false)
        Session.addProc({ kind = kind, damage = 160 })
        assert(Session.hasData() == true and Session.hitCount() == 0)
        local s = Session.snapshot()
        assert(Session.snapshotHasData(s) == true)
        assert(s.damage.total == 160 and s.damage.fixed == 160 and s.damage.status == 0)
        assert(#s.procs == 0 and #s.motions == 0)
        assert(stubs.encode(s.skillDamage) == stubs.encode({ { kind = kind, damage = 160, share = 160 / 160 } }))
        Session.reset(0)
        assert(Session.hasData() == false)
        s = Session.snapshot()
        assert(s.damage.total == 0 and s.damage.fixed == 0 and #s.skillDamage == 0)
    end
end

function T.skillProcRowsSortByShareWithHitSkillDamage()
    Session.reset(0)
    Session.addHit(hit({ skillExtras = { { kind = "violent", damage = 30 } } }))
    Session.addProc({ kind = "flayer", damage = 20 })
    local rows = Session.snapshot().skillDamage
    assert(stubs.encode(rows) == stubs.encode({
        { kind = "violent", damage = 30, share = 30 / 120 },
        { kind = "flayer", damage = 20, share = 20 / 120 },
    }))
    Session.addProc({ kind = "flayer", damage = 140 })
    rows = Session.snapshot().skillDamage
    assert(stubs.encode(rows) == stubs.encode({
        { kind = "flayer", damage = 160, share = 160 / 260 },
        { kind = "violent", damage = 30, share = 30 / 260 },
    }))
end

function T.skillAndStatusProcsAccumulateWithoutDoubleCounting()
    Session.reset(0)
    Session.addHit(hit())
    for _, kind in ipairs({ "flayer", "elementConvert" }) do
        assert(Session.addProc({ kind = kind, damage = 0 }) == false)
        assert(Session.addProc({ kind = kind, damage = -10 }) == false)
        Session.addProc({ kind = kind, damage = 40 })
        Session.addProc({ kind = kind, damage = 60 })
    end
    Session.addProc({ kind = "blast", damage = 50 })
    local s = Session.snapshot()
    assert(s.damage.total == 350 and s.damage.fixed == 200 and s.damage.status == 50)
    assert(s.damage.physical + s.damage.element + s.damage.fixed + s.damage.status == s.damage.total)
    assert(#s.procs == 1 and s.procs[1].kind == "blast" and #s.motions == 2)
    assert(stubs.encode(s.skillDamage) == stubs.encode({
        { kind = "elementConvert", damage = 100, share = 100 / 350 },
        { kind = "flayer", damage = 100, share = 100 / 350 },
    }))
end

function T.combatDpsUsesFightingTime()
    Session.reset(0)
    Session.addHit(hit({ finalDamage = 100 }))
    Session.addProc({ kind = "blast", damage = 50, time = 11 })
    Session.addFightingTime(2)
    Session.addFightingTime(3)
    Session.addFightingTime(-1)
    local s = Session.snapshot()
    assert(s.stats.fightingSeconds == 5)
    assert(s.stats.combatDps == 30, tostring(s.stats.combatDps))
    assert(s.diagnostics.fightingFallback == false)
end

function T.combatDpsFallsBackToFirstAndLastHit()
    Session.reset(0)
    Session.addHit(hit({ finalDamage = 100, time = 10 }))
    Session.addHit(hit({ finalDamage = 100, time = 30 }))
    local s = Session.snapshot()
    assert(Session.firstHitTime() == 10)
    assert(s.stats.fightingSeconds == 20 and s.stats.combatDps == 10)
    assert(s.diagnostics.fightingFallback == true)
end

function T.combatDpsIsNilWithoutFightingTime()
    Session.reset(0)
    Session.addHit(hit({ finalDamage = 100, time = 10 }))
    local s = Session.snapshot()
    assert(s.stats.fightingSeconds == 0 and s.stats.combatDps == nil)
end

function T.monstersCarryShares()
    Session.reset(0)
    Session.addHit(hit({ monsterId = 1, monsterLabel = { kind = "monster", emId = 1 }, finalDamage = 30 }))
    Session.addHit(hit({ monsterId = 2, monsterLabel = { kind = "monster", emId = 2 }, finalDamage = 70 }))
    local s = Session.snapshot()
    assert(math.abs(s.monsters[1].share - 0.7) < 1e-9 and math.abs(s.monsters[2].share - 0.3) < 1e-9)
end

function T.resetClearsStats()
    Session.reset(0)
    Session.addHit(hit({ canCrit = true, critType = 1, baseHitzone = 50, skillExtras = { { kind = "flare", damage = 5 } } }))
    Session.addFightingTime(4)
    Session.reset(1)
    local s = Session.snapshot()
    assert(s.stats.critRate == nil and s.stats.avgHitzone == nil and s.stats.fightingSeconds == 0)
    assert(#s.skillDamage == 0 and s.damage.fixed == 0 and Session.firstHitTime() == nil)
end

function T.weaponTypesAreCollectedInFirstSeenOrder()
    Session.reset(0)
    Session.addHit(hit({ weaponType = 10 }))
    Session.addHit(hit({ weaponType = 13, time = 11 }))
    Session.addHit(hit({ weaponType = 10, time = 12 }))
    Session.addHit(hit({ weaponType = -1, time = 13 }))
    Session.addHit(hit({ time = 14 }))
    local types = Session.weaponTypes()
    assert(#types == 2 and types[1] == 10 and types[2] == 13, table.concat(types, ","))
    Session.reset(1)
    assert(#Session.weaponTypes() == 0)
end

function T.snapshotCarriesWeaponsFromOptions()
    Session.reset(0)
    Session.addHit(hit({ weaponType = 10 }))
    local s = Session.snapshot({ weapons = { { type = 10 }, { type = 13 } } })
    assert(#s.quest.weapons == 2 and s.quest.weapons[2].name == "#13")
    assert(#Session.snapshot().quest.weapons == 0)
end

function T.rejectedSkillNamesAreHidden()
    Session.reset(0)
    Session.addHit(hit({ activeSkills = { [144] = true, [63] = true } }))
    local s = Session.snapshot({
        equippedSkills = { { id = 63 }, { id = 156 } },
        resolveName = function(label)
            if label.kind == "skill" and label.id ~= 63 then
                return "<COLOR FF0000>#Rejected#</COLOR> SkillCommon_424767232"
            end
            return "Weakness Exploit"
        end,
    })
    assert(#s.skills == 1, "expected one row, got " .. #s.skills)
    assert(s.skills[1].id == 63)
end

function T.snapshotCombinesStringAndNumericSkillKeys()
    Session.reset(0)
    Session.addHit(hit({ activeSkills = { [59] = true, ["burst:stage1"] = true }, weight = 10 }))
    Session.addHit(hit({ activeSkills = { [59] = true, ["burst:stage2"] = true }, weight = 30 }))
    local s = Session.snapshot({ equippedSkills = { { id = "burst:stage1" }, { id = 59 } } })
    local rows = {}
    for _, row in ipairs(s.skills) do rows[row.id] = row end
    assert(#s.skills == 3)
    assert(rows[59].weight == 40 and rows[59].share == 1)
    assert(rows["burst:stage1"].weight == 10 and rows["burst:stage1"].share == 0.25)
    assert(rows["burst:stage2"].weight == 30 and rows["burst:stage2"].share == 0.75)
end

function T.snapshotCarriesLabelsAndResolvesEveryRow()
    Session.reset(0)
    Session.addHit(hit({ activeSkills = { ["burst:stage2"] = true } }))
    Session.addProc({ kind = "blast", damage = 20 })
    local s = Session.snapshot({
        weapon = { type = 7 }, weapons = { { type = 7 }, { type = 13 } },
        equippedSkills = { { id = "burst:stage2" }, { id = 29 } },
        resolveName = function(label) return "resolved:" .. label.kind end,
    })
    assert(s.monsters[1].label.kind == "monster" and s.monsters[1].label.emId == 26)
    assert(s.motions[1].label.kind == "motion" and s.motions[1].label.className == "cShellFire")
    assert(s.motions[1].label.guideId == -1)
    assert(s.motions[2].label.kind == "proc" and s.motions[2].label.proc == "blast")
    assert(s.procs[1].label.proc == "blast")
    assert(s.skills[1].label.kind == "skill" and s.skills[1].label.id == "burst:stage2")
    assert(s.quest.weapon.label.kind == "weapon" and s.quest.weapon.label.type == 7)
    assert(s.quest.weapons[2].label.type == 13)
    for _, rows in ipairs({ s.monsters, s.motions, s.procs, s.skills, s.quest.weapons, { s.quest.weapon } }) do
        for _, row in ipairs(rows) do assert(row.name == "resolved:" .. row.label.kind) end
    end
end

function T.relabelMutatesNamesAndResortsTies()
    Session.reset(0)
    Session.addHit(hit({ motionKey = "a", motionLabel = { kind = "motion", className = "a", guideId = 1 },
        activeSkills = { [29] = true, [63] = true } }))
    Session.addHit(hit({ motionKey = "b", motionLabel = { kind = "motion", className = "b", guideId = 2 },
        activeSkills = { [29] = true, [63] = true } }))
    Session.addProc({ kind = "blast", damage = 1 })
    local s = Session.snapshot({ weapon = { type = 7 }, weapons = { { type = 13 } } })
    local rows = { s.monsters[1], s.motions[1], s.motions[2], s.motions[3], s.procs[1],
        s.skills[1], s.skills[2], s.quest.weapon, s.quest.weapons[1] }
    local function resolve(label)
        if label.className == "a" or label.id == 29 then return "Z" end
        if label.className == "b" or label.id == 63 then return "A" end
        return "new:" .. label.kind
    end
    assert(Session.relabel(s, resolve) == s)
    for _, row in ipairs(rows) do assert(row.name == resolve(row.label)) end
    assert(s.motions[1].key == "b" and s.motions[2].key == "a")
    assert(s.skills[1].id == 63 and s.skills[2].id == 29)
end

function T.relabelMergesMotionRowsWithTheSameName()
    local firstLabel = { kind = "motion", className = "cMStart1", guideId = -208341008 }
    local secondLabel = { kind = "motion", className = "cMMove", guideId = 113146256 }
    local s = {
        motions = {
            { key = "5:cMStart1", label = firstLabel, damage = 20, hits = 2, share = 0.2 },
            { key = "5:cMMove", label = secondLabel, damage = 30, hits = 3, share = 0.3 },
            { key = "5:cOther", label = { kind = "motion", className = "cOther" }, damage = 40, hits = 4, share = 0.4 },
        },
    }
    Session.relabel(s, function(label)
        return label.className == "cOther" and "Other" or "Performance"
    end)
    assert(#s.motions == 2)
    local row = s.motions[1]
    assert(row.name == "Performance" and row.damage == 50 and row.hits == 5)
    assert(math.abs(row.share - 0.5) < 1e-9)
    assert(row.key == "5:cMStart1" and row.label == firstLabel)
    assert(s.motions[2].name == "Other" and s.motions[2].damage == 40)
end

function T.relabelMergedSnapshotIsIdempotent()
    Session.reset(0)
    Session.addHit(hit({ finalDamage = 60 }))
    Session.addHit(hit({ motionKey = "7:cSlash", motionLabel = { kind = "motion", className = "cSlash" }, finalDamage = 20 }))
    Session.addProc({ kind = "blast", damage = 20 })
    local s = Session.snapshot()
    local function resolve(label)
        if label.kind == "motion" or label.kind == "proc" then return "Shared name" end
        return label.kind
    end
    Session.relabel(s, resolve)
    assert(#s.motions == 1)
    assert(s.motions[1].damage == 100 and s.motions[1].hits == 3)
    assert(math.abs(s.motions[1].share - 1) < 1e-9)
    assert(s.motions[1].key == "7:cShellFire")
    assert(s.motions[1].label.className == "cShellFire")
    assert(#s.procs == 1 and s.procs[1].damage == 20 and s.procs[1].count == 1)
    local before = stubs.encode(s)
    assert(Session.relabel(s, resolve) == s)
    assert(stubs.encode(s) == before)
end

function T.relabelKeepsDistinctMotionRowsAndSortOrder()
    local s = {
        motions = {
            { key = "low", label = { kind = "motion", className = "Low" }, damage = 10, hits = 1, share = 0.1 },
            { key = "z", label = { kind = "motion", className = "Z" }, damage = 25, hits = 2, share = 0.25 },
            { key = "high", label = { kind = "motion", className = "High" }, damage = 40, hits = 4, share = 0.4 },
            { key = "a", label = { kind = "motion", className = "A" }, damage = 25, hits = 3, share = 0.25 },
        },
    }
    local expected = { s.motions[3], s.motions[4], s.motions[2], s.motions[1] }
    local before = {}
    for index, row in ipairs(expected) do
        row.name = row.label.className
        before[index] = stubs.encode(row)
    end
    Session.relabel(s)
    assert(#s.motions == #expected)
    for index, row in ipairs(s.motions) do
        assert(row == expected[index])
        assert(stubs.encode(row) == before[index])
    end
end

function T.relabelLeavesLegacyRowsAlone()
    local legacy = {
        monsters = { { name = "Saved monster" } }, motions = { { name = "Saved motion", share = 1 } },
        procs = { { name = "Saved proc" } }, skills = { { name = "Saved skill", share = 1 } },
        quest = { weapon = { name = "Saved weapon" }, weapons = { { name = "Saved weapon" } } },
    }
    local before = stubs.encode(legacy)
    Session.relabel(legacy, function() error("legacy row resolved") end)
    assert(legacy.diagnostics == nil)
    assert(stubs.encode(legacy) == before)
end

function T.defaultResolverUsesIdentifiers()
    local s = {
        monsters = { { label = { kind = "monster", emId = 26 } } },
        motions = {
            { label = { kind = "motion", className = "cActAttack", guideId = -1 }, share = 1 },
            { label = { kind = "kinsect" }, share = 0 },
        },
        procs = { { label = { kind = "proc", proc = "blast" } } },
        skills = { { label = { kind = "skill", id = "burst:stage1" }, share = 1 } },
        quest = { weapon = { label = { kind = "weapon", type = 13 } } },
    }
    Session.relabel(s)
    assert(s.monsters[1].name == "#26" and s.motions[1].name == "cActAttack")
    assert(s.motions[2].name == "kinsect" and s.procs[1].name == "blast")
    assert(s.skills[1].name == "#burst:stage1" and s.quest.weapon.name == "#13")
end

function T.relabelFiltersNewlyRejectedSkillNames()
    Session.reset(0)
    Session.addHit(hit({ activeSkills = { [29] = true, [63] = true } }))
    local s = Session.snapshot()
    Session.relabel(s, function(label)
        if label.kind == "skill" and label.id == 29 then return "#Rejected# hidden" end
        return "visible"
    end)
    assert(#s.skills == 1 and s.skills[1].id == 63)
end

function T.attributionCountersCopyAndReset()
    Session.reset(0)
    local paths = { "action", "shell:ammo:1234", "shell:cSlash", "kinsect", "slinger", "weapon-1", "lastAttack", "nonattack", "unknown", false, "shell", "weaponMinus1" }
    for _, path in ipairs(paths) do Session.addHit(hit({ attribution = path })) end
    Session.addHit(hit())
    assert(Session.addHit(hit({ attribution = "kinsect", finalDamage = 0 })) == false)
    local expected = { action = 6, shell = 2, kinsect = 1, slinger = 1, weaponMinus1 = 1, lastAttack = 1, nonattack = 1 }
    local first = Session.snapshot().diagnostics.attribution
    assert(stubs.encode(first) == stubs.encode(expected), stubs.encode(first))
    Session.addHit(hit({ attribution = "kinsect" }))
    assert(first.kinsect == 1)
    Session.addHit(hit({ attribution = "slinger" }))
    assert(first.slinger == 1 and Session.snapshot().diagnostics.attribution.slinger == 2)
    first.action = 99
    assert(Session.snapshot().diagnostics.attribution.action == 6)
    Session.reset(0)
    local zero = { action = 0, shell = 0, kinsect = 0, slinger = 0, weaponMinus1 = 0, lastAttack = 0, nonattack = 0 }
    assert(stubs.encode(Session.snapshot().diagnostics.attribution) == stubs.encode(zero))
end

function T.relabelCountsSurvivingLabelsByMergedHitCount()
    local MotionNames = require("MyHuntReport.MotionNames")
    local original = MotionNames.nameFor
    local calls = {}
    MotionNames.nameFor = function(key)
        calls[#calls + 1] = key
        return key, key == "sibling" and "sibling" or key == "unmapped" and "unmapped" or "guide"
    end
    local ok, err = pcall(function()
        local s = { diagnostics = {}, motions = {
            { key = "a", label = { kind = "motion", className = "sibling" }, hits = 2, damage = 20, share = 0.2 },
            { key = "b", label = { kind = "motion", className = "guide" }, hits = 3, damage = 30, share = 0.3 },
            { key = "c", label = { kind = "motion", className = "unmapped" }, hits = 4, damage = 40, share = 0.4 },
            { key = "d", label = { kind = "kinsect" }, hits = 7, damage = 7, share = 0.07 },
            { key = "e", label = { kind = "proc", proc = "blast" }, hits = 8, damage = 8, share = 0.08 },
            { key = "f", label = { kind = "echoWave" }, hits = 9, damage = 9, share = 0.09 },
        } }
        local function resolve(label)
            if label.className == "guide" or label.className == "sibling" then return "Merged" end
            return label.className or label.kind
        end
        Session.relabel(s, resolve)
        assert(#s.motions == 5 and #calls == 2)
        assert(s.diagnostics.names.sibling == 5 and s.diagnostics.names.unmapped == 4)
        Session.relabel(s, resolve)
        assert(s.diagnostics.names.sibling == 5 and s.diagnostics.names.unmapped == 4)
        MotionNames.nameFor = function(key) return key, "guide" end
        Session.relabel(s, resolve)
        assert(s.diagnostics.names.sibling == 0 and s.diagnostics.names.unmapped == 0)
    end)
    MotionNames.nameFor = original
    if not ok then error(err, 0) end
end

function T.attributeHitzonesIncludeEveryBucketSortedByHitsThenAttribute()
    Session.reset(0)
    assert(stubs.encode(Session.snapshot().stats.attributeHitzones) == stubs.encode({}))
    for _, entry in ipairs({ { 4, 15 }, { 3, 30 }, { 1, 20 }, { 3, 50 }, { 1, 30 }, { 4, 25 }, { 4, 35 } }) do
        Session.addHit(hit({ attribute = entry[1], attributeHitzone = entry[2] }))
    end
    for _, invalid in ipairs({
        { attribute = 5, attributeHitzone = 0 },
        { attribute = 2, attributeHitzone = 20, element = 0 },
        { attribute = 0, attributeHitzone = 20 },
        { attribute = 5 },
    }) do Session.addHit(hit(invalid)) end
    local stats = Session.snapshot().stats
    local expected = {
        { attribute = 4, avgHitzone = 25.0, hits = 3 },
        { attribute = 1, avgHitzone = 25.0, hits = 2 },
        { attribute = 3, avgHitzone = 40.0, hits = 2 },
    }
    assert(stubs.encode(stats.attributeHitzones) == stubs.encode(expected), stubs.encode(stats.attributeHitzones))
    assert(stats.attribute == 4 and stats.avgAttributeHitzone == 25)
    Session.addHit(hit({ attribute = 1, attributeHitzone = 40 }))
    assert(stubs.encode(stats.attributeHitzones) == stubs.encode(expected))
    local nextStats = Session.snapshot().stats
    assert(nextStats.attribute == 1 and nextStats.avgAttributeHitzone == 30)
    assert(nextStats.attributeHitzones[1].attribute == 1 and nextStats.attributeHitzones[1].avgHitzone == 30)
    stats.attributeHitzones[1].hits = 999
    assert(Session.snapshot().stats.attributeHitzones[2].hits == 3)
    Session.reset(0)
    assert(#Session.snapshot().stats.attributeHitzones == 0)
end

function T.fixedRidingAndSlingerRowsDoNotCountAsFallbackNames()
    local Locale = require("MyHuntReport.Locale")
    local Names = require("MyHuntReport.Names")
    local MotionNames = require("MyHuntReport.MotionNames")
    Locale.init({})
    Locale.resolve("en")
    MotionNames.reset()
    Session.reset(0)
    for _, className in ipairs({ "cPorterRideMusicLoop", "cPorterRideAddMusicLoop" }) do
        Session.addHit(hit({ motionKey = className, motionLabel = { kind = "motion", className = className, guideId = -1 } }))
    end
    Session.addHit(hit({ attribution = "slinger", motionKey = "slinger", motionLabel = { kind = "slinger" } }))
    local s = Session.snapshot({ resolveName = Names.resolve })
    assert(#s.motions == 2 and s.motions[1].name == "Mounted attack" and s.motions[1].hits == 2)
    assert(s.motions[2].name == "Slinger")
    assert(stubs.encode(s.diagnostics.names) == stubs.encode({ sibling = 0, unmapped = 0 }))
    Session.relabel(s, Names.resolve)
    assert(stubs.encode(s.diagnostics.names) == stubs.encode({ sibling = 0, unmapped = 0 }))
end

function T.relabelKeepsSnapshotsWithoutDiagnosticsDiagnosticsFree()
    local stored = { version = 2, quest = { result = "clear" }, damage = { total = 1, hits = 1 }, stats = {},
        monsters = {}, skills = {}, procs = {}, skillDamage = {},
        motions = { { label = { kind = "motion", className = "cSlash", guideId = -1 }, damage = 1, hits = 1, share = 1 } } }
    Session.relabel(stored, function(label) return label.className or label.kind end)
    assert(stored.diagnostics == nil)
    local live = Session.snapshot()
    Session.relabel(live, function(label) return label.kind end)
    assert(type(live.diagnostics.names) == "table")
end

function T.addHealRejectsInvalidInput()
    Session.reset(0)
    assert(Session.addHeal({ kind = "hastenRecovery", amount = 0, maxHp = 150 }) == false)
    assert(Session.addHeal({ kind = "hastenRecovery", amount = 5, maxHp = 0 }) == false)
    assert(Session.addHeal({ kind = "potion", amount = 5, maxHp = 150 }) == false)
    assert(Session.addHeal({ kind = "superRecovery", amount = "x", maxHp = 150 }) == false)
    assert(#Session.snapshot().skills == 0)
end

function T.addHealAccumulatesShareAtEachMaxHp()
    Session.reset(0)
    assert(Session.addHeal({ kind = "hastenRecovery", amount = 15, maxHp = 150 }) == true)
    assert(Session.addHeal({ kind = "hastenRecovery", amount = 20, maxHp = 200 }) == true)
    local rows = Session.snapshot().skills
    assert(#rows == 1, #rows)
    assert(rows[1].label.kind == "heal" and rows[1].label.heal == "hastenRecovery")
    assert(math.abs(rows[1].share - 0.2) < 1e-9, rows[1].share)
    assert(rows[1].valueKind == "hp" and rows[1].id == nil)
    assert(rows[1].name == "hastenRecovery")
end

function T.healRowsFollowUptimeRowsInKindOrder()
    Session.reset(0)
    Session.addHit(hit({ activeSkills = { [59] = true }, weight = 10 }))
    Session.addHeal({ kind = "superRecovery", amount = 3, maxHp = 150 })
    Session.addHeal({ kind = "hastenRecovery", amount = 30, maxHp = 150 })
    local rows = Session.snapshot({ equippedSkills = { { id = 59 } } }).skills
    assert(#rows == 3, #rows)
    assert(rows[1].id == 59)
    assert(rows[2].label.heal == "hastenRecovery" and math.abs(rows[2].share - 0.2) < 1e-9)
    assert(rows[3].label.heal == "superRecovery" and math.abs(rows[3].share - 0.02) < 1e-9)
end

function T.healSharesCanExceedOneAndResetClearsThem()
    Session.reset(0)
    Session.addHeal({ kind = "superRecovery", amount = 300, maxHp = 150 })
    assert(math.abs(Session.snapshot().skills[1].share - 2) < 1e-9)
    Session.reset(0)
    assert(#Session.snapshot().skills == 0)
end

function T.healOnlySessionHasNoDamageData()
    Session.reset(0)
    Session.addHeal({ kind = "superRecovery", amount = 3, maxHp = 150 })
    assert(Session.hasData() == false)
end

function T.relabelKeepsHigherHealSharesAfterSortedUptimeRows()
    Session.reset(0)
    Session.addHit(hit({ activeSkills = { [59] = true, [65] = true }, weight = 10 }))
    Session.addHit(hit({ activeSkills = { [59] = true }, weight = 30 }))
    Session.addHeal({ kind = "superRecovery", amount = 90, maxHp = 150 })
    Session.addHeal({ kind = "hastenRecovery", amount = 15, maxHp = 150 })
    local snapshot = Session.snapshot({ equippedSkills = { { id = 59 }, { id = 65 } } })
    local rows = snapshot.skills
    assert(#rows == 4, #rows)
    assert(rows[1].id == 59 and math.abs(rows[1].share - 1) < 1e-9)
    assert(rows[2].id == 65 and math.abs(rows[2].share - 0.25) < 1e-9)
    assert(rows[3].label.heal == "hastenRecovery" and math.abs(rows[3].share - 0.1) < 1e-9)
    assert(rows[4].label.heal == "superRecovery" and math.abs(rows[4].share - 0.6) < 1e-9)
    Session.relabel(snapshot)
    assert(snapshot.skills[1].id == 59 and snapshot.skills[2].id == 65)
    assert(snapshot.skills[3].label.heal == "hastenRecovery" and snapshot.skills[4].label.heal == "superRecovery")
end

return T
