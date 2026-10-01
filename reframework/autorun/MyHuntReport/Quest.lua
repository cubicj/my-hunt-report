local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Locale = require("MyHuntReport.Locale")
local Names = require("MyHuntReport.Names")
local Settings = require("MyHuntReport.Settings")
local Session = require("MyHuntReport.Session")
local SkillState = require("MyHuntReport.SkillState")
local HitCapture = require("MyHuntReport.HitCapture")
local ShellTracker = require("MyHuntReport.ShellTracker")
local Procs = require("MyHuntReport.Procs")
local SkillExtras = require("MyHuntReport.SkillExtras")
local HealTracker = require("MyHuntReport.HealTracker")
local History = require("MyHuntReport.History")
local ReportWindow = require("MyHuntReport.ReportWindow")

local Quest = {}

local STORAGE_KEY = "mhr_result_info"
local RESULTS = { [2] = "clear", [3] = "fail", [1] = "abandon" }

local phase = "idle"
local trainingSession = false
local trainingEndTime = nil
local questLevel = nil
local endedElapsed = nil
local saved = false
local pendingSnapshot = nil
local finalSnapshot = nil
local installed = false

function Quest.resultFromEndType(endType)
    return RESULTS[endType] or "unknown"
end

function Quest.weaponInfo(weaponType)
    return { type = weaponType }
end

local function usedWeapons()
    local list = {}
    for index, weaponType in ipairs(Session.weaponTypes()) do
        list[index] = Quest.weaponInfo(weaponType)
    end
    return list
end

local function equippedSkills()
    local list = {}
    for index, entry in ipairs(SkillState.equippedTracked()) do list[index] = { id = entry.id } end
    return list
end

function Quest.state()
    return { phase = phase, saved = saved }
end

function Quest.phase()
    return phase
end

function Quest.handleTrainingEnter(now)
    Quest.handleQuestStart(now)
    questLevel = nil
    phase = "training"
    trainingSession = true
    trainingEndTime = nil
    Log.debug("training area entered at " .. tostring(now))
    ReportWindow.onSessionStart(Quest.currentSnapshot(now))
end

function Quest.handleTrainingLeave(now)
    if phase == "training" then
        phase = "idle"
        trainingEndTime = tonumber(now)
    end
    Log.debug("training area left")
end

local function trainingHookIsMaster(this)
    local ok, masterAddress, thisAddress = pcall(function()
        local hunter = Game.masterHunter()
        if not hunter then return end
        local stamina = hunter:get_HunterStamina()
        if not stamina or not this then return end
        return stamina:get_address(), this:get_address()
    end)
    local outcome = "unresolved"
    if ok and masterAddress and thisAddress and masterAddress ~= 0 and thisAddress ~= 0 then
        outcome = masterAddress == thisAddress and "master" or "foreign"
    end
    Log.debug("training hook owner check: " .. tostring(outcome), "quest:training-owner")
    return outcome ~= "foreign"
end

Quest.trainingHookIsMaster = trainingHookIsMaster

local function flushUnsaved()
    if not pendingSnapshot then return end
    local snapshot = pendingSnapshot
    pendingSnapshot = nil
    if not Session.snapshotHasData(snapshot) then
        Log.debug("quest discarded without hits")
        return
    end
    snapshot.quest.result = "unknown"
    local ok = History.append(snapshot)
    if not ok then Log.error("history append failed for an unfinished quest", "quest:flush") end
end

function Quest.handleQuestStart(now)
    Locale.refresh()
    if not pendingSnapshot and Session.hasData() then
        Log.debug("quest session discarded without result")
    end
    flushUnsaved()
    finalSnapshot = nil
    Session.reset(now)
    questLevel = Quest.readQuestLevel()
    HitCapture.reset()
    ShellTracker.reset()
    SkillState.reset()
    SkillState.refreshEquipped()
    Names.reset()
    Procs.reset()
    SkillExtras.reset()
    HealTracker.reset()
    ReportWindow.setNotSaved(false)
    phase = "playing"
    trainingSession = false
    trainingEndTime = nil
    endedElapsed = nil
    saved = false
    Log.debug("quest start at " .. tostring(now))
    ReportWindow.onSessionStart(Quest.currentSnapshot(now))
