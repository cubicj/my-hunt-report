local stubs = require("stubs")
local Settings = require("MyHuntReport.Settings")

local T = {}

function T.defaultsWhenFileMissing()
    local s = Settings.load()
    assert(s.autoPopup == true)
    assert(s.closeOnQuestStart == true)
    assert(s.toggleKey == 118)
    assert(s.fontSize == 18)
    assert(s.visibleRows == nil)
    assert(s.windowX == -1 and s.windowY == -1)
    assert(s.language == "auto")
    assert(s.developerMode == false)
    assert(s.skillProcCapture == true)
end

function T.clampsAndCoercesLoadedValues()
    stubs.jsonFiles[Settings.FILE] = {
        autoPopup = "yes",
        toggleKey = 999,
        fontSize = 99,
        visibleRows = 12, windowX = 640.5, windowY = -3,
        language = "jp",
        developerMode = true,
        skillProcCapture = "off",
    }
    local s = Settings.load()
    assert(s.autoPopup == true, "wrong type falls back to default")
    assert(s.toggleKey == 254)
    assert(s.fontSize == 36)
    assert(s.visibleRows == nil, "unknown keys are dropped")
    assert(s.windowX == 640.5 and s.windowY == -3, "window position accepts any number")
    assert(s.language == "auto")
    assert(s.developerMode == true)
    assert(s.skillProcCapture == true, "non-boolean falls back to default")
end

