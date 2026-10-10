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
            combo = function(label, value)
                if label == "언어" then return true, 2 end
                return false, value
            end,
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

function T.settingsPanelClearButtonPrecedesSkillProcAndDeveloperMode()
    withClearPanel(function(ui)
        local Settings = require("MyHuntReport.Settings")
        local Procs = require("MyHuntReport.Procs")
        local Theme = require("MyHuntReport.Theme")
        local installed = Procs.skillProcsInstalled
        Procs.skillProcsInstalled = function() return true end
        for _, enabled in ipairs({ false, true }) do
            Settings.set("developerMode", enabled)
            ui.draw()
            local _, font = ui.find("Font size (px)")
            local _, language = ui.find("Language")
            local button, clear = ui.find("Delete all history")
            local skillProc, skill = ui.find("Record Flayer, Element Convert, wound-break, and poison damage")
            local crashHint, crash = ui.find("If the game crashes, try turning this off (turning it off needs a game restart)")
            local _, developer = ui.find("Developer Mode")
            assert(button.kind == "button" and skillProc.kind == "checkbox")
            assert(crashHint.kind == "text" and crashHint.colors[0] == Theme.colors.textMuted)
            local hdrCombo, hdr = ui.find("HDR color correction")
            assert(hdrCombo.kind == "combo")
            assert(font < language and language + 1 == hdr and hdr + 1 == clear)
            assert(clear + 1 == skill and skill + 1 == crash and crash + 1 == developer)
            assert(ui.find("Takes effect after a game restart") == nil)
        end
        Settings.set("developerMode", false)
        Procs.skillProcsInstalled = installed
    end)
end

