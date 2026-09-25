local stubs = require("stubs")
local ReportWindow = require("MyHuntReport.ReportWindow")
local Locale = require("MyHuntReport.Locale")

local T = {}

local function snapshot(result)
    return { version = 2, quest = { result = result }, damage = { total = 1, hits = 1 }, stats = {}, monsters = {}, skills = {}, motions = {}, procs = {}, skillDamage = {} }
end

function T.settingsLanguageComboNotifiesAfterLocaleResolves()
    local SettingsPanel = require("MyHuntReport.SettingsPanel")
    local Settings = require("MyHuntReport.Settings")
    local onDraw, originalImgui, onLanguage = re.on_draw_ui, imgui, ReportWindow.onLanguageChanged
    local draw, calls = nil, 0
    Settings.load()
    Settings.set("language", "ko")
    Locale.resolve("ko")
    local ok, err = pcall(function()
        re.on_draw_ui = function(callback) draw = callback end
        imgui = setmetatable({
            tree_node = function() return true end,
            combo = function() return true, 2 end,
        }, { __index = originalImgui })
        ReportWindow.onLanguageChanged = function()
            calls = calls + 1
            assert(Locale.current() == "en" and Settings.get().language == "en")
        end
        SettingsPanel.register({})
        draw()
        assert(calls == 1)
    end)
    re.on_draw_ui, imgui, ReportWindow.onLanguageChanged = onDraw, originalImgui, onLanguage
    if not ok then error(err, 0) end
end

function T.settingsFontSizeSliderSavesAndPreloadsPixels()
    local SettingsPanel = require("MyHuntReport.SettingsPanel")
    local Settings = require("MyHuntReport.Settings")
    local Fonts = require("MyHuntReport.Fonts")
    local onDraw, originalImgui, preload = re.on_draw_ui, imgui, Fonts.preload
    local draw, loadedSize, sliderCalls = nil, nil, 0
    Settings.load()
    Locale.resolve("en")
    local ok, err = pcall(function()
        re.on_draw_ui = function(callback) draw = callback end
        imgui = setmetatable({
            tree_node = function() return true end,
            slider_int = function(label, value, minimum, maximum)
                assert(label == "Font size (px)")
                assert(value == 18 and minimum == 14 and maximum == 36)
                sliderCalls = sliderCalls + 1
                return true, 24
            end,
        }, { __index = originalImgui })
        Fonts.preload = function(size) loadedSize = size end
        SettingsPanel.register({})
        draw()
        assert(sliderCalls == 1 and loadedSize == 24)
        assert(Settings.get().fontSize == 24)
        assert(stubs.jsonFiles[Settings.FILE].fontSize == 24)
    end)
    re.on_draw_ui, imgui, Fonts.preload = onDraw, originalImgui, preload
    if not ok then error(err, 0) end
end

