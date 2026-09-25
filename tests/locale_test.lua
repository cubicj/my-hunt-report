local stubs = require("stubs")
local Locale = require("MyHuntReport.Locale")

local T = {}

local function sameKeys(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

function T.koHasEveryEnKey()
    assert(sameKeys(Locale.keys("en"), Locale.keys("ko")), "en and ko key sets differ")
    assert(#Locale.keys("en") > 10)
end

function T.explicitSettingWins()
    Locale.init({ gameLanguage = function() return "ko" end })
    assert(Locale.resolve("en") == "en")
    assert(Locale.text("close") == "Close")
    assert(Locale.resolve("ko") == "ko")
    assert(Locale.text("close") == "닫기")
end

function T.autoUsesGameLanguage()
    Locale.init({ gameLanguage = function() return "ko" end })
    assert(Locale.resolve("auto") == "ko")
    Locale.init({ gameLanguage = function() return "fr" end })
    assert(Locale.resolve("auto") == "en")
    Locale.init({ gameLanguage = function() return nil end })
    assert(Locale.resolve("auto") == "en")
end

function T.detectorErrorFallsBackToEnglish()
    Locale.init({ gameLanguage = function() error("no api") end })
    assert(Locale.resolve("auto") == "en")
    assert(#stubs.logLines == 1)
end

function T.missingKeyReturnsKeyAndLogs()
    Locale.init({})
    Locale.resolve("en")
    assert(Locale.text("nope_key") == "nope_key")
    assert(stubs.logLines[1]:find("missing locale key: nope_key", 1, true))
end

function T.detectorFailuresShareLogKey()
    local Log = require("MyHuntReport.Log")
    Log.resetCounts()
    local calls = 0
    Locale.init({ gameLanguage = function()
        calls = calls + 1
        error("detector failure " .. calls)
    end })
    for i = 1, 7 do
        Locale.resolve("auto")
    end
    assert(Log.count("locale:detect") == 7)
    assert(#stubs.logLines == 5)
end

function T.viaLanguageFollowsTheSetting()
    Locale.init({ gameLanguage = function() return "ko" end })
    Locale.resolve("en")
    assert(Locale.viaLanguage() == 1)
    Locale.resolve("ko")
    assert(Locale.viaLanguage() == 11)
    Locale.resolve("auto")
    assert(Locale.viaLanguage() == nil)
end

function T.refreshReRunsDetectionOnlyForAuto()
    local calls, answer = 0, "en"
    Locale.init({ gameLanguage = function() calls = calls + 1; return answer end })
    Locale.resolve("auto")
    assert(Locale.current() == "en" and calls == 1)
    answer = "ko"
    assert(Locale.refresh() == "ko" and calls == 2)
    Locale.resolve("en")
    assert(Locale.refresh() == "en" and calls == 2)
end

function T.textKeySeparatesForcedAndAutomaticLanguages()
    Locale.init({ gameLanguage = function() return "fr" end })
    Locale.resolve("en")
    assert(Locale.textKey() == "via:1")
    Locale.resolve("ko")
    assert(Locale.textKey() == "via:11")
    Locale.resolve("auto")
    assert(Locale.textKey() == "auto:en")
    local raw = 2
    Locale.init({ gameLanguage = function() return "fr", raw end })
    Locale.resolve("auto")
    assert(Locale.textKey() == "auto:2")
    raw = 4
    Locale.refresh()
    assert(Locale.textKey() == "auto:4")
    raw = nil
    Locale.refresh()
    assert(Locale.textKey() == "auto:en")
end

function T.newSettingsKeysExistInBothLanguages()
    for _, language in ipairs({ "en", "ko" }) do
        Locale.resolve(language)
        assert(Locale.text("settings_draw_list") ~= "settings_draw_list")
        assert(Locale.text("settings_force_fallback") ~= "settings_force_fallback")
    end
    Locale.resolve("ko")
    assert(Locale.text("damage_types") == "데미지 구성")
    Locale.resolve("en")
    assert(Locale.text("damage_types") == "Damage breakdown")
end

function T.clearHistoryStringsMatchTheDesign()
    local expected = {
        en = { "Delete all history", "Confirm delete", "This cannot be undone. Press again to delete every record.", "History deleted.", "Delete failed." },
        ko = { "기록 전부 삭제", "정말 삭제", "되돌릴 수 없는 작업입니다. 한 번 더 누르면 모든 기록이 삭제됩니다.", "기록을 삭제했습니다.", "삭제에 실패했습니다." },
    }
    local keys = { "settings_clear_history", "settings_clear_history_confirm", "settings_clear_history_warning", "settings_clear_history_done", "settings_clear_history_failed" }
    for language, values in pairs(expected) do
        Locale.resolve(language)
        for index, key in ipairs(keys) do assert(Locale.text(key) == values[index]) end
    end
end

function T.slingerAndRidingLabelsMatchInBothLocales()
    Locale.init({})
    Locale.resolve("en")
    assert(Locale.text("motion_slinger") == "Slinger")
    assert(Locale.text("motion_riding") == "Mounted attack")
    Locale.resolve("ko")
    assert(Locale.text("motion_slinger") == "슬링어")
    assert(Locale.text("motion_riding") == "탑승 공격")
    assert(sameKeys(Locale.keys("en"), Locale.keys("ko")))
end

return T
