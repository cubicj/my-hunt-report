local Game = require("MyHuntReport.Game")
local Locale = require("MyHuntReport.Locale")
local Log = require("MyHuntReport.Log")
local MotionNames = require("MyHuntReport.MotionNames")
local SkillState = require("MyHuntReport.SkillState")

local Names = {}

local LEGENDARY_NORMAL = 1
local LEGENDARY_KING = 2
local ROLE_FRENZY = 3

local monsters = {}
local items = {}
local weapons = {}
local echoWaves = {}

local function echoWaveName(highFreq)
    local key = Locale.textKey() .. ":" .. tostring(highFreq)
    if echoWaves[key] then return echoWaves[key] end
    local ok, name = pcall(function()
        local guid = Game.callStatic("app.Wp05Def",
            "MusicSkillName(app.Wp05Def.WP05_MUSIC_SKILL_TYPE, app.Wp05Def.WP05_MUSIC_SKILL_HIGH_FREQ_TYPE)", 48, highFreq)
        return Game.messageText(guid)
    end)
    if not ok or not Game.isUsableText(name) then
        name = Locale.text("motion_echo_wave")
    end
    echoWaves[key] = name
    return name
end

local function monsterName(label)
    local emId, roleId, legendaryId = label.emId, label.roleId or 0, label.legendaryId or 0
    local key = Locale.textKey() .. ":" .. tostring(emId) .. ":" .. tostring(roleId) .. ":" .. tostring(legendaryId)
    if monsters[key] then return monsters[key] end
    local path = "EnemyName"
    local ok, name = pcall(function()
        local guid = Game.callStatic("app.EnemyDef", "EnemyName(app.EnemyDef.ID)", emId)
        return Game.messageText(guid)
    end)
    if not ok or type(name) ~= "string" or #name == 0 then
        Log.error("monster name unavailable for " .. tostring(emId), "hit:name:" .. tostring(emId))
        name = "#" .. tostring(emId)
        path = "identifier"
    end
    if legendaryId == LEGENDARY_NORMAL or legendaryId == LEGENDARY_KING or roleId == ROLE_FRENZY then
        local okVariant, variantName = pcall(function()
            return Game.callStatic("app.EnemyDef",
                "NameString(app.EnemyDef.ID, app.EnemyDef.ROLE_ID, app.EnemyDef.LEGENDARY_ID)", emId, roleId, legendaryId)
        end)
        if okVariant and Game.isUsableText(variantName) and variantName ~= name then
            name = variantName
            path = "NameString"
        else
            local prefix = legendaryId == LEGENDARY_KING and "monster_arch_tempered"
                or legendaryId == LEGENDARY_NORMAL and "monster_tempered" or "monster_frenzied"
            name = Locale.text(prefix) .. name
            path = "prefix"
        end
    end
    Log.debug("monster name " .. key .. " via " .. path, "monster:name:" .. key)
    monsters[key] = name
    return name
end

function Names.item(itemId)
    local key = Locale.textKey() .. ":" .. tostring(itemId)
    if items[key] then return items[key] end
    local guid = Game.callStatic("app.ItemDef", "Name(app.ItemDef.ID)", itemId)
    local name = Game.messageText(guid)
    if not name then name = Game.callStatic("app.ItemDef", "NameString(app.ItemDef.ID)", itemId) end
    if type(name) ~= "string" or #name == 0 then name = "#" .. tostring(itemId) end
    items[key] = name
    return name
end

local function weaponName(weaponType)
    if weaponType == nil then return nil end
    local key = Locale.textKey() .. ":" .. tostring(weaponType)
    if weapons[key] ~= nil then return weapons[key] or nil end
    local guid = Game.callStatic("app.WeaponUtil", "getWeaponTypeName(app.WeaponDef.TYPE)", weaponType)
    local name = Game.messageText(guid)
    weapons[key] = name or false
    return name
end

function Names.resolve(label)
    if label.kind == "echoWave" then return echoWaveName(label.highFreq) end
    if label.kind == "monster" then return monsterName(label) end
    if label.kind == "motion" then
        if label.itemRole == "ammo" then
            local name = Names.item(label.itemId)
            if label.className:find("Variable", 1, true) or label.className:find("StepDodge", 1, true) then
                name = name .. " - " .. MotionNames.nameFor(label.className, label.guideId)
            elseif label.rapid then
                name = name .. " " .. Locale.text("rapid_fire")
            end
            return name
        end
        local name = MotionNames.nameFor(label.className, label.guideId)
        if label.itemRole == "coating" then return name .. " [" .. Names.item(label.itemId) .. "]" end
        if label.itemId ~= nil then name = name .. " " .. Names.item(label.itemId) end
        return name
    end
    if label.kind == "kinsect" then return Locale.text("motion_kinsect") end
    if label.kind == "slinger" then return Locale.text("motion_slinger") end
    if label.kind == "proc" then return Locale.text("proc_" .. label.proc) end
    if label.kind == "skill" then return SkillState.skillName(label.id) end
    if label.kind == "weapon" then return weaponName(label.type) end
end

function Names.reset()
    monsters = {}
    items = {}
    weapons = {}
    echoWaves = {}
end

return Names
