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

function T.hdrCorrectionStringsMatchTheDesign()
    Locale.resolve("en")
    assert(Locale.text("settings_hdr_correction") == "HDR color correction")
    assert(Locale.text("settings_hdr_auto") == "Auto" and Locale.text("settings_hdr_on") == "On" and Locale.text("settings_hdr_off") == "Off")
    Locale.resolve("ko")
    assert(Locale.text("settings_hdr_correction") == "HDR 색 보정")
    assert(Locale.text("settings_hdr_auto") == "자동" and Locale.text("settings_hdr_on") == "켬" and Locale.text("settings_hdr_off") == "끔")
    Locale.resolve("en")
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

function T.questOutcomeStringsMatchTheDesign()
    local expected = {
        en = { "Clear", "Failed", "Abandoned" },
        ko = { "클리어", "실패", "포기" },
    }
    local keys = { "result_clear", "result_fail", "result_abandon" }
    for language, values in pairs(expected) do
        Locale.resolve(language)
        for index, key in ipairs(keys) do assert(Locale.text(key) == values[index], key) end
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

function T.weaponStateKeysExistInBothLanguages()
    for _, id in ipairs({ "2_1", "3_1", "8_1", "8_2", "9_1", "9_2", "9_3", "10_1" }) do
        for _, code in ipairs({ "en", "ko" }) do
            Locale.init({})
            Locale.resolve(code)
            assert(Locale.text("weapon_state_" .. id) ~= "weapon_state_" .. id, code .. " " .. id)
        end
    end
end

function T.bundledFontCoversForcedLanguages()
    Locale.init({ gameLanguage = function() return "en", 11 end })
    Locale.resolve("en")
    assert(Locale.bundledFontCovers() == true)
    Locale.resolve("ko")
    assert(Locale.bundledFontCovers() == true)
end

function T.bundledFontCoversAutoOnlyForEnglishAndKorean()
    local cases = {
        { code = "en", raw = 1, covered = true },
        { code = "ko", raw = 9, covered = true },
        { code = "en", raw = 0, covered = false },
        { code = "en", raw = 10, covered = false },
        { code = "en", raw = 11, covered = false },
        { code = "en", raw = 2, covered = false },
        { code = nil, raw = nil, covered = true },
    }
    for _, case in ipairs(cases) do
        Locale.init({ gameLanguage = function() return case.code, case.raw end })
        Locale.resolve("auto")
        assert(Locale.bundledFontCovers() == case.covered, "raw " .. tostring(case.raw))
    end
end

function T.bundledFontCoversWhenDetectorFails()
    Locale.init({ gameLanguage = function() error("no api") end })
    Locale.resolve("auto")
    assert(Locale.bundledFontCovers() == true)
end

function T.reportFontLabelExistsInBothLanguages()
    Locale.resolve("en")
    assert(Locale.text("settings_report_font") == "Report font")
    Locale.resolve("ko")
    assert(Locale.text("settings_report_font") == "리포트 글꼴")
end

function T.autoKeepsTheOldTextLanguageUntilTheProbeSaysReady()
    local raw, ready = 11, false
    Locale.init({ gameLanguage = function() return raw == 9 and "ko" or "en", raw end, textReady = function() return ready end })
    Locale.resolve("auto")
    assert(Locale.textKey() == "auto:11" and Locale.current() == "en" and Locale.bundledFontCovers() == false)
    raw = 9
    Locale.refresh()
    assert(Locale.textKey() == "auto:11", Locale.textKey())
    assert(Locale.current() == "en" and Locale.bundledFontCovers() == false)
    Locale.refresh()
    assert(Locale.textKey() == "auto:11")
    ready = true
    Locale.refresh()
    assert(Locale.textKey() == "auto:9" and Locale.current() == "ko" and Locale.bundledFontCovers() == true)
    Locale.refresh()
    assert(Locale.textKey() == "auto:9")
end

