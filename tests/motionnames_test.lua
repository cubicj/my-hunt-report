local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Locale = require("MyHuntReport.Locale")
local MotionNames = require("MyHuntReport.MotionNames")

local T = {}

local function fakeAction(className, guideId)
    return {
        get_type_definition = function() return { get_name = function() return className end } end,
        _ActionGuideID = guideId,
    }
end

local function describeName(action)
    local className, guideId = MotionNames.describe(action)
    if not className then return nil, nil end
    return className, MotionNames.nameFor(className, guideId)
end

local function fakeList(entries)
    return {
        getValues = function()
            return {
                get_Count = function() return #entries end,
                get_Item = function(_, index) return entries[index + 1] end,
            }
        end,
    }
end

local function withGuides(texts, callback)
    local originalSingleton, originalText = Game.singleton, Game.messageText
    Game.singleton = function(name)
        if name ~= "app.VariousDataManager" then return nil end
        return { _Setting = { _ActionGuideSetting = {
            _ActionGuideName_Common = fakeList({ { _Action = -754623232, _ActionName = "guid-common" } }),
            _ActionGuideName_Wp00 = fakeList({ { _Action = 9328, _ActionName = "guid-9328" } }),
            _ActionGuideName_Wp05 = fakeList({ { _Action = 1763677568, _ActionName = "guid-jump" } }),
            _ActionGuideName_Wp07 = fakeList({ { _Action = 1497865856, _ActionName = "guid-wyrmstake" } }),
            _ActionGuideName_Wp10 = fakeList({ { _Action = -448700960, _ActionName = "guid-neg" } }),
            _ActionGuideName_Wp13 = fakeList({ { _Action = 4001, _ActionName = "guid-4001" }, { _Action = 4002, _ActionName = "guid-4002" } }),
        } } }
    end
    Game.messageText = function(guid) return texts[Locale.current() .. ":" .. tostring(guid)] end
    MotionNames.reset()
    local ok, err = pcall(callback)
    Game.singleton, Game.messageText = originalSingleton, originalText
    MotionNames.reset()
    if not ok then error(err, 0) end
end

function T.guideNameReturnsGuideTextWithoutFallbacks()
    withGuides({ ["ko:guid-9328"] = "강나락 베기", ["en:guid-9328"] = "Overhead Slash" }, function()
        Locale.init({})
        Locale.resolve("ko")
        assert(MotionNames.guideName(9328) == "강나락 베기")
        Locale.resolve("en")
        assert(MotionNames.guideName(9328) == "Overhead Slash")
        assert(MotionNames.guideName(777) == nil)
        assert(MotionNames.guideName(-90670656) == nil)
    end)
    Locale.resolve("en")
end

function T.guideTextNamesTheAction()
    withGuides({ ["ko:guid-9328"] = "강나락 베기", ["en:guid-9328"] = "Overhead Slash" }, function()
        Locale.init({})
        Locale.resolve("ko")
        local key, name = describeName(fakeAction("cAttackHigh", 9328))
        assert(key == "cAttackHigh" and name == "강나락 베기", tostring(name))
        Locale.resolve("en")
        key, name = describeName(fakeAction("cAttackHigh", 9328))
        assert(name == "Overhead Slash")
    end)
end

function T.negativeGuideIdNamesTheAction()
    withGuides({ ["ko:guid-neg"] = "이동 베기" }, function()
        Locale.init({})
        Locale.resolve("ko")
        local key, name = describeName(fakeAction("cBatonMoveAttack", -448700960))
        assert(key == "cBatonMoveAttack" and name == "이동 베기", tostring(name))
    end)
end

function T.unknownGuideReusesCachedSiblingWithAnyGuideId()
    withGuides({ ["en:guid-9328"] = "Sibling action" }, function()
        Locale.init({})
        Locale.resolve("en")
        assert(MotionNames.nameFor("cFoo", 9328) == "Sibling action")
        for _, suffix in ipairs({ "Land", "NoCombo", "WeakHit", "Front", "Back", "Left", "Right", "Loop", "End" }) do
            assert(MotionNames.nameFor("cFoo" .. suffix, 77) == "Sibling action")
            assert(MotionNames.nameFor("cFoo" .. suffix, -1) == "Sibling action")
        end
        assert(MotionNames.nameFor("cFooLandEnd", 77) == "Other action")
        assert(MotionNames.nameFor("cFooLandExtra", 77) == "Other action")
        assert(MotionNames.nameFor("cFoLand", 77) == "Other action")
        Locale.resolve("ko")
        assert(MotionNames.nameFor("cFooLand", 77) == "기타 동작")
    end)
