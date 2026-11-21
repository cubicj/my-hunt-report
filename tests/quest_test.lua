local stubs = require("stubs")
local Quest = require("MyHuntReport.Quest")
local Session = require("MyHuntReport.Session")
local History = require("MyHuntReport.History")
local ReportWindow = require("MyHuntReport.ReportWindow")
local Settings = require("MyHuntReport.Settings")
local Game = require("MyHuntReport.Game")
local Names = require("MyHuntReport.Names")
local SkillState = require("MyHuntReport.SkillState")

local T = {}

local function addHit(time, damage)
    damage = damage or 10
    Session.addHit({ monsterId = 1, monsterLabel = { kind = "monster", emId = 26 }, finalDamage = damage, physical = damage, element = 0, weight = 1,
        motionKey = "7:x", motionLabel = { kind = "motion", className = "x", guideId = -1 }, activeSkills = {}, time = time })
end

local function playQuestWithOneHit()
    Quest.resetForTests()
    History.resetForTests()
    Settings.load()
    Quest.handleQuestStart(100)
    addHit(130)
end

local function playQuestWithTwoSegments()
    playQuestWithOneHit()
    Quest.resetSegment(400)
    addHit(450, 20)
    Quest.handleQuestEnd(700)
    Quest.handleResultStart()
end