function T.autoProbeReceivesTheNewRawValue()
    local raw, probed = 1, {}
    Locale.init({ gameLanguage = function() return "en", raw end, textReady = function(value) probed[#probed + 1] = value return true end })
    Locale.resolve("auto")
    assert(#probed == 0, "the first detection adopts without probing")
    raw = 11
    Locale.refresh()
    assert(#probed == 1 and probed[1] == 11)
    assert(Locale.textKey() == "auto:11")
end

function T.autoSwitchesAfterTheSettleTimeout()
    local raw, now = 1, 1000
    Locale.init({ gameLanguage = function() return "en", raw end, textReady = function() return false end, clock = function() return now end })
    Locale.resolve("auto")
    raw = 11
    Locale.refresh()
    now = 1009
    Locale.refresh()
    assert(Locale.textKey() == "auto:1", Locale.textKey())
    now = 1010
    Locale.refresh()
    assert(Locale.textKey() == "auto:11", Locale.textKey())
end

function T.autoPendingRestartsWhenTheTargetChangesAgain()
    local raw, now = 1, 1000
    Locale.init({ gameLanguage = function() return "en", raw end, textReady = function() return false end, clock = function() return now end })
    Locale.resolve("auto")
    raw = 11
    Locale.refresh()
    now = 1008
    raw = 10
    Locale.refresh()
    now = 1012
    Locale.refresh()
    assert(Locale.textKey() == "auto:1", "a new target restarts the settle timer")
    now = 1018
    Locale.refresh()
    assert(Locale.textKey() == "auto:10", Locale.textKey())
end

function T.autoAdoptsImmediatelyWhenTheProbeErrorsOrRawIsNil()
    local raw = 1
    Locale.init({ gameLanguage = function() return "en", raw end, textReady = function() error("probe broke") end })
    Locale.resolve("auto")
    raw = 11
    Locale.refresh()
    assert(Locale.textKey() == "auto:11")
    local Log = require("MyHuntReport.Log")
    assert(Log.count("locale:probe") == 1)
    Locale.init({ gameLanguage = function() return "en", raw end, textReady = function() return false end })
    Locale.resolve("auto")
    raw = nil
    Locale.refresh()
    assert(Locale.textKey() == "auto:en")
end

function T.returningToAutoAfterAForcedLanguageKeepsTheEffectiveRaw()
    local raw, ready = 9, false
    Locale.init({ gameLanguage = function() return "ko", raw end, textReady = function() return ready end })
    Locale.resolve("auto")
    Locale.resolve("ko")
    assert(Locale.textKey() == "via:11")
    raw = 11
    Locale.resolve("auto")
    assert(Locale.textKey() == "auto:9", "the forced interval does not adopt an unsettled raw")
    ready = true
    Locale.refresh()
    assert(Locale.textKey() == "auto:11")
end

function T.pendingAutoRestoresTheEffectiveUiLanguageAfterAForcedInterval()
    local raw, ready = 11, false
    Locale.init({ gameLanguage = function() return raw == 9 and "ko" or "en", raw end, textReady = function() return ready end })
    Locale.resolve("auto")
    Locale.resolve("ko")
    raw = 9
    assert(Locale.resolve("auto") == "en")
    assert(Locale.textKey() == "auto:11" and Locale.current() == "en" and Locale.bundledFontCovers() == false)
    ready = true
    Locale.refresh()
    assert(Locale.textKey() == "auto:9" and Locale.current() == "ko")
    raw, ready = 9, false
    Locale.init({ gameLanguage = function() return raw == 9 and "ko" or "en", raw end, textReady = function() return ready end })
    Locale.resolve("auto")
    Locale.resolve("en")
    raw = 11
    assert(Locale.resolve("auto") == "ko")
    assert(Locale.textKey() == "auto:9" and Locale.current() == "ko" and Locale.bundledFontCovers() == true)
    ready = true
    Locale.refresh()
    assert(Locale.textKey() == "auto:11" and Locale.current() == "en")
end

function T.statusDamageTextsResolve()
    Locale.init({ gameLanguage = function() return "en" end })
    assert(Locale.resolve("en") == "en")
    assert(Locale.text("proc_blast") == "Blast")
    assert(Locale.text("proc_poison") == "Poison")
    assert(Locale.text("skill_damage_blast") == "Blast")
    assert(Locale.text("skill_damage_poison") == "Poison")
    assert(Locale.resolve("ko") == "ko")
    assert(Locale.text("proc_blast") == "폭파")
    assert(Locale.text("proc_poison") == "독")
    assert(Locale.text("skill_damage_blast") == "폭파")
    assert(Locale.text("skill_damage_poison") == "독")
end

function T.woundBreakTextsResolve()
    Locale.init({ gameLanguage = function() return "en" end })
    assert(Locale.resolve("en") == "en")
    assert(Locale.text("proc_woundBreak") == "Wound break")
    assert(Locale.text("settings_skill_proc_capture") == "Record Flayer, Element Convert, wound-break, and poison damage")
    assert(Locale.resolve("ko") == "ko")
    assert(Locale.text("proc_woundBreak") == "상처 파괴")
    assert(Locale.text("settings_skill_proc_capture") == "쇄인자격·속성 변환·상처 파괴·독 대미지 집계")
end

function T.hoverCursorTextsResolve()
    Locale.init({ gameLanguage = function() return "en" end })
    assert(Locale.resolve("en") == "en")
    assert(Locale.text("settings_hover_cursor") == "Show the mouse cursor over the report window")
    assert(Locale.resolve("ko") == "ko")
    assert(Locale.text("settings_hover_cursor") == "리포트 창 위에서 마우스 커서 표시")
end

function T.closeOnResultCloseTextsResolve()
    Locale.init({ gameLanguage = function() return "en" end })
    assert(Locale.resolve("en") == "en")
    assert(Locale.text("settings_close_on_result_close") == "Close report when the quest result screen closes")
    assert(Locale.resolve("ko") == "ko")
    assert(Locale.text("settings_close_on_result_close") == "결과 화면을 닫으면 리포트 닫기")
end

function T.avgAttackTextsResolve()
    Locale.init({ gameLanguage = function() return "en" end })
    assert(Locale.resolve("en") == "en")
    assert(Locale.text("avg_attack") == "Avg attack")
    assert(Locale.resolve("ko") == "ko")
    assert(Locale.text("avg_attack") == "평균 공격력")
end

function T.palicoShareLabelExistsInBothLanguages()
    local previous = Locale.current()
    Locale.resolve("en")
    assert(Locale.text("palico_share") == "Palico")
    Locale.resolve("ko")
    assert(Locale.text("palico_share") == "아이루")
    Locale.resolve(previous)
end

return T