end

function T.missingSiblingUsesLocalizedLabel()
    withGuides({}, function()
        Locale.init({})
        for _, case in ipairs({ { "en", "Other action" }, { "ko", "기타 동작" } }) do
            Locale.resolve(case[1])
            assert(MotionNames.nameFor("cActSpecial", 77) == case[2])
            assert(MotionNames.nameFor("cFooLand", -1) == case[2])
        end
    end)
end

function T.localizedFallbackRetriesAfterSiblingResolves()
    withGuides({ ["en:guid-9328"] = "Sibling action" }, function()
        Locale.init({})
        Locale.resolve("en")
        assert(MotionNames.nameFor("cFooLand", 77) == "Other action")
        assert(MotionNames.nameFor("cFooLand", -1) == "Other action")
        assert(MotionNames.nameFor("cFoo", 9328) == "Sibling action")
        assert(MotionNames.nameFor("cFooLand", 77) == "Sibling action")
        assert(MotionNames.nameFor("cFooLand", -1) == "Sibling action")
    end)
end

function T.siblingFallbackRetriesUntilOwnGuideResolves()
    local texts = { ["en:guid-9328"] = "Sibling action" }
    withGuides(texts, function()
        Locale.init({})
        Locale.resolve("en")
        assert(MotionNames.nameFor("cFoo", 9328) == "Sibling action")
        assert(MotionNames.nameFor("cFooLand", 4001) == "Sibling action")
        texts["en:guid-4001"] = "Landing action"
        assert(MotionNames.nameFor("cFooLand", 4001) == "Landing action")
        texts["en:guid-4001"] = nil
        assert(MotionNames.nameFor("cFooLand", 4001) == "Landing action")
    end)
end

function T.rejectedGuideTextFallsBack()
    withGuides({ ["en:guid-4001"] = "<COLOR FF0000>#Rejected#</COLOR> Action_1", ["en:guid-4002"] = "---" }, function()
        Locale.init({})
        Locale.resolve("en")
        local _, name = describeName(fakeAction("cShootNormal", 4001))
        assert(name == "Other action")
        _, name = describeName(fakeAction("cShootStep", 4002))
        assert(name == "Other action")
    end)
end

function T.nilAndUnreadableActionsGiveNil()
    assert(MotionNames.describe(nil) == nil)
    local key, name = MotionNames.describe({ get_type_definition = function() error("gone") end })
    assert(key == nil and name == nil)
end

function T.unavailableGuidesRetryWithoutReset()
    for _, failure in ipairs({ "missing", "scan" }) do
        withGuides({ ["en:guid-9328"] = "Overhead Slash" }, function()
            Locale.init({})
            Locale.resolve("en")
            local singleton = Game.singleton
            Game.singleton = function(name)
                if failure == "missing" then return nil end
                local manager = singleton(name)
                manager._Setting._ActionGuideSetting._ActionGuideName_Wp13 = {
                    getValues = function() error("scan failed") end,
                }
                return manager
            end
            local action = fakeAction("cActAttackHigh", 9328)
            local key, name = describeName(action)
            assert(key == "cActAttackHigh" and name == "Other action", tostring(name))
            local guid, available = MotionNames.guideGuid(9328)
            assert(guid == nil and available == false)
            Game.singleton = singleton
            key, name = describeName(action)
            assert(key == "cActAttackHigh" and name == "Overhead Slash", tostring(name))
            guid, available = MotionNames.guideGuid(9328)
            assert(guid == "guid-9328" and available == true)
        end)
    end
end

