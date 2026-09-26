local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local SkillState = require("MyHuntReport.SkillState")
local Locale = require("MyHuntReport.Locale")
local Log = require("MyHuntReport.Log")

local T = {}

local function fakeInfo(entries, burst)
    local fields = {}
    local object = {}
    for name, entry in pairs(entries) do
        fields[#fields + 1] = { get_name = function() return name end, get_type = function() return { is_a = function() return true end } end }
        object[name] = entry
    end
    object._ContinuousAttackInfo = burst
    object.get_type_definition = function()
        return { get_fields = function() return fields end, get_parent_type = function() return nil end }
    end
    return object
end

local function withHunter(info, equipped, callback, frenzy, music)
    local original = Game.masterHunter
    Game.masterHunter = function()
        return { get_HunterSkill = function()
            return { _HunterSkillParamInfo = info, _Wp05MusicSkill = music, checkSkillActive = function(_, id) return equipped[id] == true end }
        end, get_HunterStatus = function()
            return { _BadConditions = { _Frenzy = frenzy } }
        end }
    end
    SkillState.reset()
    local ok, err = pcall(callback)
    Game.masterHunter = original
    SkillState.reset()
    if not ok then error(err, 0) end
end

local function withOpeners(entries, callback)
    local original = Game.singleton
    Game.singleton = function(name)
        if name ~= "app.VariousDataManager" then return nil end
        return { _Setting = { _SkillData = { getValues = function()
            return {
                get_Count = function() return #entries end,
                get_Item = function(_, index)
                    local entry = entries[index + 1]
                    return {
                        _skillId = -123456789,
                        get_skillId = function() return entry.id end,
                        get_openSkill = function() return { get_elements = function() return entry.opens end } end,
                    }
                end,
            }
        end } } }
    end
    local ok, err = pcall(callback)
    Game.singleton = original
    if not ok then error(err, 0) end
end

function T.hiddenEffectIdsDisplayAsTheirOpener()
    withOpeners({ { id = 240, opens = { 243 } }, { id = 155, opens = { 156, 155, -1073401280 } } }, function()
        local info = fakeInfo({ _ChallengerAttrInfo = { _Skill = 243, _Timer = 1 }, _RebellionInfo = { _Skill = 156, _Timer = 2 } })
        withHunter(info, { [243] = true, [156] = true }, function()
            assert(SkillState.displayId(243) == 240 and SkillState.displayId(156) == 155 and SkillState.displayId(59) == 59)
            local set = SkillState.activeSet()
            assert(set[240] == true and set[155] == true and set[243] == nil and set[156] == nil)
            local rows = SkillState.equippedTracked()
            assert(#rows == 2 and rows[1].id == 155 and rows[2].id == 240, tostring(#rows))
        end)
    end)
end

function T.burstLevelRule()
    assert(SkillState.burstLevel(0, 9) == nil)
    assert(SkillState.burstLevel(3, 4) == "burst:stage1")
    assert(SkillState.burstLevel(3, 5) == "burst:stage2")
end

function T.activeSetCreditsBurstLevelsNotBurst()
    local info = fakeInfo({ _Agitator = { _Skill = 59, _Timer = 2 }, _BurstSlot = { _Skill = 115, _Timer = 3 } }, { _Timer = 3, _HitCount = 5 })
    withHunter(info, {}, function()
        local set = SkillState.activeSet()
        assert(set[59] == true and set["burst:stage2"] == true and set[115] == nil and set["burst:stage1"] == nil)
    end)
    info._ContinuousAttackInfo._HitCount = 2
    withHunter(info, {}, function()
        local set = SkillState.activeSet()
        assert(set["burst:stage1"] == true and set["burst:stage2"] == nil)
    end)
    info._ContinuousAttackInfo._Timer = 0
    withHunter(info, {}, function()
        local set = SkillState.activeSet()
        assert(set["burst:stage1"] == nil and set["burst:stage2"] == nil)
    end)
end

function T.burstNamesAndEquippedRows()
    Locale.resolve("en")
    local originalCall, originalText = Game.callStatic, Game.messageText
    Game.callStatic = function(_, signature, id) return "guid:" .. tostring(id) end
    Game.messageText = function(guid) return guid == "guid:115" and "Burst" or nil end
    local info = fakeInfo({ _BurstSlot = { _Skill = 115, _Timer = 0 }, _Agitator = { _Skill = 59, _Timer = 0 } }, { _Timer = 0, _HitCount = 0 })
    local ok, err = pcall(function()
        withHunter(info, { [115] = true }, function()
            assert(SkillState.skillName("burst:stage1") == "Burst Stage 1" and SkillState.skillName("burst:stage2") == "Burst Stage 2")
            local rows = SkillState.equippedTracked()
            assert(#rows == 2 and rows[1].id == "burst:stage1" and rows[2].id == "burst:stage2", tostring(#rows))
            assert(rows[1].name == "Burst Stage 1")
            Locale.resolve("ko")
            Game.messageText = function(guid) return guid == "guid:115" and "연격" or nil end
            assert(SkillState.skillName("burst:stage1") == "연격 1단계")
            assert(SkillState.skillName("burst:stage2") == "연격 2단계")
        end)
    end)
    Game.callStatic, Game.messageText = originalCall, originalText
    Locale.resolve("en")
    if not ok then error(err, 0) end
end

local ALL = { [63] = true, [19] = true, [56] = true }

function T.weaknessExploitOnHighHitzoneOrWound()
    assert(SkillState.conditionSet({ rawHitzone = 45, wounded = false, hien = false }, ALL)[63] == true)
    assert(SkillState.conditionSet({ rawHitzone = 30, wounded = true, hien = false }, ALL)[63] == true)
    assert(SkillState.conditionSet({ rawHitzone = 44, wounded = false, hien = false }, ALL)[63] == nil)
    assert(SkillState.conditionSet({ wounded = true }, ALL)[63] == true)
end

function T.woundHitCreditsBothWeaknessExploitRows()
    for _, context in ipairs({ { rawHitzone = 30, wounded = true }, { rawHitzone = 45, wounded = true }, { wounded = true } }) do
        local set = SkillState.conditionSet(context, { [63] = true })
        assert(stubs.encode(set) == stubs.encode({ [63] = true, ["wex:wound"] = true }))
    end
end

function T.unwoundedHitsOnlyCreditBaseWeaknessExploit()
    for _, raw in ipairs({ 45, 80 }) do
        local set = SkillState.conditionSet({ rawHitzone = raw, wounded = false }, { [63] = true })
        assert(stubs.encode(set) == stubs.encode({ [63] = true }))
    end
    assert(next(SkillState.conditionSet({ rawHitzone = 44, wounded = false }, { [63] = true })) == nil)
    assert(SkillState.conditionSet({ rawHitzone = 45, wounded = 1 }, { [63] = true })["wex:wound"] == nil)
end

function T.woundRowRequiresEquippedWeaknessExploit()
    local set = SkillState.conditionSet({ rawHitzone = 80, wounded = true }, {})
    assert(set[63] == nil and set["wex:wound"] == nil)
end

function T.activeSetCreditsWoundRow()
    withHunter(fakeInfo({}), { [63] = true }, function()
        assert(SkillState.displayId("wex:wound") == "wex:wound")
        assert(stubs.encode(SkillState.activeSet({ rawHitzone = 30, wounded = true })) == stubs.encode({ [63] = true, ["wex:wound"] = true }))
        assert(stubs.encode(SkillState.activeSet({ rawHitzone = 45, wounded = false })) == stubs.encode({ [63] = true }))
    end)
end

function T.conditionWoundNamesAndEquippedRows()
    local originalCall, originalText = Game.callStatic, Game.messageText
    Game.callStatic = function(_, _, id) return "guid:" .. tostring(id) end
    Game.messageText = function(guid)
        if guid == "guid:63" then return Locale.current() == "ko" and "약점 특효" or "Weakness Exploit" end
    end
    local ok, err = pcall(function()
        withHunter(fakeInfo({}), { [63] = true }, function()
            for _, language in ipairs({ "en", "ko" }) do
                Locale.resolve(language)
                local base = language == "ko" and "약점 특효" or "Weakness Exploit"
                local wound = base .. (language == "ko" and " · 상처" or " · Wound")
                assert(SkillState.skillName(63) == base)
                assert(SkillState.skillName("wex:wound") == wound)
                local rows = SkillState.equippedTracked()
                assert(#rows == 2 and rows[1].id == 63 and rows[2].id == "wex:wound")
                assert(rows[1].name == base and rows[2].name == wound)
                assert(next((SkillState.activeSet())) == nil)
            end
        end)
        withHunter(fakeInfo({}), {}, function()
            assert(#SkillState.equippedTracked() == 0)
        end)
    end)
    Game.callStatic, Game.messageText = originalCall, originalText
    Locale.resolve("en")
    if not ok then error(err, 0) end
end

function T.mindsEyeOnLowHitzoneOnly()
    local low = SkillState.conditionSet({ rawHitzone = 44, wounded = false, hien = false }, ALL)
    assert(low[19] == true and low[63] == nil)
    assert(SkillState.conditionSet({ rawHitzone = nil, wounded = false, hien = false }, ALL)[19] == nil)
    assert(SkillState.conditionSet({ rawHitzone = 45 }, ALL)[19] == nil)
    local wounded = SkillState.conditionSet({ rawHitzone = 30, wounded = true }, ALL)
    assert(wounded[19] == true and wounded[63] == true)
end

function T.airborneAndEquippedGate()
    assert(SkillState.conditionSet({ rawHitzone = 80, wounded = false, hien = true }, ALL)[56] == true)
    local none = SkillState.conditionSet({ rawHitzone = 80, wounded = true, hien = true }, {})
    assert(next(none) == nil)
    assert(next(SkillState.conditionSet(nil, ALL)) == nil)
    assert(next(SkillState.conditionSet({ rawHitzone = "45", wounded = 1, hien = 1 }, ALL)) == nil)
end

function T.activeSetReadsBooleanFields()
    local fields = { [59] = "_IsActiveChallenger", [60] = "_IsActiveFullCharge", [65] = "_IsActiveKonshin", [101] = "_IsAdrenalineRush", [240] = "_IsActiveChallengerAttr" }
    for id, field in pairs(fields) do
        local info = fakeInfo({})
        info[field] = true
        withHunter(info, { [id] = true }, function()
            assert(SkillState.activeSet()[id] == true, field)
            info[field] = false
            assert(SkillState.activeSet()[id] == nil, field)
        end)
    end
end

function T.activeSetFrenzyRequiresActiveOvercome()
    local frenzy = { _IsActive = true, _State = 2 }
    withHunter(fakeInfo({}), { [194] = true }, function()
        assert(SkillState.activeSet()[194] == true)
        frenzy._IsActive = false
        assert(SkillState.activeSet()[194] == nil)
        frenzy._IsActive = true
        frenzy._State = 1
        assert(SkillState.activeSet()[194] == nil)
    end, frenzy)
end

function T.activeSetGatesAllNewSkillsByEquipment()
    local info = fakeInfo({})
    info._IsActiveChallenger = true
    info._IsActiveFullCharge = true
    info._IsActiveKonshin = true
    info._IsAdrenalineRush = true
    withHunter(info, {}, function()
        assert(next((SkillState.activeSet({ rawHitzone = 30, wounded = true, hien = true }))) == nil)
    end, { _IsActive = true, _State = 2 })
    withHunter(info, ALL, function()
        local active = SkillState.activeSet({ rawHitzone = 30, wounded = true, hien = true })
        assert(active[19] and active[63] and active[56])
        assert(active[59] == nil and active[194] == nil)
    end, { _IsActive = true, _State = 2 })
end

function T.unreadableBooleanAndFrenzyAreIsolated()
    local Log = require("MyHuntReport.Log")
    local info = setmetatable(fakeInfo({}), { __index = function(_, key)
        if key == "_IsActiveChallenger" then error("unreadable") end
    end })
    info._IsActiveFullCharge = true
    withHunter(info, { [59] = true, [60] = true, [194] = true, [56] = true }, function()
        Log.resetCounts()
        local active = SkillState.activeSet({ hien = true })
        assert(active[59] == nil and active[194] == nil)
        assert(active[60] and active[56])
        assert(Log.count("skill:field:_IsActiveChallenger") == 1)
        assert(Log.count("skill:field:_Frenzy") == 1)
    end)
end

function T.equippedUnionIsSortedAndBurstExpanded()
    local ids = { 19, 56, 59, 60, 63, "wex:wound", 65, 101, 111, "burst:stage1", "burst:stage2", 194 }
    local equipped = { [115] = true }
    for _, id in ipairs(ids) do equipped[id] = true end
    withHunter(fakeInfo({ _Counter = { _Skill = 111, _Timer = 0 }, _BurstSlot = { _Skill = 115, _Timer = 0 } }), equipped, function()
        local rows = SkillState.equippedTracked()
        assert(#rows == #ids, tostring(#rows))
        for index, id in ipairs(ids) do
            assert(rows[index].id == id and rows[index].name == SkillState.skillName(id))
        end
    end)
end

function T.refreshAndResetRebuildEquippedCache()
    local equipment = { [59] = true }
    withHunter(fakeInfo({}), equipment, function()
        assert(SkillState.refreshEquipped()[59] == true)
        equipment[59], equipment[60] = nil, true
        assert(SkillState.equippedTracked()[1].id == 59)
        local refreshed = SkillState.refreshEquipped()
        assert(refreshed[59] == nil and refreshed[60] == true)
        equipment[60], equipment[65] = nil, true
        SkillState.reset()
        assert(SkillState.equippedTracked()[1].id == 65)
    end)
end

function T.refreshReportsSetChangesAndLogsOnlyChanges()
    local Log = require("MyHuntReport.Log")
    local developerMode = Log.isDeveloperMode()
    Log.setDeveloperMode(true)
    Log.resetCounts()
    local equipment = { [59] = true }
    local ok, err = pcall(function()
        withHunter(fakeInfo({}), equipment, function()
            local function refresh(expected, changed)
                local actual, actualChanged = SkillState.refreshEquipped()
                assert(stubs.encode(actual) == stubs.encode(expected))
                assert(actualChanged == changed)
            end
            refresh({ [59] = true }, true)
            refresh({ [59] = true }, false)
            equipment[59], equipment[60] = nil, true
            refresh({ [60] = true }, true)
            equipment[59] = true
            refresh({ [59] = true, [60] = true }, true)
            equipment[59] = nil
            refresh({ [60] = true }, true)
            equipment[60] = nil
            refresh({}, true)
            refresh({}, false)
            SkillState.reset()
            refresh({}, true)
            local lines = {}
            for _, line in ipairs(stubs.logLines) do
                if line:find("equipped skills: ", 1, true) then lines[#lines + 1] = line end
            end
            assert(stubs.encode(lines) == stubs.encode({
                "[MyHuntReport] equipped skills: 59",
                "[MyHuntReport] equipped skills: 60",
                "[MyHuntReport] equipped skills: 59,60",
                "[MyHuntReport] equipped skills: 60",
                "[MyHuntReport] equipped skills: ",
                "[MyHuntReport] equipped skills: ",
            }))
        end)
    end)
    Log.setDeveloperMode(developerMode)
    Log.resetCounts()
    if not ok then error(err, 0) end
end

function T.refreshWithoutHunterReturnsEmptySetAndChangeFlag()
    local original = Game.masterHunter
    Game.masterHunter = function() return nil end
    SkillState.reset()
    local ok, err = pcall(function()
        local equipped, changed = SkillState.refreshEquipped()
        assert(next(equipped) == nil and changed == true)
        equipped, changed = SkillState.refreshEquipped()
        assert(next(equipped) == nil and changed == false)
    end)
    Game.masterHunter = original
    SkillState.reset()
    if not ok then error(err, 0) end
end

function T.activePhasePollReadsOnlyAtTwoSecondIntervalsAndResetClearsTimer()
    for _, activePhase in ipairs({ "training", "playing" }) do
        local checks = 0
        local equipment = setmetatable({}, { __index = function()
            checks = checks + 1
            return true
        end })
        withHunter(fakeInfo({}), equipment, function()
            for _, phase in ipairs({ "idle", "result" }) do SkillState.pollEquipped(0, phase) end
            assert(checks == 0)
            SkillState.pollEquipped(0, activePhase)
            local perRead = checks
            assert(perRead > 0)
            for _, now in ipairs({ 0, 0.5, 1.999 }) do SkillState.pollEquipped(now, activePhase) end
            assert(checks == perRead)
            SkillState.pollEquipped(2, activePhase)
            assert(checks == 2 * perRead)
            for _, phase in ipairs({ "idle", "result" }) do SkillState.pollEquipped(4, phase) end
            assert(checks == 2 * perRead)
            SkillState.pollEquipped(4, activePhase)
            assert(checks == 3 * perRead)
            SkillState.reset()
            SkillState.pollEquipped(4.1, activePhase)
            assert(checks == 4 * perRead)
        end)
    end
end

function T.equipmentChangeHookRefreshesAndLogsOnlyChangedSets()
    local Log = require("MyHuntReport.Log")
    local hook, debug = Game.hook, Log.debug
    local hooks, messages = {}, {}
    local registrations = 0
    Game.hook = function(typeName, signature, pre, post)
        registrations = registrations + 1
        hooks[typeName .. "." .. signature] = { pre = pre, post = post }
        return true
    end
    Log.debug = function(message, key)
        if key == "skill:equip-change" then messages[#messages + 1] = message end
    end
    local ok, err = pcall(function()
        local equipment = { [59] = true }
        withHunter(fakeInfo({}), equipment, function()
            SkillState.refreshEquipped()
            SkillState.install()
            SkillState.install()
            assert(registrations == 1)
            local registration = hooks["app.GUIManager.onPlEquipChange()"]
            assert(registration and registration.pre == nil and type(registration.post) == "function")
            registration.post()
            assert(#messages == 0)
            equipment[59], equipment[63] = nil, true
            assert(SkillState.activeSet({ rawHitzone = 45 })[63] == nil)
            registration.post()
            assert(SkillState.activeSet({ rawHitzone = 45 })[63] == true)
            local rows = SkillState.equippedTracked()
            assert(#rows == 2 and rows[1].id == 63 and rows[2].id == "wex:wound")
            assert(#messages == 1 and messages[1] == "equip change refreshed equipped skills")
            registration.post()
            assert(#messages == 1)
            SkillState.reset()
            SkillState.install()
            assert(registrations == 1)
        end)
    end)
    Game.hook, Log.debug = hook, debug
    if not ok then error(err, 0) end
end

function T.trainingPollUpdatesTrackedRowsAndActiveSkills()
    local equipment = { [59] = true }
    withHunter(fakeInfo({}), equipment, function()
        SkillState.pollEquipped(10, "training")
        assert(SkillState.equippedTracked()[1].id == 59)
        equipment[59], equipment[63] = nil, true
        SkillState.pollEquipped(11.999, "training")
        assert(SkillState.activeSet({ rawHitzone = 45 })[63] == nil)
        SkillState.pollEquipped(12, "training")
        local rows = SkillState.equippedTracked()
        assert(#rows == 2 and rows[1].id == 63 and rows[2].id == "wex:wound")
        assert(SkillState.activeSet({ rawHitzone = 45 })[63] == true)
    end)
end

function T.refreshIsolatesSkillReadFailures()
    local equipment = setmetatable({ [63] = true }, { __index = function() error("unreadable skill") end })
    withHunter(fakeInfo({}), equipment, function()
        local equipped, changed = SkillState.refreshEquipped()
        assert(stubs.encode(equipped) == stubs.encode({ [63] = true }) and changed == true)
        equipped, changed = SkillState.refreshEquipped()
        assert(stubs.encode(equipped) == stubs.encode({ [63] = true }) and changed == false)
    end)
end

function T.activeSetCreditsMelodiesAndBubbleWithoutEquipment()
    local music = { call = function(_, method, slot)
        assert(method == "isEnable")
        return slot == 12 or slot == 56 or slot == 1 or slot == 39
    end }
    withHunter(fakeInfo({}), {}, function()
        local set = SkillState.activeSet()
        assert(stubs.encode(set) == stubs.encode({ [2012] = true, [3004] = true }))
        assert(SkillState.displayId(2012) == 2012 and SkillState.displayId(3004) == 3004)
        assert(#SkillState.equippedTracked() == 0)
    end, nil, music)
end

function T.activeSetCreditsOnlyTheSevenTrackedMelodies()
    local slots = {}
    local music = { call = function(_, method, slot)
        assert(method == "isEnable")
        slots[#slots + 1] = slot
        return true
    end }
    withHunter(nil, {}, function()
        local set = SkillState.activeSet()
        assert(stubs.encode(set) == stubs.encode({
            [2011] = true, [2012] = true, [2013] = true, [2014] = true,
            [2042] = true, [2043] = true, [3004] = true,
        }))
        table.sort(slots)
        assert(stubs.encode(slots) == stubs.encode({ 11, 12, 13, 14, 42, 43, 56 }))
        assert(#SkillState.equippedTracked() == 0)
    end, nil, music)
end

function T.activeSetIgnoresUntrackedMelodies()
    withHunter(fakeInfo({}), {}, function()
        assert(next((SkillState.activeSet())) == nil)
    end, nil, { call = function(_, _, slot) return slot == 1 or slot == 39 end })
end

function T.activeSetHandlesMissingOrFailingMusic()
    withHunter(fakeInfo({}), {}, function()
        assert(next((SkillState.activeSet())) == nil)
    end)
    withHunter(fakeInfo({}), {}, function()
        assert(next((SkillState.activeSet())) == nil)
    end, nil, { call = function() error("unreadable music") end })
end

function T.activeSetIsolatesMelodyCallErrors()
    withHunter(fakeInfo({}), {}, function()
        assert(stubs.encode(SkillState.activeSet()) == stubs.encode({ [2012] = true, [3004] = true }))
    end, nil, { call = function(_, _, slot)
        if slot == 11 then error("unreadable slot") end
        if slot == 13 then return 1 end
        return slot == 12 or slot == 56
    end })
end

function T.activeSetHandlesUnavailableHunterSkillAndMusicField()
    local original = Game.masterHunter
    local hunters = {
        false,
        { get_HunterSkill = function() return nil end },
        { get_HunterSkill = function() error("unreadable skill") end },
        { get_HunterSkill = function()
            return setmetatable({}, { __index = function(_, key)
                if key == "_Wp05MusicSkill" then error("unreadable music field") end
            end })
        end },
    }
    local ok, err = pcall(function()
        for _, hunter in ipairs(hunters) do
            Game.masterHunter = function() return hunter or nil end
            SkillState.reset()
            assert(next((SkillState.activeSet())) == nil)
        end
    end)
    Game.masterHunter = original
    SkillState.reset()
    if not ok then error(err, 0) end
end

function T.melodyNamesUseMusicSkillNameAndCachePerLanguage()
    local originalCall, originalText = Game.callStatic, Game.messageText
    local calls, texts = 0, 0
    Game.callStatic = function(typeName, signature, ...)
        assert(typeName == "app.Wp05Def")
        assert(signature == "MusicSkillName(app.Wp05Def.WP05_MUSIC_SKILL_TYPE, app.Wp05Def.WP05_MUSIC_SKILL_HIGH_FREQ_TYPE)")
        local args = { ... }
        assert(#args == 2 and args[1] == 12 and args[2] == 0)
        calls = calls + 1
        return "melody-guid"
    end
    Game.messageText = function(guid)
        assert(guid == "melody-guid")
        texts = texts + 1
        return Locale.current() == "ko" and "공격력 1.1배" or "Attack x1.1"
    end
    local ok, err = pcall(function()
        Locale.resolve("en")
        assert(SkillState.skillName(2012) == "Melody: Attack x1.1")
        assert(SkillState.skillName(2012) == "Melody: Attack x1.1" and calls == 1 and texts == 1)
        Locale.resolve("ko")
        assert(SkillState.skillName(2012) == "선율: 공격력 1.1배")
        assert(SkillState.skillName(2012) == "선율: 공격력 1.1배" and calls == 2 and texts == 2)
        Locale.resolve("en")
        assert(SkillState.skillName(2012) == "Melody: Attack x1.1" and calls == 2 and texts == 2)
    end)
    Game.callStatic, Game.messageText = originalCall, originalText
    Locale.resolve("auto")
    if not ok then error(err, 0) end
end

function T.melodyNamesFallBackForMissingOrInvalidText()
    local originalCall, originalText = Game.callStatic, Game.messageText
    Game.callStatic = function(_, _, id) return id end
    local values = { [1] = false, [11] = "", [13] = "<COLOR>#Rejected#</COLOR>", [999] = "text---text" }
    Game.messageText = function(guid) return values[guid] or nil end
    local ok, err = pcall(function()
        Locale.resolve("en")
        for id in pairs(values) do
            assert(SkillState.skillName(2000 + id) == "Melody: #" .. id)
        end
    end)
    Game.callStatic, Game.messageText = originalCall, originalText
    Locale.resolve("auto")
    if not ok then error(err, 0) end
end

function T.bubbleNameUsesGameTextWithPrefixAndLocaleFallback()
    local originalCall, originalText = Game.callStatic, Game.messageText
    local bubbleText = nil
    Game.callStatic = function(typeName, signature, ...)
        assert(typeName == "app.Wp05Def")
        assert(signature == "SkillName(app.Wp05Def.WP05_HIBIKI_SKILL_TYPE)")
        local args = { ... }
        assert(#args == 1 and args[1] == 4)
        return "bubble-guid"
    end
    Game.messageText = function(guid)
        assert(guid == "bubble-guid")
        return bubbleText
    end
    local ok, err = pcall(function()
        Locale.resolve("en")
        assert(SkillState.skillName(3004) == "Echo Bubble: Attack & Affinity Up")
        Locale.resolve("ko")
        bubbleText = "공격력 1.1배 & 회심률+25%"
        assert(SkillState.skillName(3004) == "소리 구슬: 공격력 1.1배 & 회심률+25%")
        assert(SkillState.skillName(3004) == "소리 구슬: 공격력 1.1배 & 회심률+25%")
    end)
    Game.callStatic, Game.messageText = originalCall, originalText
    Locale.resolve("auto")
    SkillState.reset()
    if not ok then error(err, 0) end
end

local function weaponHandling(members)
    return { call = function(_, name, ...)
        local member = members[name]
        if member == nil then error("no method " .. name) end
        if type(member) == "function" then return member(...) end
        return member
    end }
end

local function withWeaponHunter(weaponType, handling, callback)
    local original = Game.masterHunter
    Game.masterHunter = function()
        return {
            get_HunterSkill = function() return { _HunterSkillParamInfo = fakeInfo({}), checkSkillActive = function() return false end } end,
            get_HunterStatus = function() return { _BadConditions = {} } end,
            get_WeaponType = function() return weaponType end,
            get_WeaponHandling = type(handling) == "function" and handling or function() return handling end,
        }
    end
    SkillState.reset()
    Log.resetCounts()
    local ok, err = pcall(callback)
    Game.masterHunter = original
    SkillState.reset()
    if not ok then error(err, 0) end
end

function T.weaponStateIdsRoundTrip()
    assert(SkillState.weaponStateId(9, 2) == 4092)
    local weaponType, code = SkillState.weaponStateType(4092)
    assert(weaponType == 9 and code == 2)
    assert(SkillState.weaponStateType(4099) == nil)
    assert(SkillState.weaponStateType(2012) == nil)
    assert(SkillState.weaponStateType("burst:stage1") == nil)
end

function T.dualBladesAndLongSwordCreditWithoutEligibility()
    withWeaponHunter(2, weaponHandling({ get_IsMikiriBuff = true }), function()
        local active, eligible = SkillState.activeSet({})
        assert(stubs.encode(active) == stubs.encode({ [4021] = true }), stubs.encode(active))
        assert(stubs.encode(eligible) == "{}")
    end)
    withWeaponHunter(3, weaponHandling({ get_AuraLevel = 4 }), function()
        local active = SkillState.activeSet({})
        assert(stubs.encode(active) == stubs.encode({ [4031] = true }))
    end)
    withWeaponHunter(3, weaponHandling({ get_AuraLevel = 3 }), function()
        assert(stubs.encode(SkillState.activeSet({})) == "{}")
    end)
end

function T.switchAxeRowsAreEligibleByMode()
    local handling = weaponHandling({ get_Mode = 1, get_IsSwordAwaken = true, get_IsAxeEnhanced = true })
    withWeaponHunter(8, handling, function()
        local active, eligible = SkillState.activeSet({})
        assert(stubs.encode(active) == stubs.encode({ [4081] = true }), stubs.encode(active))
        assert(stubs.encode(eligible) == stubs.encode({ [4081] = true }), stubs.encode(eligible))
    end)
    withWeaponHunter(8, weaponHandling({ get_Mode = 0, get_IsSwordAwaken = true, get_IsAxeEnhanced = false }), function()
        local active, eligible = SkillState.activeSet({})
        assert(stubs.encode(active) == "{}")
        assert(stubs.encode(eligible) == stubs.encode({ [4082] = true }))
    end)
end

function T.chargeBladeShieldRowCountsShellHitsInSwordMode()
    local handling = weaponHandling({ get_Mode = 0, get_IsSwordEnhanced = false, get_IsShieldEnhanced = true, get_IsAxeEnhanced = true })
    withWeaponHunter(9, handling, function()
        local active, eligible = SkillState.activeSet({ shell = false })
        assert(stubs.encode(active) == "{}")
        assert(stubs.encode(eligible) == stubs.encode({ [4091] = true }), stubs.encode(eligible))
        active, eligible = SkillState.activeSet({ shell = true })
        assert(stubs.encode(active) == stubs.encode({ [4092] = true }), stubs.encode(active))
        assert(stubs.encode(eligible) == stubs.encode({ [4091] = true, [4092] = true }), stubs.encode(eligible))
    end)
    withWeaponHunter(9, weaponHandling({ get_Mode = 1, get_IsSwordEnhanced = true, get_IsShieldEnhanced = true, get_IsAxeEnhanced = true }), function()
        local active, eligible = SkillState.activeSet({ shell = false })
        assert(stubs.encode(active) == stubs.encode({ [4092] = true, [4093] = true }))
        assert(stubs.encode(eligible) == stubs.encode({ [4092] = true, [4093] = true }))
    end)
end

function T.insectGlaiveTripleUpSkipsKinsectHits()
    withWeaponHunter(10, weaponHandling({ get_IsTrippleUp = true }), function()
        local active, eligible = SkillState.activeSet({ kinsect = false })
        assert(stubs.encode(active) == stubs.encode({ [4101] = true }))
        assert(stubs.encode(eligible) == stubs.encode({ [4101] = true }))
        active, eligible = SkillState.activeSet({ kinsect = true })
        assert(stubs.encode(active) == "{}")
        assert(stubs.encode(eligible) == "{}")
    end)
end

function T.weaponStateReadFailuresCreditNothingAndLogOnce()
    withWeaponHunter(8, weaponHandling({ get_Mode = 1 }), function()
        Log.setDeveloperMode(true)
        local active, eligible = SkillState.activeSet({})
        assert(stubs.encode(active) == "{}")
        assert(stubs.encode(eligible) == "{}")
        SkillState.activeSet({})
        local failures = 0
        local first = nil
        for _, line in ipairs(stubs.logLines) do
            if line:find("weapon state read failed", 1, true) then
                failures = failures + 1
                first = first or line
            end
        end
        assert(failures == 2, "got " .. failures)
        assert(first and first:find("4081", 1, true), tostring(first))
        Log.setDeveloperMode(false)
    end)
    withWeaponHunter(12, weaponHandling({}), function()
        local active, eligible = SkillState.activeSet({})
        assert(stubs.encode(active) == "{}" and stubs.encode(eligible) == "{}")
    end)
    withWeaponHunter(8, nil, function()
        local active, eligible = SkillState.activeSet({})
        assert(stubs.encode(active) == "{}" and stubs.encode(eligible) == "{}")
    end)
end

function T.weaponHandlingReadFailureCreditsNothingAndLogs()
    withWeaponHunter(8, function() error("boom") end, function()
        local developerMode = Log.isDeveloperMode()
        Log.setDeveloperMode(true)
        local active, eligible = SkillState.activeSet({})
        Log.setDeveloperMode(developerMode)
        assert(stubs.encode(active) == "{}")
        assert(stubs.encode(eligible) == "{}")
        local failures = 0
        for _, line in ipairs(stubs.logLines) do
            if line:find("weapon handling read failed", 1, true) then
                failures = failures + 1
                assert(line:find("boom", 1, true), line)
            end
        end
        assert(failures == 1, "got " .. failures)
        assert(Log.count("skill:weapon-state:handling") == 1)
    end)
end

function T.weaponStateNamesComeFromLocaleWithScope()
    Locale.init({})
    Locale.resolve("ko")
    assert(SkillState.skillName(4021) == "귀인 회피", SkillState.skillName(4021))
    assert(SkillState.skillName(4092) == "방패 강화 · 도끼 모드+병", SkillState.skillName(4092))
    Locale.resolve("en")
    assert(SkillState.skillName(4101) == "Triple Up · hunter hits", SkillState.skillName(4101))
    assert(SkillState.skillName(4031) == "Red Spirit Gauge", SkillState.skillName(4031))
end

return T
