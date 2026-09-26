local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")
local Locale = require("MyHuntReport.Locale")

local SkillState = {}

local INFO_TYPE = "app.cHunterSkillParamInfo.cInfo"
local BURST_SKILL = 115
local BURST_LV1 = "burst:stage1"
local BURST_LV2 = "burst:stage2"
local BURST_LV2_HITS = 5
local MELODY_BASE = 2000
local HIBIKI_BASE = 3000
local MELODY_SLOTS = { 11, 12, 13, 14, 42, 43 }
local HIBIKI_ATTACK_TYPE = 4
local WEAPON_BASE = 4000
local WEAPON_STATES = {
    [2] = {
        { code = 1, read = function(handling) return handling:call("get_IsMikiriBuff") == true end },
    },
    [3] = {
        { code = 1, read = function(handling) return handling:call("get_AuraLevel") == 4 end },
    },
    [8] = {
        { code = 1, read = function(handling) return handling:call("get_IsSwordAwaken") == true end,
            eligible = function(handling) return handling:call("get_Mode") == 1 end },
        { code = 2, read = function(handling) return handling:call("get_IsAxeEnhanced") == true end,
            eligible = function(handling) return handling:call("get_Mode") == 0 end },
    },
    [9] = {
        { code = 1, read = function(handling) return handling:call("get_IsSwordEnhanced") == true end,
            eligible = function(handling) return handling:call("get_Mode") == 0 end },
        { code = 2, read = function(handling) return handling:call("get_IsShieldEnhanced") == true end },
        { code = 3, read = function(handling) return handling:call("get_IsAxeEnhanced") == true end,
            eligible = function(handling) return handling:call("get_Mode") == 1 end },
    },
    [10] = {
        { code = 1, read = function(handling) return handling:call("get_IsTrippleUp") == true end,
            eligible = function(_, hit) return hit.kinsect ~= true end },
    },
}

local fieldNames = nil
local names = {}
local BOOLEAN_FIELDS = {
    { id = 59, field = "_IsActiveChallenger" },
    { id = 60, field = "_IsActiveFullCharge" },
    { id = 65, field = "_IsActiveKonshin" },
    { id = 101, field = "_IsAdrenalineRush" },
    { id = 240, field = "_IsActiveChallengerAttr" },
}
local FRENZY_ID = 194
local WEAKNESS_EXPLOIT_ID = 63
local WEX_WOUND = "wex:wound"
local MINDS_EYE_ID = 19
local AIRBORNE_ID = 56
local CONDITION_IDS = { WEAKNESS_EXPLOIT_ID, MINDS_EYE_ID, AIRBORNE_ID }
local WEAK_HITZONE = 45

local equipped = nil
local lastEquippedPoll = nil
local seenActive = {}
local openers = nil
local installed = false

local function enumValue(value)
    if type(value) == "number" then return value end
    local ok, raw = pcall(function() return value:get_field("value__") end)
    if ok and type(raw) == "number" then return raw end
    return nil
end

