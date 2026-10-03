local stubs = require("stubs")
local Quest = require("MyHuntReport.Quest")
local Session = require("MyHuntReport.Session")
local History = require("MyHuntReport.History")
local ReportWindow = require("MyHuntReport.ReportWindow")
local Settings = require("MyHuntReport.Settings")
local Game = require("MyHuntReport.Game")
local Names = require("MyHuntReport.Names")

local T = {}

local function playQuestWithOneHit()
    Quest.resetForTests()
    History.resetForTests()
    Settings.load()
    Quest.handleQuestStart(100)
    Session.addHit({ monsterId = 1, monsterLabel = { kind = "monster", emId = 26 }, finalDamage = 10, physical = 10, element = 0, weight = 1,
        motionKey = "7:x", motionLabel = { kind = "motion", className = "x", guideId = -1 }, activeSkills = {}, time = 130 })
end

local function withQuestDirector(callback)
    local singleton = Game.singleton
    local director = { _QuestData = { _KeepQuestData = { _QuestLv = 5 } } }
    Game.singleton = function(name)
        if name == "app.MissionManager" then
            return { get_QuestDirector = function() return director end }
        end
        return singleton(name)
    end
    local ok, err = pcall(callback, director)
    Game.singleton = singleton
    Quest.resetForTests()
    if not ok then error(err, 0) end
end

function T.questStartCapturesLevelInLiveAndResultSnapshots()
    withQuestDirector(function(director)
        playQuestWithOneHit()
        assert(Quest.readQuestLevel() == 5)
        director._QuestData._KeepQuestData._QuestLv = 6
        assert(Quest.currentSnapshot(140).quest.level == 5)
        Quest.handleResultStart()
        assert(Quest.currentSnapshot(160).quest.level == 5)
        Quest.handleResultInfo({ endType = 2 }, 161)
        assert(History.readAll()[1].quest.level == 5)
        Quest.resetForTests()
        assert(Quest.currentSnapshot(170).quest.level == nil)
    end)
end

function T.questLevelReadFailureClearsPreviousLevel()
    withQuestDirector(function()
        playQuestWithOneHit()
        assert(Quest.currentSnapshot(140).quest.level == 5)
        local singleton = Game.singleton
        Game.singleton = function(name)
            if name == "app.MissionManager" then error("quest director unavailable") end
            return singleton(name)
        end
        assert(Quest.readQuestLevel() == nil)
        Quest.handleQuestStart(200)
        assert(Quest.currentSnapshot(210).quest.level == nil)
        Quest.handleResultStart()
        assert(Quest.currentSnapshot(220).quest.level == nil)
    end)
end

function T.resultLevelOverridesStartLevelAndPersists()
    withQuestDirector(function()
        playQuestWithOneHit()
        Quest.handleResultStart()
        Quest.handleResultInfo({ endType = 2, questLevel = 7 }, 161)
        assert(Quest.currentSnapshot(170).quest.level == 7)
        assert(History.readAll()[1].quest.level == 7)
    end)
end

function T.invalidResultLevelsPreserveStartLevel()
    withQuestDirector(function()
        for _, level in ipairs({ 0, -1, "7", false }) do
            playQuestWithOneHit()
            Quest.handleResultStart()
            Quest.handleResultInfo({ endType = 2, questLevel = level }, 161)
            assert(Quest.currentSnapshot(170).quest.level == 5)
            assert(History.readAll()[1].quest.level == 5)
        end
    end)
end

function T.trainingSnapshotsHaveNoQuestLevel()
    withQuestDirector(function()
        playQuestWithOneHit()
        Quest.handleTrainingEnter(200)
        local current = Quest.currentSnapshot(210)
        assert(current.quest.result == "training" and current.quest.level == nil)
        Quest.handleTrainingLeave(220)
        current = Quest.currentSnapshot(230)
        assert(current.quest.result == "training" and current.quest.level == nil)
    end)
end

