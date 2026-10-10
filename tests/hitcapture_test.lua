local stubs = require("stubs")
local HitCapture = require("MyHuntReport.HitCapture")
local Game = require("MyHuntReport.Game")
local Session = require("MyHuntReport.Session")
local SkillState = require("MyHuntReport.SkillState")
local SkillExtras = require("MyHuntReport.SkillExtras")

local T = {}

local function enemy(uniqueIndex)
    return {
        get_IsBoss = function() return true end,
        get_UniqueIndex = function() return uniqueIndex end,
        get_EmID = function() return 26 end,
        get_RoleID = function() return 0 end,
        get_LegendaryID = function() return 0 end,
    }
end

local function hitInfo(address, ownerAddress, attackOverrides, uniqueIndex, attackObj)
    local em = enemy(uniqueIndex or 10)
    local attackData = { _OriginalAttackAdjust = 30, _ActionType = 1, _WeaponType = 7, _UseSkillAdditionalDamage = false }
    for key, value in pairs(attackOverrides or {}) do attackData[key] = value end
    return {
        get_AttackData = function() return attackData end,
        getActualAttackOwner = function()
            return { get_address = function() return ownerAddress end }
        end,
        get_DamageOwner = function() return { em = em } end,
        get_AttackObj = function() return attackObj end,
        get_address = function() return address end,
    }
end

local function meat(physical, elements)
    local m = { _Fire = 0, _Water = 0, _Thunder = 0, _Ice = 0, _Dragon = 0 }
    for key, value in pairs(elements or {}) do m[key] = value end
    m.getActionMeat = function(_, actionType) return physical end
    return m
end

local function fakeThis(hitMeat, baseMeat, uniqueIndex, scarState)
    local meats = { [3] = hitMeat, [4] = baseMeat }
    local paramParts = {
        _MeatArray = { _DataArray = meats },
        _PartsArray = { _DataArray = { [0] = { getPartsMeatGuid = function() return "guid" end } } },
        getMeatIndex = function() return { _Value = 4 } end,
    }
    local em = enemy(uniqueIndex or 10)
    em.Scar = { _ScarParts = { Get = function(_, index)
        assert(index == 0)
        return { get_State = function() return scarState end }
    end } }
    em.Parts = { _ParamParts = paramParts, _DmgParts = { [0] = { get_MeatSlot = function() return 0 end } } }
    return { get_Context = function() return { get_Em = function() return em end } end }
end

local function preCalc(actionType, overrides)
    local p = { ActionType = actionType, Attack = 100, FixAttack = 0, AttrValue = 30, AttackAttr = 1,
        Common = { MeatIndex = { _Value = 3 }, PartsIndex = 0, ScarIndex = -1 } }
    for key, value in pairs(overrides or {}) do p[key] = value end
    return p
end

local function withCapture(callback)
    HitCapture.reset()
    Session.reset(0)
    SkillExtras.reset()
    local masterAddress, enemyContext, addHit = Game.masterAddress, Game.enemyContext, Session.addHit
    local enemyIsDead = Game.enemyIsDead
    local hits = {}
    Game.masterAddress = function() return 1 end
    Game.enemyContext = function(go) return go.em end
    Game.enemyIsDead = function(go) return go.dead == true end
    Session.addHit = function(hit)
        hits[#hits + 1] = hit
        return addHit(hit)
    end
    local ok, err = pcall(callback, hits)
    Game.masterAddress, Game.enemyContext, Session.addHit = masterAddress, enemyContext, addHit
    Game.enemyIsDead = enemyIsDead
    HitCapture.reset()
    SkillExtras.reset()
    if not ok then error(err, 0) end
end

local function complete(info, calc)
    HitCapture.handlePlayHitMarkEffect(calc or { FinalDamage = 100, Physical = 100, Element = 0 }, info)
end

function T.excludedHitDoesNotConsumeStalePending()
    withCapture(function(hits)
        local hitInfoA, hitInfoB = hitInfo(101, 1), hitInfo(102, 2)
        HitCapture.handleStockDamageDetail(hitInfoA)
        HitCapture.handleStockDamageDetail(hitInfoB)
        complete(hitInfoB, { FinalDamage = 999, Physical = 999, Element = 0 })
        assert(#hits == 0 and Session.hitCount() == 0)
        assert(Session.snapshot().diagnostics.droppedPending == 1)
    end)
end

function T.mismatchedHitInfoDropsPending()
    withCapture(function(hits)
        local hitInfoA, hitInfoC = hitInfo(101, 1), hitInfo(103, 1)
        HitCapture.handleStockDamageDetail(hitInfoA)
        complete(hitInfoC, { FinalDamage = 999, Physical = 999, Element = 0 })
        assert(#hits == 0 and Session.hitCount() == 0)
        assert(Session.snapshot().diagnostics.droppedPending == 1)
    end)
end

function T.hitOnDeadEnemyIsIgnored()
    withCapture(function(hits)
        local info = hitInfo(101, 1)
        local owner = info.get_DamageOwner()
        owner.dead = true
        info.get_DamageOwner = function() return owner end
        HitCapture.handleStockDamageDetail(info)
        assert(HitCapture.pendingCount() == 0)
        complete(info, { FinalDamage = 50, Physical = 50, Element = 0 })
        assert(#hits == 0 and Session.hitCount() == 0)
        assert(Session.snapshot().diagnostics.droppedPending == 0)
    end)
end

function T.masterBossHitIsRecorded()
    withCapture(function(hits)
        local hitInfoA = hitInfo(101, 1)
        HitCapture.handleStockDamageDetail(hitInfoA)
        complete(hitInfoA)
        assert(#hits == 1 and Session.hitCount() == 1)
        assert(hits[1].finalDamage == 100 and hits[1].weight == 30)
        assert(hits[1].weaponType == 7, "weaponType " .. tostring(hits[1].weaponType))
        assert(Session.snapshot().diagnostics.weightFallbacks == 1)
    end)
end

function T.fixedTypeUsesMotionValue()
    local weight, fallback = HitCapture.weightFor(11.25, 0, 0)
    assert(weight == 11.25 and fallback == false)
    weight, fallback = HitCapture.weightFor(47, 0, nil)
    assert(weight == 47 and fallback == false)
end

function T.hitzoneScalesMotionValue()
    local weight, fallback = HitCapture.weightFor(30, 2, 80)
    assert(weight == 24 and fallback == false)
end

function T.missingHitzoneFallsBack()
    local weight, fallback = HitCapture.weightFor(30, 1, nil)
    assert(weight == 30 and fallback == true)
    weight, fallback = HitCapture.weightFor(nil, 1, nil)
    assert(weight == 0 and fallback == true)
end

function T.motionKeyJoinsWeaponAndName()
    assert(HitCapture.motionKey(7, "cShellFire") == "7:cShellFire")
    assert(HitCapture.motionKey(13, "ammo:1234") == "13:ammo:1234")
    assert(HitCapture.motionKey(12, "ammo:1234") == "12:ammo:1234")
    assert(HitCapture.motionKey(13, "ammo:1234:rapid") == "13:ammo:1234:rapid")
    assert(HitCapture.motionKey(13, "ammo:1234:776922048") == "13:ammo:1234:776922048")
end

function T.resetClearsWeaponType()
    HitCapture.reset()
    assert(HitCapture.lastWeaponType() == nil)
    assert(HitCapture.pendingCount() == 0)
end

function T.weaponChangesRefreshBeforeSkillCreditInEveryPhase()
    local Quest = require("MyHuntReport.Quest")
    local refresh, masterHunter, phase = SkillState.refreshEquipped, Game.masterHunter, Quest.phase
    local equipment = { [56] = true }
    local refreshes = 0
    local info = { get_type_definition = function()
        return { get_fields = function() return {} end, get_parent_type = function() return nil end }
    end }
    Game.masterHunter = function()
        return { get_HunterSkill = function()
            return { _HunterSkillParamInfo = info, checkSkillActive = function(_, id) return equipment[id] == true end }
        end }
    end
    SkillState.refreshEquipped = function()
        refreshes = refreshes + 1
        return refresh()
    end
    local ok, err = pcall(function()
        for _, currentPhase in ipairs({ "idle", "playing", "training", "result" }) do
            Quest.phase = function() return currentPhase end
            equipment[56], equipment[63] = true, nil
            SkillState.reset()
            refresh()
            refreshes = 0
            withCapture(function(hits)
                local function hit(weaponType)
                    local h = hitInfo(100 + #hits, 1, { _WeaponType = weaponType, _IsSkillHien = true }, 10,
                        { get_Name = function() return weaponType == -1 and "it1003_test" or "weapon" end })
                    HitCapture.handleStockDamageDetail(h)
                    HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45)), preCalc(1), { Hide = 1.0 })
                    complete(h)
                end
                hit(-1)
                assert(refreshes == 0 and HitCapture.lastWeaponType() == nil)
                hit(7)
                assert(refreshes == 0 and HitCapture.lastWeaponType() == 7)
                assert(hits[2].activeSkills[56] == true)
                equipment[56], equipment[63] = nil, true
                hit(7)
                assert(refreshes == 0 and hits[3].activeSkills[56] == true and hits[3].activeSkills[63] == nil)
                hit(10)
                assert(refreshes == 1 and HitCapture.lastWeaponType() == 10)
                assert(hits[4].activeSkills[56] == nil and hits[4].activeSkills[63] == true)
                hit(-1)
                hit(10)
                assert(refreshes == 1 and HitCapture.lastWeaponType() == 10)
                local snapshot = Session.snapshot({ equippedSkills = SkillState.equippedTracked() })
                assert(#snapshot.skills == 2)
                local weights = {}
                for _, row in ipairs(snapshot.skills) do weights[row.id] = row.weight end
                assert(weights[56] > 0 and weights[63] > 0)
                assert(#hits == 6 and Session.hitCount() == 6 and HitCapture.pendingCount() == 0)
                assert(snapshot.diagnostics.droppedPending == 0)
                HitCapture.reset()
                hit(7)
                assert(refreshes == 1 and HitCapture.lastWeaponType() == 7)
                hit(10)
                assert(refreshes == 2)
            end)
        end
    end)
    SkillState.refreshEquipped, Game.masterHunter, Quest.phase = refresh, masterHunter, phase
    SkillState.reset()
    if not ok then error(err, 0) end
end

function T.weaponRefreshFailureKeepsCurrentHitAndUpdatesWeaponType()
    local refresh, activeSet = SkillState.refreshEquipped, SkillState.activeSet
    local calls = 0
    SkillState.refreshEquipped = function()
        calls = calls + 1
        error("refresh unavailable")
    end
    SkillState.activeSet = function() return { [56] = true } end
    local ok, err = pcall(function()
        withCapture(function(hits)
            for index, weaponType in ipairs({ 7, 10, 10 }) do
                local info = hitInfo(100 + index, 1, { _WeaponType = weaponType })
                HitCapture.handleStockDamageDetail(info)
                assert(HitCapture.pendingCount() == 1)
                complete(info)
                assert(#hits == index and hits[index].activeSkills[56] == true)
            end
            assert(calls == 1 and HitCapture.lastWeaponType() == 10)
            assert(Session.hitCount() == 3 and Session.snapshot().damage.total == 300)
            assert(Session.snapshot().diagnostics.droppedPending == 0)
            assert(HitCapture.pendingCount() == 0)
        end)
    end)
    SkillState.refreshEquipped, SkillState.activeSet = refresh, activeSet
    if not ok then error(err, 0) end
end

function T.isFixedRule()
    assert(HitCapture.isFixed(0, 1.0) == true)
    assert(HitCapture.isFixed(1, 1.5) == true)
    assert(HitCapture.isFixed(1, 1.0) == false)
    assert(HitCapture.isFixed(1, nil) == false)
end

function T.fixedByHideRateMovesPhysical()
    withCapture(function(hits)
        local info = hitInfo(101, 1)
        HitCapture.handleStockDamageDetail(info)
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45)), preCalc(1), { Hide = 1.5 })
        complete(info)
        assert(#hits == 1 and hits[1].fixed == true)
        assert(Session.snapshot().damage.fixed == 100)
    end)
end

function T.normalRateIsNotFixed()
    withCapture(function(hits)
        local info = hitInfo(101, 1)
        HitCapture.handleStockDamageDetail(info)
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45)), preCalc(1), { Hide = 1.0 })
        complete(info)
        assert(hits[1].fixed == false)
    end)