local function withCapturedSnapshots(callback)
    local snapshot = Session.snapshot
    local snapshots = {}
    Session.snapshot = function(options)
        local captured = snapshot(options)
        snapshots[#snapshots + 1] = captured
        return captured
    end
    local ok, err = pcall(callback, snapshots)
    Session.snapshot = snapshot
    if not ok then error(err, 0) end
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
    assert(entries[1].quest.segment == nil)
    assert(Quest.state().saved == true)
end

function T.resultSavesBothSegmentsWithTheSameQuestFields()
    playQuestWithTwoSegments()
    local resolve = Names.resolve
    Names.resolve = function(label) return "result:" .. label.kind end
    local fields = { endType = 2, questLevel = 7, clearTimeMs = 605000, mainWeaponType = 3, joinMemberNum = 4 }
    local ok, err = pcall(function()
        Quest.handleResultInfo(fields, 710)
        Quest.handleResultInfo(fields, 720)
    end)
    Names.resolve = resolve
    if not ok then error(err, 0) end

    local entries, _, lines = History.readAll()
    assert(#entries == 2, "expected two history lines, got " .. #entries)
    for _, entry in ipairs(entries) do
        local quest = entry.quest
        assert(quest.result == "clear" and quest.level == 7 and quest.elapsedSeconds == 605)
        assert(quest.weapon.type == 3 and quest.playerCount == 4)
        assert(entry.monsters[1].name == "result:monster" and entry.motions[1].name == "result:motion")
    end
    assert(stubs.encode(entries[1].quest.segment) == stubs.encode({ index = 1, count = 2, startSeconds = 0, endSeconds = 300 }))
    assert(stubs.encode(entries[2].quest.segment) == stubs.encode({ index = 2, count = 2, startSeconds = 300, endSeconds = 600 }))
    assert(entries[1].damage.total == 10 and entries[2].damage.total == 20)
    assert(History.remove(lines[1], entries[1].quest.endedAt) == true)
    local remaining = History.readAll()
    assert(#remaining == 1 and remaining[1].quest.segment.index == 2)
end

function T.resultStartCopiesWholeQuestElapsedToTheClosedSegment()
    playQuestWithOneHit()
    withCapturedSnapshots(function(snapshots)
        Quest.resetSegment(400)
        local closed = snapshots[1]
        assert(closed.quest.elapsedSeconds == 300)
        addHit(450, 20)
        Quest.handleQuestEnd(700)
        Quest.handleResultStart()
        local last = Quest.currentSnapshot(710)
        assert(closed.quest.elapsedSeconds == last.quest.elapsedSeconds and last.quest.elapsedSeconds == 600,
            "closed segment still has elapsedSeconds=" .. closed.quest.elapsedSeconds)
        assert(last.quest.segment.endSeconds == 600)
    end)
end

function T.abandonIsSaved()
    playQuestWithOneHit()
    Quest.handleResultStart()
    assert(Quest.currentSnapshot(160).quest.elapsedSeconds == 30)
    Quest.handleResultInfo({ endType = 1, failedType = 0, clearTimeMs = 27170, mainWeaponType = 13, joinMemberNum = 1 }, 161)
    local entries = History.readAll()
    assert(#entries == 1 and entries[1].quest.result == "abandon")
end

function T.abandonAfterResetUsesTheWholeQuestLastHit()
    playQuestWithOneHit()
    Quest.resetSegment(400)
    addHit(450, 20)
    Quest.handleResultStart()
    local result = Quest.currentSnapshot(460)
    assert(result.quest.elapsedSeconds == 350, "expected whole-quest elapsed, got " .. result.quest.elapsedSeconds)
    assert(result.quest.segment.endSeconds == 350)
end

function T.abandonWithAnEmptyLastSegmentSavesTheEarlierSegment()
    playQuestWithOneHit()
    Quest.resetSegment(400)
    Quest.handleResultStart()
    local result = Quest.currentSnapshot(410)
    assert(result.damage.total == 10, "expected the earlier segment's 10 damage, got " .. result.damage.total)
    assert(result.quest.elapsedSeconds == 300,
        "expected elapsed to reach the last reset, got " .. result.quest.elapsedSeconds)
    Quest.handleResultInfo({ endType = 1 }, 410)
    local entries = History.readAll()
    assert(#entries == 1 and entries[1].quest.elapsedSeconds == 300)
    assert(stubs.encode(entries[1].quest.segment) == stubs.encode({ index = 1, count = 1, startSeconds = 0, endSeconds = 300 }))
    assert(entries[1].damage.total == 10)
end

function T.clearWithAnEmptyLastSegmentShowsAndSavesTheEarlierSegment()
    playQuestWithOneHit()
    Settings.set("autoPopup", true)
    Quest.resetSegment(400)
    Quest.handleQuestEnd(700)
    Quest.handleResultStart()
    assert(ReportWindow.isOpen(), "expected the result popup with a kept segment")
    local shown = ReportWindow.debugState().snapshot
    assert(shown.damage.total == 10 and Quest.currentSnapshot(710) == shown)

    local relabel, relabels = Session.relabel, 0
    Session.relabel = function(snapshot, resolve)
        if snapshot == shown then relabels = relabels + 1 end
        return relabel(snapshot, resolve)
    end
    local fields = { endType = 2, questLevel = 7, clearTimeMs = 605000, mainWeaponType = 3, joinMemberNum = 4 }
    local ok, err = pcall(function()
        Quest.handleResultInfo(fields, 710)
        Quest.handleResultInfo(fields, 720)
    end)
    Session.relabel = relabel
    if not ok then error(err, 0) end

    assert(relabels == 1)
    local entries = History.readAll()
    assert(#entries == 1 and entries[1].damage.total == 10)
    for _, quest in ipairs({ shown.quest, entries[1].quest }) do
        assert(quest.result == "clear" and quest.level == 7 and quest.elapsedSeconds == 605)
        assert(quest.weapon.type == 3 and quest.playerCount == 4)
    end
end

function T.abandonAfterResetWithOnlyProcDamageEndsAtTheProc()
    playQuestWithOneHit()
    Quest.resetSegment(400)
    Session.addProc({ kind = "woundBreak", damage = 5, time = 450 })
    Quest.handleResultStart()
    Quest.handleResultInfo({ endType = 1 }, 460)
    local entries = History.readAll()
    assert(#entries == 2 and entries[2].damage.total == 5)
    local segment = entries[2].quest.segment
    assert(stubs.encode(segment) == stubs.encode({ index = 2, count = 2, startSeconds = 300, endSeconds = 350 }),
        "expected proc at second 350 in the segment, got endSeconds=" .. segment.endSeconds)
    assert(entries[1].quest.elapsedSeconds == 350 and entries[2].quest.elapsedSeconds == 350)
end

function T.resultSkipsEmptySegmentsBetweenResets()
    playQuestWithOneHit()
    Quest.resetSegment(400)
    Quest.resetSegment(500)
    addHit(550, 20)
    Quest.handleQuestEnd(700)
    Quest.handleResultStart()
    Quest.handleResultInfo({ endType = 2 }, 710)
    local entries = History.readAll()
    assert(#entries == 2)
    assert(stubs.encode(entries[1].quest.segment) == stubs.encode({ index = 1, count = 2, startSeconds = 0, endSeconds = 300 }))
    assert(stubs.encode(entries[2].quest.segment) == stubs.encode({ index = 2, count = 2, startSeconds = 400, endSeconds = 600 }))
end

function T.resultKeepsSegmentMetadataWhenTheFirstResetClosesNoHits()
    Quest.resetForTests()
    History.resetForTests()
    Settings.load()
    Quest.handleQuestStart(100)
    Quest.resetSegment(400)
    addHit(450, 20)
    Quest.handleQuestEnd(700)
    Quest.handleResultStart()
    Quest.handleResultInfo({ endType = 2 }, 710)
    local entries = History.readAll()
    assert(#entries == 1)
    assert(stubs.encode(entries[1].quest.segment) == stubs.encode({ index = 1, count = 1, startSeconds = 300, endSeconds = 600 }))
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

function T.nextQuestStartFlushesBothPendingSegments()
    playQuestWithTwoSegments()
    Quest.handleQuestStart(800)
    local entries = History.readAll()
    assert(#entries == 2, "expected two flushed history lines, got " .. #entries)
    for _, entry in ipairs(entries) do
        assert(entry.quest.result == "unknown" and entry.quest.elapsedSeconds == 600)
    end
    assert(stubs.encode(entries[1].quest.segment) == stubs.encode({ index = 1, count = 2, startSeconds = 0, endSeconds = 300 }))
    assert(stubs.encode(entries[2].quest.segment) == stubs.encode({ index = 2, count = 2, startSeconds = 300, endSeconds = 600 }))
    assert(entries[1].damage.total == 10 and entries[2].damage.total == 20)
end

function T.repeatedResultStartDoesNotDuplicateSavedSegments()
    playQuestWithTwoSegments()
    Quest.handleResultInfo({ endType = 2 }, 710)
    local shown = Quest.currentSnapshot(711)
    Quest.handleResultStart()
    assert(Quest.currentSnapshot(712) == shown)
    Quest.handleQuestStart(800)
    local entries = History.readAll()
    assert(#entries == 2, "expected two history lines, got " .. #entries)
    for index, entry in ipairs(entries) do
        assert(entry.quest.result == "clear" and entry.quest.segment.index == index)
    end
    assert(entries[1].damage.total == 10 and entries[2].damage.total == 20)
end

function T.resultAttemptsTheRemainingSegmentsAfterAnAppendFails()
    playQuestWithOneHit()
    Quest.resetSegment(200)
    addHit(230, 20)
    Quest.resetSegment(300)
    addHit(330, 30)
    Quest.handleQuestEnd(400)
    Quest.handleResultStart()
    local append = History.append
    local attempted = {}
    History.append = function(snapshot)
        attempted[#attempted + 1] = snapshot.quest.segment.index
        if #attempted == 2 then return false end
        return append(snapshot)
    end
    local fields = { endType = 2 }
    local ok, err = pcall(function()
        Quest.handleResultInfo(fields, 410)
        Quest.handleResultInfo(fields, 420)
    end)
    History.append = append
    if not ok then error(err, 0) end

    assert(stubs.encode(attempted) == stubs.encode({ 1, 2, 3 }))
    local entries = History.readAll()
    assert(#entries == 2 and entries[1].quest.segment.index == 1 and entries[2].quest.segment.index == 3)
    assert(ReportWindow.debugState().notSaved == true and Quest.state().saved == true)
    Quest.handleQuestStart(500)
    assert(#History.readAll() == 2)
end

function T.resultReportKeepsTheLastSegmentAndNotifiesOnce()
    playQuestWithTwoSegments()
    local shown = ReportWindow.debugState().snapshot
    assert(shown == Quest.currentSnapshot(701) and shown.damage.total == 20)
    local notify = ReportWindow.onSnapshotMutated
    local notifications = 0
    ReportWindow.onSnapshotMutated = function()
        assert(shown.quest.result == "clear" and shown.quest.segment.index == 2 and shown.quest.segment.count == 2)
        notifications = notifications + 1
        notify()
    end
    local ok, err = pcall(function()
        Quest.handleResultInfo({ endType = 2 }, 710)
        Quest.handleResultInfo({ endType = 2 }, 720)
    end)
    ReportWindow.onSnapshotMutated = notify
    if not ok then error(err, 0) end
    assert(notifications == 1 and Quest.currentSnapshot(730) == shown)
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

function T.resetAvailabilityFollowsPhase()
    Quest.resetForTests()
    addHit(50)
    assert(Quest.canReset() == false)
    assert(Quest.resetSegment(60) == false and Session.hitCount() == 1)
    playQuestWithOneHit()
    assert(Quest.canReset() == true)
    Quest.handleResultStart()
    assert(Quest.canReset() == false)
    assert(Quest.resetSegment(200) == false and Session.hitCount() == 1)
    Quest.handleTrainingEnter(300)
    assert(Quest.canReset() == true)
end

function T.resetClosesACompleteSnapshotWithoutWritingHistory()
    withQuestDirector(function()
        playQuestWithOneHit()
        Session.addFightingTime(2.5)
        stubs.now = stubs.now + 300
        local expected = Quest.currentSnapshot(400)
        expected.quest.result = "unknown"
        expected.quest.segment = { startSeconds = 0, endSeconds = 300 }
        withCapturedSnapshots(function(snapshots)
            assert(Quest.resetSegment(400) == true)
            assert(stubs.encode(snapshots[1]) == stubs.encode(expected))
        end)
        assert(#History.readAll() == 0)
        assert(Session.hitCount() == 0 and Quest.currentSnapshot(450).damage.total == 0)
    end)
end

function T.resetKeepsElapsedBasedOnOriginalQuestStart()
    playQuestWithOneHit()
    assert(Quest.resetSegment(400) == true)
    assert(Quest.currentSnapshot(500).quest.elapsedSeconds == 400)
    Quest.handleQuestEnd(700)
    Quest.handleResultStart()
    assert(Quest.currentSnapshot(710).quest.elapsedSeconds == 600)
end

function T.resetAddsLiveSegmentAndSkipsEmptySegmentsInItsIndex()
    playQuestWithOneHit()
    assert(Quest.currentSnapshot(140).quest.segment == nil)
    assert(Quest.resetSegment(400) == true)
    local first = Quest.currentSnapshot(450).quest.segment
    assert(stubs.encode(first) == stubs.encode({ index = 2, startSeconds = 300 }))
    assert(Quest.resetSegment(500) == true)
    local second = Quest.currentSnapshot(550).quest.segment
    assert(stubs.encode(second) == stubs.encode({ index = 2, startSeconds = 400 }))
    Quest.handleQuestStart(600)
    assert(Quest.currentSnapshot(610).quest.segment == nil and #History.readAll() == 0)
    assert(Quest.resetSegment(620) == true)
    assert(stubs.encode(Quest.currentSnapshot(630).quest.segment) == stubs.encode({ index = 1, startSeconds = 20 }))
end

function T.resetRoundsSegmentBoundaryFromGameClock()
    withQuestDirector(function(director)
        local clock = 37.6
        director.get_QuestElapsedTime = function() return clock end
        playQuestWithOneHit()
        withCapturedSnapshots(function(snapshots)
            assert(Quest.resetSegment(400) == true)
            assert(snapshots[1].quest.segment.endSeconds == 38)
        end)
        clock = 39.1
        local live = Quest.currentSnapshot(450)
        assert(live.quest.segment.startSeconds == 38 and live.quest.elapsedSeconds == 39.1)
        clock = nil
        assert(math.abs(Quest.currentSnapshot(460).quest.elapsedSeconds - 49.1) < 1e-6,
            "fallback must use the most recent clock reading")
    end)
end

function T.lateJoinRetainsTheHostClockAtQuestEndAfterReset()
    withQuestDirector(function(director)
        local clock = 170
        director.get_QuestElapsedTime = function() return clock end
        Quest.resetForTests()
        History.resetForTests()
        Settings.load()
        Quest.handleQuestStart(1000)
        assert(Quest.currentSnapshot(1000).quest.elapsedSeconds == 170)
        addHit(1010)
        clock = 190
        assert(Quest.resetSegment(1020))
        addHit(1040, 20)
        clock = nil
        Quest.handleQuestEnd(1041)
        Quest.handleResultStart()
        Quest.handleResultInfo({ endType = 3 }, 1042)
        local entries = History.readAll()
        assert(#entries == 2)
        local quest = entries[2].quest
        assert(quest.segment.startSeconds == 190)
        assert(quest.segment.endSeconds == 211, "expected host quest second 211, got " .. quest.segment.endSeconds)
        assert(quest.elapsedSeconds == 211)
    end)
end

function T.resetKeepsShellLaunchAttributionAndTracking()
    local modules = {}
    local environment = setmetatable({
        require = function(name) return modules[name] or require(name) end,
    }, { __index = _G })
    for _, name in ipairs({ "ShellTracker", "HitCapture", "Quest" }) do
        modules["MyHuntReport." .. name] = assert(loadfile("reframework/autorun/MyHuntReport/" .. name .. ".lua", "t", environment))()
    end
    local tracker = modules["MyHuntReport.ShellTracker"]
    local capture = modules["MyHuntReport.HitCapture"]
    local quest = modules["MyHuntReport.Quest"]
    local className, guideId = "cBeforeReset", -1
    local equippedSkill = 59
    local owner = { get_address = function() return 1 end }
    local hunter = {
        get_GameObject = function() return owner end,
        get_WeaponType = function() return 7 end,
        get_HunterSkill = function()
            return { checkSkillActive = function(_, id) return id == equippedSkill end }
        end,
        call = function(_, getter)
            if getter ~= "get_BaseActionController" then return nil end
            return { get_CurrentAction = function()
                return { _ActionGuideID = guideId, get_type_definition = function() return { get_name = function() return className end } end }
            end }
        end,
    }
    local shell = {
        get_address = function() return 42 end,
        get_ParentShell = function() return nil end,
        get_Name = function() return "Wp07Shell" end,
        call = function(self, getter)
            if getter == "getComponent(System.Type)" then return self end
            if getter == "get_NameHash" then return 1853117018 end
        end,
    }
    local enemy = {
        get_IsBoss = function() return true end,
        get_UniqueIndex = function() return 10 end,
        get_EmID = function() return 26 end,
    }
    local function hit(address, time, weaponType, attackObject, damage)
        local info = {
            get_AttackData = function() return { _OriginalAttackAdjust = 30, _ActionType = 0, _WeaponType = weaponType } end,
            getActualAttackOwner = function() return owner end,
            get_DamageOwner = function() return enemy end,
            get_AttackObj = function() return attackObject end,
            get_address = function() return address end,
        }
        Game.uptime = function() return time end
        capture.handleStockDamageDetail(info)
        capture.handlePlayHitMarkEffect({ FinalDamage = damage, Physical = damage, Element = 0 }, info)
    end
    local hooks = {}
    local hook, master, enemyContext, uptime, managed = Game.hook, Game.masterHunter, Game.enemyContext, Game.uptime, sdk.to_managed_object
    Game.hook = function(_, signature, pre) hooks[signature] = pre end
    Game.masterHunter = function() return hunter end
    Game.enemyContext = function(target) return target end
    sdk.to_managed_object = function(object) return object end
    local ok, err = pcall(function()
        Settings.load()
        tracker.install()
        quest.handleQuestStart(100)
        hit(101, 130, 7, nil, 10)
        className, guideId = "cShellFire", 9300
        hooks.doOnSetUp({ [2] = shell })
        assert(capture.lastWeaponType() == 7 and stubs.encode(SkillState.trackedIds()) == stubs.encode({ 59 }))
        className, guideId = "cAfterReset", -1
        equippedSkill = nil
        withCapturedSnapshots(function(snapshots)
            assert(quest.resetSegment(400) == true)
            assert(capture.lastWeaponType() == 7 and stubs.encode(SkillState.trackedIds()) == stubs.encode({ 59 }))
            hit(102, 450, -1, shell, 25)
            local closed = snapshots[1]
            assert(closed.damage.hits == 1 and closed.damage.total == 10 and closed.motions[1].label.className == "cBeforeReset")
            local live = quest.currentSnapshot(450)
            local row = live.motions[1]
            assert(#live.motions == 1 and row.label.className == "cShellFire" and row.label.guideId == 9300 and row.hits == 1)
            assert(live.damage.total == 25)
        end)
    end)
    Game.hook, Game.masterHunter, Game.enemyContext, Game.uptime, sdk.to_managed_object = hook, master, enemyContext, uptime, managed
    SkillState.reset()
    quest.resetForTests()
    if not ok then error(err, 0) end
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

function T.trainingResetRestartsElapsedAndKeepsHistoryEmpty()
    Quest.resetForTests()
    History.resetForTests()
    Settings.load()
    Quest.handleTrainingEnter(100)
    addHit(130)
    assert(Quest.resetSegment(200) == true)
    assert(Session.hitCount() == 0)
    local live = Quest.currentSnapshot(250)
    assert(live.quest.segment == nil and live.quest.elapsedSeconds == 50)
    Quest.handleTrainingLeave(260)
    assert(Quest.currentSnapshot(280).quest.elapsedSeconds == 60)
    Quest.handleQuestStart(300)
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
        elapsed = nil
        local s = Quest.currentSnapshot(900)
        assert(s.quest.result == "running" and s.quest.elapsedSeconds == 42, tostring(s.quest.elapsedSeconds))
        elapsed = 52
        assert(Quest.resetSegment(910) == true)
        elapsed = nil
        assert(Quest.currentSnapshot(920).quest.elapsedSeconds == 62)
        Quest.resetForTests()
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
    local snapshot, tracked = Session.snapshot, SkillState.trackedIds
    local calls = 0
    local ok, err = pcall(function()
        Quest.resetForTests()
        ReportWindow.hide()
        SkillState.trackedIds = function() return { "burst:stage2" } end
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
    Session.snapshot, SkillState.trackedIds = snapshot, tracked
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
    Quest.handleQuestEnd(150)
    Quest.handleResultStart()
    Settings.set("closeOnResultClose", true)
    ReportWindow.hide()
    Quest.handleResultClose(170)
    assert(ReportWindow.isOpen() == false)
    Settings.set("closeOnResultClose", false)
end

function T.resultCloseOutsideResultPhaseIsIgnored()
    playQuestWithOneHit()
    showClearReport()
    Settings.set("closeOnResultClose", true)
    Quest.handleResultClose(140)
    assert(ReportWindow.isOpen() == true)
    Settings.set("closeOnResultClose", false)
end

function T.resultCloseActsOncePerResult()
    playQuestWithOneHit()
    Quest.handleQuestEnd(150)
    Quest.handleResultStart()
    Settings.set("closeOnResultClose", true)
    Quest.handleResultClose(170)
    assert(ReportWindow.isOpen() == false)
    showClearReport()
    Quest.handleResultClose(171)
    assert(ReportWindow.isOpen() == true)
    Quest.handleQuestStart(300)
    Session.addHit({ monsterId = 1, monsterLabel = { kind = "monster", emId = 26 }, finalDamage = 10, physical = 10, element = 0, weight = 1,
        motionKey = "7:x", motionLabel = { kind = "motion", className = "x", guideId = -1 }, activeSkills = {}, time = 330 })
    Quest.handleQuestEnd(350)
    Quest.handleResultStart()
    showClearReport()
    Quest.handleResultClose(370)
    assert(ReportWindow.isOpen() == false)
    Settings.set("closeOnResultClose", false)
end

function T.installRegistersTheEndFlowHookInsteadOfRewardEnter()
    local hook = Game.hook
    local names = {}
    local ok, err = pcall(function()
        Game.hook = function(typeName, signature) names[#names + 1] = typeName .. "." .. signature end
        Quest.install()
        local endFlow, rewardEnter = false, false
        for _, name in ipairs(names) do
            if name == "app.cQuestDirector.endFlow()" then endFlow = true end
            if name == "app.cQuestReward.enter()" then rewardEnter = true end
        end
        assert(endFlow and not rewardEnter, table.concat(names, ","))
    end)
    Game.hook = hook
    if not ok then error(err, 0) end
end

function T.questStartAndResetClearThePalicoCapture()
    local Palico = require("MyHuntReport.Palico")
    local reset, resets = Palico.reset, 0
    Palico.reset = function() resets = resets + 1 end
    local ok, err = pcall(function()
        Quest.resetForTests()
        assert(resets == 1)
        Quest.handleQuestStart(100)
        assert(resets == 2)
    end)
    Palico.reset = reset
    Quest.resetForTests()
    if not ok then error(err, 0) end
end

function T.resultStartLogsThePalicoSummaryForTheTailSnapshot()
    local Palico = require("MyHuntReport.Palico")
    local logSummary, logged = Palico.logSummary, {}
    Palico.logSummary = function(snapshot) logged[#logged + 1] = snapshot end
    local ok, err = pcall(function()
        playQuestWithOneHit()
        Session.addPalicoHit(10)
        Quest.handleResultStart()
        assert(#logged == 1)
        assert(logged[1].palico.damage == 10 and logged[1].palico.share == 0.5 and logged[1].damage.total == 10)

        playQuestWithOneHit()
        Quest.resetSegment(400)
        Session.addPalicoHit(20)
        Quest.handleResultStart()
        assert(#logged == 2 and logged[2].palico.damage == 20 and logged[2].damage.total == 0)
    end)
    Palico.logSummary = logSummary
    Quest.resetForTests()
    History.resetForTests()
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.resultInfoNotifiesTheReportAfterMutatingTheShownSnapshot()
    local notify = ReportWindow.onSnapshotMutated
    local seen = {}
    local ok, err = pcall(function()
        playQuestWithOneHit()
        Quest.handleResultStart()
        local shown = ReportWindow.debugState().snapshot
        assert(shown ~= nil)
        ReportWindow.onSnapshotMutated = function()
            seen[#seen + 1] = { result = shown.quest.result, elapsed = shown.quest.elapsedSeconds }
            notify()
        end
        local fields = { endType = 2, failedType = 0, clearTimeMs = 27430, mainWeaponType = 13, joinMemberNum = 1 }
        Quest.handleResultInfo(fields, 161)
        assert(#seen == 1 and seen[1].result == "clear" and seen[1].elapsed == 27)
        Quest.handleResultInfo(fields, 168)
        assert(#seen == 1)
    end)
    ReportWindow.onSnapshotMutated = notify
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

return T