end

local function playingElapsed(now)
    if endedElapsed then return endedElapsed end
    local clock = Quest.questElapsedSeconds()
    if clock then return clock end
    return math.max(0, (tonumber(now) or 0) - Session.startTime())
end

function Quest.handleQuestEnd(now)
    if phase ~= "playing" or endedElapsed then return end
    endedElapsed = math.floor(playingElapsed(now) + 0.5)
    Log.debug("quest end at " .. tostring(now) .. ", elapsed=" .. tostring(endedElapsed))
end

function Quest.handleResultStart()
    pendingSnapshot = Session.snapshot({
        questLevel = questLevel,
        result = "unknown",
        elapsedSeconds = endedElapsed,
        endedAt = os.time(),
        weapon = Quest.weaponInfo(HitCapture.lastWeaponType()),
        weapons = usedWeapons(),
        equippedSkills = equippedSkills(),
        resolveName = Names.resolve,
    })
    finalSnapshot = pendingSnapshot
    phase = "result"
    if Settings.get().autoPopup and Session.hasData() then
        ReportWindow.show(pendingSnapshot)
    end
    Log.debug("quest result start, hits=" .. tostring(Session.hitCount()))
end

function Quest.handleResultInfo(fields, now)
    if type(fields) ~= "table" then return end
    if saved or not pendingSnapshot then return end
    local snapshot = pendingSnapshot
    snapshot.quest.result = Quest.resultFromEndType(fields.endType)
    if type(fields.questLevel) == "number" and fields.questLevel > 0 then
        snapshot.quest.level = fields.questLevel
    end
    if type(fields.clearTimeMs) == "number" and fields.clearTimeMs > 0 then
        snapshot.quest.elapsedSeconds = math.floor(fields.clearTimeMs / 1000 + 0.5)
    end
    if type(fields.mainWeaponType) == "number" then
        snapshot.quest.weapon = {
            type = fields.mainWeaponType,
            label = { kind = "weapon", type = fields.mainWeaponType },
        }
    end
    snapshot.quest.playerCount = fields.joinMemberNum
    Session.relabel(snapshot, Names.resolve)
    if Session.hasData() then
        local ok = History.append(snapshot)
        ReportWindow.setNotSaved(not ok)
    else
        Log.debug("quest result without hits, not saved")
    end
    saved = true
    pendingSnapshot = nil
    Log.debug("quest result " .. snapshot.quest.result .. " at " .. tostring(now))
end

function Quest.currentSnapshot(now)
    if phase == "result" and finalSnapshot then return Session.relabel(finalSnapshot, Names.resolve) end
    local result = "unknown"
    if phase == "playing" then result = "running" end
    if phase == "training" or (phase == "idle" and trainingSession) then result = "training" end
    local endTime = tonumber(now) or 0
    if phase == "idle" and trainingEndTime then endTime = trainingEndTime end
    local elapsed = math.max(0, endTime - Session.startTime())
    if phase == "playing" then elapsed = playingElapsed(now) end
    return Session.snapshot({
        questLevel = questLevel,
        result = result,
        elapsedSeconds = elapsed,
        endedAt = os.time(),
        weapon = Quest.weaponInfo(HitCapture.lastWeaponType()),
        weapons = usedWeapons(),
        equippedSkills = equippedSkills(),
        resolveName = Names.resolve,
    })
end

local function readResultFields(info)
    local fields = {}
    local ok, err = pcall(function()
        fields.endType = info:get_QuestEndType()
        fields.failedType = info:get_QuestFailedType()
        fields.clearTimeMs = info:get_ClearTime()
        fields.mainWeaponType = info:get_MainWeaponType()
        fields.joinMemberNum = info:get_JoinMemberNum()
        fields.questLevel = info:get_QuestLevel()
    end)
    if not ok then
        Log.error("quest result read failed: " .. tostring(err), "quest:result")
        return nil
    end
    return fields