function T.corruptFileIsBackedUpAndReplaced()
    stubs.files[Settings.FILE] = "{not json"
    local s = Settings.load()
    assert(s.toggleKey == 118)
    local backupFound = false
    for path in pairs(stubs.files) do
        if path:find("MyHuntReport/settings.invalid-", 1, true) then backupFound = true end
    end
    assert(backupFound, "backup file missing")
    assert(stubs.jsonFiles[Settings.FILE] ~= nil, "defaults were not saved")
    assert(#stubs.logLines >= 1)
end

function T.setSanitizesAndSaves()
    Settings.load()
    assert(Settings.set("fontSize", 0.1) == true)
    assert(Settings.get().fontSize == 14)
    assert(stubs.jsonFiles[Settings.FILE].fontSize == 14)
    assert(Settings.set("unknownKey", 1) == false)
end

function T.setDeveloperModeFlowsToLog()
    local Log = require("MyHuntReport.Log")
    Settings.load()
    Settings.set("developerMode", true)
    assert(Log.isDeveloperMode() == true)
    Settings.set("developerMode", false)
    assert(Log.isDeveloperMode() == false)
end

function T.skillProcCaptureLoadsAndSavesFalse()
    stubs.jsonFiles[Settings.FILE] = { skillProcCapture = false }
    local s = Settings.load()
    assert(s.skillProcCapture == false)
    assert(Settings.set("skillProcCapture", true) == true)
    assert(Settings.get().skillProcCapture == true)
    assert(stubs.jsonFiles[Settings.FILE].skillProcCapture == true)
    assert(Settings.set("skillProcCapture", false) == true)
    assert(stubs.jsonFiles[Settings.FILE].skillProcCapture == false)
end

function T.scalarFileBackupPreservesRawText()
    stubs.jsonFiles[Settings.FILE] = "abc"
    stubs.files[Settings.FILE] = '"abc"'
    local s = Settings.load()
    assert(s.toggleKey == 118)
    local backupFound = false
    for path, text in pairs(stubs.files) do
        if path:find("MyHuntReport/settings.invalid-", 1, true) then
            backupFound = true
            assert(text == '"abc"', "backup did not preserve raw text")
        end
    end
    assert(backupFound, "backup file missing")
    assert(stubs.jsonFiles[Settings.FILE].toggleKey == 118)
end

function T.whitespaceFileIsReplacedWithoutBackup()
    for _, text in ipairs({ "", "  \n" }) do
        stubs.files[Settings.FILE] = text
        stubs.jsonFiles[Settings.FILE] = nil
        local s = Settings.load()
        for key, value in pairs(Settings.defaults()) do
            assert(s[key] == value)
        end
        assert(stubs.jsonFiles[Settings.FILE] ~= nil, "defaults were not saved")
        for path in pairs(stubs.files) do
            assert(not path:find("MyHuntReport/settings.invalid-", 1, true), "unexpected backup")
        end
        assert(#stubs.logLines == 0, "unexpected log output")
    end
end

function T.backupFailurePreservesOriginalFile()
    stubs.files[Settings.FILE] = "{not json"
    local originalWrite = fs.write
    fs.write = function(path, text)
        if path:find("settings.invalid-", 1, true) then error("backup write failed") end
        return originalWrite(path, text)
    end
    local ok, s = pcall(Settings.load)
    fs.write = originalWrite
    assert(ok, tostring(s))
    for key, value in pairs(Settings.defaults()) do
        assert(s[key] == value)
    end
    assert(stubs.jsonFiles[Settings.FILE] == nil, "original file was overwritten")
    assert(stubs.files[Settings.FILE] == "{not json")
end

function T.scalarFileReadFailurePreservesOriginalFile()
    stubs.jsonFiles[Settings.FILE] = "abc"
    local s = Settings.load()
    for key, value in pairs(Settings.defaults()) do
        assert(s[key] == value)
    end
    assert(stubs.jsonFiles[Settings.FILE] == "abc", "original file was overwritten")
    assert(next(stubs.files) == nil, "unexpected file created")
    assert(#stubs.logLines == 1, "expected one error line")
    assert(stubs.logLines[1] == "[MyHuntReport] Error: settings file could not be parsed and could not be read back; defaults applied in memory")
    local Log = require("MyHuntReport.Log")
    assert(Log.isDeveloperMode() == false)
end

function T.pendingBackupBlocksSaveUntilRetrySucceeds()
    local Log = require("MyHuntReport.Log")
    Log.resetCounts()
    stubs.jsonFiles[Settings.FILE] = "abc"
    stubs.files[Settings.FILE] = '"abc"'
    local originalWrite = fs.write
    fs.write = function() return false end
    local ok, err = pcall(function()
        Settings.load()
        assert(Settings.set("fontSize", 22) == false)
        assert(stubs.jsonFiles[Settings.FILE] == "abc", "original file was overwritten")
        assert(stubs.files[Settings.FILE] == '"abc"')
        assert(Log.count("settings:pending-backup") == 1)
    end)
    fs.write = originalWrite
    assert(ok, tostring(err))
    assert(Settings.set("fontSize", 22) == true)
    local backupFound = false
    for path, text in pairs(stubs.files) do
        if path:find("MyHuntReport/settings.invalid-", 1, true) then
            backupFound = true
            assert(text == '"abc"')
        end
    end
    assert(backupFound, "backup file missing")
    assert(stubs.jsonFiles[Settings.FILE].fontSize == 22)
end

function T.fontSizeRoundsToIntegerPixels()
    stubs.jsonFiles[Settings.FILE] = { fontSize = 23.5 }
    assert(Settings.load().fontSize == 24)
    assert(Settings.set("fontSize", 23.4) == true)
    assert(Settings.get().fontSize == 23)
    assert(stubs.jsonFiles[Settings.FILE].fontSize == 23)
end

function T.migratesLegacyFontSettingAndRewritesFile()
    local legacyKey = "font" .. "Scale"
    stubs.jsonFiles[Settings.FILE] = { [legacyKey] = 1.2 }
    assert(Settings.load().fontSize == 22)
    local saved = stubs.jsonFiles[Settings.FILE]
    assert(saved.fontSize == 22)
    assert(saved[legacyKey] == nil)
    assert(Settings.get()[legacyKey] == nil)
    assert(Settings.load().fontSize == 22)
end

function T.migratedFontSizeIsClamped()
    local legacyKey = "font" .. "Scale"
    for _, case in ipairs({ { 0.1, 14 }, { 3, 36 } }) do
        stubs.jsonFiles[Settings.FILE] = { [legacyKey] = case[1] }
        assert(Settings.load().fontSize == case[2])
        assert(stubs.jsonFiles[Settings.FILE].fontSize == case[2])
        assert(stubs.jsonFiles[Settings.FILE][legacyKey] == nil)
    end
end

function T.migrationRequiresMissingSizeAndNumericLegacyValue()
    local legacyKey = "font" .. "Scale"
    for _, case in ipairs({ { 24, 24 }, { false, 18 } }) do
        stubs.jsonFiles[Settings.FILE] = { fontSize = case[1], [legacyKey] = 1.2 }
        assert(Settings.load().fontSize == case[2])
    end
    stubs.jsonFiles[Settings.FILE] = { [legacyKey] = "1.2" }
    assert(Settings.load().fontSize == 18)
end

return T
