local Locale = require("MyHuntReport.Locale")
local ReportText = require("MyHuntReport.ReportText")

local T = {}

local function snapshot(result)
    return { version = 2, quest = { result = result }, damage = { total = 1, hits = 1 }, stats = {}, monsters = {}, skills = {}, motions = {}, procs = {}, skillDamage = {} }
end

function T.textModuleLoadsWithoutTheReportWindow()
    local required = {}
    local environment = setmetatable({
        require = function(name)
            required[#required + 1] = name
            return require(name)
        end,
    }, { __index = _G })
    local module = assert(loadfile("reframework/autorun/MyHuntReport/ReportText.lua", "t", environment))()
    assert(type(module.statTiles) == "function" and type(ReportText.historyRow) == "function")
    for _, name in ipairs(required) do assert(name ~= "MyHuntReport.ReportWindow", name) end
end

function T.resultTextAddsStarsOnlyForPositiveQuestLevels()
    assert(ReportText.resultText({ result = "clear" }) == Locale.text("result_quest"))
    assert(ReportText.resultText({ result = "clear", level = 5 }) == Locale.text("result_quest") .. " ★5")
    assert(ReportText.resultText({ result = "training", level = 5 }) == Locale.text("result_training"))
    for _, level in ipairs({ 0, -1, "5", false }) do
        assert(ReportText.resultText({ result = "clear", level = level }) == Locale.text("result_quest"))
    end
end

function T.outcomeTextLabelsClearFailAndAbandonOnly()
    local Theme = require("MyHuntReport.Theme")
    local language = Locale.current()
    local ok, err = pcall(function()
        assert(Theme.colors.success ~= nil and Theme.colors.warning ~= nil and Theme.colors.textMuted ~= nil)
        Locale.resolve("en")
        local expected = {
            clear = { "Clear", Theme.colors.success },
            fail = { "Failed", Theme.colors.warning },
            abandon = { "Abandoned", Theme.colors.textMuted },
        }
        for result, want in pairs(expected) do
            local label, color = ReportText.outcomeText({ result = result })
            assert(label == want[1], result)
            assert(color == want[2], result)
        end
        for _, quest in ipairs({ { result = "running" }, { result = "unknown" }, { result = "training" }, { result = "victory" }, {} }) do
            local label, color = ReportText.outcomeText(quest)
            assert(label == nil and color == nil, tostring(quest.result))
        end
        assert(ReportText.outcomeText(nil) == nil)
        Locale.resolve("ko")
        assert(ReportText.outcomeText({ result = "clear" }) == "클리어")
        assert(ReportText.outcomeText({ result = "fail" }) == "실패")
        assert(ReportText.outcomeText({ result = "abandon" }) == "포기")
    end)
    Locale.resolve(language)
    if not ok then error(err, 0) end
end

function T.skillDamageNamesComeFromLocale()
    Locale.init({})
    Locale.resolve("en")
    assert(ReportText.skillDamageName("violent") == "Violent Strike")
    assert(ReportText.skillDamageName("flare") == "Rathalos's Flare")
    assert(ReportText.skillDamageName("fury") == "Lagiacrus's Fury")
    assert(ReportText.skillDamageName("darkWave") == "Dark Knight")
    assert(ReportText.skillDamageName("flayer") == "Flayer")
    assert(ReportText.skillDamageName("elementConvert") == "Element Convert")
    Locale.resolve("ko")
    assert(ReportText.skillDamageName("mirrorBlade") == "거울대검")
    assert(ReportText.skillDamageName("flare") == "화룡의 힘")
    assert(ReportText.skillDamageName("fury") == "해룡의 와뢰")
    assert(ReportText.skillDamageName("darkWave") == "암흑기사")
    assert(ReportText.skillDamageName("flayer") == "쇄인자격")
    assert(ReportText.skillDamageName("elementConvert") == "속성 변환")
end

function T.headerWeaponTextJoinsUsedWeapons()
    Locale.init({})
    Locale.resolve("ko")
    assert(ReportText.headerWeaponText({ weapons = { { type = 0, name = "대검" }, { type = 13, name = "라이트보우건" } } })
        == "대검, 라이트보우건")
    assert(ReportText.headerWeaponText({ weapons = {}, weapon = { type = 13, name = "라이트보우건" } }) == "라이트보우건")
    assert(ReportText.headerWeaponText({ weapon = { type = 13, name = "라이트보우건" } }) == "라이트보우건")
    assert(ReportText.headerWeaponText({}) == "알 수 없는 무기")
    Locale.resolve("en")
    assert(ReportText.headerWeaponText({ weapons = { { type = 0, name = "Great Sword" } } }) == "Great Sword")
    assert(ReportText.headerWeaponText({}) == "Unknown weapon")
    assert(Locale.text("used_weapons") == "used_weapons", "used_weapons key must be gone")
end

function T.metaTextJoinsMonstersAndTime()
    assert(ReportText.metaText({ monsters = { { name = "미즈츠네" } }, quest = { elapsedSeconds = 754 } }) == "미즈츠네 · 12:34")
    assert(ReportText.metaText({ monsters = { { name = "A" }, { id = 7 } }, quest = { elapsedSeconds = 5 } }) == "A, 7 · 0:05")
    assert(ReportText.metaText({ monsters = {}, quest = { elapsedSeconds = 65 } }) == "1:05")
    assert(ReportText.metaText({}) == "0:00")
end

function T.historyRowSplitsTimeStarsWeaponsMonsters()
    Locale.init({})
    Locale.resolve("ko")
    local entry = snapshot("clear")
    entry.quest.endedAt = os.time({ year = 2026, month = 9, day = 23, hour = 21, min = 36, sec = 0 })
    entry.quest.weapons = { { name = "조충곤" }, { name = "라이트보우건" } }
    entry.quest.weapon = { name = "대검" }
    entry.monsters = { { name = "아자라칸" }, { id = 3 } }
    entry.quest.level = 5
    local row = ReportText.historyRow(entry)
    assert(row.time == "26-09-23 21:36" and row.stars == "★5")
    assert(row.weapons == "조충곤, 라이트보우건" and row.monsters == "아자라칸, 3")
    entry.quest.weapons = {}
    assert(ReportText.historyRow(entry).weapons == "대검")
    entry.quest.weapon = nil
    assert(ReportText.historyRow(entry).weapons == "알 수 없는 무기")
    entry.quest.result = "training"
    assert(ReportText.historyRow(entry).stars == "")
    entry.quest.result = "clear"
    entry.quest.level = nil
    assert(ReportText.historyRow(entry).stars == "")
    assert(ReportText.historyRow({}).monsters == "" and ReportText.historyRow({}).time == require("MyHuntReport.Format").clock(0))
end

function T.shareTextPrintsDashForMissingValues()
    assert(ReportText.shareText(nil, 100) == "-")
    assert(ReportText.shareText(25, 100) == "25.0%")
    assert(ReportText.shareText(0, 0) == "0.0%")
end

function T.statTilesFollowTheSnapshot()
    Locale.init({})
    Locale.resolve("en")
    local tiles = ReportText.statTiles({ stats = { combatDps = 45.66, critRate = 0.293, negativeCritRate = 0, avgAttack = 279.849, avgHitzone = 77.7, attribute = 0 } })
    assert(#tiles == 4)
    assert(tiles[1].label == "Combat DPS" and tiles[1].value == "45.7")
    assert(tiles[2].label == "Crit" and tiles[2].value == "29.3%")
    assert(tiles[3].label == "Avg attack" and tiles[3].value == "279.8", tiles[3].value)
    assert(tiles[4].label == "Avg hitzone" and tiles[4].value == "77.7")
    local withNegative = ReportText.statTiles({ stats = { combatDps = 45.66, critRate = 0.293, negativeCritRate = 0.045, avgAttack = 279.849, avgHitzone = 77.7, attribute = 0 } })
    assert(#withNegative == 5)
    assert(withNegative[2].label == "Crit" and withNegative[3].label == "Neg. crit" and withNegative[3].value == "4.5%")
    assert(withNegative[4].label == "Avg attack" and withNegative[5].label == "Avg hitzone")
    local rare = ReportText.statTiles({ stats = { negativeCritRate = 0.0001 } })
    assert(#rare == 5 and rare[3].label == "Neg. crit" and rare[3].value == "<0.1%")
    local withElement = ReportText.statTiles({ stats = { attribute = 1, avgAttributeHitzone = 29.2 } })
    assert(#withElement == 5 and withElement[5].value == "29.2" and withElement[1].value == "-")
    assert(withElement[3].label == "Avg attack" and withElement[3].value == "-")
    assert(withElement[5].label == "Fire hitzone", withElement[5].label)
    local training = ReportText.statTiles({ quest = { result = "training" }, stats = { combatDps = 45.66, critRate = 0.293, avgAttack = 260, attribute = 0 } })
    assert(#training == 3 and training[1].label == "Crit" and training[1].value == "29.3%")
    assert(training[2].label == "Avg attack" and training[2].value == "260.0")
    assert(training[3].label == "Avg hitzone")
    assert(ReportText.statTiles({ stats = { attribute = 4, avgAttributeHitzone = 10 } })[5].label == "Ice hitzone")
    assert(ReportText.statTiles({ stats = { attribute = 9, avgAttributeHitzone = 10 } })[5].label == "Avg elem. hitzone")
    Locale.resolve("ko")
    assert(ReportText.statTiles({ stats = { combatDps = 45.66 } })[1].label == "전투 DPS")
    assert(ReportText.statTiles({ stats = { combatDps = 45.66 } })[3].label == "평균 공격력")
    assert(ReportText.statTiles({ stats = { negativeCritRate = 0.1 } })[3].label == "역회심")
    Locale.resolve("en")
end

function T.elementTilesUseListOrderAndSuppressLegacyTileWhenListExists()
    Locale.init({})
    Locale.resolve("en")
    local stats = { attribute = 1, avgAttributeHitzone = 99, attributeHitzones = {
        { attribute = 3, avgHitzone = 22.26, hits = 3 },
        { attribute = 1, avgHitzone = 15.75, hits = 2 },
    } }
    local tiles = ReportText.statTiles({ stats = stats })
    assert(#tiles == 6)
    assert(tiles[5].label == "Thunder hitzone" and tiles[5].value == "22.3")
    assert(tiles[6].label == "Fire hitzone" and tiles[6].value == "15.8")
    stats.attributeHitzones = {}
    assert(#ReportText.statTiles({ stats = stats }) == 4)
    stats.attributeHitzones = nil
    tiles = ReportText.statTiles({ stats = stats })
    assert(#tiles == 5 and tiles[5].label == "Fire hitzone" and tiles[5].value == "99.0")
end

function T.versionTextShowsStoredVersion()
    local label = Locale.text("mod_version")
    assert(ReportText.versionText({ modVersion = "1.15.0" }) == string.format(label, "1.15.0"))
    assert(ReportText.versionText({ modVersion = "1.16.2" }) == string.format(label, "1.16.2"))
end

function T.versionTextLabelsEntriesWithoutVersionAsLegacy()
    local Version = require("MyHuntReport.Version")
    local legacy = string.format(Locale.text("mod_version"), string.format(Locale.text("mod_version_legacy"), Version.LAST_UNRECORDED))
    assert(ReportText.versionText({}) == legacy, ReportText.versionText({}))
    assert(ReportText.versionText({ modVersion = "" }) == legacy)
    assert(ReportText.versionText(nil) == legacy)
end

function T.versionTextIsLocalized()
    Locale.init({ gameLanguage = function() return "en" end })
    Locale.resolve("en")
    assert(ReportText.versionText({ modVersion = "1.15.0" }) == "Mod version: 1.15.0", ReportText.versionText({ modVersion = "1.15.0" }))
    assert(ReportText.versionText({}) == "Mod version: 1.14.1 or earlier", ReportText.versionText({}))
    Locale.resolve("ko")
    assert(ReportText.versionText({ modVersion = "1.15.0" }) == "모드 버전: 1.15.0", ReportText.versionText({ modVersion = "1.15.0" }))
    assert(ReportText.versionText({}) == "모드 버전: 1.14.1 이하", ReportText.versionText({}))
    Locale.resolve("en")
end

local function burstName(id)
    assert(id == 115, tostring(id))
    return "Burst"
end

local function shape(rows)
    local parts = {}
    for _, row in ipairs(rows) do
        parts[#parts + 1] = (row.child and ">" or "") .. row.name .. "=" .. tostring(row.share)
    end
    return table.concat(parts, "|")
end

function T.skillRowsGroupBurstStagesAtTheFirstStagePosition()
    Locale.resolve("en")
    local rows = ReportText.skillRows({
        { id = 10, name = "A", share = 0.5 },
        { id = "burst:stage2", name = "Burst Stage 2", share = 0.25 },
        { id = 11, name = "B", share = 0.125 },
        { id = "burst:stage1", name = "Burst Stage 1", share = 0.0625 },
    }, burstName)
    assert(shape(rows) == "A=0.5|Burst=0.3125|>Stage 1=0.0625|>Stage 2=0.25|B=0.125", shape(rows))
    assert(rows[1].child == false and rows[2].child == false and rows[3].child == true)
end

function T.skillRowsBurstWithOneStageShowsOneChild()
    Locale.resolve("en")
    local rows = ReportText.skillRows({ { id = "burst:stage1", name = "Burst Stage 1", share = 0.25 } }, burstName)
    assert(shape(rows) == "Burst=0.25|>Stage 1=0.25", shape(rows))
end

function T.skillRowsSplitWeaknessExploitIntoWeakPointAndWound()
    Locale.resolve("en")
    local rows = ReportText.skillRows({
        { id = 63, name = "Weakness Exploit", share = 0.5 },
        { id = 20, name = "C", share = 0.375 },
        { id = "wex:wound", name = "Weakness Exploit · Wound", share = 0.125 },
    }, burstName)
    assert(shape(rows) == "Weakness Exploit=0.5|>Weak point=0.375|>Wound=0.125|C=0.375", shape(rows))
end

function T.skillRowsClampWeakPointAtZero()
    Locale.resolve("en")
    local rows = ReportText.skillRows({
        { id = 63, name = "Weakness Exploit", share = 0.125 },
        { id = "wex:wound", name = "Weakness Exploit · Wound", share = 0.25 },
    }, burstName)
    assert(shape(rows) == "Weakness Exploit=0.125|>Wound=0.25", shape(rows))
end

function T.skillRowsHideZeroChildrenAndKeepTheParentAlone()
    Locale.resolve("en")
    local rows = ReportText.skillRows({
        { id = "burst:stage1", name = "Burst Stage 1", share = 0 },
        { id = "burst:stage2", name = "Burst Stage 2", share = 0 },
        { id = 63, name = "Weakness Exploit", share = 0 },
        { id = "wex:wound", name = "Weakness Exploit · Wound", share = 0 },
    }, burstName)
    assert(shape(rows) == "Burst=0|Weakness Exploit=0", shape(rows))
    rows = ReportText.skillRows({ { id = 63, name = "Weakness Exploit", share = 0.25 } }, burstName)
    assert(shape(rows) == "Weakness Exploit=0.25|>Weak point=0.25", shape(rows))
end

function T.skillRowsShowAnOrphanWoundRowWithItsFullName()
    Locale.resolve("en")
    local rows = ReportText.skillRows({ { id = "wex:wound", name = "Weakness Exploit · Wound", share = 0.25 } }, burstName)
    assert(shape(rows) == "Weakness Exploit · Wound=0.25", shape(rows))
    assert(rows[1].child == false)
end

function T.skillRowsKeepUnrelatedRowsAndValueKinds()
    local rows = ReportText.skillRows({
        { id = 1, name = "X", share = 0.5 },
        { label = { kind = "heal" }, name = "Hasten Recovery", share = 0.25, valueKind = "hp" },
    }, burstName)
    assert(shape(rows) == "X=0.5|Hasten Recovery=0.25", shape(rows))
    assert(rows[1].valueKind == nil and rows[2].valueKind == "hp")
    assert(#ReportText.skillRows({}, burstName) == 0)
end

function T.skillRowsChildNamesFollowTheLanguage()
    local input = {
        { id = "burst:stage1", name = "연격 1단계", share = 0.25 },
        { id = "burst:stage2", name = "연격 2단계", share = 0.25 },
        { id = 63, name = "약점 특효", share = 0.5 },
        { id = "wex:wound", name = "약점 특효 · 상처", share = 0.25 },
    }
    Locale.resolve("ko")
    local rows = ReportText.skillRows(input, function() return "연격" end)
    assert(shape(rows) == "연격=0.5|>1단계=0.25|>2단계=0.25|약점 특효=0.5|>약점 부위=0.25|>상처=0.25", shape(rows))
    Locale.resolve("en")
    rows = ReportText.skillRows(input, burstName)
    assert(shape(rows) == "Burst=0.5|>Stage 1=0.25|>Stage 2=0.25|약점 특효=0.5|>Weak point=0.25|>Wound=0.25", shape(rows))
end

return T
