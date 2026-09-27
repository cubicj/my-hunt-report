local loadErrors = {}

local function tryRequire(name)
    local ok, result = pcall(require, name)
    if ok then return result end
    loadErrors[#loadErrors + 1] = name .. ": " .. tostring(result)
    return nil
end

local Log = tryRequire("MyHuntReport.Log")
local Settings = tryRequire("MyHuntReport.Settings")
local Hotkey = tryRequire("MyHuntReport.Hotkey")
local Locale = tryRequire("MyHuntReport.Locale")
local Game = tryRequire("MyHuntReport.Game")
local Fonts = tryRequire("MyHuntReport.Fonts")
local ReportWindow = tryRequire("MyHuntReport.ReportWindow")
local SettingsPanel = tryRequire("MyHuntReport.SettingsPanel")
local ShellTracker = tryRequire("MyHuntReport.ShellTracker")
local HitCapture = tryRequire("MyHuntReport.HitCapture")
local Procs = tryRequire("MyHuntReport.Procs")
local SkillExtras = tryRequire("MyHuntReport.SkillExtras")
local Pulse = tryRequire("MyHuntReport.Pulse")
local Quest = tryRequire("MyHuntReport.Quest")
local SkillState = tryRequire("MyHuntReport.SkillState")
local Session = tryRequire("MyHuntReport.Session")
local Names = tryRequire("MyHuntReport.Names")

if #loadErrors > 0 then
    for _, err in ipairs(loadErrors) do
        log.error("[MyHuntReport] Error: failed to load " .. err)
    end
    re.on_draw_ui(function()
        local okNode, opened = pcall(imgui.tree_node, "My Hunt Report [load error]")
        if not okNode then
            log.error("[MyHuntReport] Error: settings panel tree failed: " .. tostring(opened))
            return
        end
        if opened then
            local ok, err = pcall(function()
                for _, loadError in ipairs(loadErrors) do
                    imgui.text(loadError)
                end
            end)
            if not ok then pcall(imgui.text, "panel error: " .. tostring(err)) end
            pcall(imgui.tree_pop)
        end
    end)
    return
end

Settings.load()
Locale.init({ gameLanguage = Game.languageCode, textReady = Game.textLanguageReady })
Locale.resolve(Settings.get().language)
Fonts.preload(Settings.get().fontSize)
ShellTracker.install()
HitCapture.install()
Procs.install()
SkillExtras.install()
Quest.install()
SkillState.install()
Quest.adoptCurrentState(Game.uptime())
ReportWindow.setRelabeler(function(snapshot)
    return Session.relabel(snapshot, Names.resolve)
end)
ReportWindow.setSnapshotProvider(function()
    return Quest.currentSnapshot(Game.uptime())
end)

SettingsPanel.register({ quest = Quest })

re.on_frame(function()
    ShellTracker.update()
    Pulse.tick()
    local event = Hotkey.update(function(code)
        local ok, down = pcall(reframework.is_key_down, reframework, code)
        return ok and down == true
    end, Settings.get().toggleKey)
    if event then
        if event.captured then Settings.set("toggleKey", event.captured) end
        if event.toggle then ReportWindow.toggle(nil) end
    end
    ReportWindow.draw()
end)

re.on_config_save(function()
    Settings.save()
end)

Log.debug("My Hunt Report loaded")
