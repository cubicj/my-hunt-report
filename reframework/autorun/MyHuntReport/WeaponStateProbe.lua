local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local WeaponStateProbe = {}

WeaponStateProbe.GETTERS = {
    [2] = { "get_IsKijinOn", "get_IsKijinEnhancement", "get_IsMikiriBuff", "get_KijinGauge", "get_KijinComboLv" },
    [3] = { "get_AuraLevel" },
    [8] = { "get_Mode", "get_IsSwordAwaken", "get_SwordAwakeTimer", "get_IsAxeEnhanced", "get_AxeEnhancedTimer" },
    [9] = { "get_Mode", "get_IsSwordEnhanced", "get_SwordEnhancedTimer", "get_IsShieldEnhanced", "get_ShieldEnhancedTimer",
        "get_IsAxeEnhanced", "get_AxeEnhancedTimer", "get_SwordBinNum", "get_SwordEnergyState" },
    [10] = { "get_IsRed", "get_IsWhite", "get_IsOrange", "get_IsTrippleUp" },
    [12] = { "get_IsEnergyMode", "get_SnipeAmmo", "_EnergyPartsState", "_PrevEnergyPartsState", "get_EnergyParts" },
}

local lastWeaponType = nil
local lastState = nil

local function typeNameOf(object)
    local ok, name = pcall(function() return object:get_type_definition():get_name() end)
    if ok and type(name) == "string" then return name end
    return "?"
end

function WeaponStateProbe.formatValue(value)
    local kind = type(value)
    if kind == "boolean" then return tostring(value) end
    if kind == "nil" then return "nil" end
    if kind == "number" then
        if math.type(value) == "integer" then return tostring(value) end
        return string.format("%.1f", value)
    end
    if kind == "string" then return value end
    local ok, inner = pcall(function() return value:get_Value() end)
    if ok and type(inner) == "number" then return WeaponStateProbe.formatValue(inner) end
    return typeNameOf(value)
end

local function readMember(handling, name)
    local ok, value = pcall(function()
        local member = handling[name]
        if type(member) == "function" then return member(handling) end
        return member
    end)
    if not ok then return "err" end
    return WeaponStateProbe.formatValue(value)
end

function WeaponStateProbe.serialize(handling, names)
    local parts = {}
    for index, name in ipairs(names) do
        local label = name:gsub("^get_", "")
        parts[index] = label .. "=" .. readMember(handling, name)
    end
    return table.concat(parts, " ")
end

function WeaponStateProbe.update()
    if not Log.isDeveloperMode() then return end
    local hunter = Game.masterHunter()
    if not hunter then return end
    local ok, weaponType, handling = pcall(function()
        return hunter:get_WeaponType(), hunter:get_WeaponHandling()
    end)
    if not ok or handling == nil then return end
    if weaponType ~= lastWeaponType then
        lastWeaponType = weaponType
        lastState = nil
        Log.trace("wpstate class=" .. typeNameOf(handling) .. " wp=" .. tostring(weaponType))
    end
    local names = WeaponStateProbe.GETTERS[weaponType]
    if not names then return end
    local line = WeaponStateProbe.serialize(handling, names)
    if line == lastState then return end
    lastState = line
    Log.trace("wpstate wp=" .. tostring(weaponType) .. " " .. line)
end

function WeaponStateProbe.reset()
    lastWeaponType = nil
    lastState = nil
end

return WeaponStateProbe
