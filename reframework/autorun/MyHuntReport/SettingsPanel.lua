local Settings = require("MyHuntReport.Settings")
local Log = require("MyHuntReport.Log")
local Locale = require("MyHuntReport.Locale")
local Fonts = require("MyHuntReport.Fonts")
local History = require("MyHuntReport.History")
local ReportWindow = require("MyHuntReport.ReportWindow")
local Hotkey = require("MyHuntReport.Hotkey")
local Theme = require("MyHuntReport.Theme")
local Draw = require("MyHuntReport.Draw")

local SettingsPanel = {}

local LANGUAGE_OPTIONS = { "auto", "en", "ko" }

local quest = nil
local armedAt = nil
local statusUntil = nil
local statusKey = nil

local function languageIndex(code)
    for index, value in ipairs(LANGUAGE_OPTIONS) do
        if value == code then return index end
    end
    return 1
end

local function drawClearHistory()
    local now = os.clock()
    if armedAt and now - armedAt >= 5 then armedAt = nil end
    if statusUntil and now >= statusUntil then
        statusUntil = nil
        statusKey = nil
    end

    local key = armedAt and "settings_clear_history_confirm" or "settings_clear_history"
    local token = armedAt and Theme.pushWarningButton() or nil
    local ok, clicked = pcall(imgui.button, Locale.text(key))
    if token then Theme.popBar(token) end
    if not ok then error(clicked, 0) end
    if clicked then
        if armedAt then
            armedAt = nil
            if History.clear() then
                ReportWindow.onHistoryCleared()
                statusKey = "settings_clear_history_done"
            else
                statusKey = "settings_clear_history_failed"
            end
            statusUntil = now + 3
        else
            armedAt = now
            statusUntil = nil
            statusKey = nil
        end
    end

    local textKey = armedAt and "settings_clear_history_warning" or statusKey
    if textKey then
        local color = armedAt and Theme.colors.warning or Theme.colors.textMuted
        local pushed = pcall(imgui.push_style_color, 0, color)
        local okText, err = pcall(imgui.text, Locale.text(textKey))
        if pushed then pcall(imgui.pop_style_color, 1) end
        if not okText then Log.error("history clear text failed: " .. tostring(err), "panel:history") end
    end
end

local function drawHotkey(s, L)
    imgui.text(L("settings_toggle_key") .. ": " .. Hotkey.name(s.toggleKey))
    imgui.same_line()
    if Hotkey.isCapturing() then
        local pushed = pcall(imgui.push_style_color, 0, Theme.colors.textMuted)
        local ok, err = pcall(imgui.text, L("settings_toggle_listening"))
        if pushed then pcall(imgui.pop_style_color, 1) end
        if not ok then Log.error("hotkey capture text failed: " .. tostring(err), "panel:hotkey") end
        imgui.same_line()
        if imgui.button(L("settings_toggle_cancel")) then Hotkey.cancelCapture() end
    else
        if imgui.button(L("settings_toggle_change")) then Hotkey.beginCapture() end
    end
end

local function drawFontAndLanguage(s, L)
    local changed, value = imgui.slider_int(L("settings_font_size"), s.fontSize, 14, 36)
    if changed then
        Settings.set("fontSize", value)
        Fonts.preload(Settings.get().fontSize)
    end

    changed, value = imgui.combo(L("settings_language"), languageIndex(s.language), LANGUAGE_OPTIONS)
    if changed then
        Settings.set("language", LANGUAGE_OPTIONS[value])
        Locale.resolve(Settings.get().language)
        ReportWindow.onLanguageChanged()
    end
end

local function drawDeveloperBlock(L)
    imgui.spacing()
    local fontStatus = Fonts.status()
    imgui.text(L("settings_font_status") .. ": " .. (fontStatus.loaded and "loaded" or ("not loaded " .. tostring(fontStatus.lastError))))
    imgui.text(L("settings_draw_list") .. ": " .. Draw.statusText())
    local changedForce, force = imgui.checkbox(L("settings_force_fallback"), Draw.isForced())
    if changedForce then Draw.setForced(force) end
    imgui.text(L("settings_history_mode") .. ": " .. tostring(History.appendMode()))
    if quest then
        local questState = quest.state()
        imgui.text("Quest: " .. tostring(questState.phase) .. " saved=" .. tostring(questState.saved))
    end
end

local function drawTree()
    local before = Locale.current()
    if Locale.refresh() ~= before then ReportWindow.onLanguageChanged() end
    local s = Settings.get()
    local L = Locale.text

    if imgui.button(L("settings_open_report")) then
        ReportWindow.toggle(nil)
    end
    imgui.spacing()

    local changed, value = imgui.checkbox(L("settings_auto_popup"), s.autoPopup)
    if changed then Settings.set("autoPopup", value) end

    changed, value = imgui.checkbox(L("settings_close_on_quest_start"), s.closeOnQuestStart)
    if changed then Settings.set("closeOnQuestStart", value) end

    drawHotkey(s, L)
    drawFontAndLanguage(s, L)
    drawClearHistory()

    changed, value = imgui.checkbox(L("settings_developer_mode"), s.developerMode)
    if changed then
        Settings.set("developerMode", value)
    end

    if Settings.get().developerMode then
        drawDeveloperBlock(L)
    end
end

function SettingsPanel.register(deps)
    quest = deps and deps.quest or nil
    re.on_draw_ui(function()
        local okNode, opened = pcall(imgui.tree_node, "My Hunt Report")
        if not okNode then
            Log.error("settings panel tree failed: " .. tostring(opened), "panel:tree")
            return
        end
        if opened then
            local ok, err = pcall(drawTree)
            if not ok then pcall(imgui.text, "panel error: " .. tostring(err)) end
            pcall(imgui.tree_pop)
        end
    end)
end

function SettingsPanel.resetForTests()
    armedAt = nil
    statusUntil = nil
    statusKey = nil
end

return SettingsPanel
