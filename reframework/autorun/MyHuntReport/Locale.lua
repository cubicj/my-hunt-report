local Log = require("MyHuntReport.Log")

local Locale = {}

local STRINGS = {
    en = {
        report_title = "My Hunt Report",
        weapon_unknown = "Unknown weapon",
        monsters = "Monsters",
        monster_tempered = "Tempered ",
        monster_arch_tempered = "Arch-tempered ",
        monster_frenzied = "Frenzied ",
        elapsed = "Time",
        combat_dps = "Combat DPS",
        burst_stage = "%s Stage %d",
        wex_wound = "%s · Wound",
        crit_rate = "Crit",
        negative_crit_rate = "Neg. crit",
        avg_hitzone = "Avg hitzone",
        avg_attribute_hitzone = "Avg elem. hitzone",
        avg_hitzone_fire = "Fire hitzone",
        avg_hitzone_water = "Water hitzone",
        avg_hitzone_thunder = "Thunder hitzone",
        avg_hitzone_ice = "Ice hitzone",
        avg_hitzone_dragon = "Dragon hitzone",
        damage_types = "Damage breakdown",
        fixed = "Fixed",
        result_training = "Training",
        result_quest = "Quest",
        skill_damage_violent = "Violent Strike",
        skill_damage_ryukiExplosion = "Incandescent Torrent",
        skill_damage_mirrorBlade = "Mirror Blade",
        skill_damage_flare = "Rathalos's Flare",
        skill_damage_fury = "Lagiacrus's Fury",
        skill_damage_darkWave = "Dark Knight",
        skill_damage_flayer = "Flayer",
        skill_damage_elementConvert = "Element Convert",
        physical = "Physical",
        element = "Element",
        status = "Status",
        skills_header = "Skill uptime",
        motions_header = "Damage by motion",
        motion_kinsect = "Kinsect",
        motion_slinger = "Slinger",
        motion_riding = "Mounted attack",
        motion_pinned = "Pinned struggle",
        motion_mounting = "Mounting attack",
        motion_unmapped = "Other action",
        motion_echo_wave = "Echo Wave",
        melody_prefix = "Melody: ",
        bubble_prefix = "Echo Bubble: ",
        melody_hibiki_attack = "Echo Bubble: Attack & Affinity Up",
        weapon_state_2_1 = "Demon Boost",
        weapon_state_3_1 = "Red Spirit Gauge",
        weapon_state_8_1 = "Amped State",
        weapon_state_8_2 = "Power Axe",
        weapon_state_9_1 = "Sword Boost",
        weapon_state_9_2 = "Element Boost",
        weapon_state_9_3 = "Power Axe",
        weapon_state_10_1 = "Triple Up",
        rapid_fire = "(Rapid Fire)",
        proc_blast = "Blast",
        proc_poison = "Poison",
        history_title = "History",
        history_empty = "No saved reports yet",
        no_data = "No hits recorded yet",
        history = "History",
        close = "Close",
        not_saved = "Not saved to history",
        diagnostics = "Diagnostics",
        settings_auto_popup = "Show report when a quest ends",
        settings_close_on_quest_start = "Close report when a quest starts",
        settings_toggle_key = "Toggle key",
        settings_toggle_change = "Change",
        settings_toggle_listening = "Press a key (Esc cancels)",
        settings_toggle_cancel = "Cancel",
        settings_font_size = "Font size (px)",
        settings_language = "Language",
        settings_clear_history = "Delete all history",
        settings_clear_history_confirm = "Confirm delete",
        settings_clear_history_warning = "This cannot be undone. Press again to delete every record.",
        settings_clear_history_done = "History deleted.",
        settings_clear_history_failed = "Delete failed.",
        settings_developer_mode = "Developer Mode",
        settings_open_report = "Open report",
        settings_font_status = "Font",
        settings_report_font = "Report font",
        settings_history_mode = "History write mode",
        settings_draw_list = "Draw list",
        settings_force_fallback = "Force button fallback",
    },
    ko = {
        report_title = "My Hunt Report",
        weapon_unknown = "알 수 없는 무기",
        monsters = "몬스터",
        monster_tempered = "역전 ",
        monster_arch_tempered = "역전왕 ",
        monster_frenzied = "광룡화 ",
        elapsed = "시간",
        combat_dps = "전투 DPS",
        burst_stage = "%s %d단계",
        wex_wound = "%s · 상처",
        crit_rate = "회심",
        negative_crit_rate = "역회심",
        avg_hitzone = "평균 육질",
        avg_attribute_hitzone = "평균 속성 육질",
        avg_hitzone_fire = "불속성 육질",
        avg_hitzone_water = "물속성 육질",
        avg_hitzone_thunder = "번개속성 육질",
        avg_hitzone_ice = "얼음속성 육질",
        avg_hitzone_dragon = "용속성 육질",
        damage_types = "데미지 구성",
        fixed = "고정",
        result_training = "수련장",
        result_quest = "퀘스트",
        skill_damage_violent = "한격",
        skill_damage_ryukiExplosion = "백열의 격류",
        skill_damage_mirrorBlade = "거울대검",
        skill_damage_flare = "화룡의 힘",
        skill_damage_fury = "해룡의 와뢰",
        skill_damage_darkWave = "암흑기사",
        skill_damage_flayer = "쇄인자격",
        skill_damage_elementConvert = "속성 변환",
        physical = "물리",
        element = "속성",
        status = "상태 이상",
        skills_header = "스킬 업타임",
        motions_header = "모션별 데미지",
        motion_kinsect = "조충 공격",
        motion_slinger = "슬링어",
        motion_riding = "탑승 공격",
        motion_pinned = "구속 몸부림",
        motion_mounting = "단차상태 공격",
        motion_unmapped = "기타 동작",
        motion_echo_wave = "향주파",
        melody_prefix = "선율: ",
        bubble_prefix = "소리 구슬: ",
        melody_hibiki_attack = "소리 구슬: 공격력&회심율 강화",
        weapon_state_2_1 = "귀인 회피",
        weapon_state_3_1 = "연기 게이지 빨강",
        weapon_state_8_1 = "검 강화",
        weapon_state_8_2 = "도끼 강화",
        weapon_state_9_1 = "검 강화",
        weapon_state_9_2 = "방패 강화",
        weapon_state_9_3 = "도끼 강화",
        weapon_state_10_1 = "3색 진액",
        rapid_fire = "(속사)",
        proc_blast = "폭파",
        proc_poison = "독",
        history_title = "기록",
        history_empty = "저장된 리포트가 없습니다",
        no_data = "기록된 히트가 없습니다",
        history = "기록",
        close = "닫기",
        not_saved = "기록에 저장되지 않음",
        diagnostics = "진단",
        settings_auto_popup = "퀘스트 종료 시 리포트 표시",
        settings_close_on_quest_start = "퀘스트 시작 시 리포트 닫기",
        settings_toggle_key = "토글 키",
        settings_toggle_change = "변경",
        settings_toggle_listening = "키를 누르세요 (Esc 취소)",
        settings_toggle_cancel = "취소",
        settings_font_size = "글꼴 크기 (px)",
        settings_language = "언어",
        settings_clear_history = "기록 전부 삭제",
        settings_clear_history_confirm = "정말 삭제",
        settings_clear_history_warning = "되돌릴 수 없는 작업입니다. 한 번 더 누르면 모든 기록이 삭제됩니다.",
        settings_clear_history_done = "기록을 삭제했습니다.",
        settings_clear_history_failed = "삭제에 실패했습니다.",
        settings_developer_mode = "개발자 모드",
        settings_open_report = "리포트 열기",
        settings_font_status = "글꼴",
        settings_report_font = "리포트 글꼴",
        settings_history_mode = "기록 저장 방식",
        settings_draw_list = "드로우 리스트",
        settings_force_fallback = "버튼 fallback 강제",
    },
}

