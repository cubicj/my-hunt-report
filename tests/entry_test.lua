local ReportWindow = require("MyHuntReport.ReportWindow")

local T = {}

local function snapshot(result)
    return { version = 2, quest = { result = result }, damage = { total = 1, hits = 1 }, stats = {}, monsters = {}, skills = {}, motions = {}, procs = {}, skillDamage = {} }
end

function T.entryRegistersSessionNamesRelabeler()
    local Session = require("MyHuntReport.Session")
    local Names = require("MyHuntReport.Names")
    local original = Names.resolve
    local noop = function() end
    local dummy = setmetatable({}, { __index = function() return noop end })
    local modules = {
        ["MyHuntReport.ReportWindow"] = ReportWindow,
        ["MyHuntReport.Session"] = Session,
        ["MyHuntReport.Names"] = Names,
        ["MyHuntReport.Settings"] = {
            load = noop,
            get = function() return { language = "en", fontSize = 18, developerMode = false, skillProcCapture = true } end,
        },
    }
    local environment = setmetatable({
        require = function(name) return modules[name] or dummy end,
        re = { on_draw_ui = noop, on_frame = noop, on_config_save = noop },
    }, { __index = _G })
    ReportWindow.setRelabeler(nil)
    Names.resolve = function(label) return "entry:" .. label.kind end
    local ok, err = pcall(function()
        assert(loadfile("reframework/autorun/my_hunt_report.lua", "t", environment))()
        local result = snapshot("clear")
        result.monsters = { { name = "old", label = { kind = "monster", emId = 26 } } }
        ReportWindow.show(result)
        ReportWindow.onLanguageChanged()
        assert(result.monsters[1].name == "entry:monster")
    end)
    Names.resolve = original
    ReportWindow.setRelabeler(nil)
    ReportWindow.setSnapshotProvider(nil)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.entryInstallsSkillProcHooksOnlyWhenTheSettingIsOn()
    local Session = require("MyHuntReport.Session")
    local Names = require("MyHuntReport.Names")
    local noop = function() end
    local dummy = setmetatable({}, { __index = function() return noop end })
    local function run(skillProcCapture)
        local calls = {}
        local modules = {
            ["MyHuntReport.ReportWindow"] = ReportWindow,
            ["MyHuntReport.Session"] = Session,
            ["MyHuntReport.Names"] = Names,
            ["MyHuntReport.Procs"] = {
                install = function() calls[#calls + 1] = "install" end,
                installSkillProcs = function() calls[#calls + 1] = "installSkillProcs" end,
                skillProcsInstalled = function() return false end,
            },
            ["MyHuntReport.Settings"] = {
                load = noop,
                get = function() return { language = "en", fontSize = 18, developerMode = false, skillProcCapture = skillProcCapture } end,
            },
        }
        local environment = setmetatable({
            require = function(name) return modules[name] or dummy end,
            re = { on_draw_ui = noop, on_frame = noop, on_config_save = noop },
        }, { __index = _G })
        assert(loadfile("reframework/autorun/my_hunt_report.lua", "t", environment))()
        return table.concat(calls, ",")
    end
    local ok, err = pcall(function()
        local enabled = run(true)
        assert(enabled == "install,installSkillProcs", enabled)
        local disabled = run(false)
        assert(disabled == "install", disabled)
    end)
    ReportWindow.setRelabeler(nil)
    ReportWindow.setSnapshotProvider(nil)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.entryInstallsTheHealTracker()
    local Session = require("MyHuntReport.Session")
    local Names = require("MyHuntReport.Names")
    local noop = function() end
    local dummy = setmetatable({}, { __index = function() return noop end })
    local calls = {}
    local modules = {
        ["MyHuntReport.ReportWindow"] = ReportWindow,
        ["MyHuntReport.Session"] = Session,
        ["MyHuntReport.Names"] = Names,
        ["MyHuntReport.HealTracker"] = { install = function() calls[#calls + 1] = "install" end, reset = noop },
        ["MyHuntReport.Settings"] = {
            load = noop,
            get = function() return { language = "en", fontSize = 18, developerMode = false, skillProcCapture = true } end,
        },
    }
    local environment = setmetatable({
        require = function(name) return modules[name] or dummy end,
        re = { on_draw_ui = noop, on_frame = noop, on_config_save = noop },
    }, { __index = _G })
    local ok, err = pcall(function()
        assert(loadfile("reframework/autorun/my_hunt_report.lua", "t", environment))()
        assert(table.concat(calls, ",") == "install", table.concat(calls, ","))
    end)
    ReportWindow.setRelabeler(nil)
    ReportWindow.setSnapshotProvider(nil)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.entryDoesNotLoadTheAttackProbe()
    local Session = require("MyHuntReport.Session")
    local Names = require("MyHuntReport.Names")
    local noop = function() end
    local dummy = setmetatable({}, { __index = function() return noop end })
    local required = {}
    local modules = {
        ["MyHuntReport.ReportWindow"] = ReportWindow,
        ["MyHuntReport.Session"] = Session,
        ["MyHuntReport.Names"] = Names,
        ["MyHuntReport.Settings"] = {
            load = noop,
            get = function() return { language = "en", fontSize = 18, developerMode = false, skillProcCapture = false } end,
        },
    }
    local environment = setmetatable({
        require = function(name)
            required[name] = true
            return modules[name] or dummy
        end,
        re = { on_draw_ui = noop, on_frame = noop, on_config_save = noop },
    }, { __index = _G })
    local ok, err = pcall(function()
        assert(loadfile("reframework/autorun/my_hunt_report.lua", "t", environment))()
        assert(required["MyHuntReport.HitCapture"] == true)
        assert(required["MyHuntReport.AttackProbe"] == nil)
        assert(loadfile("reframework/autorun/MyHuntReport/AttackProbe.lua") == nil)
    end)
    ReportWindow.setRelabeler(nil)
    ReportWindow.setSnapshotProvider(nil)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.entryUpdatesAttackLogDirectlyAfterShellTracker()
    local noop = function() end
    local calls, required = {}, {}
    local frame
    local function module(name)
        return setmetatable({}, { __index = function(_, method)
            return function() calls[#calls + 1] = name .. "." .. method end
        end })
    end
    local modules = {
        ["MyHuntReport.Settings"] = {
            load = noop,
            get = function() return { language = "en", fontSize = 18, developerMode = false, skillProcCapture = false } end,
        },
        ["MyHuntReport.AttackLog"] = {
            update = function() calls[#calls + 1] = "MyHuntReport.AttackLog.update" end,
        },
    }
    local environment = setmetatable({
        require = function(name)
            required[name] = true
            return modules[name] or module(name)
        end,
        re = { on_draw_ui = noop, on_frame = function(callback) frame = callback end, on_config_save = noop },
    }, { __index = _G })
    assert(loadfile("reframework/autorun/my_hunt_report.lua", "t", environment))()
    assert(required["MyHuntReport.AttackLog"] == true)
    assert(type(frame) == "function")
    calls = {}
    frame()
    assert(calls[1] == "MyHuntReport.ShellTracker.update", table.concat(calls, ","))
    assert(calls[2] == "MyHuntReport.AttackLog.update", table.concat(calls, ","))
    local updates = 0
    for _, call in ipairs(calls) do
        if call == "MyHuntReport.AttackLog.update" then updates = updates + 1 end
    end
    assert(updates == 1, updates)
end

function T.entryInstallsThePalicoCaptureAfterHitCaptureAndNotTheRetiredProbe()
    local Session = require("MyHuntReport.Session")
    local Names = require("MyHuntReport.Names")
    local noop = function() end
    local dummy = setmetatable({}, { __index = function() return noop end })
    local calls, required = {}, {}
    local modules = {
        ["MyHuntReport.ReportWindow"] = ReportWindow,
        ["MyHuntReport.Session"] = Session,
        ["MyHuntReport.Names"] = Names,
        ["MyHuntReport.HitCapture"] = { install = function() calls[#calls + 1] = "hitcapture" end, reset = noop },
        ["MyHuntReport.Palico"] = { install = function() calls[#calls + 1] = "palico" end, reset = noop },
        ["MyHuntReport.Settings"] = {
            load = noop,
            get = function() return { language = "en", fontSize = 18, developerMode = false, skillProcCapture = true } end,
        },
    }
    local environment = setmetatable({
        require = function(name)
            required[name] = true
            return modules[name] or dummy
        end,
        re = { on_draw_ui = noop, on_frame = noop, on_config_save = noop },
    }, { __index = _G })
    local ok, err = pcall(function()
        assert(loadfile("reframework/autorun/my_hunt_report.lua", "t", environment))()
        assert(table.concat(calls, ",") == "hitcapture,palico", table.concat(calls, ","))
        assert(required["MyHuntReport.PalicoProbe"] == nil)
        assert(loadfile("reframework/autorun/MyHuntReport/PalicoProbe.lua") == nil)
        assert(loadfile("tests/palicoprobe_test.lua") == nil)
    end)
    ReportWindow.setRelabeler(nil)
    ReportWindow.setSnapshotProvider(nil)
    ReportWindow.hide()
    if not ok then error(err, 0) end
end

function T.entryUpdatesTheHoverCursorDirectlyAfterTheReportWindowDraw()
    local noop = function() end
    local calls, required = {}, {}
    local frame
    local function module(name)
        return setmetatable({}, { __index = function(_, method)
            return function() calls[#calls + 1] = name .. "." .. method end
        end })
    end
    local reader
    local modules = {
        ["MyHuntReport.MouseNav"] = {
            update = function(isDown)
                calls[#calls + 1] = "MyHuntReport.MouseNav.update"
                reader = isDown
            end,
        },
        ["MyHuntReport.Settings"] = {
            load = noop,
            get = function() return { language = "en", fontSize = 18, developerMode = false, skillProcCapture = false } end,
        },
    }
    local environment = setmetatable({
        require = function(name)
            required[name] = true
            return modules[name] or module(name)
        end,
        re = { on_draw_ui = noop, on_frame = function(callback) frame = callback end, on_config_save = noop },
    }, { __index = _G })
    assert(loadfile("reframework/autorun/my_hunt_report.lua", "t", environment))()
    assert(required["MyHuntReport.HoverCursor"] == true)
    assert(required["MyHuntReport.CursorProbe"] == nil)
    assert(loadfile("reframework/autorun/MyHuntReport/CursorProbe.lua") == nil)
    assert(loadfile("tests/cursorprobe_test.lua") == nil)
    assert(required["MyHuntReport.MouseNav"] == true)
    assert(type(frame) == "function")
    calls = {}
    frame()
    assert(calls[#calls - 2] == "MyHuntReport.ReportWindow.draw", table.concat(calls, ","))
    assert(calls[#calls - 1] == "MyHuntReport.HoverCursor.update", table.concat(calls, ","))
    assert(calls[#calls] == "MyHuntReport.MouseNav.update", table.concat(calls, ","))
    local asked
    local original = rawget(imgui, "is_mouse_down")
    imgui.is_mouse_down = function(button)
        asked = button
        return true
    end
    local okRead, down = pcall(reader, 4)
    imgui.is_mouse_down = original
    assert(okRead and down == true and asked == 4)
end

function T.entryRegistersTheHoverCursorRestoreForScriptReset()
    local noop = function() end
    local dummy = setmetatable({}, { __index = function() return noop end })
    local resets, restores = {}, 0
    local modules = {
        ["MyHuntReport.Settings"] = {
            load = noop,
            get = function() return { language = "en", fontSize = 18, developerMode = false, skillProcCapture = false } end,
        },
        ["MyHuntReport.HoverCursor"] = {
            update = noop,
            restore = function() restores = restores + 1 end,
        },
    }
    local environment = setmetatable({
        require = function(name) return modules[name] or dummy end,
        re = {
            on_draw_ui = noop, on_frame = noop, on_config_save = noop,
            on_script_reset = function(callback) resets[#resets + 1] = callback end,
        },
    }, { __index = _G })
    assert(loadfile("reframework/autorun/my_hunt_report.lua", "t", environment))()
    assert(#resets == 1 and type(resets[1]) == "function")
    assert(restores == 0)
    resets[1]()
    assert(restores == 1)
end

return T
