local stubs = require("stubs")
local Hotkey = require("MyHuntReport.Hotkey")
local Log = require("MyHuntReport.Log")
local ReportWindow = require("MyHuntReport.ReportWindow")
local Settings = require("MyHuntReport.Settings")

local T = {}

local BACK, FORWARD = 0x05, 0x06

local function withNav(callback)
    local originalImgui = imgui
    local originals = {
        screen = ReportWindow.screen, back = ReportWindow.back, forward = ReportWindow.forward,
        bounds = ReportWindow.bounds, filterBounds = ReportWindow.filterBounds,
        isCapturing = Hotkey.isCapturing,
    }
    local developerMode, toggleKey = Log.isDeveloperMode(), Settings.get().toggleKey
    local c = {
        screen = "history", bounds = { 100, 200, 300, 400 }, filterBounds = nil,
        mouse = { x = 150, y = 250 }, capturing = false, keys = {}, calls = {},
        result = { back = true, forward = true }, next = { back = "live", forward = "past" },
    }
    local ok, err = pcall(function()
        Log.setDeveloperMode(true)
        Settings.get().toggleKey = 118
        ReportWindow.screen = function() return c.screen end
        ReportWindow.bounds = function()
            if c.bounds then return table.unpack(c.bounds) end
        end
        ReportWindow.filterBounds = function()
            if c.filterBounds then return table.unpack(c.filterBounds) end
        end
        for _, name in ipairs({ "back", "forward" }) do
            ReportWindow[name] = function()
                c.calls[#c.calls + 1] = name
                if c.result[name] then c.screen = c.next[name] end
                return c.result[name]
            end
        end
        Hotkey.isCapturing = function() return c.capturing end
        imgui = setmetatable({ get_mouse = function() return c.mouse end }, { __index = originalImgui })
        package.loaded["MyHuntReport.MouseNav"] = nil
        local MouseNav = require("MyHuntReport.MouseNav")
        c.update = function() MouseNav.update(function(code) return c.keys[code] == true end) end
        callback(c)
    end)
    imgui = originalImgui
    for name, value in pairs(originals) do
        if name == "isCapturing" then Hotkey.isCapturing = value else ReportWindow[name] = value end
    end
    Settings.get().toggleKey = toggleKey
    Log.setDeveloperMode(developerMode)
    package.loaded["MyHuntReport.MouseNav"] = nil
    if not ok then error(err, 0) end
end

local function navLines()
    local lines = {}
    for _, line in ipairs(stubs.logLines) do
        if line:find("mouse nav ", 1, true) then lines[#lines + 1] = line end
    end
    return lines
end

function T.aPressActsOnceAndAHeldButtonDoesNotRepeat()
    withNav(function(c)
        c.update()
        assert(#c.calls == 0)
        c.keys[BACK] = true
        c.update()
        c.update()
        c.update()
        assert(table.concat(c.calls, ",") == "back")
        c.keys[BACK] = false
        c.update()
        c.screen = "history"
        c.keys[BACK] = true
        c.update()
        assert(table.concat(c.calls, ",") == "back,back")
    end)
end

function T.forwardButtonCallsForward()
    withNav(function(c)
        c.keys[FORWARD] = true
        c.update()
        assert(table.concat(c.calls, ",") == "forward")
        local lines = navLines()
        assert(#lines == 1)
        assert(lines[1]:find("mouse nav button=forward hover=true from=history to=past applied=true reason=ok", 1, true), lines[1])
    end)
end

function T.aPressOutsideTheWindowIsIgnoredAndNotReplayed()
    withNav(function(c)
        c.mouse = { x = 50, y = 250 }
        c.keys[BACK] = true
        c.update()
        assert(#c.calls == 0)
        local lines = navLines()
        assert(lines[1]:find("button=back hover=false from=history to=history applied=false reason=not_hovered", 1, true), lines[1])
        c.mouse = { x = 150, y = 250 }
        c.update()
        assert(#c.calls == 0)
        assert(#navLines() == 1)
    end)
end

function T.windowEdgesAreHalfOpen()
    withNav(function(c)
        for _, case in ipairs({
            { 100, 200, true }, { 399, 599, true }, { 400, 250, false }, { 150, 600, false }, { 99, 250, false },
        }) do
            c.calls, c.screen = {}, "history"
            c.mouse = { x = case[1], y = case[2] }
            c.keys[BACK] = true
            c.update()
            c.keys[BACK] = false
            c.update()
            assert((#c.calls == 1) == case[3], case[1] .. "," .. case[2])
        end
    end)
end

function T.hoveringTheFilterWindowCounts()
    withNav(function(c)
        c.filterBounds = { 420, 200, 100, 100 }
        c.mouse = { x = 450, y = 250 }
        c.keys[BACK] = true
        c.update()
        assert(table.concat(c.calls, ",") == "back")
    end)
end

function T.hotkeyCaptureSuppressesNavigation()
    withNav(function(c)
        c.capturing = true
        c.keys[BACK] = true
        c.update()
        assert(#c.calls == 0)
        assert(navLines()[1]:find("applied=false reason=capturing", 1, true))
    end)
end

function T.aSideButtonUsedAsTheToggleKeyDoesNotNavigate()
    withNav(function(c)
        Settings.get().toggleKey = BACK
        c.keys[BACK] = true
        c.keys[FORWARD] = true
        c.update()
        assert(table.concat(c.calls, ",") == "forward")
        assert(navLines()[1]:find("button=back", 1, true) and navLines()[1]:find("reason=toggle_key", 1, true))
    end)
end

function T.aClosedWindowSuppressesNavigation()
    withNav(function(c)
        c.screen, c.bounds = nil, nil
        c.keys[BACK] = true
        c.update()
        assert(#c.calls == 0)
        assert(navLines()[1]:find("button=back hover=false from=closed to=closed applied=false reason=not_open", 1, true), navLines()[1])
    end)
end

function T.aPressWithNowhereToGoLogsNoTarget()
    withNav(function(c)
        c.screen = "live"
        c.result.back = false
        c.keys[BACK] = true
        c.update()
        assert(table.concat(c.calls, ",") == "back")
        assert(navLines()[1]:find("from=live to=live applied=false reason=no_target", 1, true), navLines()[1])
    end)
end

function T.aFailingMouseReadCountsAsNotHovered()
    withNav(function(c)
        imgui.get_mouse = function() error("no mouse") end
        c.keys[BACK] = true
        c.update()
        assert(#c.calls == 0)
        assert(navLines()[1]:find("hover=false", 1, true) and navLines()[1]:find("reason=not_hovered", 1, true))
    end)
end

function T.nothingIsLoggedWithDeveloperModeOff()
    withNav(function(c)
        Log.setDeveloperMode(false)
        c.keys[BACK] = true
        c.update()
        assert(table.concat(c.calls, ",") == "back")
        assert(#navLines() == 0)
    end)
end

return T