function T.resultMapping()
    assert(Quest.resultFromEndType(2) == "clear")
    assert(Quest.resultFromEndType(3) == "fail")
    assert(Quest.resultFromEndType(1) == "abandon")
    assert(Quest.resultFromEndType(0) == "unknown")
    assert(Quest.resultFromEndType(nil) == "unknown")
end

function T.clearSavesOnceDespiteTwoExecutes()
    playQuestWithOneHit()
    Quest.handleResultStart()
    assert(ReportWindow.isOpen() == true)
    local fields = { endType = 2, failedType = 0, clearTimeMs = 27430, mainWeaponType = 13, joinMemberNum = 1 }
    Quest.handleResultInfo(fields, 161)
    Quest.handleResultInfo(fields, 168)
    local entries = History.readAll()
    assert(#entries == 1, "expected one history line, got " .. #entries)
    assert(entries[1].quest.result == "clear")
    assert(entries[1].quest.elapsedSeconds == 27)
    assert(entries[1].quest.weapon.type == 13)
    assert(entries[1].quest.playerCount == 1)
    assert(Quest.state().saved == true)
end

function T.abandonIsSaved()
    playQuestWithOneHit()
    Quest.handleResultStart()
    Quest.handleResultInfo({ endType = 1, failedType = 0, clearTimeMs = 27170, mainWeaponType = 13, joinMemberNum = 1 }, 161)
    local entries = History.readAll()
    assert(#entries == 1 and entries[1].quest.result == "abandon")
end

function T.emptySessionIsNotSavedOrShown()
    Quest.resetForTests()
    History.resetForTests()
    Settings.load()
    ReportWindow.hide()
    Quest.handleQuestStart(100)
    Quest.handleResultStart()
    assert(ReportWindow.isOpen() == false)
    Quest.handleResultInfo({ endType = 2, failedType = 0, clearTimeMs = 1000, mainWeaponType = 7, joinMemberNum = 1 }, 161)
    assert(#History.readAll() == 0)
end

function T.unsavedSnapshotIsFlushedAtNextQuestStart()
    playQuestWithOneHit()
    Quest.handleResultStart()
    Quest.handleQuestStart(300)
    local entries = History.readAll()
    assert(#entries == 1 and entries[1].quest.result == "unknown")
    assert(entries[1].quest.elapsedSeconds == 30)
    assert(Session.hitCount() == 0)
end

function T.procOnlySessionIsSavedAndFlushed()
    Quest.resetForTests()
    History.resetForTests()
    Settings.load()
    Quest.handleQuestStart(100)
    Session.addProc({ kind = "blast", damage = 100, time = 120 })
    Quest.handleResultStart()
    assert(ReportWindow.isOpen() == true)
    Quest.handleQuestStart(300)
    local entries = History.readAll()
    assert(#entries == 1)
    assert(entries[1].damage.status == 100 and entries[1].quest.result == "unknown")
end

function T.autoPopupOffKeepsWindowClosed()
    playQuestWithOneHit()
    Settings.set("autoPopup", false)
    ReportWindow.hide()
    Quest.handleResultStart()
    assert(ReportWindow.isOpen() == false)
end

function T.currentSnapshotReportsRunningWhilePlaying()
    playQuestWithOneHit()
    local s = Quest.currentSnapshot(140)
    assert(s.quest.result == "running" and s.quest.elapsedSeconds == 40)
    Quest.handleResultStart()
    Quest.handleResultInfo({ endType = 2, failedType = 0, clearTimeMs = 1000, mainWeaponType = 7, joinMemberNum = 1 }, 161)
    local final = Quest.currentSnapshot(170)
    assert(final.quest.result == "clear")
    assert(final.quest.elapsedSeconds == 1)
end

function T.questEndFreezesElapsedUntilResultInfo()
    playQuestWithOneHit()
    Quest.handleQuestEnd(140)
    local frozen = Quest.currentSnapshot(150)
    assert(frozen.quest.result == "running" and frozen.quest.elapsedSeconds == 40, tostring(frozen.quest.elapsedSeconds))
    assert(Quest.currentSnapshot(200).quest.elapsedSeconds == 40)
    Quest.handleResultStart()
    assert(Quest.currentSnapshot(210).quest.elapsedSeconds == 40)
    Quest.handleResultInfo({ endType = 2, clearTimeMs = 41000, mainWeaponType = 7, joinMemberNum = 1 }, 220)
    assert(Quest.currentSnapshot(230).quest.elapsedSeconds == 41)
    Quest.handleQuestStart(300)
    assert(Quest.currentSnapshot(310).quest.elapsedSeconds == 10)
end

function T.questEndUsesQuestClockAndRoundsLikeClearTime()
    withQuestDirector(function(director)
        local clock = 37.6
        director.get_QuestElapsedTime = function() return clock end
        playQuestWithOneHit()
        assert(Quest.currentSnapshot(150).quest.elapsedSeconds == 37.6)
        clock = 37.9
        assert(Quest.currentSnapshot(160).quest.elapsedSeconds == 37.9)
        Quest.handleQuestEnd(160)
        clock = 55
        assert(Quest.currentSnapshot(170).quest.elapsedSeconds == 38)
        Quest.handleResultStart()
        assert(Quest.currentSnapshot(180).quest.elapsedSeconds == 38)
    end)
end

function T.questEndOutsidePlayingIsIgnored()
    Quest.resetForTests()
    Settings.load()
    Quest.handleQuestEnd(50)
    assert(Quest.phase() == "idle")
    Quest.handleTrainingEnter(200)
    Quest.handleQuestEnd(230)
    assert(Quest.currentSnapshot(240).quest.result == "training")
    assert(Quest.currentSnapshot(240).quest.elapsedSeconds == 40)
end

function T.currentSnapshotDuringResultKeepsFinalSnapshot()
    playQuestWithOneHit()
    Settings.set("autoPopup", false)
    ReportWindow.show(Quest.currentSnapshot(140))
    ReportWindow.setSnapshotProvider(function() return Quest.currentSnapshot(165) end)
    local ok, err = pcall(function()
        Quest.handleResultStart()
        local final = Quest.currentSnapshot(165)
        assert(final.quest.result == "unknown")
        assert(final == Quest.currentSnapshot(170))
        assert(ReportWindow.refreshLive(165) == true)
        assert(ReportWindow.debugState().snapshot == final)
        Quest.handleResultInfo({ endType = 2, clearTimeMs = 1000, mainWeaponType = 7, joinMemberNum = 1 }, 166)
        assert(ReportWindow.refreshLive(170) == false)
        assert(final.quest.result == "clear" and final.quest.elapsedSeconds == 1)
        assert(ReportWindow.debugState().snapshot == final)
        Quest.handleQuestStart(200)
        local running = Quest.currentSnapshot(210)
        assert(running ~= final and running.quest.result == "running" and running.quest.elapsedSeconds == 10)
        assert(Quest.currentSnapshot(220).quest.elapsedSeconds == 20)
        Quest.resetForTests()
        assert(Quest.currentSnapshot(230) ~= final)
    end)
    ReportWindow.hide()
    ReportWindow.setSnapshotProvider(nil)
    if not ok then error(err, 0) end
end

function T.emptyPendingSnapshotIsNotFlushed()
    Quest.resetForTests()
    History.resetForTests()
    Settings.load()
    Quest.handleQuestStart(100)
    Quest.handleResultStart()
    Quest.handleQuestStart(300)
    assert(#History.readAll() == 0)
end

function T.openReportSwitchesToTrainingSession()
    playQuestWithOneHit()
    Settings.set("closeOnQuestStart", false)
    ReportWindow.show({ version = 2, quest = { result = "clear" }, damage = { total = 1, hits = 1 },
        stats = {}, monsters = {}, skills = {}, motions = {}, procs = {}, skillDamage = {} })
    Quest.handleTrainingEnter(200)
    assert(ReportWindow.debugState().snapshot.quest.result == "training")
end

function T.openReportSwitchesToNewQuest()
    playQuestWithOneHit()
    Settings.set("closeOnQuestStart", false)
    ReportWindow.show({ version = 2, quest = { result = "clear" }, damage = { total = 1, hits = 1 },
        stats = {}, monsters = {}, skills = {}, motions = {}, procs = {}, skillDamage = {} })
    Quest.handleQuestStart(300)
    assert(ReportWindow.debugState().snapshot.quest.result == "running")
end

function T.openReportClosesOnSessionStartByDefault()
    playQuestWithOneHit()
    ReportWindow.show({ version = 2, quest = { result = "clear" }, damage = { total = 1, hits = 1 },
        stats = {}, monsters = {}, skills = {}, motions = {}, procs = {}, skillDamage = {} })
    assert(Settings.get().closeOnQuestStart == true)
    Quest.handleQuestStart(300)
    assert(ReportWindow.isOpen() == false)
    Quest.handleTrainingEnter(400)
    assert(ReportWindow.isOpen() == false)
end

function T.historyViewIsNotReplacedOnSessionStart()
    playQuestWithOneHit()
    ReportWindow.showHistory()
    Quest.handleQuestStart(300)
    assert(ReportWindow.debugState().view == "history")
end

function T.failedResultReadKeepsPendingForRetry()
    playQuestWithOneHit()
    Quest.handleResultStart()
    Quest.handleResultInfo(nil, 161)
    assert(#History.readAll() == 0 and Quest.state().saved == false)
    Quest.handleResultInfo({ endType = 2, failedType = 0, clearTimeMs = 5000, mainWeaponType = 7, joinMemberNum = 1 }, 168)
    local entries = History.readAll()
    assert(#entries == 1 and entries[1].quest.result == "clear")
end

function T.trainingEnterResetsAndSetsPhase()
    playQuestWithOneHit()
    Quest.handleTrainingEnter(200)
    assert(Session.hitCount() == 0)
    assert(Quest.phase() == "training")
    local s = Quest.currentSnapshot(210)
    assert(s.quest.result == "training" and s.quest.elapsedSeconds == 10)
    assert(#History.readAll() == 0)
end

function T.adoptCurrentStateEntersTrainingOrQuestAtLoad()
    Quest.resetForTests()
    local originalSingleton = Game.singleton
    local flag = true
    Game.singleton = function(name)
        if name ~= "app.PorterManager" then return nil end
        return { get_CacheHolder = function() return { get_IsInTrainingArea = function() return { get_Value = function() return flag end } end } end }
    end
    local ok, err = pcall(function()
        assert(Quest.adoptCurrentState(500) == true)
        assert(Quest.phase() == "training")
        assert(Quest.currentSnapshot(510).quest.elapsedSeconds == 10)
        assert(Quest.adoptCurrentState(600) == false)
        Quest.resetForTests()
        flag = false
        assert(Quest.adoptCurrentState(700) == false)
        assert(Quest.phase() == "idle")
        Game.singleton = function() return nil end
        assert(Quest.adoptCurrentState(800) == false)
        assert(Quest.phase() == "idle")
        local playing, elapsed = true, 42
        Game.singleton = function(name)
            if name ~= "app.MissionManager" then return nil end
            return {
                get_IsPlayingQuest = function() return playing end,
                get_QuestDirector = function() return { get_QuestElapsedTime = function() return elapsed end } end,
            }
        end
        assert(Quest.adoptCurrentState(900) == true)
        assert(Quest.phase() == "playing")
        local s = Quest.currentSnapshot(910)
        assert(s.quest.result == "running" and s.quest.elapsedSeconds == 42, tostring(s.quest.elapsedSeconds))
        Quest.resetForTests()
        elapsed = nil
        assert(Quest.adoptCurrentState(1000) == true)
        assert(Quest.currentSnapshot(1005).quest.elapsedSeconds == 5)
        Quest.resetForTests()
        playing = false
        assert(Quest.adoptCurrentState(1100) == false)
        assert(Quest.phase() == "idle")
    end)
    Game.singleton = originalSingleton
    if not ok then error(err, 0) end
end

function T.trainingLeaveKeepsData()
    Quest.resetForTests()
    History.resetForTests()
    Settings.load()
    Quest.handleTrainingEnter(200)
    Session.addHit({ monsterId = 5, monsterLabel = { kind = "monster", emId = 5 }, finalDamage = 10, physical = 10, element = 0, weight = 1,
        motionKey = "7:x", motionLabel = { kind = "motion", className = "x", guideId = -1 }, activeSkills = {}, time = 230 })
    Quest.handleTrainingLeave(236)
    assert(Quest.phase() == "idle")
    assert(Session.hitCount() == 1)
    local snapshot = Quest.currentSnapshot(240)
    assert(snapshot.quest.result == "training")
    assert(snapshot.quest.elapsedSeconds == 36)
    Quest.handleQuestStart(300)
    assert(Quest.currentSnapshot(310).quest.result == "running")
end

function T.trainingSessionIsNeverSaved()
    Quest.resetForTests()
    History.resetForTests()
    Settings.load()
    Quest.handleTrainingEnter(200)
    Session.addHit({ monsterId = 5, monsterLabel = { kind = "monster", emId = 5 }, finalDamage = 10, physical = 10, element = 0, weight = 1,
        motionKey = "7:x", motionLabel = { kind = "motion", className = "x", guideId = -1 }, activeSkills = {}, time = 230 })
    Quest.handleTrainingLeave(240)
    Quest.handleQuestStart(300)
    assert(#History.readAll() == 0)
    assert(Session.hitCount() == 0)
end

function T.trainingEnterFlushesUnsavedQuest()
    playQuestWithOneHit()
    Quest.handleResultStart()
    Quest.handleTrainingEnter(300)
    local entries = History.readAll()
    assert(#entries == 1 and entries[1].quest.result == "unknown")
end

function T.foreignTrainingHookIsIgnored()
    local masterHunter = Game.masterHunter
    local ok, err = pcall(function()
        Game.masterHunter = function()
            return { get_HunterStamina = function()
                return { get_address = function() return 100 end }
            end }
        end
        assert(Quest.trainingHookIsMaster({ get_address = function() return 200 end }) == false)
        assert(Quest.trainingHookIsMaster({ get_address = function() return 100 end }) == true)
    end)
    Game.masterHunter = masterHunter
    if not ok then error(err, 0) end
end

function T.unresolvedTrainingOwnerFailsOpen()
    local masterHunter = Game.masterHunter
    local ok, err = pcall(function()
        Game.masterHunter = function() return nil end
        assert(Quest.trainingHookIsMaster({ get_address = function() return 200 end }) == true)
        Game.masterHunter = function()
            return { get_HunterStamina = function() error("boom") end }
        end
        assert(Quest.trainingHookIsMaster({ get_address = function() return 200 end }) == true)
    end)
    Game.masterHunter = masterHunter
    if not ok then error(err, 0) end
end

local function withFakeWeaponInfo(callback)
    local original = Names.resolve
    Names.resolve = function(label)
        if label.kind == "weapon" and label.type ~= nil then return "W" .. label.type end
        return label.kind
    end
    local ok, err = pcall(callback)
    Names.resolve = original
    if not ok then error(err, 0) end
end

function T.liveSnapshotListsUsedWeapons()
    withFakeWeaponInfo(function()
        playQuestWithOneHit()
        Session.addHit({ monsterId = 1, monsterLabel = { kind = "monster", emId = 26 }, finalDamage = 10, physical = 10, element = 0, weight = 1,
            motionKey = "13:y", motionLabel = { kind = "motion", className = "y", guideId = -1 }, activeSkills = {}, time = 131, weaponType = 13 })
        Session.addHit({ monsterId = 1, monsterLabel = { kind = "monster", emId = 26 }, finalDamage = 10, physical = 10, element = 0, weight = 1,
            motionKey = "10:z", motionLabel = { kind = "motion", className = "z", guideId = -1 }, activeSkills = {}, time = 132, weaponType = 10 })
        local snapshot = Quest.currentSnapshot(140)
        assert(#snapshot.quest.weapons == 2)
        assert(snapshot.quest.weapons[1].name == "W13" and snapshot.quest.weapons[2].name == "W10")
    end)
end

function T.resultWeaponOverrideLeavesWeaponsAlone()
    withFakeWeaponInfo(function()
        playQuestWithOneHit()
        Session.addHit({ monsterId = 1, monsterLabel = { kind = "monster", emId = 26 }, finalDamage = 10, physical = 10, element = 0, weight = 1,
            motionKey = "13:y", motionLabel = { kind = "motion", className = "y", guideId = -1 }, activeSkills = {}, time = 131, weaponType = 13 })
        Quest.handleResultStart()
        Quest.handleResultInfo({ endType = 2, failedType = 0, clearTimeMs = 1000, mainWeaponType = 7, joinMemberNum = 1 }, 161)
        local entry = History.readAll()[1]
        assert(entry.quest.weapon.type == 7 and entry.quest.weapon.name == "W7")
        assert(entry.quest.weapon.label.kind == "weapon" and entry.quest.weapon.label.type == 7)
        assert(#entry.quest.weapons == 1 and entry.quest.weapons[1].type == 13)
    end)
end

function T.weaponInfoContainsOnlyType()
    local call = Game.callStatic
    local ok, err = pcall(function()
        Game.callStatic = function() error("weaponInfo must not resolve text") end
        assert(stubs.encode(Quest.weaponInfo(13)) == stubs.encode({ type = 13 }))
        assert(next(Quest.weaponInfo(nil)) == nil)
    end)
    Game.callStatic = call
    if not ok then error(err, 0) end
end

function T.snapshotsResolveNamesAndResultRelabelDoesNotRewriteHistory()
    local original = Names.resolve
    local language = "ko"
    Names.resolve = function(label) return language .. ":" .. label.kind end
    local ok, err = pcall(function()
        playQuestWithOneHit()
        local live = Quest.currentSnapshot(140)
        assert(live.monsters[1].name == "ko:monster" and live.motions[1].name == "ko:motion")
        Quest.handleResultStart()
        local final = ReportWindow.debugState().snapshot
        assert(final.monsters[1].name == "ko:monster")
        Quest.handleResultInfo({ endType = 2, mainWeaponType = 7 }, 161)
        local savedFiles = stubs.encode(stubs.files)
        language = "en"
        assert(Quest.currentSnapshot(170) == final)
        assert(final.monsters[1].name == "en:monster" and final.motions[1].name == "en:motion")
        assert(final.quest.weapon.name == "en:weapon")
        assert(stubs.encode(stubs.files) == savedFiles)
        local saved = History.readAll()[1]
        assert(saved.monsters[1].name == "ko:monster" and saved.monsters[1].label.emId == 26)
        assert(saved.quest.weapon.name == "ko:weapon")
    end)
    Names.resolve = original
    if not ok then error(err, 0) end
end

function T.questStartResetsNamesCache()
    local original = Names.reset
    local resets = 0
    Names.reset = function() resets = resets + 1 end
    local ok, err = pcall(function()
        Quest.resetForTests()
        local before = resets
        Quest.handleQuestStart(100)
        assert(resets == before + 1)
    end)
    Names.reset = original
    if not ok then error(err, 0) end
end

function T.snapshotOptionsCarryOnlyEquippedSkillIds()
    local SkillState = require("MyHuntReport.SkillState")
    local snapshot, equipped = Session.snapshot, SkillState.equippedTracked
    local calls = 0
    local ok, err = pcall(function()
        Quest.resetForTests()
        ReportWindow.hide()
        SkillState.equippedTracked = function() return { { id = "burst:stage2", name = "old" } } end
        Session.snapshot = function(options)
            calls = calls + 1
            assert(options.resolveName == Names.resolve)
            assert(stubs.encode(options.equippedSkills) == stubs.encode({ { id = "burst:stage2" } }))
            return snapshot(options)
        end
        Quest.currentSnapshot(100)
        Quest.handleResultStart()
        assert(calls == 2)
    end)
    Session.snapshot, SkillState.equippedTracked = snapshot, equipped
    if not ok then error(err, 0) end
end

function T.questStartRefreshesEquipmentAfterReset()
    local SkillState = require("MyHuntReport.SkillState")
    local originalReset, originalRefresh = SkillState.reset, SkillState.refreshEquipped
    local events = {}
    SkillState.reset = function() events[#events + 1] = "reset" end
    SkillState.refreshEquipped = function() events[#events + 1] = "refresh" end
    local ok, err = pcall(function()
        Quest.resetForTests()
        History.resetForTests()
        Quest.handleQuestStart(100)
        assert(#events == 2 and events[1] == "reset" and events[2] == "refresh", table.concat(events, ","))
    end)
    SkillState.reset, SkillState.refreshEquipped = originalReset, originalRefresh
    SkillState.reset()
    if not ok then error(err, 0) end
end

function T.questStartAndResetForTestsResetTheHealTracker()
    local HealTracker = require("MyHuntReport.HealTracker")
    local reset = HealTracker.reset
    local calls = 0
    local ok, err = pcall(function()
        HealTracker.reset = function() calls = calls + 1 end
        Quest.resetForTests()
        assert(calls == 1, calls)
        History.resetForTests()
        Settings.load()
        Quest.handleQuestStart(100)
        assert(calls == 2, calls)
    end)
    HealTracker.reset = reset
    Quest.resetForTests()
    if not ok then error(err, 0) end
end

local function showClearReport()
    ReportWindow.show({ version = 2, quest = { result = "clear" }, damage = { total = 1, hits = 1 },
        stats = {}, monsters = {}, skills = {}, motions = {}, procs = {}, skillDamage = {} })
end

function T.resultCloseHidesReportWhenSettingIsOn()
    playQuestWithOneHit()
    Quest.handleQuestEnd(150)
    Quest.handleResultStart()
    Quest.handleResultInfo({ endType = 2, clearTimeMs = 50000 }, 160)
    showClearReport()
    Settings.set("closeOnResultClose", true)
    Quest.handleResultClose(170)
    assert(ReportWindow.isOpen() == false)
    assert(#History.readAll() == 1)
    Settings.set("closeOnResultClose", false)
end

function T.resultCloseLeavesReportOpenWhenSettingIsOff()
    playQuestWithOneHit()
    Quest.handleQuestEnd(150)
    Quest.handleResultStart()
    Quest.handleResultInfo({ endType = 2, clearTimeMs = 50000 }, 160)
    showClearReport()
    assert(Settings.get().closeOnResultClose == false)
    Quest.handleResultClose(170)
    assert(ReportWindow.isOpen() == true)
    assert(#History.readAll() == 1)
end

function T.resultCloseWithClosedWindowIsHarmless()
    playQuestWithOneHit()
    Settings.set("closeOnResultClose", true)
    ReportWindow.hide()
    Quest.handleResultClose(170)
    assert(ReportWindow.isOpen() == false)
    Settings.set("closeOnResultClose", false)
end

function T.installRegistersTheRewardEnterHook()
    local hook = Game.hook
    local names = {}
    local ok, err = pcall(function()
        Game.hook = function(typeName, signature) names[#names + 1] = typeName .. "." .. signature end
        Quest.install()
        local found = false
        for _, name in ipairs(names) do
            if name == "app.cQuestReward.enter()" then found = true end
        end
        assert(found, table.concat(names, ","))
    end)
    Game.hook = hook
    if not ok then error(err, 0) end
end

return T