local function withHdrStubs(callback)
    local Hdr = require("MyHuntReport.Hdr")
    local Theme = require("MyHuntReport.Theme")
    local targetNits, apply = Hdr.targetNits, Theme.apply
    local state = { settings = {}, applied = {}, nits = 455 }
    Hdr.targetNits = function(setting)
        state.settings[#state.settings + 1] = setting
        return state.nits
    end
    Theme.apply = function(nits)
        state.applied[#state.applied + 1] = nits
        if state.onApply then state.onApply() end
    end
    local ok, err = pcall(callback, state)
    Hdr.targetNits, Theme.apply = targetNits, apply
    if not ok then error(err, 0) end
end

function T.settingsPanelAppliesTheHdrTargetBeforeDrawing()
    withClearPanel(function(ui)
        local Settings = require("MyHuntReport.Settings")
        withHdrStubs(function(state)
            Settings.set("hdrCorrection", "on")
            local drawnAtApply
            state.onApply = function() drawnAtApply = #ui.events end
            ui.draw()
            assert(#state.settings == 1 and state.settings[1] == "on", tostring(state.settings[1]))
            assert(#state.applied == 1 and state.applied[1] == 455)
            assert(drawnAtApply == 0 and #ui.events > 0, tostring(drawnAtApply))
            Settings.set("hdrCorrection", "auto")
        end)
    end)
end

function T.settingsPanelReadsNoHdrStateWhileTheTreeIsCollapsed()
    withClearPanel(function(ui)
        withHdrStubs(function(state)
            ui.opened = false
            ui.draw()
            assert(#state.settings == 0 and #state.applied == 0)
            assert(#ui.events == 0)
        end)
    end)
end

function T.settingsPanelHdrComboShowsLocalizedOptionsAndStoresTheChoice()
    withClearPanel(function(ui)
        local Settings = require("MyHuntReport.Settings")
        withHdrStubs(function(state)
            state.nits = nil
            local combo = imgui.combo
            local seen
            local ok, err = pcall(function()
                Settings.set("hdrCorrection", "off")
                imgui.combo = function(label, index, options)
                    if label ~= "HDR color correction" then return false, index end
                    seen = { index = index, options = options }
                    return true, 2
                end
                ui.draw()
                assert(seen.index == 3 and #seen.options == 3)
                assert(seen.options[1] == "Auto" and seen.options[2] == "On" and seen.options[3] == "Off")
                assert(Settings.get().hdrCorrection == "on")
            end)
            imgui.combo = combo
            Settings.set("hdrCorrection", "auto")
            if not ok then error(err, 0) end
        end)
    end)
end

local function withSkillProcStubs(callback)
    local Procs = require("MyHuntReport.Procs")
    local installed, install = Procs.skillProcsInstalled, Procs.installSkillProcs
    local state = { installed = true, installs = 0 }
    Procs.skillProcsInstalled = function() return state.installed end
    Procs.installSkillProcs = function()
        state.installs = state.installs + 1
        state.installed = true
    end
    local ok, err = pcall(callback, state)
    Procs.skillProcsInstalled, Procs.installSkillProcs = installed, install
    if not ok then error(err, 0) end
end

function T.settingsPanelSkillProcHintShowsOnlyWhileDisabledButInstalled()
    withClearPanel(function(ui)
        local Settings = require("MyHuntReport.Settings")
        local Theme = require("MyHuntReport.Theme")
        withSkillProcStubs(function(state)
            ui.draw()
            assert(Settings.get().skillProcCapture == true)
            assert(ui.find("Takes effect after a game restart") == nil)
            Settings.set("skillProcCapture", false)
            ui.draw()
            local hint, hintIndex = ui.find("Takes effect after a game restart")
            local _, skill = ui.find("Record Flayer, Element Convert, wound-break, and poison damage")
            local _, crash = ui.find("If the game crashes, try turning this off (turning it off needs a game restart)")
            local _, developer = ui.find("Developer Mode")
            assert(hint and hint.kind == "text" and hint.colors[0] == Theme.colors.textMuted)
            assert(skill + 1 == crash and crash + 1 == hintIndex and hintIndex + 1 == developer)
            state.installed = false
            ui.draw()
            assert(ui.find("Takes effect after a game restart") == nil)
            assert(state.installs == 0)
            Settings.set("skillProcCapture", true)
        end)
    end)
end

function T.settingsPanelSkillProcEnableInstallsHooksImmediately()
    withClearPanel(function(ui)
        local Settings = require("MyHuntReport.Settings")
        withSkillProcStubs(function(state)
            state.installed = false
            Settings.set("skillProcCapture", false)
            ui.draw()
            assert(state.installs == 0)
            local checkbox = imgui.checkbox
            imgui.checkbox = function(label, value)
                if label == "Record Flayer, Element Convert, wound-break, and poison damage" then return true, true end
                return checkbox(label, value)
            end
            ui.draw()
            imgui.checkbox = checkbox
            assert(Settings.get().skillProcCapture == true)
            assert(state.installs == 1 and state.installed == true)
            assert(ui.find("Takes effect after a game restart") == nil)
            ui.draw()
            assert(state.installs == 1)
        end)
    end)
end

function T.settingsPanelSkillProcDisableIsSavedAndShowsHint()
    withClearPanel(function(ui)
        local Settings = require("MyHuntReport.Settings")
        withSkillProcStubs(function(state)
            local checkbox = imgui.checkbox
            imgui.checkbox = function(label, value)
                if label == "Record Flayer, Element Convert, wound-break, and poison damage" then return true, false end
                return checkbox(label, value)
            end
            ui.draw()
            imgui.checkbox = checkbox
            assert(Settings.get().skillProcCapture == false)
            assert(stubs.jsonFiles[Settings.FILE].skillProcCapture == false)
            assert(state.installs == 0)
            local hint = ui.find("Takes effect after a game restart")
            assert(hint and hint.kind == "text")
            Settings.set("skillProcCapture", true)
        end)
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

function T.settingsDeveloperBlockShowsReportFontModeAndTextKey()
    local SettingsPanel = require("MyHuntReport.SettingsPanel")
    local Settings = require("MyHuntReport.Settings")
    local Fonts = require("MyHuntReport.Fonts")
    local onDraw, originalImgui = re.on_draw_ui, imgui
    local draw, texts = nil, {}
    Settings.load()
    Locale.init({ gameLanguage = function() return "en", 11 end })
    Settings.set("language", "auto")
    Locale.resolve("auto")
    local ok, err = pcall(function()
        re.on_draw_ui = function(callback) draw = callback end
        imgui = setmetatable({
            tree_node = function() return true end,
            text = function(text) texts[#texts + 1] = text end,
        }, { __index = originalImgui })
        Settings.set("developerMode", true)
        Fonts.setMode(false)
        SettingsPanel.register({})
        draw()
        local found = false
        for _, text in ipairs(texts) do
            if text == "Report font: default (auto:11)" then found = true end
        end
        assert(found, table.concat(texts, "\n"))
    end)
    Fonts.setMode(true)
    Settings.set("developerMode", false)
    Settings.set("language", "en")
    Locale.resolve("en")
    re.on_draw_ui, imgui = onDraw, originalImgui
    if not ok then error(err, 0) end
end

function T.settingsPanelRelabelsAndUpdatesFontModeWhenTheRawLanguageChanges()
    local SettingsPanel = require("MyHuntReport.SettingsPanel")
    local Settings = require("MyHuntReport.Settings")
    local Fonts = require("MyHuntReport.Fonts")
    local onDraw, originalImgui, onLanguage = re.on_draw_ui, imgui, ReportWindow.onLanguageChanged
    local draw, calls, texts = nil, 0, {}
    local code, raw = "en", 11
    Settings.load()
    Settings.set("language", "auto")
    Locale.init({ gameLanguage = function() return code, raw end })
    Settings.set("developerMode", true)
    Locale.resolve("auto")
    local ok, err = pcall(function()
        re.on_draw_ui = function(callback) draw = callback end
        imgui = setmetatable({
            tree_node = function() return true end,
            text = function(text) texts[#texts + 1] = text end,
        }, { __index = originalImgui })
        ReportWindow.onLanguageChanged = function() calls = calls + 1 end
        SettingsPanel.register({})
        draw()
        assert(calls == 0, tostring(calls))
        local drawn = table.concat(texts, "\n")
        assert(drawn:find("Report font: default (auto:11)", 1, true), drawn)
        code, raw = "en", 1
        texts = {}
        draw()
        assert(calls == 1, tostring(calls))
        drawn = table.concat(texts, "\n")
        assert(drawn:find("Report font: bundled (auto:1)", 1, true), drawn)
    end)
    re.on_draw_ui, imgui, ReportWindow.onLanguageChanged = onDraw, originalImgui, onLanguage
    Fonts.setMode(true)
    Settings.set("developerMode", false)
    Settings.set("language", "en")
    Locale.init({ gameLanguage = function() return nil end })
    Locale.resolve("en")
    if not ok then error(err, 0) end
end

function T.settingsPanelCloseOnResultCloseFollowsCloseOnQuestStartAndSaves()
    withClearPanel(function(ui)
        local Settings = require("MyHuntReport.Settings")
        ui.draw()
        local questStart, questStartIndex = ui.find("Close report when a quest starts")
        local resultClose, resultCloseIndex = ui.find("Close report when the quest result screen closes")
        assert(questStart.kind == "checkbox" and resultClose.kind == "checkbox")
        assert(questStartIndex + 1 == resultCloseIndex)
        assert(Settings.get().closeOnResultClose == false)
        local checkbox = imgui.checkbox
        imgui.checkbox = function(label, value)
            if label == "Close report when the quest result screen closes" then return true, true end
            return checkbox(label, value)
        end
        ui.draw()
        imgui.checkbox = checkbox
        assert(Settings.get().closeOnResultClose == true)
        Settings.set("closeOnResultClose", false)
    end)
end

function T.settingsPanelHoverCursorFollowsCloseOnResultCloseAndSaves()
    withClearPanel(function(ui)
        local Settings = require("MyHuntReport.Settings")
        ui.draw()
        local resultClose, resultCloseIndex = ui.find("Close report when the quest result screen closes")
        local hoverCursor, hoverCursorIndex = ui.find("Show the mouse cursor over the report window")
        assert(resultClose.kind == "checkbox" and hoverCursor.kind == "checkbox")
        assert(resultCloseIndex + 1 == hoverCursorIndex)
        assert(Settings.get().hoverCursor == true)
        local checkbox = imgui.checkbox
        imgui.checkbox = function(label, value)
            if label == "Show the mouse cursor over the report window" then return true, false end
            return checkbox(label, value)
        end
        ui.draw()
        imgui.checkbox = checkbox
        assert(Settings.get().hoverCursor == false)
        Settings.set("hoverCursor", true)
    end)
end

function T.settingsPanelHintTextFailuresLogUnderThePanelKeyAndBalanceColors()
    local SettingsPanel = require("MyHuntReport.SettingsPanel")
    local Settings = require("MyHuntReport.Settings")
    local Log = require("MyHuntReport.Log")
    local onDraw, originalImgui = re.on_draw_ui, imgui
    local draw, colors = nil, 0
    Settings.load()
    Locale.resolve("en")
    Log.resetCounts()
    local ok, err = pcall(function()
        re.on_draw_ui = function(callback) draw = callback end
        imgui = setmetatable({
            tree_node = function() return true end,
            push_style_color = function() colors = colors + 1 end,
            pop_style_color = function(count) colors = colors - count end,
            text = function(value)
                if value == Locale.text("settings_skill_proc_crash_hint") then error("hint broke") end
            end,
        }, { __index = originalImgui })
        SettingsPanel.register({})
        draw()
        assert(colors == 0, colors)
        assert(Log.count("panel:crash") == 1, Log.count("panel:crash"))
        local logged = false
        for _, line in ipairs(stubs.logLines) do
            if line:find("crash hint text failed: ", 1, true) and line:find("hint broke", 1, true) then logged = true end
        end
        assert(logged)
    end)
    re.on_draw_ui, imgui = onDraw, originalImgui
    if not ok then error(err, 0) end
end

return T