function T.describeKeepsIdentifiersWithoutResolvingText()
    local className, guideId = MotionNames.describe(fakeAction("cAttackHigh", 9328))
    assert(className == "cAttackHigh" and guideId == 9328)
    for _, action in ipairs({
        fakeAction("cActSpecial", "unreadable"),
        fakeAction("cActSpecial", nil),
        setmetatable(fakeAction("cActSpecial", nil), { __index = function() error("gone") end }),
    }) do
        className, guideId = MotionNames.describe(action)
        assert(className == "cActSpecial" and guideId == -1)
    end
end

function T.nameSourcesFollowGuideCacheSiblingAndUnmappedFallback()
    local texts = { ["en:guid-9328"] = "Slash" }
    withGuides(texts, function()
        Locale.init({})
        Locale.resolve("en")
        local name, source = MotionNames.nameFor("cSlashLand", 4001)
        assert(name == "Other action" and source == "unmapped")
        name, source = MotionNames.nameFor("cSlash", 9328)
        assert(name == "Slash" and source == "guide")
        texts["en:guid-9328"] = nil
        name, source = MotionNames.nameFor("cSlash", 9328)
        assert(name == "Slash" and source == "guide")
        name, source = MotionNames.nameFor("cSlashLand", 4001)
        assert(name == "Slash" and source == "sibling")
        texts["en:guid-4001"] = "Landing Slash"
        name, source = MotionNames.nameFor("cSlashLand", 4001)
        assert(name == "Landing Slash" and source == "guide")
        Locale.resolve("ko")
        name, source = MotionNames.nameFor("cSlashLand", -1)
        assert(name == "기타 동작" and source == "unmapped")
        local Names = require("MyHuntReport.Names")
        assert(select("#", Names.resolve({ kind = "motion", className = "cSlashLand", guideId = -1 })) == 1)
    end)
end

function T.ridingFallbackIsFixedBeforeSiblingButAfterUsableGuide()
    local texts = { ["en:guid-9328"] = "Named riding action", ["en:guid-4002"] = "---" }
    withGuides(texts, function()
        Locale.init({})
        Locale.resolve("en")
        local name, source = MotionNames.nameFor("cPorterRideMusic", 9328)
        assert(name == "Named riding action" and source == "guide")
        for _, language in ipairs({ "en", "ko" }) do
            Locale.resolve(language)
            for _, className in ipairs({ "cPorterRideAttack1", "cPorterRideMusicLoop", "cPorterRideAddMusicLoop" }) do
                for _, guideId in ipairs({ -1, 4001, 4002 }) do
                    name, source = MotionNames.nameFor(className, guideId)
                    assert(name == (language == "en" and "Mounted attack" or "탑승 공격") and source == "fixed")
                end
            end
        end
        Locale.resolve("en")
        texts["en:guid-4001"] = "Named mounted attack"
        name, source = MotionNames.nameFor("cPorterRideAttack1", 4001)
        assert(name == "Named mounted attack" and source == "guide")
        name, source = MotionNames.nameFor("prefixcPorterRideAttack", -1)
        assert(name == "Other action" and source == "unmapped")
    end)
end

function T.commonGuideTableNamesSharedActions()
    withGuides({ ["ko:guid-common"] = "몸부림", ["en:guid-common"] = "Struggle" }, function()
        Locale.init({})
        Locale.resolve("ko")
        local name, source = MotionNames.nameFor("cDamageCatchBoss", -754623232)
        assert(name == "몸부림" and source == "guide", tostring(name))
        Locale.resolve("en")
        name, source = MotionNames.nameFor("cDamageCatchBoss", -754623232)
        assert(name == "Struggle" and source == "guide", tostring(name))
    end)
end

function T.landingGuideAliasesToItsSwing()
    local texts = { ["en:guid-jump"] = "Jumping Smash", ["ko:guid-jump"] = "점프 내려치기" }
    withGuides(texts, function()
        Locale.init({})
        Locale.resolve("en")
        local name, source = MotionNames.nameFor("cJumpSwingLand", -90670656)
        assert(name == "Jumping Smash" and source == "guide", tostring(name))
        Locale.resolve("ko")
        name, source = MotionNames.nameFor("cJumpSwingLand", -90670656)
        assert(name == "점프 내려치기" and source == "guide", tostring(name))
        name, source = MotionNames.nameFor("cWpFlyOn", 1763677568)
        assert(name == "점프 내려치기" and source == "guide")
    end)