end

function Quest.isInTrainingArea()
    local ok, value = pcall(function()
        return Game.singleton("app.PorterManager"):get_CacheHolder():get_IsInTrainingArea():get_Value()
    end)
    return ok and value == true
end

function Quest.isPlayingQuest()
    local ok, value = pcall(function()
        return Game.singleton("app.MissionManager"):get_IsPlayingQuest()
    end)
    return ok and value == true
end

function Quest.questElapsedSeconds()
    local ok, value = pcall(function()
        return Game.singleton("app.MissionManager"):get_QuestDirector():get_QuestElapsedTime()
    end)
    if ok and type(value) == "number" and value >= 0 then return value end
    return nil
end

function Quest.readQuestLevel()
    local ok, value = pcall(function()
        return Game.singleton("app.MissionManager"):get_QuestDirector()._QuestData._KeepQuestData._QuestLv
    end)
    if ok and type(value) == "number" and value > 0 then return value end
    return nil
end

function Quest.adoptCurrentState(now)
    if phase ~= "idle" then return false end
    if Quest.isInTrainingArea() then
        Quest.handleTrainingEnter(now)
        Log.debug("training area adopted at load")
        return true
    end
    if Quest.isPlayingQuest() then
        local elapsed = Quest.questElapsedSeconds() or 0
        Quest.handleQuestStart(now - elapsed)
        Log.debug(string.format("quest adopted at load, elapsed=%.1f", elapsed))
        return true
    end
    return false
end

function Quest.install()
    if installed then return end
    installed = true
    Game.hook("app.cQuestPlaying", "enter()", function()
        Quest.handleQuestStart(Game.uptime())
    end)
    Game.hook("app.cQuestClear", "enter()", function()
        Quest.handleQuestEnd(Game.uptime())
    end)
    Game.hook("app.cQuestFailed", "enter()", function()
        Quest.handleQuestEnd(Game.uptime())
    end)
    Game.hook("app.cQuestResult", "enter()", function()
        Quest.handleResultStart()
    end)
    Game.hook("app.cGUIQuestResultInfo", "execute()", function(args)
        thread.get_hook_storage()[STORAGE_KEY] = sdk.to_managed_object(args[2])
    end, function()
        local storage = thread.get_hook_storage()
        local info = storage[STORAGE_KEY]
        storage[STORAGE_KEY] = nil
        if info then
            local fields = readResultFields(info)
            if type(fields) == "table" then Quest.handleResultInfo(fields, Game.uptime()) end
        end
    end)
    Game.hook("app.cHunterStamina", "onEnterTrainingArea(System.Boolean)", function(args)
        thread.get_hook_storage()["mhr_training_enter"] = sdk.to_managed_object(args[2])
    end, function()
        local storage = thread.get_hook_storage()
        local this = storage["mhr_training_enter"]
        storage["mhr_training_enter"] = nil
        if Quest.trainingHookIsMaster(this) then Quest.handleTrainingEnter(Game.uptime()) end
    end)
    Game.hook("app.cHunterStamina", "onLeaveTrainingArea(System.Boolean)", function(args)
        thread.get_hook_storage()["mhr_training_leave"] = sdk.to_managed_object(args[2])
    end, function()
        local storage = thread.get_hook_storage()
        local this = storage["mhr_training_leave"]
        storage["mhr_training_leave"] = nil
        if Quest.trainingHookIsMaster(this) then Quest.handleTrainingLeave(Game.uptime()) end
    end)
end

function Quest.resetForTests()
    phase = "idle"
    questLevel = nil
    trainingSession = false
    trainingEndTime = nil
    endedElapsed = nil
    saved = false
    pendingSnapshot = nil
    Session.reset(0)
    finalSnapshot = nil
    HitCapture.reset()
    ShellTracker.reset()
    Procs.reset()
    SkillExtras.reset()
    HealTracker.reset()
    ReportWindow.hide()
    ReportWindow.setNotSaved(false)
end

return Quest