end

function T.critFieldsPassThrough()
    withCapture(function(hits)
        local info = hitInfo(101, 1, { _CriticaType = 1, _IsNoCritical = false, _SpecialType = 3 })
        HitCapture.handleStockDamageDetail(info)
        complete(info)
        assert(hits[1].critType == 1 and hits[1].canCrit == true and hits[1].specialType == 3)
        local noCrit = hitInfo(102, 1, { _CriticaType = 0, _IsNoCritical = true })
        HitCapture.handleStockDamageDetail(noCrit)
        complete(noCrit)
        assert(hits[2].canCrit == false)
    end)
end

function T.unwoundedHitzoneAndAttributeAreRead()
    withCapture(function(hits)
        local info = hitInfo(101, 1)
        HitCapture.handleStockDamageDetail(info)
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45, { _Fire = 20 })), preCalc(1), { Hide = 1.0 })
        complete(info, { FinalDamage = 100, Physical = 80, Element = 20 })
        assert(hits[1].hitzone == 60 and hits[1].baseHitzone == 45, tostring(hits[1].baseHitzone))
        assert(hits[1].attribute == 1 and hits[1].attributeHitzone == 20)
    end)
end

function T.attributeIsZeroWhenAttackAttrIsZero()
    withCapture(function(hits)
        local info = hitInfo(101, 1)
        HitCapture.handleStockDamageDetail(info)
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45, { _Fire = 20 })), preCalc(1, { AttackAttr = 0 }), { Hide = 1.0 })
        complete(info, { FinalDamage = 100, Physical = 80, Element = 20 })
        assert(hits[1].attribute == 0 and hits[1].attributeHitzone == nil)
    end)
end

function T.zeroAttackClearsPending()
    withCapture(function(hits)
        local info = hitInfo(101, 1)
        HitCapture.handleStockDamageDetail(info)
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45)), preCalc(1, { Attack = 0, AttrValue = 0 }), { Hide = 1.0 })
        assert(HitCapture.pendingCount() == 0)
        complete(info)
        assert(#hits == 0 and Session.snapshot().diagnostics.droppedPending == 0)
    end)
end