end

function T.wyrmstakeStabAliasesToWyrmstakeCannon()
    local texts = { ["en:guid-wyrmstake"] = "Wyrmstake Cannon", ["ko:guid-wyrmstake"] = "용항포" }
    withGuides(texts, function()
        Locale.init({})
        Locale.resolve("ko")
        local name, source = MotionNames.nameFor("cPileStab", 1088001664)
        assert(name == "용항포" and source == "guide", tostring(name))
        name, source = MotionNames.nameFor("cPileShoot", 1497865856)
        assert(name == "용항포" and source == "guide")
        Locale.resolve("en")
        name = MotionNames.nameFor("cPileStab", 1088001664)
        assert(name == "Wyrmstake Cannon", tostring(name))
    end)
end

function T.pinnedStruggleFallsBackToFixedLabel()
    withGuides({ ["en:guid-4002"] = "---" }, function()
        Locale.init({})
        for _, language in ipairs({ "en", "ko" }) do
            Locale.resolve(language)
            for _, guideId in ipairs({ -1, 4002, -123456 }) do
                local name, source = MotionNames.nameFor("cDamageCatchBoss", guideId)
                assert(name == (language == "en" and "Pinned struggle" or "구속 몸부림") and source == "fixed", tostring(name))
            end
        end
        Locale.resolve("en")
        local name, source = MotionNames.nameFor("prefixcDamageCatch", -1)
        assert(name == "Other action" and source == "unmapped")
    end)
end

function T.mountedBattleAttacksShareOneFixedLabel()
    withGuides({ ["en:guid-4002"] = "---" }, function()
        Locale.init({})
        for _, language in ipairs({ "en", "ko" }) do
            Locale.resolve(language)
            for _, className in ipairs({ "cBattleRideAttack", "cBattleRideAttackLow", "cBattleRideAttackWp", "cBattleRideFinishAttack" }) do
                for _, guideId in ipairs({ -1, 4002, 27767636 }) do
                    local name, source = MotionNames.nameFor(className, guideId)
                    assert(name == (language == "en" and "Mounting attack" or "단차상태 공격") and source == "fixed", className .. ":" .. tostring(name))
                end
            end
        end
        Locale.resolve("en")
        local name, source = MotionNames.nameFor("prefixcBattleRideAttack", -1)
        assert(name == "Other action" and source == "unmapped")
    end)
end

function T.motionDiagnosticIsFormattedOnlyInDeveloperMode()
    local Log = require("MyHuntReport.Log")
    local format = string.format
    local developerMode = Log.isDeveloperMode()
    local formatted = 0
    string.format = function(pattern, ...)
        if pattern == "motion guide=%d class=%s -> %s" then formatted = formatted + 1 end
        return format(pattern, ...)
    end
    local ok, err = pcall(function()
        withGuides({}, function()
            Locale.init({})
            Locale.resolve("en")
            Log.resetCounts()
            Log.setDeveloperMode(false)
            assert(MotionNames.nameFor("cProbeAction", 77) == "Other action")
            assert(formatted == 0, formatted)
            Log.setDeveloperMode(true)
            assert(MotionNames.nameFor("cProbeAction", 77) == "Other action")
            local key = "motion:" .. Locale.textKey() .. ":cProbeAction:77"
            assert(formatted == 1 and Log.count(key) == 1, key)
            local logged = false
            for _, line in ipairs(stubs.logLines) do
                if line == "[MyHuntReport] motion guide=77 class=cProbeAction -> Other action entry=none" then logged = true end
            end
            assert(logged)
        end)
    end)
    string.format = format
    Log.setDeveloperMode(developerMode)
    if not ok then error(err, 0) end
end

local function debugLine(prefix)
    for index = #stubs.logLines, 1, -1 do
        local line = stubs.logLines[index]
        if line:find(prefix, 1, true) == 1 then return line end
    end
    return nil
end