local function arrayElements(array)
    if array == nil then return {} end
    local ok, elements = pcall(function() return array:get_elements() end)
    if ok and type(elements) == "table" then return elements end
    local okSize, size = pcall(function() return array:get_size() end)
    if not okSize or type(size) ~= "number" then return {} end
    local list = {}
    for index = 0, size - 1 do
        local okItem, item = pcall(function() return array[index] end)
        if okItem and item ~= nil then list[#list + 1] = item end
    end
    return list
end

local MAX_PLAIN_SKILL_ID = 1000

local function plainSkillId(value)
    local id = enumValue(value)
    if id and id >= 0 and id < MAX_PLAIN_SKILL_ID then return id end
    return nil
end

local function entrySkillId(entry)
    local ok, value = pcall(function() return entry:get_skillId() end)
    if ok and value ~= nil then return plainSkillId(value) end
    local okField, field = pcall(function() return entry["<skillId>k__BackingField"] end)
    if okField then return plainSkillId(field) end
    return nil
end

local function entryOpenSkills(entry)
    local ok, array = pcall(function() return entry:get_openSkill() end)
    if not ok or array == nil then
        local okField, field = pcall(function() return entry["<openSkill>k__BackingField"] end)
        array = okField and field or nil
    end
    return arrayElements(array)
end

local function loadOpeners()
    local map = {}
    local manager = Game.singleton("app.VariousDataManager")
    if not manager then return map, false end
    local count = 0
    local ok, err = pcall(function()
        local values = manager._Setting._SkillData:getValues()
        for index = 0, values:get_Count() - 1 do
            local entry = values:get_Item(index)
            if entry then
                local skillId = entrySkillId(entry)
                for _, opened in ipairs(entryOpenSkills(entry)) do
                    local openedId = plainSkillId(opened)
                    if skillId and openedId and openedId ~= skillId and map[openedId] == nil then
                        map[openedId] = skillId
                        count = count + 1
                    end
                end
            end
        end
    end)
    if not ok then
        Log.error("skill opener scan failed: " .. tostring(err), "skillstate:openers")
        return map, false
    end
    Log.debug("skill openers loaded: " .. count)
    return map, true
end

local function openerMap()
    if openers == nil then
        local map, ok = loadOpeners()
        if ok then openers = map else return map end
    end
    return openers
end

function SkillState.displayId(id)
    return openerMap()[id] or id
end

local function paramInfo()
    local hunter = Game.masterHunter()
    if not hunter then return nil end
    local ok, info = pcall(function()
        local skill = hunter:get_HunterSkill()
        if not skill then return nil end
        return skill._HunterSkillParamInfo
    end)
    if ok then return info end
    return nil
end

local function hunterSkill()
    local hunter = Game.masterHunter()
    if not hunter then return nil end
    local ok, skill = pcall(function() return hunter:get_HunterSkill() end)
    if ok then return skill end
    return nil
end

local function collectFields(info)
    local list = {}
    local ok, err = pcall(function()
        local td = info:get_type_definition()
        while td do
            for _, field in pairs(td:get_fields()) do
                local fieldType = field:get_type()
                if fieldType and fieldType:is_a(INFO_TYPE) then
                    list[#list + 1] = field:get_name()
                end
            end
            td = td:get_parent_type()
        end
    end)
    if not ok then
        Log.error("skill field scan failed: " .. tostring(err), "skillstate:scan")
        return nil
    end
    table.sort(list)
    Log.debug("skill fields found: " .. #list)
    return list
end

local function eachInfo(info, callback)
    if not fieldNames then fieldNames = collectFields(info) end
    if not fieldNames then return end
    for _, name in ipairs(fieldNames) do
        local ok, object = pcall(function() return info[name] end)
        if ok and object then
            local okRead, skillId, timer = pcall(function() return object._Skill, object._Timer end)
            if okRead and type(skillId) == "number" then callback(skillId, timer or 0) end
        end
    end
end

function SkillState.conditionSet(context, equippedSet)
    local set = {}
    local raw = context and context.rawHitzone or nil
    if equippedSet[WEAKNESS_EXPLOIT_ID] and ((type(raw) == "number" and raw >= WEAK_HITZONE) or (context and context.wounded == true)) then
        set[WEAKNESS_EXPLOIT_ID] = true
    end
    if equippedSet[WEAKNESS_EXPLOIT_ID] and context and context.wounded == true then
        set[WEX_WOUND] = true
    end
    if equippedSet[MINDS_EYE_ID] and type(raw) == "number" and raw < WEAK_HITZONE then
        set[MINDS_EYE_ID] = true
    end
    if equippedSet[AIRBORNE_ID] and context and context.hien == true then
        set[AIRBORNE_ID] = true
    end
    return set
end

local function noteActive(id)
    if not seenActive[id] then
        seenActive[id] = true
        Log.debug("skill state " .. tostring(id) .. " active")
    end
end

local function booleanSet(info, equippedSet)
    local set = {}
    for _, entry in ipairs(BOOLEAN_FIELDS) do
        if equippedSet[entry.id] then
            local ok, value = pcall(function() return info[entry.field] end)
            if not ok then
                Log.error("skill field unreadable " .. entry.field, "skill:field:" .. entry.field)
            elseif value == true then
                set[entry.id] = true
                noteActive(entry.id)
            end
        end
    end
    return set
end

local function frenzyActive(hunter)
    local ok, active = pcall(function()
        local frenzy = hunter:get_HunterStatus()._BadConditions._Frenzy
        return frenzy._IsActive == true and frenzy._State == 2
    end)
    if not ok then
        Log.error("skill field unreadable _Frenzy", "skill:field:_Frenzy")
        return false
    end
    if active then noteActive(FRENZY_ID) end
    return active == true
end

function SkillState.refreshEquipped()
    local previous = equipped
    local skill = hunterSkill()
    if not skill and previous then return previous, false end
    equipped = {}
    local list = {}
    if skill then
        local ids = {}
        local info = paramInfo()
        if info then eachInfo(info, function(skillId) ids[skillId] = true end) end
        for _, entry in ipairs(BOOLEAN_FIELDS) do ids[entry.id] = true end
        ids[FRENZY_ID] = true
        for _, id in ipairs(CONDITION_IDS) do ids[id] = true end
        for id in pairs(ids) do
            local ok, active = pcall(function() return skill:checkSkillActive(id) end)
            if ok and active == true then
                equipped[id] = true
                list[#list + 1] = id
            end
        end
    end
    local changed = previous == nil
    for id in pairs(equipped) do
        if not previous or not previous[id] then changed = true end
    end
    for id in pairs(previous or {}) do
        if not equipped[id] then changed = true end
    end
    if changed then
        table.sort(list)
        local text = {}
        for index, id in ipairs(list) do text[index] = tostring(id) end
        Log.debug("equipped skills: " .. table.concat(text, ","))
    end
    return equipped, changed
end

function SkillState.pollEquipped(now, phase)
    if phase ~= "training" and phase ~= "playing" then return end
    if lastEquippedPoll ~= nil and now - lastEquippedPoll < 2 then return end
    lastEquippedPoll = now
    SkillState.refreshEquipped()
end

function SkillState.install()
    if installed then return end
    installed = true
    Game.hook("app.GUIManager", "onPlEquipChange()", nil, function()
        local _, changed = SkillState.refreshEquipped()
        if changed then Log.debug("equip change refreshed equipped skills", "skill:equip-change") end
    end)
end

local function equippedSet()
    if equipped == nil then SkillState.refreshEquipped() end
    return equipped
end

function SkillState.reset()
    fieldNames = nil
    equipped = nil
    lastEquippedPoll = nil
    seenActive = {}
end

function SkillState.burstLevel(timer, hitCount)
    if (tonumber(timer) or 0) <= 0 then return nil end
    if (tonumber(hitCount) or 0) >= BURST_LV2_HITS then return BURST_LV2 end
    return BURST_LV1
end

local function burstState(info)
    local ok, timer, hitCount = pcall(function()
        local burst = info._ContinuousAttackInfo
        if not burst then return nil end
        return burst._Timer, burst._HitCount
    end)
    if not ok or timer == nil then return nil end
    Log.debug(string.format("burst timer=%s hits=%s", tostring(timer), tostring(hitCount)), "skillstate:burst")
    return SkillState.burstLevel(timer, hitCount)
end

local function validName(text)
    if not Game.isUsableText(text) then return nil end
    return text
end

local function melodySet()
    local set = {}
    local skill = hunterSkill()
    if not skill then return set end
    local ok, music = pcall(function() return skill._Wp05MusicSkill end)
    if not ok or not music then return set end
    for _, slot in ipairs(MELODY_SLOTS) do
        local enabled, active = pcall(function() return music:call("isEnable", slot) end)
        if enabled and active == true then set[MELODY_BASE + slot] = true end
    end
    local enabled, active = pcall(function() return music:call("isEnable", 52 + HIBIKI_ATTACK_TYPE) end)
    if enabled and active == true then set[HIBIKI_BASE + HIBIKI_ATTACK_TYPE] = true end
    return set
end

function SkillState.weaponStateId(weaponType, code)
    return WEAPON_BASE + weaponType * 10 + code
end

function SkillState.weaponStateType(id)
    if type(id) ~= "number" or id < WEAPON_BASE or id >= WEAPON_BASE + 1000 then return nil end
    local weaponType = (id - WEAPON_BASE) // 10
    local code = (id - WEAPON_BASE) % 10
    for _, entry in ipairs(WEAPON_STATES[weaponType] or {}) do
        if entry.code == code then return weaponType, code end
    end
    return nil
end

local function weaponStateSets(context)
    local active, eligible = {}, {}
    local hunter = Game.masterHunter()
    if not hunter then return active, eligible end
    local ok, weaponType, handling = pcall(function()
        return hunter:get_WeaponType(), hunter:get_WeaponHandling()
    end)
    if not ok then
        Log.debug("weapon handling read failed: " .. tostring(weaponType), "skill:weapon-state:handling")
        return active, eligible
    end
    if handling == nil then return active, eligible end
    for _, entry in ipairs(WEAPON_STATES[weaponType] or {}) do
        local id = SkillState.weaponStateId(weaponType, entry.code)
        local okEntry, isEligible = pcall(function()
            return not entry.eligible or entry.eligible(handling, context) == true
        end)
        if not okEntry then
            Log.debug("weapon state read failed for " .. tostring(id) .. ": " .. tostring(isEligible), "skill:weapon-state:" .. tostring(id))
        elseif isEligible then
            eligible[id] = true
            local okRead, isActive = pcall(function() return entry.read(handling) end)
            if not okRead then
                Log.debug("weapon state read failed for " .. tostring(id) .. ": " .. tostring(isActive), "skill:weapon-state:" .. tostring(id))
            elseif isActive == true then
                active[id] = true
            end
        end
    end
    return active, eligible
end

function SkillState.activeSet(context)
    context = context or {}
    local set = {}
    local info = paramInfo()
    if info then
        eachInfo(info, function(skillId, timer)
            if skillId ~= BURST_SKILL and timer > 0 then set[skillId] = true end
        end)
        local level = burstState(info)
        if level then set[level] = true end
    end
    local equippedIds = equippedSet()
    if info then
        for id in pairs(booleanSet(info, equippedIds)) do set[id] = true end
    end
    if equippedIds[FRENZY_ID] then
        local hunter = Game.masterHunter()
        if hunter and frenzyActive(hunter) then set[FRENZY_ID] = true end
    end
    for id in pairs(SkillState.conditionSet(context, equippedIds)) do set[id] = true end
    for id in pairs(melodySet()) do set[id] = true end
    local weaponActive, eligible = weaponStateSets(context)
    for id in pairs(weaponActive) do set[id] = true end
    local shown = {}
    for id in pairs(set) do shown[SkillState.displayId(id)] = true end
    return shown, eligible
end

function SkillState.skillName(skillId)
    if skillId == BURST_LV1 then return string.format(Locale.text("burst_stage"), SkillState.skillName(BURST_SKILL), 1) end
    if skillId == BURST_LV2 then return string.format(Locale.text("burst_stage"), SkillState.skillName(BURST_SKILL), 2) end
    if skillId == WEX_WOUND then return string.format(Locale.text("wex_wound"), SkillState.skillName(WEAKNESS_EXPLOIT_ID)) end
    local key = Locale.textKey() .. ":" .. tostring(skillId)
    local cached = names[key]
    if cached then return cached end
    local text
    if skillId == HIBIKI_BASE + HIBIKI_ATTACK_TYPE then
        local guid = Game.callStatic("app.Wp05Def", "SkillName(app.Wp05Def.WP05_HIBIKI_SKILL_TYPE)", HIBIKI_ATTACK_TYPE)
        text = validName(Game.messageText(guid))
        text = text and (Locale.text("bubble_prefix") .. text) or Locale.text("melody_hibiki_attack")
    elseif SkillState.weaponStateType(skillId) then
        local weaponType, code = SkillState.weaponStateType(skillId)
        local suffix = weaponType .. "_" .. code
        text = Locale.text("weapon_state_" .. suffix)
    elseif skillId > MELODY_BASE and skillId < HIBIKI_BASE then
        local melodyType = skillId - MELODY_BASE
        local guid = Game.callStatic("app.Wp05Def", "MusicSkillName(app.Wp05Def.WP05_MUSIC_SKILL_TYPE, app.Wp05Def.WP05_MUSIC_SKILL_HIGH_FREQ_TYPE)", melodyType, 0)
        text = Locale.text("melody_prefix") .. (validName(Game.messageText(guid)) or ("#" .. tostring(melodyType)))
    else
        local guid = Game.callStatic("app.MessageUtil", "getHunterSkillName(app.HunterDef.Skill)", skillId)
        text = Game.messageText(guid) or ("#" .. tostring(skillId))
    end
    names[key] = text
    return text
end

function SkillState.equippedTracked()
    local rows = {}
    local seen = {}
    for rawId in pairs(equippedSet()) do
        local id = SkillState.displayId(rawId)
        if not seen[id] then
            seen[id] = true
            if id == BURST_SKILL then
                rows[#rows + 1] = { id = BURST_LV1, name = SkillState.skillName(BURST_LV1) }
                rows[#rows + 1] = { id = BURST_LV2, name = SkillState.skillName(BURST_LV2) }
            else
                rows[#rows + 1] = { id = id, name = SkillState.skillName(id) }
                if id == WEAKNESS_EXPLOIT_ID then
                    rows[#rows + 1] = { id = WEX_WOUND, name = SkillState.skillName(WEX_WOUND) }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        local aId = type(a.id) == "number" and a.id or (a.id == WEX_WOUND and WEAKNESS_EXPLOIT_ID or BURST_SKILL)
        local bId = type(b.id) == "number" and b.id or (b.id == WEX_WOUND and WEAKNESS_EXPLOIT_ID or BURST_SKILL)
        if aId ~= bId then return aId < bId end
        return tostring(a.id) < tostring(b.id)
    end)
    return rows
end

return SkillState