local active = "en"
local setting = "auto"
local VIA_LANGUAGE = { en = 1, ko = 11 }
local SETTLE_TIMEOUT_SECONDS = 10
local detector = nil
local textReady = nil
local clock = os.time
local effectiveRaw = nil
local effectiveCode = "en"
local pendingRaw = nil
local pendingSince = nil

function Locale.init(options)
    options = options or {}
    detector = options.gameLanguage
    textReady = options.textReady
    clock = options.clock or os.time
    effectiveRaw, pendingRaw, pendingSince = nil, nil, nil
    effectiveCode = "en"
    active = "en"
end

local function adopt(detected, detectedRaw)
    effectiveRaw = detectedRaw
    if detected == "ko" then active = "ko" else active = "en" end
    effectiveCode = active
    Log.debug("language auto raw=" .. tostring(detectedRaw) .. " -> " .. active, "locale:auto:" .. tostring(detectedRaw))
    return active
end

function Locale.resolve(setting_)
    setting = setting_ or "auto"
    if setting == "en" or setting == "ko" then
        active = setting
        return active
    end
    local detected, detectedRaw = nil, nil
    if detector then
        local ok, err = pcall(function()
            detected, detectedRaw = detector()
        end)
        if not ok then
            Log.error("language detection failed: " .. tostring(err), "locale:detect")
        end
    end
    if detectedRaw == nil or effectiveRaw == nil or detectedRaw == effectiveRaw then
        pendingRaw, pendingSince = nil, nil
        return adopt(detected, detectedRaw)
    end
    local now = clock()
    if pendingRaw ~= detectedRaw then
        pendingRaw, pendingSince = detectedRaw, now
        Log.debug("text language pending raw=" .. tostring(effectiveRaw) .. " -> " .. tostring(detectedRaw), "locale:pending:" .. tostring(detectedRaw))
    end
    local ready = true
    if textReady then
        local ok, value = pcall(textReady, detectedRaw)
        ready = (not ok) or value == true
        if not ok then Log.error("text readiness probe failed: " .. tostring(value), "locale:probe") end
    end
    local waited = now - pendingSince
    if not ready and waited < SETTLE_TIMEOUT_SECONDS then
        active = effectiveCode
        return active
    end
    Log.debug("text language switched raw=" .. tostring(effectiveRaw) .. " -> " .. tostring(detectedRaw) .. " after " .. tostring(waited) .. "s " .. (ready and "ready" or "timeout"), "locale:switch:" .. tostring(detectedRaw))
    pendingRaw, pendingSince = nil, nil
    return adopt(detected, detectedRaw)
end

function Locale.refresh()
    if setting == "auto" then return Locale.resolve("auto") end
    return active
end

local COVERED_TEXT_LANGUAGES = { [1] = true, [9] = true }

function Locale.bundledFontCovers()
    if setting == "en" or setting == "ko" then return true end
    if effectiveRaw == nil then return true end
    return COVERED_TEXT_LANGUAGES[effectiveRaw] == true
end

function Locale.viaLanguage()
    return VIA_LANGUAGE[setting]
end

function Locale.textKey()
    local language = VIA_LANGUAGE[setting]
    if language then return "via:" .. tostring(language) end
    return "auto:" .. tostring(effectiveRaw ~= nil and effectiveRaw or active)
end

function Locale.current()
    return active
end

function Locale.text(key)
    local table_ = STRINGS[active]
    local value = table_ and table_[key]
    if value == nil then value = STRINGS.en[key] end
    if value == nil then
        Log.error("missing locale key: " .. tostring(key), "locale:" .. tostring(key))
        return tostring(key)
    end
    return value
end

function Locale.keys(code)
    local list = {}
    for key in pairs(STRINGS[code] or {}) do list[#list + 1] = key end
    table.sort(list)
    return list
end

return Locale