function T.fallbackDiagnosticPrintsTheGuideEntryAndRawText()
    local Log = require("MyHuntReport.Log")
    local developerMode = Log.isDeveloperMode()
    local ok, err = pcall(function()
        withGuides({ ["en:guid-9328"] = "", ["en:guid-4001"] = "Named" }, function()
            Locale.init({})
            Locale.resolve("en")
            Log.resetCounts()
            Log.setDeveloperMode(true)
            assert(MotionNames.nameFor("cDiagEmpty", 9328) == "Other action")
            assert(debugLine("[MyHuntReport] motion guide=9328 class=cDiagEmpty ") == "[MyHuntReport] motion guide=9328 class=cDiagEmpty -> Other action entry=Wp00 text=\"\"")
            assert(MotionNames.nameFor("cDiagCommon", -754623232) == "Other action")
            assert(debugLine("[MyHuntReport] motion guide=-754623232 class=cDiagCommon ") == "[MyHuntReport] motion guide=-754623232 class=cDiagCommon -> Other action entry=Common text=nil")
            assert(MotionNames.nameFor("cDiagMissing", 8482) == "Other action")
            assert(debugLine("[MyHuntReport] motion guide=8482 class=cDiagMissing ") == "[MyHuntReport] motion guide=8482 class=cDiagMissing -> Other action entry=none")
            assert(MotionNames.nameFor("cDiagNamed", 4001) == "Named")
            assert(debugLine("[MyHuntReport] motion guide=4001 class=cDiagNamed ") == "[MyHuntReport] motion guide=4001 class=cDiagNamed -> Named")
            assert(MotionNames.nameFor("cDiagNoGuide", -1) == "Other action")
            assert(debugLine("[MyHuntReport] motion guide=-1 class=cDiagNoGuide ") == "[MyHuntReport] motion guide=-1 class=cDiagNoGuide -> Other action")
            Log.setDeveloperMode(false)
            local count = #stubs.logLines
            assert(MotionNames.nameFor("cDiagQuiet", 8482) == "Other action")
            assert(#stubs.logLines == count)
        end)
    end)
    Log.setDeveloperMode(developerMode)
    if not ok then error(err, 0) end
end

function T.fallbackDiagnosticReportsAnUnavailableGuideTable()
    local Log = require("MyHuntReport.Log")
    local developerMode, singleton = Log.isDeveloperMode(), Game.singleton
    local ok, err = pcall(function()
        Game.singleton = function() return nil end
        MotionNames.reset()
        Locale.init({})
        Locale.resolve("en")
        Log.resetCounts()
        Log.setDeveloperMode(true)
        assert(MotionNames.nameFor("cDiagUnavailable", 8482) == "Other action")
        assert(debugLine("[MyHuntReport] motion guide=8482 class=cDiagUnavailable ") == "[MyHuntReport] motion guide=8482 class=cDiagUnavailable -> Other action entry=unavailable")
    end)
    Game.singleton = singleton
    MotionNames.reset()
    Log.setDeveloperMode(developerMode)
    if not ok then error(err, 0) end
end

function T.unavailableGuideSettingRetriesWithoutReset()
    local Log = require("MyHuntReport.Log")
    local developerMode = Log.isDeveloperMode()
    local singleton, messageText = Game.singleton, Game.messageText
    local ok, err = pcall(function()
        local manager = { _Setting = {} }
        Game.singleton = function() return manager end
        Game.messageText = function(guid)
            if guid == "guid-9328" then return "Overhead Slash" end
            return nil
        end
        MotionNames.reset()
        Locale.init({})
        Locale.resolve("en")
        Log.resetCounts()
        Log.setDeveloperMode(true)
        local name, source = MotionNames.nameFor("cDiagLate", 9328)
        assert(name == "Other action" and source == "unmapped")
        assert(debugLine("[MyHuntReport] motion guide=9328 class=cDiagLate ") == "[MyHuntReport] motion guide=9328 class=cDiagLate -> Other action entry=unavailable")
        manager._Setting._ActionGuideSetting = {
            _ActionGuideName_Wp00 = fakeList({ { _Action = 9328, _ActionName = "guid-9328" } }),
        }
        name, source = MotionNames.nameFor("cDiagReady", 9328)
        assert(name == "Overhead Slash" and source == "guide")
    end)
    Game.singleton, Game.messageText = singleton, messageText
    Log.setDeveloperMode(developerMode)
    MotionNames.reset()
    if not ok then error(err, 0) end
end

return T