function T.interleavedHitsOnDifferentMonstersAreBothRecorded()
    withCapture(function(hits)
        local kinsect = hitInfo(101, 1, { _WeaponType = -1, _ActionType = 2 }, 20,
            { get_Name = function() return "it1003_test" end })
        local glaive = hitInfo(102, 1, {}, 10)
        HitCapture.handleStockDamageDetail(kinsect)
        HitCapture.handleStockDamageDetail(glaive)
        assert(HitCapture.pendingCount() == 2)
        HitCapture.handleCalcStockDamage(fakeThis(meat(70), meat(70), 20), preCalc(2), { Hide = 1.0 })
        HitCapture.handleCalcStockDamage(fakeThis(meat(28), meat(28), 10), preCalc(1), { Hide = 1.0 })
        complete(kinsect, { FinalDamage = 21, Physical = 21, Element = 0 })
        complete(glaive, { FinalDamage = 90, Physical = 90, Element = 0 })
        assert(#hits == 2, tostring(#hits))
        assert(hits[1].monsterId == 20 and hits[1].hitzone == 70 and hits[1].finalDamage == 21)
        assert(hits[2].monsterId == 10 and hits[2].hitzone == 28 and hits[2].finalDamage == 90)
        assert(Session.snapshot().diagnostics.droppedPending == 0)
        assert(HitCapture.pendingCount() == 0)
    end)
end

function T.sameMonsterSecondHitDropsTheFirst()
    withCapture(function(hits)
        local first, second = hitInfo(101, 1, {}, 10), hitInfo(102, 1, {}, 10)
        HitCapture.handleStockDamageDetail(first)
        HitCapture.handleStockDamageDetail(second)
        assert(HitCapture.pendingCount() == 1)
        complete(second)
        assert(#hits == 1 and hits[1].finalDamage == 100)
        assert(Session.snapshot().diagnostics.droppedPending == 1)
    end)
end

local function additionalArray(entries)
    local array = { get_Count = function() return #entries end }
    for i, entry in ipairs(entries) do array[i - 1] = entry end
    return { _Array = array }
end

function T.unmappedAdditionalDamageLogsOnlyInDeveloperMode()
    local Log = require("MyHuntReport.Log")
    local developerMode = Log.isDeveloperMode()
    local attackData = { _UseSkillAdditionalDamage = true, _SkillAdditinalDamageArray = additionalArray({
        { _SkillType = 999, _Damage = 30, _Attr = 0 },
        { _SkillType = 0, _Damage = 30, _Attr = 0 },
        { _SkillType = 998, _Damage = 0, _Attr = 0 },
        { _SkillType = 997, _Damage = -30, _Attr = 0 },
    }) }
    Log.resetCounts()
    local ok, err = pcall(function()
        Log.setDeveloperMode(false)
        assert(#HitCapture.readAttackStats(attackData).extras == 0)
        assert(#stubs.logLines == 0)
        Log.setDeveloperMode(true)
        assert(#HitCapture.readAttackStats(attackData).extras == 0)
        assert(#stubs.logLines == 1)
        assert(stubs.logLines[1]:find("unmapped skill additional damage sid=999 dmg=30 attr=0", 1, true))
        assert(Log.count("extra:unmapped:999") == 1)
    end)
    Log.setDeveloperMode(developerMode)
    Log.resetCounts()
    if not ok then error(err, 0) end
end

function T.violentAdditionalArrayEntryIsMappedWithoutDiagnostic()
    local Log = require("MyHuntReport.Log")
    local developerMode = Log.isDeveloperMode()
    Log.setDeveloperMode(true)
    Log.resetCounts()
    local ok, err = pcall(function()
        local attackData = { _UseSkillAdditionalDamage = true, _SkillAdditinalDamageArray = additionalArray({
            { _SkillType = 155, _Damage = 45, _Attr = 0 },
        }) }
        local stats = HitCapture.readAttackStats(attackData)
        assert(stubs.encode(stats.extras) == stubs.encode({ { kind = "violent", damage = 45 } }))
        assert(#stubs.logLines == 0 and Log.count("extra:unmapped:155") == 0)
        withCapture(function(hits)
            local info = hitInfo(101, 1, attackData)
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(stubs.encode(hits[1].skillExtras) == stubs.encode({ { kind = "violent", damage = 45 } }))
            assert(Session.snapshot().skillDamage[1].damage == 45)
        end)
    end)
    Log.setDeveloperMode(developerMode)
    Log.resetCounts()
    if not ok then error(err, 0) end
end

function T.specialTypeDiagnosticSkipsShellingAndMappedKinds()
    local Log = require("MyHuntReport.Log")
    local developerMode = Log.isDeveloperMode()
    Log.setDeveloperMode(true)
    Log.resetCounts()
    local ok, err = pcall(function()
        for _, kind in ipairs({ 6, 11, 12 }) do
            HitCapture.readAttackStats({ _SpecialType = kind }, nil, 100)
            assert(Log.count("special:" .. kind) == 0)
        end
        assert(#stubs.logLines == 0)
        HitCapture.readAttackStats({ _SpecialType = 9 }, nil, 100)
        assert(#stubs.logLines == 1 and stubs.logLines[1]:find("special type 9", 1, true))
        assert(Log.count("special:9") == 1)
        Log.setDeveloperMode(false)
        HitCapture.readAttackStats({ _SpecialType = 9 }, nil, 100)
        assert(#stubs.logLines == 1)
    end)
    Log.setDeveloperMode(developerMode)
    Log.resetCounts()
    if not ok then error(err, 0) end
end

function T.additionalArrayExtrasScaleByElementHitzone()
    withCapture(function(hits)
        local info = hitInfo(101, 1, { _UseSkillAdditionalDamage = true, _SkillAdditinalDamageArray = additionalArray({
            { _SkillType = 157, _Damage = 20, _Attr = 0 },
            { _SkillType = 157, _Damage = 60, _Attr = 1 },
            { _SkillType = 214, _Damage = 40, _Attr = 3 },
            { _SkillType = 0, _Damage = 0, _Attr = 0 },
        }) })
        HitCapture.handleStockDamageDetail(info)
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45, { _Fire = 20 })), preCalc(1), { Hide = 1.0 })
        complete(info)
        local extras = hits[1].skillExtras
        assert(#extras == 1, tostring(#extras))
        assert(extras[1].kind == "flare" and math.abs(extras[1].damage - 32) < 1e-9, tostring(extras[1].damage))
        assert(extras[2] == nil)
    end)
end

function T.additionalArrayIgnoredWithoutUseAdd()
    withCapture(function(hits)
        local info = hitInfo(101, 1, { _UseSkillAdditionalDamage = false, _SkillAdditinalDamageArray = additionalArray({
            { _SkillType = 157, _Damage = 20, _Attr = 0 },
        }) })
        HitCapture.handleStockDamageDetail(info)
        complete(info)
        assert(#hits[1].skillExtras == 0)
    end)
end

function T.specialTypeAddsWholeHit()
    withCapture(function(hits)
        local info = hitInfo(101, 1, { _SpecialType = 11 })
        HitCapture.handleStockDamageDetail(info)
        complete(info, { FinalDamage = 70, Physical = 70, Element = 0 })
        assert(#hits[1].skillExtras == 1 and hits[1].skillExtras[1].kind == "darkWave" and hits[1].skillExtras[1].damage == 70)
        local mirror = hitInfo(102, 1, { _SpecialType = 12 })
        HitCapture.handleStockDamageDetail(mirror)
        complete(mirror, { FinalDamage = 30, Physical = 30, Element = 0 })
        assert(hits[2].skillExtras[1].kind == "mirrorBlade" and hits[2].skillExtras[1].damage == 30)
    end)
end

function T.pendingSkillExtrasAttachToUseAddHitOnce()
    withCapture(function(hits)
        SkillExtras.enter(true)
        SkillExtras.record("ryukiExplosion", 30)
        SkillExtras.leave()
        local info = hitInfo(101, 1, { _UseSkillAdditionalDamage = true })
        HitCapture.handleStockDamageDetail(info)
        assert(SkillExtras.pendingCount() == 0)
        complete(info)
        assert(#hits[1].skillExtras == 1 and hits[1].skillExtras[1].kind == "ryukiExplosion" and hits[1].skillExtras[1].damage == 30)
        local next_ = hitInfo(102, 1, { _UseSkillAdditionalDamage = true })
        HitCapture.handleStockDamageDetail(next_)
        complete(next_)
        assert(#hits[2].skillExtras == 0)
    end)
end

function T.hitWithoutUseAddLeavesSkillExtrasPending()
    withCapture(function(hits)
        SkillExtras.enter(true)
        SkillExtras.record("ryukiExplosion", 30)
        SkillExtras.leave()
        local kinsect = hitInfo(101, 1, { _WeaponType = -1, _ActionType = 2 }, 20)
        HitCapture.handleStockDamageDetail(kinsect)
        assert(SkillExtras.pendingCount() == 1)
        complete(kinsect, { FinalDamage = 21, Physical = 21, Element = 0 })
        assert(#hits[1].skillExtras == 0 and SkillExtras.pendingCount() == 1)
        local glaive = hitInfo(102, 1, { _UseSkillAdditionalDamage = true }, 10)
        HitCapture.handleStockDamageDetail(glaive)
        assert(SkillExtras.pendingCount() == 0)
        complete(glaive)
        assert(#hits[2].skillExtras == 1 and hits[2].skillExtras[1].kind == "ryukiExplosion")
    end)
end

function T.droppedUseAddHitClearsSkillExtras()
    withCapture(function(hits)
        SkillExtras.enter(true)
        SkillExtras.record("ryukiExplosion", 30)
        SkillExtras.leave()
        local info = hitInfo(101, 1, { _UseSkillAdditionalDamage = true })
        HitCapture.handleStockDamageDetail(info)
        assert(SkillExtras.pendingCount() == 0)
        complete(info, { FinalDamage = 0, Physical = 0, Element = 0 })
        assert(#hits == 0 and SkillExtras.pendingCount() == 0)
        local next_ = hitInfo(102, 1, { _UseSkillAdditionalDamage = true })
        HitCapture.handleStockDamageDetail(next_)
        complete(next_)
        assert(#hits == 1 and #hits[1].skillExtras == 0)
    end)
end

function T.zeroAttackDropDiscardsSkillExtras()
    withCapture(function(hits)
        SkillExtras.enter(true)
        SkillExtras.record("ryukiExplosion", 30)
        SkillExtras.leave()
        local info = hitInfo(101, 1, { _UseSkillAdditionalDamage = true })
        HitCapture.handleStockDamageDetail(info)
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45)),
            preCalc(1, { Attack = 0, FixAttack = 0, AttrValue = 0 }), { Hide = 1.0 })
        assert(HitCapture.pendingCount() == 0)
        complete(info)
        assert(#hits == 0)
        SkillExtras.enter(true)
        assert(SkillExtras.record("ryukiExplosion", 0) == false)
        SkillExtras.leave()
        local next_ = hitInfo(102, 1, { _UseSkillAdditionalDamage = true })
        HitCapture.handleStockDamageDetail(next_)
        complete(next_)
        assert(#hits == 1 and #hits[1].skillExtras == 0)
        assert(SkillExtras.pendingCount() == 0)
    end)
end

function T.storedSkillExtrasMustBeBelowPhysical()
    withCapture(function(hits)
        SkillExtras.enter(true)
        SkillExtras.record("testExtra", 100)
        SkillExtras.record("ryukiExplosion", 20)
        SkillExtras.leave()
        local info = hitInfo(101, 1, { _UseSkillAdditionalDamage = true })
        HitCapture.handleStockDamageDetail(info)
        complete(info, { FinalDamage = 100, Physical = 100, Element = 0 })
        assert(#hits[1].skillExtras == 1 and hits[1].skillExtras[1].kind == "ryukiExplosion")
        assert(SkillExtras.pendingCount() == 0)
    end)
end

function T.interleavedHitsKeepTheirOwnSkillExtras()
    withCapture(function(hits)
        SkillExtras.enter(true)
        SkillExtras.record("ryukiExplosion", 30)
        SkillExtras.leave()
        local first = hitInfo(101, 1, { _UseSkillAdditionalDamage = true }, 10)
        HitCapture.handleStockDamageDetail(first)
        SkillExtras.enter(true)
        SkillExtras.record("ryukiExplosion", 45)
        SkillExtras.leave()
        local second = hitInfo(102, 1, { _UseSkillAdditionalDamage = true }, 20)
        HitCapture.handleStockDamageDetail(second)
        complete(first)
        complete(second)
        assert(#hits == 2)
        assert(#hits[1].skillExtras == 1 and hits[1].skillExtras[1].damage == 30)
        assert(#hits[2].skillExtras == 1 and hits[2].skillExtras[1].damage == 45)
        assert(SkillExtras.pendingCount() == 0)
    end)
end

function T.invalidCompletionDiscardsSkillExtras()
    for _, mismatch in ipairs({ false, true }) do
        withCapture(function(hits)
            SkillExtras.enter(true)
            SkillExtras.record("ryukiExplosion", 30)
            SkillExtras.leave()
            local info = hitInfo(101, 1, { _UseSkillAdditionalDamage = true })
            HitCapture.handleStockDamageDetail(info)
            if mismatch then
                complete(hitInfo(103, 1))
            else
                HitCapture.handlePlayHitMarkEffect(nil, info)
            end
            assert(#hits == 0 and HitCapture.pendingCount() == 0)
            assert(SkillExtras.pendingCount() == 0)
            local next_ = hitInfo(102, 1, { _UseSkillAdditionalDamage = true })
            HitCapture.handleStockDamageDetail(next_)
            complete(next_)
            assert(#hits == 1 and #hits[1].skillExtras == 0)
        end)
    end
end

function T.monsterLabelCarriesEnemyIdWithoutResolvingText()
    local originalCall = Game.callStatic
    local ok, err = pcall(function()
        Game.callStatic = function(typeName, ...)
            assert(typeName ~= "app.EnemyDef", "monster names must resolve at snapshot time")
            return originalCall(typeName, ...)
        end
        withCapture(function(hits)
            local info = hitInfo(1, 1)
            local em = info:get_DamageOwner().em
            em.get_RoleID = function() return 3 end
            em.get_LegendaryID = function() return 2 end
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(hits[1].monsterLabel.kind == "monster" and hits[1].monsterLabel.emId == 26)
            assert(hits[1].monsterLabel.roleId == 3 and hits[1].monsterLabel.legendaryId == 2)
            assert(hits[1].monsterName == nil)
        end)
    end)
    Game.callStatic = originalCall
    if not ok then error(err, 0) end
end

function T.variantGetterFailureKeepsHitAndDefaultsBothIds()
    for _, getter in ipairs({ "get_RoleID", "get_LegendaryID" }) do
        withCapture(function(hits)
            local info = hitInfo(1, 1)
            local em = info:get_DamageOwner().em
            em.get_RoleID = function() return 3 end
            em.get_LegendaryID = function() return 2 end
            em[getter] = function() error("getter unavailable") end
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1 and Session.hitCount() == 1)
            assert(hits[1].finalDamage == 100)
            assert(hits[1].monsterLabel.emId == 26)
            assert(hits[1].monsterLabel.roleId == 0 and hits[1].monsterLabel.legendaryId == 0)
        end)
    end
end

function T.motionRowCarriesGuideIdAndClassKey()
    local ShellTracker = require("MyHuntReport.ShellTracker")
    local originalCurrent = ShellTracker.currentAction
    local ok, err = pcall(function()
        ShellTracker.currentAction = function() return "cAttackHigh", 9328 end
        withCapture(function(hits)
            local info = hitInfo(1, 1)
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(hits[1].motionKey == "7:cAttackHigh", hits[1].motionKey)
            assert(hits[1].motionLabel.kind == "motion" and hits[1].motionLabel.className == "cAttackHigh")
            assert(hits[1].motionLabel.guideId == 9328 and hits[1].motionLabel.itemId == nil)
            assert(hits[1].motionName == nil)
        end)
    end)
    ShellTracker.currentAction = originalCurrent
    if not ok then error(err, 0) end
end

local function withLongSwordAction(className, guideId, getHandling, callback)
    local ShellTracker = require("MyHuntReport.ShellTracker")
    local originalCurrent, originalHunter = ShellTracker.currentAction, Game.masterHunter
    local ok, err = pcall(function()
        ShellTracker.currentAction = function() return className, guideId end
        Game.masterHunter = function() return { get_WeaponHandling = getHandling } end
        withCapture(callback)
    end)
    ShellTracker.currentAction, Game.masterHunter = originalCurrent, originalHunter
    if not ok then error(err, 0) end
end

function T.redAuraRemapsLongSwordSlashes()
    for _, case in ipairs({
        { "cSlash1", -1997082496, 1927826048 },
        { "cWpMoveOn", -1997082496, 1927826048 },
        { "cSlash2", 1472591744, 850992256 },
        { "cSlash3", -1065507968, -1171603968 },
    }) do
        withLongSwordAction(case[1], case[2], function()
            return { ["<AuraLevel>k__BackingField"] = 4 }
        end, function(hits)
            local info = hitInfo(1, 1, { _WeaponType = 3 })
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1)
            assert(hits[1].motionKey == "3:" .. case[1] .. ":crimson", hits[1].motionKey)
            assert(hits[1].motionLabel.kind == "motion")
            assert(hits[1].motionLabel.className == case[1])
            assert(hits[1].motionLabel.guideId == case[3])
        end)
    end
end

function T.nonRedAuraKeepsOrdinaryLongSwordSlash()
    withLongSwordAction("cSlash1", -1997082496, function()
        return { ["<AuraLevel>k__BackingField"] = 3 }
    end, function(hits)
        local info = hitInfo(1, 1, { _WeaponType = 3 })
        HitCapture.handleStockDamageDetail(info)
        complete(info)
        assert(#hits == 1)
        assert(hits[1].motionKey == "3:cSlash1", hits[1].motionKey)
        assert(hits[1].motionLabel.kind == "motion" and hits[1].motionLabel.className == "cSlash1")
        assert(hits[1].motionLabel.guideId == -1997082496)
    end)
end

function T.unrelatedActionsSkipLongSwordAuraRead()
    for _, case in ipairs({ { 3, 9328 }, { 7, -1997082496 } }) do
        local reads = 0
        withLongSwordAction("cSlash1", case[2], function()
            reads = reads + 1
            return { ["<AuraLevel>k__BackingField"] = 4 }
        end, function(hits)
            local info = hitInfo(1, 1, { _WeaponType = case[1] })
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1 and reads == 0)
            assert(hits[1].motionKey == tostring(case[1]) .. ":cSlash1", hits[1].motionKey)
            assert(hits[1].motionLabel.kind == "motion" and hits[1].motionLabel.className == "cSlash1")
            assert(hits[1].motionLabel.guideId == case[2])
        end)
    end
end

function T.failedHandlingReadKeepsOrdinaryLongSwordSlash()
    for _, getHandling in ipairs({
        function() error("handling unavailable") end,
        function() return nil end,
    }) do
        withLongSwordAction("cSlash1", -1997082496, getHandling, function(hits)
            local info = hitInfo(1, 1, { _WeaponType = 3 })
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1)
            assert(hits[1].motionKey == "3:cSlash1", hits[1].motionKey)
            assert(hits[1].motionLabel.kind == "motion" and hits[1].motionLabel.className == "cSlash1")
            assert(hits[1].motionLabel.guideId == -1997082496)
        end)
    end
end

function T.motionLabelUsesShellLaunchEntry()
    local ShellTracker = require("MyHuntReport.ShellTracker")
    local original = ShellTracker.nameForAttackObject
    local label = { kind = "motion", className = "cShootRapidLight", guideId = 4001, itemId = 1234, itemRole = "ammo" }
    local ok, err = pcall(function()
        ShellTracker.nameForAttackObject = function(object)
            assert(object == "shell")
            return "ammo:1234", label
        end
        withCapture(function(hits)
            local info = hitInfo(1, 1, { _WeaponType = 13 })
            info.get_AttackObj = function() return "shell" end
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(hits[1].motionKey == "13:ammo:1234")
            assert(hits[1].attribution == "shell:ammo:1234")
            assert(hits[1].motionLabel == label)
            label.weaponType = 11
            local blast = hitInfo(2, 1, { _WeaponType = -1 })
            blast.get_AttackObj = function() return "shell" end
            HitCapture.handleStockDamageDetail(blast)
            complete(blast)
            assert(hits[2].motionKey == "11:ammo:1234", hits[2].motionKey)
            assert(hits[2].attribution == "shell:ammo:1234")
            assert(hits[2].motionLabel == label)
        end)
    end)
    ShellTracker.nameForAttackObject = original
    if not ok then error(err, 0) end
end

function T.kinsectAndUnknownHitsCarryLabels()
    local ShellTracker = require("MyHuntReport.ShellTracker")
    local original = ShellTracker.currentAction
    local ok, err = pcall(function()
        ShellTracker.currentAction = function() return nil, nil end
        withCapture(function(hits)
            local kinsect = hitInfo(1, 1, { _WeaponType = -1 }, nil,
                { get_Name = function() return "it1003_test" end })
            HitCapture.handleStockDamageDetail(kinsect)
            complete(kinsect)
            assert(hits[1].motionKey == "kinsect" and hits[1].motionLabel.kind == "kinsect")
            assert(hits[1].attribution == "kinsect")
            local unknown = hitInfo(2, 1)
            HitCapture.handleStockDamageDetail(unknown)
            complete(unknown)
            assert(hits[2].motionKey == "7:unknown")
            assert(hits[2].motionLabel.kind == "motion" and hits[2].motionLabel.className == "unknown")
            assert(hits[2].motionLabel.guideId == -1)
        end)
    end)
    ShellTracker.currentAction = original
    if not ok then error(err, 0) end
end

function T.kinsectHitsTakeTheTriggerRowAndKeepTheKinsectPath()
    local ShellTracker = require("MyHuntReport.ShellTracker")
    local KinsectTracker = require("MyHuntReport.KinsectTracker")
    local originalCurrent, originalTrigger = ShellTracker.currentAction, KinsectTracker.triggerFor
    local ok, err = pcall(function()
        local asked = {}
        ShellTracker.currentAction = function() return "cBatonMoveAttack", 11 end
        KinsectTracker.triggerFor = function(object)
            asked[#asked + 1] = object
            return "cBatonMoveAttack", 11
        end
        withCapture(function(hits)
            local object = { get_Name = function() return "it1003_test" end }
            local own = hitInfo(1, 1, { _WeaponType = 10 })
            HitCapture.handleStockDamageDetail(own)
            complete(own, { FinalDamage = 50, Physical = 50, Element = 0 })
            ShellTracker.currentAction = function() return "cSlingerShot", 61, "sub", "slinger" end
            local kinsect = hitInfo(2, 1, { _WeaponType = -1, _ActionType = 2 }, nil, object)
            HitCapture.handleStockDamageDetail(kinsect)
            complete(kinsect, { FinalDamage = 20, Physical = 20, Element = 0 })
            assert(#asked == 1 and asked[1] == object)
            assert(hits[2].motionKey == "10:cBatonMoveAttack")
            assert(hits[2].motionLabel.kind == "motion")
            assert(hits[2].motionLabel.className == "cBatonMoveAttack" and hits[2].motionLabel.guideId == 11)
            assert(hits[2].attribution == "kinsect")
            assert(hits[2].weaponType == -1)
            local motions = Session.snapshot().motions
            assert(#motions == 1, #motions)
            assert(motions[1].key == "10:cBatonMoveAttack" and motions[1].hits == 2 and motions[1].damage == 70)
            KinsectTracker.triggerFor = function() return nil end
            ShellTracker.currentAction = function() return "cBatonMoveAttack2", 21 end
            local fallback = hitInfo(3, 1, { _WeaponType = -1, _ActionType = 2 }, nil, object)
            HitCapture.handleStockDamageDetail(fallback)
            complete(fallback, { FinalDamage = 20, Physical = 20, Element = 0 })
            assert(hits[3].motionKey == "kinsect" and hits[3].motionLabel.kind == "kinsect")
            assert(hits[3].attribution == "kinsect")
            ShellTracker.currentAction = function() return "cSlingerShot", 61, "sub", "slinger" end
            local unnamed = hitInfo(4, 1, { _WeaponType = -1, _ActionType = 2 }, nil,
                { get_Name = function() error("name unavailable") end })
            HitCapture.handleStockDamageDetail(unnamed)
            complete(unnamed, { FinalDamage = 20, Physical = 20, Element = 0 })
            assert(hits[4].motionKey == "slinger" and hits[4].attribution == "slinger")
            assert(#asked == 1)
        end)
    end)
    ShellTracker.currentAction, KinsectTracker.triggerFor = originalCurrent, originalTrigger
    if not ok then error(err, 0) end
end

function T.kinsectNameAndUnreadableFallbackRespectLastWeapon()
    for _, weaponType in ipairs({ 7, 10 }) do
        for _, case in ipairs({
            { object = { get_Name = function() return "it1003_test" end }, kinsect = true },
            { object = { get_Name = function() return "other_object" end }, kinsect = false },
            { object = { get_Name = function() return "prefix_it1003_test" end }, kinsect = false },
            { object = { get_Name = function() return "" end }, kinsect = false },
            { object = { get_Name = function() error("name unavailable") end }, kinsect = weaponType == 10 },
            { object = { get_Name = function() return nil end }, kinsect = weaponType == 10 },
            { object = { get_Name = function() return 1003 end }, kinsect = weaponType == 10 },
            { kinsect = weaponType == 10 },
        }) do
            withCapture(function(hits)
                local weapon = hitInfo(1, 1, { _WeaponType = weaponType })
                HitCapture.handleStockDamageDetail(weapon)
                complete(weapon)
                local info = hitInfo(2, 1, { _WeaponType = -1 }, nil, case.object)
                HitCapture.handleStockDamageDetail(info)
                complete(info)
                assert(#hits == 2 and Session.hitCount() == 2)
                assert((hits[2].motionLabel.kind == "kinsect") == case.kinsect)
                assert(HitCapture.lastWeaponType() == weaponType)
            end)
        end
    end
end

function T.otherUntypedHitsUseCurrentActionAndLogOncePerObjectName()
    local ShellTracker = require("MyHuntReport.ShellTracker")
    local Log = require("MyHuntReport.Log")
    local originalCurrent, developerMode = ShellTracker.currentAction, Log.isDeveloperMode()
    Log.resetCounts()
    local ok, err = pcall(function()
        ShellTracker.currentAction = function() return "cTestAction", 9328 end
        withCapture(function(hits)
            local function capture(name)
                local info = hitInfo(#hits + 1, 1, { _WeaponType = -1 }, nil,
                    { get_Name = function() return name end })
                HitCapture.handleStockDamageDetail(info)
                complete(info)
                local hit = hits[#hits]
                assert(hit.motionKey == "-1:cTestAction")
                assert(hit.attribution == "weapon-1")
                assert(hit.motionLabel.kind == "motion" and hit.motionLabel.className == "cTestAction")
                assert(hit.motionLabel.guideId == 9328 and hit.finalDamage == 100)
                assert(HitCapture.lastWeaponType() == nil)
            end
            Log.setDeveloperMode(false)
            capture("other_object")
            assert(Log.count("hit:wp-1:other_object") == 0)
            Log.setDeveloperMode(true)
            for _ = 1, 3 do capture("other_object") end
            capture("second_object")
            capture("second_object")
            assert(#hits == 6 and Session.hitCount() == 6)
            assert(Log.count("hit:wp-1:other_object") == 1)
            assert(Log.count("hit:wp-1:second_object") == 1)
            local messages = {}
            for _, line in ipairs(stubs.logLines) do
                if line:find("hit weaponType=-1 object=", 1, true) then messages[#messages + 1] = line end
            end
            assert(#messages == 2)
            assert(messages[1] == "[MyHuntReport] hit weaponType=-1 object=other_object")
            assert(messages[2] == "[MyHuntReport] hit weaponType=-1 object=second_object")
        end)
    end)
    ShellTracker.currentAction = originalCurrent
    Log.setDeveloperMode(developerMode)
    Log.resetCounts()
    if not ok then error(err, 0) end
end

local function withHornShells(callback)
    local originalTracker = require("MyHuntReport.ShellTracker")
    local tracker = assert(loadfile("reframework/autorun/MyHuntReport/ShellTracker.lua"))()
    local hook, master, managed = Game.hook, Game.masterHunter, sdk.to_managed_object
    local nameFor, current = originalTracker.nameForAttackObject, originalTracker.currentAction
    local hooks = {}
    local state = { className = "cMStart1", guideId = 100, weaponType = 5, highFreq = 3, polls = 0 }
    local hunter = {
        get_WeaponType = function() return state.weaponType end,
        call = function(_, getter)
            if getter == "get_WeaponHandling" then
                return { call = function(_, name)
                    assert(name == "get_HighFreqSkill")
                    if state.highFreq == "error" then error("handling unavailable") end
                    return state.highFreq
                end }
            end
            if getter == "get_SubActionController" then return nil end
            assert(getter == "get_BaseActionController")
            state.polls = state.polls + 1
            return { get_CurrentAction = function()
                return { _ActionGuideID = state.guideId,
                    get_type_definition = function()
                        return { get_name = function() return state.className end }
                    end }
            end }
        end,
    }
    local function shell(address, hash, parent)
        return {
            get_address = function() return address end,
            get_ParentShell = function() return parent end,
            call = function(self, name)
                if name == "getComponent(System.Type)" then return self end
                assert(name == "get_NameHash")
                if hash == "error" then error("hash unavailable") end
                return hash
            end,
        }
    end
    Game.hook = function(_, signature, pre) hooks[signature] = pre end
    Game.masterHunter = function() return hunter end
    sdk.to_managed_object = function(object) return object end
    originalTracker.nameForAttackObject, originalTracker.currentAction = tracker.nameForAttackObject, tracker.currentAction
    local ok, err = pcall(function()
        tracker.install()
        withCapture(function(hits)
            local function capture(object)
                local info = hitInfo(#hits + 1, 1, { _WeaponType = 5 })
                info.get_AttackObj = function() return object end
                HitCapture.handleStockDamageDetail(info)
                complete(info)
                return hits[#hits]
            end
            callback(tracker, state, shell, hooks, capture)
        end)
    end)
    Game.hook, Game.masterHunter, sdk.to_managed_object = hook, master, managed
    originalTracker.nameForAttackObject, originalTracker.currentAction = nameFor, current
    if not ok then error(err, 0) end
end

function T.echoWaveSetupStoresFrequencyLabelAndChildrenInherit()
    withHornShells(function(tracker, state, shell, hooks, capture)
        local root = shell(501, 824610146)
        hooks.doOnSetUp({ [2] = root })
        local key, label = tracker.nameForAttackObject(root)
        assert(key == "echowave:3")
        assert(stubs.encode(label) == stubs.encode({ kind = "echoWave", highFreq = 3, weaponType = 5 }))
        state.highFreq, state.className = 4, "cDodgeFront"
        local child = shell(502, 2691864323, root)
        hooks.doOnSetUp({ [2] = child })
        hooks.doOnDestroy({ [2] = root })
        local hit = capture(child)
        assert(hit.motionKey == "5:echowave:3" and hit.motionLabel == label)
        local polls = state.polls
        tracker.update()
        assert(state.polls == polls)
    end)
end

function T.echoWaveInvalidFrequencyFallsBackToLaunchAction()
    withHornShells(function(tracker, state, shell, hooks)
        for _, highFreq in ipairs({ 0, -1, "3", false, "error" }) do
            state.highFreq = highFreq
            local root = shell(501, 824610146)
            hooks.doOnSetUp({ [2] = root })
            local key, label = tracker.nameForAttackObject(root)
            assert(key == "cMStart1" and label.kind == "motion" and label.guideId == 100)
        end
    end)
end

function T.hornOtherHashesAndOtherWeaponsKeepLaunchAction()
    withHornShells(function(tracker, state, shell, hooks)
        for _, hash in ipairs({ 4055548668, "error" }) do
            local root = shell(501, hash)
            hooks.doOnSetUp({ [2] = root })
            assert(tracker.nameForAttackObject(root) == "cMStart1")
        end
        state.weaponType = 7
        for _, hash in ipairs({ 2691864323, 824610146 }) do
            local root = shell(501, hash)
            hooks.doOnSetUp({ [2] = root })
            local key, label, hitTime = tracker.nameForAttackObject(root)
            assert(key == "cMStart1" and label.weaponType == 7 and not hitTime)
        end
    end)
end

function T.bubbleSentinelResolvesCurrentHitActionAndSurvivesParentDestroy()
    withHornShells(function(tracker, state, shell, hooks, capture)
        local root = shell(501, 2691864323)
        hooks.doOnSetUp({ [2] = root })
        local key, label, hitTime = tracker.nameForAttackObject(root)
        assert(key == nil and label == nil and hitTime == true)
        local child = shell(502, 2441209651, root)
        hooks.doOnSetUp({ [2] = child })
        hooks.doOnDestroy({ [2] = root })
        tracker.update()
        state.className, state.guideId = "cNewAddMStartBase", -123
        local hit = capture(child)
        assert(hit.motionKey == "5:cNewAddMStartBase")
        assert(hit.attribution == "action")
        assert(stubs.encode(hit.motionLabel) == stubs.encode({ kind = "motion", className = "cNewAddMStartBase", guideId = -123 }))
        tracker.update()
        state.className = "cDodgeFront"
        hit = capture(child)
        assert(hit.motionKey == "5:cNewAddMStartBase" and hit.motionLabel.guideId == -123)
        assert(hit.attribution == "lastAttack")
    end)
end

function T.bubbleNonAttackPatternsUsePolledActionOnlyForSentinelHits()
    withHornShells(function(tracker, state, shell, hooks, capture)
        local root = shell(501, 2691864323)
        hooks.doOnSetUp({ [2] = root })
        tracker.update()
        for _, className in ipairs({ "cDodgeFront", "cDamageSmashFront", "cLandSmash", "cMove",
            "cAimWalk", "cDash", "cUseItem", "cSlingerAim" }) do
            state.className, state.guideId = className, 200
            tracker.update()
            local hit = capture(root)
            assert(hit.motionKey == "5:cMStart1" and hit.motionLabel.guideId == 100, className)
            assert(hit.attribution == "lastAttack")
            local action, guide, source = tracker.currentAction(Game.masterHunter(), true)
            assert(action == "cMStart1" and guide == 100 and source == "lastAttack")
            hit = capture(nil)
            assert(hit.motionKey == "5:" .. className and hit.motionLabel.guideId == 200)
            assert(hit.attribution == "nonattack")
        end
        state.className, state.guideId = "cMoveAttack", 300
        tracker.update()
        state.className = "cDodgeBack"
        local hit = capture(root)
        assert(hit.motionKey == "5:cMoveAttack" and hit.motionLabel.guideId == 300)
    end)
end

function T.bubbleWithoutPolledAttackKeepsCurrentAction()
    withHornShells(function(tracker, state, shell, hooks, capture)
        tracker.update()
        assert(state.polls == 0)
        state.className, state.guideId = "cDamageSmashFront", 200
        local root = shell(501, 2691864323)
        hooks.doOnSetUp({ [2] = root })
        tracker.update()
        local hit = capture(root)
        assert(hit.motionKey == "5:cDamageSmashFront" and hit.motionLabel.guideId == 200)
        assert(hit.attribution == "nonattack")
    end)
end

function T.bubblePollStopsAfterDestroyReuseAndReset()
    withHornShells(function(tracker, state, shell, hooks, capture)
        for _, cleanup in ipairs({ "destroy", "reuse", "reset" }) do
            state.className, state.guideId = "cMStart1", 100
            local root = shell(501, 2691864323)
            hooks.doOnSetUp({ [2] = root })
            hooks.doOnSetUp({ [2] = root })
            tracker.update()
            assert(state.polls > 0)
            if cleanup == "destroy" then
                hooks.doOnDestroy({ [2] = root })
                hooks.doOnDestroy({ [2] = root })
            elseif cleanup == "reuse" then
                hooks.doOnSetUp({ [2] = shell(501, 4055548668) })
            else
                tracker.reset()
                assert(tracker.nameForAttackObject(root) == nil)
            end
            local polls = state.polls
            tracker.update()
            assert(state.polls == polls, cleanup)
            state.className, state.guideId = "cDodgeFront", 200
            hooks.doOnSetUp({ [2] = root })
            local hit = capture(root)
            assert(hit.motionKey == "5:cDodgeFront" and hit.motionLabel.guideId == 200, cleanup)
            tracker.reset()
        end
    end)
end

local function withSkillCapture(callback)
    local original = SkillState.activeSet
    local contexts = {}
    local active = { [63] = true }
    SkillState.activeSet = function(context)
        contexts[#contexts + 1] = context or false
        return active
    end
    local ok, err = pcall(function()
        withCapture(function(hits) callback(hits, contexts, active) end)
    end)
    SkillState.activeSet = original
    if not ok then error(err, 0) end
end

function T.skillContextIsEvaluatedAtCompletion()
    withSkillCapture(function(hits, contexts, active)
        local info = hitInfo(101, 1, { _IsSkillHien = true })
        HitCapture.handleStockDamageDetail(info)
        assert(#contexts == 0, "skills evaluated before completion")
        info:get_AttackData()._IsSkillHien = false
        local pre = preCalc(1)
        pre.Common.ScarIndex = 0
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(30), 10, 2), pre, { Hide = 1.0 })
        complete(info)
        assert(#contexts == 1 and hits[1].activeSkills == active)
        assert(contexts[1].rawHitzone == 30 and contexts[1].wounded == true and contexts[1].hien == true)
        assert(hits[1].hitzone == 60 and hits[1].weight == 18)
    end)
end

function T.scarReadFailurePreservesHitAndBaseMeat()
    withSkillCapture(function(hits, contexts)
        local info = hitInfo(101, 1)
        local this = fakeThis(meat(60), meat(30))
        this:get_Context():get_Em().Scar = nil
        local pre = preCalc(1)
        pre.Common.ScarIndex = 0
        HitCapture.handleStockDamageDetail(info)
        HitCapture.handleCalcStockDamage(this, pre, { Hide = 1.0 })
        complete(info)
        assert(#hits == 1 and contexts[1].rawHitzone == 30)
        assert(contexts[1].wounded == false and contexts[1].hien == false)
    end)
end

function T.nonActiveScarAndMissingMeatDoNotCreditWound()
    withSkillCapture(function(hits, contexts)
        local info = hitInfo(101, 1)
        local pre = preCalc(1)
        pre.Common.ScarIndex = 0
        HitCapture.handleStockDamageDetail(info)
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), nil, 10, 1), pre, { Hide = 1.0 })
        complete(info)
        assert(#hits == 1 and contexts[1].rawHitzone == nil and contexts[1].wounded == false)
    end)
end

function T.interleavedHitsKeepOwnSkillConditions()
    withSkillCapture(function(hits, contexts)
        local first = hitInfo(101, 1, { _IsSkillHien = true }, 10)
        local second = hitInfo(102, 1, {}, 20)
        HitCapture.handleStockDamageDetail(first)
        HitCapture.handleStockDamageDetail(second)
        local pre = preCalc(1)
        pre.Common.ScarIndex = 0
        HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(30), 10, 2), pre, { Hide = 1.0 })
        HitCapture.handleCalcStockDamage(fakeThis(meat(70), meat(50), 20), preCalc(1), { Hide = 1.0 })
        complete(second)
        complete(first)
        assert(#hits == 2 and #contexts == 2)
        assert(contexts[1].rawHitzone == 50 and contexts[1].wounded == false and contexts[1].hien == false)
        assert(contexts[2].rawHitzone == 30 and contexts[2].wounded == true and contexts[2].hien == true)
    end)
end

local function withAuditCapture(callback)
    local Log = require("MyHuntReport.Log")
    local Names = require("MyHuntReport.Names")
    local MotionNames = require("MyHuntReport.MotionNames")
    local master, resolve, nameFor = Game.masterHunter, Names.resolve, MotionNames.nameFor
    local developerMode = Log.isDeveloperMode()
    local state = { base = "cSlash", guideId = 100, sub = "cCharge", object = "weapon", reads = 0 }
    Game.masterHunter = function()
        return { call = function(_, getter)
            local base = getter == "get_BaseActionController"
            if state.controllerError then error("controller unavailable") end
            return { get_CurrentAction = function()
                if state.actionError then error("action unavailable") end
                return setmetatable({
                    get_type_definition = function()
                        if state.classError then error("class unavailable") end
                        return { get_name = function() return base and state.base or state.sub end }
                    end,
                }, { __index = function(_, field)
                    assert(field == "_ActionGuideID")
                    if state.guideError then error("guide unavailable") end
                    return base and state.guideId or 200
                end })
            end }
        end }
    end
    Names.resolve = function(label) return label.kind == "kinsect" and "Kinsect" or "Slash" end
    MotionNames.nameFor = function() return "Slash", "guide" end
    Log.setDeveloperMode(true)
    local ok, err = pcall(function()
        withCapture(function(hits)
            local object = { get_Name = function()
                state.reads = state.reads + 1
                if state.nameError then error("name unavailable") end
                return state.object
            end }
            callback(state, hits, object)
        end)
    end)
    Game.masterHunter, Names.resolve, MotionNames.nameFor = master, resolve, nameFor
    Log.setDeveloperMode(developerMode)
    if not ok then error(err, 0) end
end

local function ledgerLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("[MyHuntReport] hit #", 1, true) == 1 then lines[#lines + 1] = line end
    end
    return lines
end

function T.ledgerUsesCapturedFieldsAndCompletedHitNumber()
    withAuditCapture(function(state, hits, object)
        local info = hitInfo(1, 1, { _OriginalAttackAdjust = 12.5 }, nil, object)
        HitCapture.handleStockDamageDetail(info)
        assert(#ledgerLines() == 0)
        state.base, state.guideId, state.sub, state.object = "cDodge", 900, "cMove", "changed"
        complete(info, { FinalDamage = 90, Physical = 70, Element = 20 })
        assert(#hits == 1 and hits[1].attribution == "action" and state.reads == 1)
        assert(hits[1].motionKey == "7:cSlash" and hits[1].motionLabel.guideId == 100)
        local lines = ledgerLines()
        assert(#lines == 1)
        assert(lines[1] == "[MyHuntReport] hit #1 dmg=90(70/20) wp=7 act=1 mv=12.5 obj=weapon base=cSlash/100 sub=cCharge row=Slash via=action name=guide mon=26 src=- root=- key=7:?:? atk=nil", lines[1])
        for _ = 1, 6 do
            local nextHit = hitInfo(#hits + 1, 1, {}, nil, object)
            HitCapture.handleStockDamageDetail(nextHit)
            complete(nextHit)
        end
        lines = ledgerLines()
        assert(#lines == 7 and lines[7]:find("hit #7 ", 1, true))
        assert(lines[7]:find("via=nonattack", 1, true))
    end)
end

function T.ledgerIsBuiltOnlyInDeveloperMode()
    withAuditCapture(function(state, hits, object)
        local Log = require("MyHuntReport.Log")
        local Names = require("MyHuntReport.Names")
        local MotionNames = require("MyHuntReport.MotionNames")
        Log.setDeveloperMode(false)
        Names.resolve = function() error("ledger name resolved outside developer mode") end
        MotionNames.nameFor = function() error("ledger source resolved outside developer mode") end
        local format = string.format
        string.format = function(pattern, ...)
            assert(not pattern:find("hit #", 1, true), "ledger formatted outside developer mode")
            return format(pattern, ...)
        end
        local ok, err = pcall(function()
            local info = hitInfo(1, 1, {}, nil, object)
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1 and #ledgerLines() == 0)
        end)
        string.format = format
        if not ok then error(err, 0) end
    end)
end

function T.ledgerKinsectAndWeaponMinusOneKeepTheirPaths()
    withAuditCapture(function(state, hits, object)
        for index, case in ipairs({ { "it1003_test", "kinsect", "Kinsect" }, { "slinger", "weapon-1", "Slash" } }) do
            state.object, state.base = case[1], "cSlingerAim"
            local info = hitInfo(index, 1, { _WeaponType = -1 }, nil, object)
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(hits[index].attribution == case[2] and state.reads == index)
            local line = ledgerLines()[index]
            assert(line:find("obj=" .. case[1], 1, true))
            assert(line:find("row=" .. case[3] .. " via=" .. case[2] .. " name=guide", 1, true), line)
        end
    end)
end

function T.auditReadFailuresNeverDropHits()
    for _, failure in ipairs({ "nameError", "controllerError", "actionError", "classError", "guideError" }) do
        withAuditCapture(function(state, hits, object)
            state[failure] = true
            local info = hitInfo(1, 1, {}, nil, object)
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1 and Session.hitCount() == 1, failure)
            local line = ledgerLines()[#ledgerLines()]
            assert(line, failure)
            if failure == "nameError" then
                assert(line:find("obj=- base=cSlash/100", 1, true), line)
            elseif failure == "guideError" then
                assert(line:find("base=cSlash/-1 sub=cCharge", 1, true), line)
            else
                assert(line:find("base=-/-1 sub=-", 1, true), line)
            end
        end)
    end
end

function T.invalidCompletionsNeverEmitLedgerLines()
    withAuditCapture(function(state, hits, object)
        for _, calc in ipairs({ { FinalDamage = 0 }, { FinalDamage = -1 }, {} }) do
            local info = hitInfo(1, 1, {}, nil, object)
            HitCapture.handleStockDamageDetail(info)
            complete(info, calc)
        end
        local info = hitInfo(1, 1, {}, nil, object)
        HitCapture.handleStockDamageDetail(info)
        complete(hitInfo(2, 1))
        assert(#hits == 0 and #ledgerLines() == 0)
    end)
end

function T.slingerHitsUseOneFixedRowAndLedgerPath()
    for _, case in ipairs({
        { object = "weapon", sub = "cCatchSlingerShoot" },
        { object = "weapon", sub = "cSlingerShootReload" },
        { object = "Tip", sub = "cNothing" },
        { object = "SlingerShellPaint", sub = "cNothing" },
        { object = "SlingerShell", sub = "cNothing" },
    }) do
        withAuditCapture(function(state, hits, object)
            local Log = require("MyHuntReport.Log")
            local Names = require("MyHuntReport.Names")
            Names.resolve = function(label)
                assert(label.kind == "slinger")
                return "Slinger"
            end
            state.base, state.sub, state.object = "cRun", case.sub, case.object
            for index, weaponType in ipairs({ -1, 7 }) do
                local info = hitInfo(index, 1, { _WeaponType = weaponType }, nil, object)
                HitCapture.handleStockDamageDetail(info)
                complete(info)
                assert(hits[index].motionKey == "slinger")
                assert(stubs.encode(hits[index].motionLabel) == stubs.encode({ kind = "slinger" }))
                assert(hits[index].attribution == "slinger")
                local lines = ledgerLines()
                assert(lines[#lines]:find("row=Slinger via=slinger name=guide", 1, true))
            end
            assert(state.reads == 2 and Session.hitCount() == 2)
            assert(Session.snapshot().diagnostics.attribution.slinger == 2)
            assert(Log.count("hit:wp-1:" .. case.object) == 0)
        end)
    end
end

function T.slingerObjectRulePrecedesActionLookupAndMatchesExactly()
    local ShellTracker = require("MyHuntReport.ShellTracker")
    local original = ShellTracker.currentAction
    local ok, err = pcall(function()
        withAuditCapture(function(state, hits, object)
            ShellTracker.currentAction = function() error("object rule must precede action lookup") end
            for _, name in ipairs({ "Tip", "SlingerShellPaint" }) do
                state.object = name
                local info = hitInfo(#hits + 1, 1, { _WeaponType = -1 }, nil, object)
                HitCapture.handleStockDamageDetail(info)
                complete(info)
                assert(hits[#hits].motionKey == "slinger")
            end
            ShellTracker.currentAction = original
            for _, name in ipairs({ "TipExtra", "prefixTip", "prefixSlingerShell", "slingerShell" }) do
                state.object = name
                local info = hitInfo(#hits + 1, 1, { _WeaponType = -1 }, nil, object)
                HitCapture.handleStockDamageDetail(info)
                complete(info)
                assert(hits[#hits].attribution == "weapon-1")
            end
        end)
    end)
    ShellTracker.currentAction = original
    if not ok then error(err, 0) end
end

function T.shellResolvedHitsSkipWeaponMinusOneDebugAndKeepLaunchLabel()
    local ShellTracker = require("MyHuntReport.ShellTracker")
    local original = ShellTracker.nameForAttackObject
    local ok, err = pcall(function()
        for _, case in ipairs({
            { "slinger", { kind = "slinger" }, "slinger", "slinger" },
            { "cLaunch", { kind = "motion", className = "cLaunch", guideId = 100, weaponType = 11 }, "11:cLaunch", "shell:cLaunch" },
        }) do
            withAuditCapture(function(state, hits, object)
                state.object = "Tip"
                ShellTracker.nameForAttackObject = function() return case[1], case[2] end
                local info = hitInfo(1, 1, { _WeaponType = -1 }, nil, object)
                HitCapture.handleStockDamageDetail(info)
                complete(info)
                assert(#hits == 1 and hits[1].motionKey == case[3])
                assert(hits[1].motionLabel == case[2] and hits[1].attribution == case[4])
                for _, line in ipairs(stubs.logLines) do
                    assert(not line:find("hit weaponType=-1 object=Tip", 1, true), line)
                end
            end)
        end
    end)
    ShellTracker.nameForAttackObject = original
    if not ok then error(err, 0) end
end

function T.ridingHitUsesSubClassAndGuide()
    withAuditCapture(function(state, hits, object)
        state.base, state.sub = "cPorterRideRun", "cPorterRideAttack1"
        local info = hitInfo(1, 1, {}, nil, object)
        HitCapture.handleStockDamageDetail(info)
        complete(info)
        assert(#hits == 1 and hits[1].motionKey == "7:cPorterRideAttack1")
        assert(hits[1].motionLabel.className == "cPorterRideAttack1" and hits[1].motionLabel.guideId == 200)
        assert(hits[1].attribution == "action")
    end)
end

function T.slingerSubSurvivesUnreadableObjectAfterGlaiveHit()
    withAuditCapture(function(state, hits, object)
        local glaive = hitInfo(1, 1, { _WeaponType = 10 }, nil, object)
        HitCapture.handleStockDamageDetail(glaive)
        complete(glaive)
        state.nameError, state.sub = true, "cCatchSlingerShoot"
        local info = hitInfo(2, 1, { _WeaponType = -1 }, nil, object)
        HitCapture.handleStockDamageDetail(info)
        complete(info)
        assert(#hits == 2 and hits[2].motionKey == "slinger" and hits[2].attribution == "slinger")
    end)
end

function T.ridingReadFailuresKeepCompletedHit()
    for _, failure in ipairs({ "nameError", "controllerError", "actionError", "classError", "guideError" }) do
        withAuditCapture(function(state, hits, object)
            state.base, state.sub, state[failure] = "cPorterRideRun", "cPorterRideAttack1", true
            local info = hitInfo(1, 1, {}, nil, object)
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1 and Session.hitCount() == 1, failure)
            if failure == "guideError" then
                assert(hits[1].motionLabel.className == "cPorterRideAttack1" and hits[1].motionLabel.guideId == -1)
            end
        end)
    end
end

function T.hitPassesWeaponContextAndEligibleSkills()
    local activeSet = SkillState.activeSet
    local seen = nil
    SkillState.activeSet = function(context)
        seen = context
        return { [4082] = true }, { [4082] = true }
    end
    local ok, err = pcall(function()
        withCapture(function(hits)
            local info = hitInfo(101, 1, { _WeaponType = 8 })
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1)
            assert(seen.shell == false and seen.kinsect == false and seen.weaponType == 8, stubs.encode(seen))
            assert(stubs.encode(hits[1].activeSkills) == stubs.encode({ [4082] = true }))
            assert(stubs.encode(hits[1].eligibleSkills) == stubs.encode({ [4082] = true }))
        end)
    end)
    SkillState.activeSet = activeSet
    if not ok then error(err, 0) end
end

local function withAttackPower(masterHunter, callback)
    local original = Game.masterHunter
    Game.masterHunter = masterHunter
    local ok, err = pcall(callback)
    Game.masterHunter = original
    if not ok then error(err, 0) end
end

local function hunterWithAttack(read)
    return function()
        return { get_HunterStatus = function()
            return { get_AttackPower = function()
                return { call = function(_, signature)
                    assert(signature == "get_CurrentAttackPower()", signature)
                    return read()
                end }
            end }
        end }
    end
end

function T.attackPowerIsReadOncePerHitAtCalcTime()
    local reads = 0
    withAttackPower(hunterWithAttack(function()
        reads = reads + 1
        return 259.85
    end), function()
        withCapture(function(hits)
            local info = hitInfo(101, 1)
            HitCapture.handleStockDamageDetail(info)
            assert(reads == 0, tostring(reads))
            HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45)), preCalc(1), { Hide = 1.0 })
            assert(reads == 1, tostring(reads))
            complete(info)
            assert(reads == 1, tostring(reads))
            assert(#hits == 1 and hits[1].attackPower == 259.85, tostring(hits[1].attackPower))
        end)
    end)
end

function T.failedAttackPowerReadLeavesNilAndKeepsTheHit()
    local Log = require("MyHuntReport.Log")
    local developerMode = Log.isDeveloperMode()
    local cases = {
        hunterWithAttack(function() error("boom") end),
        hunterWithAttack(function() return "259" end),
        hunterWithAttack(function() return nil end),
        function() return nil end,
    }
    local ok, err = pcall(function()
        for index, masterHunter in ipairs(cases) do
            Log.setDeveloperMode(true)
            Log.resetCounts()
            withAttackPower(masterHunter, function()
                withCapture(function(hits)
                    local info = hitInfo(101, 1)
                    HitCapture.handleStockDamageDetail(info)
                    HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45)), preCalc(1), { Hide = 1.0 })
                    complete(info)
                    assert(#hits == 1, "case " .. index)
                    assert(hits[1].attackPower == nil, "case " .. index)
                    assert(hits[1].baseHitzone == 45, "case " .. index)
                    assert(Log.count("hit:attack") == 1, "case " .. index .. " count " .. Log.count("hit:attack"))
                end)
            end)
        end
    end)
    Log.setDeveloperMode(developerMode)
    Log.resetCounts()
    if not ok then error(err, 0) end
end

local function checkAttackTrace(read, suffix)
    withAuditCapture(function(state, hits, object)
        local info = hitInfo(101, 1, {}, nil, object)
        HitCapture.handleStockDamageDetail(info)
        withAttackPower(hunterWithAttack(read), function()
            HitCapture.handleCalcStockDamage(fakeThis(meat(60), meat(45)), preCalc(1), { Hide = 1.0 })
        end)
        complete(info)
        local lines = ledgerLines()
        assert(#hits == 1 and #lines == 1)
        assert(lines[1]:sub(-#suffix) == suffix, lines[1])
    end)
end

function T.ledgerEndsWithCapturedAttackPower()
    checkAttackTrace(function() return 259.85 end, " atk=259.85")
end

function T.ledgerEndsWithNilWhenAttackPowerReadFails()
    checkAttackTrace(function() error("boom") end, " atk=nil")
end

local function sourcePending(monsterId)
    for index = 1, math.huge do
        local name, value = debug.getupvalue(HitCapture.handleStockDamageDetail, index)
        assert(name ~= nil, "pending upvalue missing")
        if name == "pending" then return value[monsterId] end
    end
end

local function withSourceLaunch(key, label, hitTime, rootHash, callback)
    local ShellTracker = require("MyHuntReport.ShellTracker")
    local original = ShellTracker.nameForAttackObject
    ShellTracker.nameForAttackObject = function() return key, label, hitTime, rootHash end
    local ok, err = pcall(callback)
    ShellTracker.nameForAttackObject = original
    if not ok then error(err, 0) end
end

function T.sourceShellPendingRetainsClassificationRootAndAttackKeyUntilCompletion()
    withSourceLaunch("cShoot", { kind = "motion", className = "cShoot", guideId = 100, weaponType = 7 }, nil, 543483591, function()
        withAuditCapture(function(state, hits, object)
            state.object = "Wp07Shell"
            local info = hitInfo(1, 1, {}, nil, object)
            info.get_AttackIndex = function() return { _Resource = 0, _Index = 6 } end
            HitCapture.handleStockDamageDetail(info)
            local pendingHit = sourcePending(10)
            assert(pendingHit.source == "shelling" and pendingHit.rootHash == 543483591 and pendingHit.shell == true)
            assert(pendingHit.attackResource == 0 and pendingHit.attackIndex == 6)
            state.object = "it0700_0027_0"
            info.get_AttackIndex = function() error("must use captured index") end
            complete(info)
            assert(hits[1].source == "shelling" and hits[1].motionKey == "7:cShoot")
            local line = ledgerLines()[1]
            assert(line:find("src=shelling root=543483591 key=7:0:6", 1, true), line)
        end)
    end)
end

function T.sourceShellClassificationSkipsDiagnosticReadsOutsideDeveloperMode()
    withSourceLaunch("cShoot", { kind = "motion", className = "cShoot", guideId = 100, weaponType = 7 }, nil, 543483591, function()
        withAuditCapture(function(state, hits, object)
            local Log = require("MyHuntReport.Log")
            Log.setDeveloperMode(false)
            state.object = "Wp07Shell"
            local reads = { getter = 0, _Resource = 0, _Index = 0 }
            local info = hitInfo(1, 1, {}, nil, object)
            info.get_AttackIndex = function()
                reads.getter = reads.getter + 1
                return setmetatable({}, { __index = function(_, field)
                    reads[field] = reads[field] + 1
                    return field == "_Resource" and 0 or 6
                end })
            end
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1 and hits[1].source == "shelling")
            assert(reads.getter == 0 and reads._Resource == 0 and reads._Index == 0,
                string.format("diagnostic reads: getter=%d resource=%d index=%d", reads.getter, reads._Resource, reads._Index))
        end)
    end)
end

function T.sourceKinsectPendingKeepsMinusOneWeaponAndNoRoot()
    withAuditCapture(function(state, hits, object)
        state.object = "it1003_test"
        local info = hitInfo(1, 1, { _WeaponType = -1 }, nil, object)
        HitCapture.handleStockDamageDetail(info)
        local pendingHit = sourcePending(10)
        assert(pendingHit.source == "kinsect" and pendingHit.rootHash == nil and pendingHit.shell == false)
        complete(info)
        assert(hits[1].source == "kinsect" and hits[1].weaponType == -1)
        local line = ledgerLines()[1]
        assert(line:find("src=kinsect root=- key=-1:?:?", 1, true), line)
    end)
end

function T.sourceEchoBubbleKeepsHitTimeMotionAndInheritedRoot()
    withHornShells(function(tracker, state, shell, hooks, capture)
        local root = shell(501, 2691864323)
        local child = shell(502, 2441209651, root)
        hooks.doOnSetUp({ [2] = root })
        hooks.doOnSetUp({ [2] = child })
        hooks.doOnDestroy({ [2] = root })
        state.className, state.guideId = "cNewAddMStartBase", -123
        local hit = capture(child)
        assert(hit.source == "echoBubble")
        assert(hit.motionKey == "5:cNewAddMStartBase" and hit.attribution == "action")
        assert(select(4, tracker.nameForAttackObject(child)) == 2691864323)
    end)
end

function T.sourceDiagnosticsPreservePartialIndexReadsAndNeverDropHits()
    for _, mode in ipairs({ "getter", "resource", "index", "nil" }) do
        withAuditCapture(function(state, hits, object)
            local info = hitInfo(1, 1, {}, nil, object)
            info.get_AttackIndex = function()
                if mode == "getter" then error("index unavailable") end
                if mode == "nil" then return nil end
                return setmetatable({}, { __index = function(_, field)
                    if (mode == "resource" and field == "_Resource") or (mode == "index" and field == "_Index") then
                        error("field unavailable")
                    end
                    return field == "_Resource" and 0 or 6
                end })
            end
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(#hits == 1 and hits[1].source == nil)
            local expected = mode == "resource" and "7:?:6" or mode == "index" and "7:0:?" or "7:?:?"
            local line = ledgerLines()[#ledgerLines()]
            assert(line:find("src=- root=- key=" .. expected, 1, true), line)
        end)
    end
end

function T.sourceDiagnosticsKeepUnreadableShellRootUnknown()
    withSourceLaunch("cShoot", { kind = "motion", className = "cShoot", guideId = 100 }, nil, nil, function()
        withAuditCapture(function(state, hits, object)
            state.object = "Wp07Shell"
            local info = hitInfo(1, 1, {}, nil, object)
            HitCapture.handleStockDamageDetail(info)
            complete(info)
            assert(hits[1].source == nil)
            local line = ledgerLines()[1]
            assert(line:find("src=- root=? key=7:?:?", 1, true), line)
        end)
    end)
end

function T.sourceClassificationStaysAfterOwnerBossAndDeadFilters()
    local Sources = require("MyHuntReport.Sources")
    local original = Sources.classify
    local calls = 0
    Sources.classify = function(hit)
        calls = calls + 1
        return original(hit)
    end
    local ok, err = pcall(function()
        withCapture(function(hits)
            local other = hitInfo(1, 2)
            HitCapture.handleStockDamageDetail(other)
            local small = hitInfo(2, 1)
            small:get_DamageOwner().em.get_IsBoss = function() return false end
            HitCapture.handleStockDamageDetail(small)
            local dead = hitInfo(3, 1)
            local target = dead:get_DamageOwner()
            target.dead = true
            dead.get_DamageOwner = function() return target end
            HitCapture.handleStockDamageDetail(dead)
            assert(calls == 0 and HitCapture.pendingCount() == 0 and #hits == 0)
            HitCapture.handleStockDamageDetail(hitInfo(4, 1))
            assert(calls == 1)
        end)
    end)
    Sources.classify = original
    if not ok then error(err, 0) end
end

return T
