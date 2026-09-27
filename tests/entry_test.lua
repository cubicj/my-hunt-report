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

return T