function T.settingsPanelOpensReportFirstAndShowsDrawListInDeveloperMode()
    local SettingsPanel = require("MyHuntReport.SettingsPanel")
    local Settings = require("MyHuntReport.Settings")
    local Draw = require("MyHuntReport.Draw")
    local onDraw, originalImgui = re.on_draw_ui, imgui
    local draw, calls = nil, {}
    Settings.load()
    Locale.resolve("en")
    local ok, err = pcall(function()
        re.on_draw_ui = function(callback) draw = callback end
        imgui = setmetatable({
            tree_node = function() return true end,
            button = function(label) calls[#calls + 1] = "button:" .. label return false end,
            checkbox = function(label, value)
                calls[#calls + 1] = "checkbox:" .. label
                if label == "Force button fallback" then return true, true end
                return false, value
            end,
            text = function(text) calls[#calls + 1] = "text:" .. text end,
        }, { __index = originalImgui })
        Draw.resetForTests()
        Settings.set("developerMode", false)
        SettingsPanel.register({})
        draw()
        assert(calls[1] == "button:Open report", calls[1])
        local drawListShown = false
        for _, call in ipairs(calls) do
            if call:find("Draw list", 1, true) then drawListShown = true end
        end
        assert(not drawListShown, "draw list line must be developer-only")
        calls = {}
        Settings.set("developerMode", true)
        draw()
        assert(calls[1] == "button:Open report")
        local status, forced = false, false
        for _, call in ipairs(calls) do
            if call == "text:Draw list: not probed" then status = true end
            if call == "checkbox:Force button fallback" then forced = true end
        end
        assert(status and forced, table.concat(calls, "\n"))
        assert(Draw.isForced() == true)
    end)
    Draw.setForced(false)
    Draw.resetForTests()
    Settings.set("developerMode", false)
    re.on_draw_ui, imgui = onDraw, originalImgui
    if not ok then error(err, 0) end
end

local function withClearPanel(callback)
    local SettingsPanel = require("MyHuntReport.SettingsPanel")
    local Settings = require("MyHuntReport.Settings")
    local History = require("MyHuntReport.History")
    local Log = require("MyHuntReport.Log")
    local originalImgui, onDraw, clock = imgui, re.on_draw_ui, os.clock
    local onCleared, write = ReportWindow.onHistoryCleared, fs.write
    local language = Locale.current()
    local ui = { now = 0, events = {}, colors = {}, vars = {}, notifications = 0, opened = true }
    local draw
    local function record(kind, label)
        local colors = {}
        for _, item in ipairs(ui.colors) do colors[item[1]] = item[2] end
        ui.events[#ui.events + 1] = { kind = kind, label = label, colors = colors }
    end
    function ui.find(label)
        for index, event in ipairs(ui.events) do
            if event.label == label then return event, index end
        end
    end
    function ui.draw(click, now)
        ui.click, ui.events = click, {}
        if now then ui.now = now end
        draw()
        assert(#ui.colors == 0 and #ui.vars == 0, "unbalanced panel styles")
    end
    local ok, err = pcall(function()
        Settings.load()
        SettingsPanel.resetForTests()
        History.resetForTests()
        Log.resetCounts()
        Locale.resolve("en")
        os.clock = function() return ui.now end
        re.on_draw_ui = function(value) draw = value end
        ReportWindow.onHistoryCleared = function()
            ui.notifications = ui.notifications + 1
            onCleared()
        end
        imgui = setmetatable({
            ImGuiStyleVar = { ItemSpacing = 14, FrameRounding = 12, FrameBorderSize = 13 },
            tree_node = function() return ui.opened end,
            button = function(label)
                record("button", label)
                if label == ui.failButton then error("button failed") end
                return label == ui.click
            end,
            checkbox = function(label, value) record("checkbox", label) return false, value end,
            slider_int = function(label, value) record("slider", label) return false, value end,
            combo = function(label, value) record("combo", label) return false, value end,
            text = function(label)
                record("text", label)
                if label == ui.failText then error("text failed") end
            end,
            push_style_color = function(index, color) ui.colors[#ui.colors + 1] = { index, color } end,
            pop_style_color = function(count)
                for _ = 1, count do assert(table.remove(ui.colors)) end
            end,
            push_style_var = function(index, value) ui.vars[#ui.vars + 1] = { index, value } end,
            pop_style_var = function(count)
                for _ = 1, count do assert(table.remove(ui.vars)) end
            end,
        }, { __index = originalImgui })
        assert(History.append(snapshot("clear")))
        ui.originalHistory = stubs.files[History.FILE]
        SettingsPanel.register({})
        callback(ui)
    end)
    imgui, re.on_draw_ui, os.clock = originalImgui, onDraw, clock
    ReportWindow.onHistoryCleared, fs.write = onCleared, write
    if SettingsPanel.resetForTests then SettingsPanel.resetForTests() end
    Locale.resolve(language)
    if not ok then error(err, 0) end
end

function T.settingsPanelClearButtonPrecedesDeveloperMode()
    withClearPanel(function(ui)
        local Settings = require("MyHuntReport.Settings")
        for _, enabled in ipairs({ false, true }) do
            Settings.set("developerMode", enabled)
            ui.draw()
            local _, font = ui.find("Font size (px)")
            local _, language = ui.find("Language")
            local button, clear = ui.find("Delete all history")
            local _, developer = ui.find("Developer Mode")
            assert(button.kind == "button" and font < language and language + 1 == clear and clear + 1 == developer)
        end
        Settings.set("developerMode", false)
    end)
end

function T.settingsPanelClearFirstPressArmsAndUsesWarningColors()
    withClearPanel(function(ui)
        local History = require("MyHuntReport.History")
        local Theme = require("MyHuntReport.Theme")
        ui.draw("Delete all history")
        local warning = ui.find(Locale.text("settings_clear_history_warning"))
        assert(warning and warning.colors[0] == Theme.colors.warning)
        ui.draw(nil, 4.999)
        local button = ui.find("Confirm delete")
        assert(button and button.colors[21] == Theme.colors.warning)
        assert(button.colors[22] == Theme.colors.warning and button.colors[23] == Theme.colors.warning)
        assert(stubs.files[History.FILE] == ui.originalHistory and ui.notifications == 0)
    end)
end

function T.settingsPanelClearSecondPressClearsAndShowsTimedStatus()
    withClearPanel(function(ui)
        local History = require("MyHuntReport.History")
        local Theme = require("MyHuntReport.Theme")
        ui.draw("Delete all history")
        ui.draw("Confirm delete", 4.999)
        assert(stubs.files[History.FILE] == "" and ui.notifications == 1)
        local status = ui.find("History deleted.")
        assert(status and status.colors[0] == Theme.colors.textMuted)
        assert(not ui.find(Locale.text("settings_clear_history_warning")))
        ui.draw(nil, 7.998)
        assert(ui.find("History deleted.") and ui.find("Delete all history"))
        ui.draw(nil, 7.999)
        assert(not ui.find("History deleted.") and ui.find("Delete all history"))
        assert(ui.notifications == 1)
    end)
end

function T.settingsPanelClearArmExpiresAtFiveSeconds()
    withClearPanel(function(ui)
        local History = require("MyHuntReport.History")
        ui.draw("Delete all history")
        ui.draw("Confirm delete", 5)
        assert(ui.find("Delete all history") and not ui.find("Confirm delete"))
        assert(not ui.find(Locale.text("settings_clear_history_warning")))
        assert(stubs.files[History.FILE] == ui.originalHistory and ui.notifications == 0)
        ui.draw("Delete all history", 6)
        ui.opened = false
        ui.draw(nil, 12)
        ui.opened = true
        ui.draw("Confirm delete", 12)
        assert(ui.find("Delete all history") and ui.notifications == 0)
    end)
end

function T.settingsPanelClearFailureDisarmsAndShowsTimedStatus()
    withClearPanel(function(ui)
        local History = require("MyHuntReport.History")
        local Log = require("MyHuntReport.Log")
        local Theme = require("MyHuntReport.Theme")
        fs.write = function() return false end
        ui.draw("Delete all history")
        ui.draw("Confirm delete", 1)
        local status = ui.find("Delete failed.")
        assert(status and status.colors[0] == Theme.colors.textMuted)
        assert(not ui.find(Locale.text("settings_clear_history_warning")))
        assert(stubs.files[History.FILE] == ui.originalHistory and ui.notifications == 0)
        assert(Log.count("history:clear") == 1)
        ui.draw(nil, 3.999)
        assert(ui.find("Delete failed.") and ui.find("Delete all history"))
        ui.draw(nil, 4)
        assert(not ui.find("Delete failed."))
    end)
end

function T.settingsPanelClearRearmingReplacesStatus()
    withClearPanel(function(ui)
        ui.draw("Delete all history")
        ui.draw("Confirm delete", 1)
        ui.draw("Delete all history", 2)
        assert(not ui.find("History deleted."))
        assert(ui.find(Locale.text("settings_clear_history_warning")))
        ui.draw(nil, 5)
        assert(ui.find("Confirm delete"))
        ui.draw(nil, 7)
        assert(ui.find("Delete all history") and not ui.find("History deleted."))
    end)
end

function T.settingsPanelClearRestoresStylesAfterDrawFailures()
    withClearPanel(function(ui)
        ui.draw("Delete all history")
        ui.failButton = "Confirm delete"
        ui.draw()
        ui.failButton = nil
        ui.failText = Locale.text("settings_clear_history_warning")
        ui.draw()
        ui.failText = "History deleted."
        ui.draw("Confirm delete", 1)
        assert(ui.notifications == 1)
    end)
end

function T.settingsPanelReResolvesAutoLanguageWhileOpen()
    local SettingsPanel = require("MyHuntReport.SettingsPanel")
    local Settings = require("MyHuntReport.Settings")
    local onDraw, originalImgui, onLanguage = re.on_draw_ui, imgui, ReportWindow.onLanguageChanged
    local draw, calls, detected, labels = nil, 0, "en", {}
    Settings.load()
    Settings.set("language", "auto")
    Locale.init({ gameLanguage = function() return detected end })
    Locale.resolve("auto")
    local ok, err = pcall(function()
        re.on_draw_ui = function(callback) draw = callback end
        imgui = setmetatable({
            tree_node = function() return true end,
            button = function(label) labels[#labels + 1] = label return false end,
        }, { __index = originalImgui })
        ReportWindow.onLanguageChanged = function() calls = calls + 1 end
        SettingsPanel.register({})
        draw()
        assert(labels[1] == "Open report" and calls == 0)
        detected = "ko"
        labels = {}
        draw()
        assert(labels[1] == "리포트 열기", tostring(labels[1]))
        assert(calls == 1)
        draw()
        assert(calls == 1)
    end)
    Locale.init({})
    Locale.resolve("en")
    re.on_draw_ui, imgui, ReportWindow.onLanguageChanged = onDraw, originalImgui, onLanguage
    if not ok then error(err, 0) end
end

return T
