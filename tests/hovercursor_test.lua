local stubs = require("stubs")
local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local ReportWindow = require("MyHuntReport.ReportWindow")
local Settings = require("MyHuntReport.Settings")

local T = {}

local GET_SHOW = "get_ShowCursor()"
local GET_IN_CLIENT = "get_InWindowClientArea()"
local SET_SHOW = "set_ShowCursor(System.Boolean)"

local function withCursor(callback)
    local callStatic, uptime, bounds = Game.callStatic, Game.uptime, ReportWindow.bounds
    local filterBounds = ReportWindow.filterBounds
    local originalImgui, originalFramework = imgui, reframework
    local developerMode, get = Log.isDeveloperMode(), Settings.get
    local c = {
        enabled = true, gameCalls = 0,
        show = false, inClient = true, menu = false,
        bounds = { 100, 200, 300, 400 }, mouse = { x = 0, y = 0 },
        now = 10, sets = {}, reads = 0,
    }
    local ok, err = pcall(function()
        Log.setDeveloperMode(true)
        Settings.get = function() return { hoverCursor = c.enabled } end
        Game.uptime = function()
            c.reads = c.reads + 1
            c.gameCalls = c.gameCalls + 1
            return c.now
        end
        Game.callStatic = function(typeName, signature, value)
            assert(typeName == "via.hid.Mouse", tostring(typeName))
            c.reads = c.reads + 1
            c.gameCalls = c.gameCalls + 1
            if signature == GET_SHOW then
                if c.showFails then return nil, "show unavailable" end
                return c.show
            elseif signature == GET_IN_CLIENT then
                return c.inClient
            elseif signature == SET_SHOW then
                c.sets[#c.sets + 1] = value
                if c.setFails then return nil, "set unavailable" end
                c.show = value
                return nil
            end
            error("unexpected signature " .. tostring(signature))
        end
        ReportWindow.bounds = function()
            c.reads = c.reads + 1
            if not c.bounds then return nil end
            return c.bounds[1], c.bounds[2], c.bounds[3], c.bounds[4]
        end
        ReportWindow.filterBounds = function()
            c.reads = c.reads + 1
            if not c.filterBounds then return nil end
            return table.unpack(c.filterBounds)
        end
        imgui = setmetatable({
            get_mouse = function()
                c.reads = c.reads + 1
                if c.mouseFails then error("mouse unavailable") end
                return c.mouse
            end,
        }, { __index = originalImgui })
        reframework = setmetatable({
            is_drawing_ui = function()
                c.reads = c.reads + 1
                if c.menuFails then error("menu unavailable") end
                return c.menu
            end,
        }, { __index = originalFramework })
        c.cursor = assert(loadfile("reframework/autorun/MyHuntReport/HoverCursor.lua"))()
        function c.frame(seconds)
            c.now = c.now + (seconds or 1)
            c.cursor.update()
        end
        function c.inside() c.mouse = { x = 150, y = 250 } end
        function c.outside() c.mouse = { x = 0, y = 0 } end
        function c.count(text)
            local total = 0
            for _, line in ipairs(stubs.logLines) do
                if line:find("[MyHuntReport] cursor " .. text, 1, true) then total = total + 1 end
            end
            return total
        end
        function c.has(text) return c.count(text) > 0 end
        callback(c)
    end)
    Game.callStatic, Game.uptime, ReportWindow.bounds = callStatic, uptime, bounds
    ReportWindow.filterBounds = filterBounds
    imgui, reframework = originalImgui, originalFramework
    Log.setDeveloperMode(developerMode)
    Settings.get = get
    if not ok then error(err, 0) end
end

function T.nothingIsReadSetOrLoggedWhileTheSettingAndDeveloperModeAreOff()
    withCursor(function(c)
        c.enabled = false
        Log.setDeveloperMode(false)
        c.inside()
        c.frame()
        c.frame()
        assert(c.reads == 0 and #c.sets == 0 and #stubs.logLines == 0)
    end)
end

function T.settingOnWithDeveloperModeOffActsWithoutLinesOrIdleGameCalls()
    withCursor(function(c)
        Log.setDeveloperMode(false)
        c.frame()
        c.frame()
        assert(c.gameCalls == 0 and #c.sets == 0)
        c.inside()
        c.frame()
        assert(#c.sets == 1 and c.sets[1] == true and c.show == true)
        c.frame()
        assert(#c.sets == 1)
        c.show = false
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == true and c.show == true)
        c.outside()
        c.frame()
        assert(#c.sets == 3 and c.sets[3] == false and c.show == false)
        local calls = c.gameCalls
        c.frame()
        assert(c.gameCalls == calls and #c.sets == 3)
        assert(#stubs.logLines == 0)
    end)
end

function T.settingOffWithDeveloperModeOnObservesButNeverSets()
    withCursor(function(c)
        c.enabled = false
        c.inside()
        c.frame()
        assert(c.has("snapshot at 11.000 show=false inClient=true menu=false hover=true enabled=false"))
        c.frame()
        assert(#c.sets == 0 and not c.has("hover start"))
        c.enabled = true
        c.frame()
        assert(c.has("change enabled false -> true at 13.000"))
        assert(#c.sets == 1 and c.has("hover start at 13.000 saved=false readback=true"))
    end)
end

function T.turningTheSettingOffDuringAHoverRestoresOnThatFrame()
    withCursor(function(c)
        c.inside()
        c.frame()
        assert(c.show == true)
        c.enabled = false
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == false and c.show == false)
        assert(c.has("hover end at 12.000 duration=1.000 overrides=0 restored=false readback=false"))
        assert(c.has("change enabled true -> false at 12.000"))
        c.frame()
        assert(#c.sets == 2 and c.count("hover start at") == 1)
    end)
end

function T.turningTheSettingOffDuringAHoverWithDeveloperModeOffRestoresAndGoesInert()
    withCursor(function(c)
        Log.setDeveloperMode(false)
        c.inside()
        c.frame()
        assert(c.show == true)
        c.enabled = false
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == false and c.show == false)
        local reads = c.reads
        c.frame()
        assert(c.reads == reads and #c.sets == 2 and #stubs.logLines == 0)
    end)
end

function T.aSkippedHoverStaysSkippedAcrossASettingToggle()
    withCursor(function(c)
        Log.setDeveloperMode(false)
        c.showFails = true
        c.inside()
        c.frame()
        assert(#c.sets == 0)
        c.enabled = false
        c.frame()
        c.showFails = false
        c.enabled = true
        c.frame()
        c.frame()
        assert(#c.sets == 0)
        c.outside()
        c.frame()
        c.inside()
        c.frame()
        assert(#c.sets == 1 and c.sets[1] == true and c.show == true)
    end)
end

function T.hoverEndRestoresASavedTrueWithDeveloperModeOff()
    withCursor(function(c)
        Log.setDeveloperMode(false)
        c.show = true
        c.inside()
        c.frame()
        assert(#c.sets == 1 and c.sets[1] == true)
        c.outside()
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == true and c.show == true)
        assert(#stubs.logLines == 0)
    end)
end

function T.developerModeOffKeepsTheHoverWithoutLinesAndResnapshotsLater()
    withCursor(function(c)
        c.inside()
        c.frame()
        local lines = #stubs.logLines
        Log.setDeveloperMode(false)
        c.show = false
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == true and c.show == true)
        c.outside()
        c.frame()
        assert(#c.sets == 3 and c.sets[3] == false and c.show == false)
        assert(#stubs.logLines == lines)
        Log.setDeveloperMode(true)
        c.frame()
        assert(c.count("snapshot at") == 2)
        assert(#c.sets == 3)
    end)
end

function T.pendingRestoreRetriesWithTheSettingAndDeveloperModeOffAndThenBecomesInert()
    withCursor(function(c)
        c.inside()
        c.frame()
        c.setFails = true
        c.enabled = false
        Log.setDeveloperMode(false)
        local lines = #stubs.logLines
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == false and c.show == true)
        c.frame()
        assert(#c.sets == 3 and c.sets[3] == false and c.show == true)
        assert(#stubs.logLines == lines)
        c.setFails = false
        c.frame()
        assert(#c.sets == 4 and c.sets[4] == false and c.show == false)
        assert(#stubs.logLines == lines)
        local reads = c.reads
        c.frame()
        assert(#c.sets == 4 and c.reads == reads and #stubs.logLines == lines)
        c.outside()
        Log.setDeveloperMode(true)
        c.frame()
        assert(c.count("snapshot at") == 2 and #c.sets == 4)
    end)
end

function T.firstFrameLogsASnapshotAndLaterFramesOnlyChanges()
    withCursor(function(c)
        c.frame()
        assert(c.has("snapshot at 11.000 show=false inClient=true menu=false hover=false enabled=true"))
        assert(#stubs.logLines == 1)
        c.frame()
        assert(#stubs.logLines == 1)
        c.inClient, c.menu = false, true
        c.frame()
        assert(c.has("change inClient true -> false at 13.000"))
        assert(c.has("change menu false -> true at 13.000"))
        assert(#stubs.logLines == 3)
        c.show = true
        c.frame()
        assert(c.has("change show false -> true at 14.000"))
        assert(#stubs.logLines == 4 and #c.sets == 0)
    end)
end

function T.failedReadsPrintQuestionMarks()
    withCursor(function(c)
        c.showFails, c.menuFails, c.mouseFails = true, true, true
        c.inside()
        c.frame()
        assert(c.has("snapshot at 11.000 show=? inClient=true menu=? hover=? enabled=true"))
        assert(#c.sets == 0)
    end)
end

function T.containsCoversEdgesAndOutside()
    withCursor(function(c)
        local contains = c.cursor.contains
        assert(contains(100, 200, 300, 400, 100, 200) == true)
        assert(contains(100, 200, 300, 400, 399, 599) == true)
        assert(contains(100, 200, 300, 400, 400, 599) == false)
        assert(contains(100, 200, 300, 400, 399, 600) == false)
        assert(contains(100, 200, 300, 400, 99, 200) == false)
        assert(contains(100, 200, 300, 400, 100, 199) == false)
        c.bounds = nil
        c.inside()
        c.frame()
        assert(c.has("snapshot at 11.000 show=false inClient=true menu=false hover=false enabled=true"))
        assert(#c.sets == 0)
    end)
end

function T.hoverStartSavesAndSetsOnceAndHoverEndRestores()
    withCursor(function(c)
        c.frame()
        c.inside()
        c.frame()
        assert(#c.sets == 1 and c.sets[1] == true)
        assert(c.has("hover start at 12.000 saved=false readback=true"))
        assert(c.has("change hover false -> true at 12.000"))
        assert(not c.has("change show"))
        c.frame()
        c.frame()
        assert(#c.sets == 1)
        c.outside()
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == false and c.show == false)
        assert(c.has("hover end at 15.000 duration=3.000 overrides=0 restored=false readback=false"))
        assert(c.has("change hover true -> false at 15.000"))
        assert(not c.has("change show"))
    end)
end

function T.hoverEndRestoresASavedTrue()
    withCursor(function(c)
        c.show = true
        c.inside()
        c.frame()
        assert(c.has("hover start at 11.000 saved=true readback=true"))
        c.outside()
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == true and c.show == true)
        assert(c.has("hover end at 12.000 duration=1.000 overrides=0 restored=true readback=true"))
    end)
end

function T.overridesAreCountedReassertedAndCappedAtTenLines()
    withCursor(function(c)
        c.inside()
        c.frame()
        for _ = 1, 12 do
            c.show = false
            c.frame()
            assert(c.show == true)
        end
        assert(#c.sets == 13)
        assert(c.has("override #1 at 12.000 after=1.000"))
        assert(c.has("override #10 at 21.000 after=1.000"))
        assert(c.count("override #") == 10)
        assert(not c.has("change show"))
        c.outside()
        c.frame()
        assert(c.has("hover end at 24.000 duration=13.000 overrides=12 restored=false readback=false"))
    end)
end

function T.reportClosingEndsTheHoverAndRestores()
    withCursor(function(c)
        c.inside()
        c.frame()
        c.bounds = nil
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == false)
        assert(c.has("hover end at 12.000 duration=1.000 overrides=0 restored=false readback=false"))
    end)
end

function T.aFailedHoverReadEndsTheHoverAndRestores()
    withCursor(function(c)
        c.inside()
        c.frame()
        c.mouseFails = true
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == false)
        assert(c.has("hover end at 12.000"))
        assert(c.has("change hover true -> ? at 12.000"))
    end)
end

function T.hoverUnderAnOpenMenuWaitsForTheMenuToClose()
    withCursor(function(c)
        c.menu = true
        c.inside()
        c.frame()
        c.frame()
        assert(#c.sets == 0 and not c.has("hover start"))
        c.menu = false
        c.frame()
        assert(#c.sets == 1 and c.has("hover start at 13.000 saved=false readback=true"))
        c.menu = true
        c.frame()
        assert(#c.sets == 1 and not c.has("hover end"))
        assert(c.has("change menu false -> true at 14.000"))
    end)
end

function T.anUnreadableSavedValueSkipsTheHoverOncePerHover()
    withCursor(function(c)
        c.showFails = true
        c.inside()
        c.frame()
        c.frame()
        assert(#c.sets == 0 and c.count("hover start skipped saved=?") == 1)
        c.outside()
        c.frame()
        c.inside()
        c.frame()
        assert(#c.sets == 0 and c.count("hover start skipped saved=?") == 2)
    end)
end

function T.aSkippedHoverStaysSkippedWhenTheGetterRecovers()
    withCursor(function(c)
        c.showFails = true
        c.inside()
        c.frame()
        assert(#c.sets == 0 and c.count("hover start skipped saved=?") == 1)
        c.showFails = false
        for _ = 1, 2 do
            c.frame()
            assert(#c.sets == 0)
            assert(not c.has("hover start at"))
            assert(c.count("hover start skipped saved=?") == 1)
        end
        c.outside()
        c.frame()
        c.inside()
        c.frame()
        assert(#c.sets == 1 and c.sets[1] == true)
        assert(c.count("hover start at") == 1)
        assert(c.has("hover start at 15.000 saved=false readback=true"))
    end)
end

function T.aFailingSetterLogsOncePerHover()
    withCursor(function(c)
        c.setFails = true
        c.inside()
        c.frame()
        assert(c.has("set failed set unavailable"))
        assert(c.has("hover start at 11.000 saved=false readback=false"))
        c.frame()
        c.frame()
        assert(c.count("set failed") == 1 and #c.sets == 3)
        c.outside()
        c.frame()
        assert(c.count("set failed") == 1 and not c.has("hover end"))
        assert(#c.sets == 4 and c.sets[4] == false)
        c.inside()
        c.frame()
        assert(c.count("set failed") == 1 and not c.has("hover end"))
        assert(c.count("hover start at") == 1 and not c.has("hover start at 15.000"))
        assert(#c.sets == 5 and c.sets[5] == false)
        c.setFails = false
        c.frame()
        assert(#c.sets == 6 and c.sets[6] == false and c.show == false)
        assert(c.count("hover end") == 1)
        assert(c.has("hover end at 16.000 duration=5.000 overrides=2 restored=false readback=false"))
        assert(c.count("hover start at") == 1 and c.count("set failed") == 1)
        c.setFails = true
        c.frame()
        assert(c.count("hover start at") == 2 and c.count("hover end") == 1)
        assert(c.count("set failed") == 2)
    end)
end

function T.resetRestoresAnActiveHoverAndIsIdempotent()
    withCursor(function(c)
        c.inside()
        c.frame()
        assert(c.show == true)
        c.cursor.restore()
        assert(#c.sets == 2 and c.sets[2] == false and c.show == false)
        assert(c.count("hover end") == 1)
        local reads, lines = c.reads, #stubs.logLines
        c.cursor.restore()
        assert(#c.sets == 2 and c.reads == reads and #stubs.logLines == lines)
    end)
end

function T.resetRestoresASavedTrueWithDeveloperModeOff()
    withCursor(function(c)
        c.show = true
        c.inside()
        c.frame()
        c.show = false
        local lines = #stubs.logLines
        Log.setDeveloperMode(false)
        c.cursor.restore()
        assert(#c.sets == 2 and c.sets[2] == true and c.show == true)
        assert(#stubs.logLines == lines)
        local reads = c.reads
        c.cursor.restore()
        assert(#c.sets == 2 and c.reads == reads and #stubs.logLines == lines)
    end)
end

function T.resetDoesNothingAndReadsNothingWhenIdle()
    withCursor(function(c)
        c.inside()
        c.cursor.restore()
        Log.setDeveloperMode(false)
        c.cursor.restore()
        assert(c.reads == 0 and #c.sets == 0 and #stubs.logLines == 0)
    end)
end

function T.failedResetRestorationIsRetriedByUpdate()
    withCursor(function(c)
        c.inside()
        c.frame()
        c.setFails = true
        c.cursor.restore()
        assert(#c.sets == 2 and c.sets[2] == false and c.show == true)
        assert(not c.has("hover end") and c.count("set failed") == 1)
        c.setFails = false
        c.frame()
        assert(#c.sets == 3 and c.sets[3] == false and c.show == false)
        assert(c.count("hover start at") == 1 and c.count("hover end") == 1)
        assert(c.has("hover end at 12.000 duration=1.000 overrides=0 restored=false readback=false"))
    end)
end

function T.onlyTheRestorationFailsAndLaterSucceeds()
    withCursor(function(c)
        c.inside()
        c.frame()
        assert(c.show == true and not c.has("set failed"))
        c.setFails = true
        c.outside()
        c.frame()
        assert(#c.sets == 2 and c.sets[2] == false and c.show == true)
        assert(c.count("set failed") == 1 and not c.has("hover end"))
        c.frame()
        assert(#c.sets == 3 and c.sets[3] == false)
        assert(c.count("set failed") == 1 and not c.has("hover end"))
        c.setFails = false
        c.frame()
        assert(#c.sets == 4 and c.sets[4] == false and c.show == false)
        assert(c.count("hover end") == 1)
        assert(c.has("hover end at 14.000 duration=3.000 overrides=0 restored=false readback=false"))
        c.frame()
        assert(#c.sets == 4 and c.count("hover end") == 1)
        assert(not c.has("change show"))
    end)
end

function T.pendingRestorePreventsANewHoverAndPreservesTheSavedValue()
    withCursor(function(c)
        c.inside()
        c.frame()
        c.setFails = true
        c.outside()
        c.frame()
        c.inside()
        c.frame()
        c.frame()
        assert(#c.sets == 4 and c.sets[3] == false and c.sets[4] == false)
        assert(c.count("hover start at") == 1 and not c.has("hover end"))
        assert(not c.has("override #"))
        c.setFails = false
        c.frame()
        assert(#c.sets == 5 and c.sets[5] == false and c.show == false)
        assert(c.count("hover end") == 1 and c.count("hover start at") == 1)
        assert(c.has("hover end at 15.000 duration=4.000 overrides=0 restored=false readback=false"))
        c.frame()
        assert(#c.sets == 6 and c.sets[6] == true)
        assert(c.has("hover start at 16.000 saved=false readback=true"))
    end)
end

function T.hoverOverEitherWindowKeepsTheCursorVisible()
    withCursor(function(c)
        c.filterBounds = { 450, 200, 300, 400 }
        c.inside()
        c.frame()
        assert(#c.sets == 1 and c.show)
        c.mouse = { x = 500, y = 250 }
        c.frame()
        assert(#c.sets == 1 and c.show and c.count("hover end") == 0)
        c.bounds = nil
        c.frame()
        assert(#c.sets == 1 and c.show)
        c.filterBounds = nil
        c.frame()
        assert(#c.sets == 2 and not c.show and c.count("hover end") == 1)
    end)
end

function T.filterBoundsAloneCanStartHoverAndRespectEdges()
    withCursor(function(c)
        c.bounds = nil
        c.filterBounds = { 450, 200, 300, 400 }
        c.mouse = { x = 450, y = 200 }
        c.frame()
        assert(c.show and c.count("hover start at") == 1)
        c.mouse = { x = 750, y = 200 }
        c.frame()
        assert(not c.show and c.count("hover end") == 1)
    end)
end

return T
