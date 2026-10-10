local Theme = require("MyHuntReport.Theme")
local Locale = require("MyHuntReport.Locale")
local Format = require("MyHuntReport.Format")
local Version = require("MyHuntReport.Version")

local ReportText = {}

local ELEMENT_LABELS = {
    [1] = "avg_hitzone_fire", [2] = "avg_hitzone_water", [3] = "avg_hitzone_thunder",
    [4] = "avg_hitzone_ice", [5] = "avg_hitzone_dragon",
}

local function L(key)
    return Locale.text(key)
end

function ReportText.statTiles(snapshot)
    local stats = snapshot.stats or {}
    local tiles = {}
    if not (snapshot.quest and snapshot.quest.result == "training") then
        tiles[#tiles + 1] = { label = L("combat_dps"), value = Format.decimal(stats.combatDps, 1) }
    end
    tiles[#tiles + 1] = { label = L("crit_rate"), value = Format.rate(stats.critRate) }
    if type(stats.negativeCritRate) == "number" and stats.negativeCritRate > 0 then
        tiles[#tiles + 1] = { label = L("negative_crit_rate"), value = Format.rate(stats.negativeCritRate) }
    end
    tiles[#tiles + 1] = { label = L("avg_attack"), value = Format.decimal(stats.avgAttack, 1) }
    tiles[#tiles + 1] = { label = L("avg_hitzone"), value = Format.decimal(stats.avgHitzone, 1) }
    if stats.attributeHitzones then
        for _, entry in ipairs(stats.attributeHitzones) do
            tiles[#tiles + 1] = { label = L(ELEMENT_LABELS[entry.attribute] or "avg_attribute_hitzone"), value = Format.decimal(entry.avgHitzone, 1) }
        end
    elseif (stats.attribute or 0) > 0 then
        local key = ELEMENT_LABELS[stats.attribute] or "avg_attribute_hitzone"
        tiles[#tiles + 1] = { label = L(key), value = Format.decimal(stats.avgAttributeHitzone, 1) }
    end
    return tiles
end

local function resultLabel(result)
    if result == "training" then return L("result_training"), Theme.colors.accent end
    return L("result_quest"), Theme.colors.accent
end

function ReportText.resultText(quest)
    quest = quest or {}
    local label, color = resultLabel(quest.result)
    local stars = ""
    if quest.result ~= "training" and type(quest.level) == "number" and quest.level > 0 then
        stars = "★" .. quest.level
        label = label .. " " .. stars
    end
    return label, color, stars
end

local OUTCOMES = {
    clear = { "result_clear", "success" },
    fail = { "result_fail", "warning" },
    abandon = { "result_abandon", "textMuted" },
}

function ReportText.outcomeText(quest)
    local outcome = type(quest) == "table" and OUTCOMES[quest.result]
    if not outcome then return nil end
    return L(outcome[1]), Theme.colors[outcome[2]]
end

local function weaponNames(quest)
    quest = quest or {}
    local names = {}
    for _, weapon in ipairs(type(quest.weapons) == "table" and quest.weapons or {}) do
        if type(weapon.name) == "string" and #weapon.name > 0 then names[#names + 1] = weapon.name end
    end
    if #names > 0 then return table.concat(names, ", ") end
    if type(quest.weapon) == "table" and type(quest.weapon.name) == "string" and #quest.weapon.name > 0 then
        return quest.weapon.name
    end
    return L("weapon_unknown")
end

local function monsterNames(list)
    local names = {}
    for _, monster in ipairs(type(list) == "table" and list or {}) do
        names[#names + 1] = tostring(monster.name or monster.id)
    end
    return table.concat(names, ", ")
end

function ReportText.headerWeaponText(quest)
    return weaponNames(quest)
end

function ReportText.metaText(snapshot)
    snapshot = snapshot or {}
    local quest = snapshot.quest or {}
    local time = Format.duration(quest.elapsedSeconds or 0)
    local monsters = monsterNames(snapshot.monsters)
    if monsters == "" then return time end
    return monsters .. " · " .. time
end

function ReportText.versionText(snapshot)
    local version = type(snapshot) == "table" and snapshot.modVersion
    if type(version) ~= "string" or version == "" then
        version = string.format(L("mod_version_legacy"), Version.LAST_UNRECORDED)
    end
    return string.format(L("mod_version"), version)
end

function ReportText.historyRow(entry)
    entry = entry or {}
    local quest = entry.quest or {}
    local _, _, stars = ReportText.resultText(quest)
    return {
        time = Format.clock(quest.endedAt or 0),
        stars = stars,
        weapons = weaponNames(quest),
        monsters = monsterNames(entry.monsters),
    }
end

function ReportText.shareText(value, total)
    if type(value) ~= "number" then return "-" end
    return Format.percent(total > 0 and value / total or 0)
end

function ReportText.skillDamageName(kind)
    return L("skill_damage_" .. tostring(kind))
end

return ReportText
