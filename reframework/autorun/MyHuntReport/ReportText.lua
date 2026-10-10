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
    local outcome, outcomeColor = ReportText.outcomeText(quest)
    return {
        time = Format.clock(quest.endedAt or 0),
        stars = stars,
        weapons = weaponNames(quest),
        monsters = monsterNames(entry.monsters),
        outcome = outcome,
        outcomeColor = outcomeColor,
    }
end

local BURST_SKILL_ID = 115
local BURST_STAGE1, BURST_STAGE2 = "burst:stage1", "burst:stage2"
local WEAKNESS_EXPLOIT_ID = 63
local WEX_WOUND = "wex:wound"

local function shareOf(row)
    return row and type(row.share) == "number" and row.share or 0
end

local function displayRow(name, share, valueKind, child)
    return { name = name, share = share, valueKind = valueKind, child = child }
end

local function byShareThenName(a, b)
    if shareOf(a) ~= shareOf(b) then return shareOf(a) > shareOf(b) end
    return tostring(a.name) < tostring(b.name)
end

local function childRows(entries)
    local children = {}
    for index, entry in ipairs(entries) do
        if entry.share > 0 then
            children[#children + 1] = { index = index, row = displayRow(L(entry.key), entry.share, nil, true) }
        end
    end
    table.sort(children, function(a, b)
        if a.row.share ~= b.row.share then return a.row.share > b.row.share end
        return a.index < b.index
    end)
    local rows = {}
    for _, child in ipairs(children) do rows[#rows + 1] = child.row end
    return rows
end

function ReportText.skillRows(rows, skillName)
    local byId = {}
    for _, row in ipairs(rows or {}) do
        if row.id ~= nil then byId[row.id] = row end
    end
    local groups, heals = {}, {}
    local function addGroup(parent, children)
        groups[#groups + 1] = { parent = parent, children = children or {} }
    end
    local burstShown = false
    for _, row in ipairs(rows or {}) do
        local id = row.id
        if row.label and row.label.kind == "heal" then
            heals[#heals + 1] = displayRow(row.name, row.share, row.valueKind, false)
        elseif id == BURST_STAGE1 or id == BURST_STAGE2 then
            if not burstShown then
                burstShown = true
                local stage1, stage2 = shareOf(byId[BURST_STAGE1]), shareOf(byId[BURST_STAGE2])
                addGroup(displayRow(skillName(BURST_SKILL_ID), stage1 + stage2, nil, false), childRows({
                    { key = "skill_burst_stage1", share = stage1 },
                    { key = "skill_burst_stage2", share = stage2 },
                }))
            end
        elseif id == WEAKNESS_EXPLOIT_ID then
            local wound = shareOf(byId[WEX_WOUND])
            addGroup(displayRow(row.name, row.share, row.valueKind, false), childRows({
                { key = "skill_wex_weak_point", share = math.max(0, shareOf(row) - wound) },
                { key = "skill_wex_wound", share = wound },
            }))
        elseif not (id == WEX_WOUND and byId[WEAKNESS_EXPLOIT_ID]) then
            addGroup(displayRow(row.name, row.share, row.valueKind, false))
        end
    end
    table.sort(groups, function(a, b) return byShareThenName(a.parent, b.parent) end)
    local display = {}
    for _, group in ipairs(groups) do
        display[#display + 1] = group.parent
        for _, child in ipairs(group.children) do display[#display + 1] = child end
    end
    for _, row in ipairs(heals) do display[#display + 1] = row end
    return display
end

function ReportText.shareText(value, total)
    if type(value) ~= "number" then return "-" end
    return Format.percent(total > 0 and value / total or 0)
end

function ReportText.skillDamageName(kind)
    return L("skill_damage_" .. tostring(kind))
end

return ReportText
