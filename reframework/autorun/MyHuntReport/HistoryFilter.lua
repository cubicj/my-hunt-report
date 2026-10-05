local HistoryFilter = {}

local VARIANTS = { "normal", "tempered", "arch", "frenzied" }
local AXES = { weapon = "weapons", level = "levels", emId = "species", variant = "variants" }

local function weaponTypes(quest)
    local types = {}
    for _, weapon in ipairs(type(quest.weapons) == "table" and quest.weapons or {}) do
        if type(weapon) == "table" and type(weapon.type) == "number" then types[#types + 1] = weapon.type end
    end
    if #types == 0 and type(quest.weapon) == "table" and type(quest.weapon.type) == "number" then
        types[1] = quest.weapon.type
    end
    return types
end

local function hasVariant(label, variant)
    local legendaryId, roleId = label.legendaryId or 0, label.roleId or 0
    if variant == "arch" then return legendaryId == 2 end
    if variant == "tempered" then return legendaryId == 1 end
    if variant == "frenzied" then return roleId == 3 end
    return variant == "normal" and legendaryId ~= 1 and legendaryId ~= 2 and roleId ~= 3
end

local function contains(values, value)
    for _, candidate in ipairs(values) do
        if candidate == value then return true end
    end
    return false
end

function HistoryFilter.options(entries)
    local options = { weapons = {}, levels = {}, species = {}, variants = {} }
    local seen = { weapons = {}, levels = {}, species = {}, variants = {} }
    local function add(axis, value)
        if seen[axis][value] then return end
        seen[axis][value] = true
        options[axis][#options[axis] + 1] = value
    end
    for _, entry in ipairs(entries or {}) do
        local quest = entry.quest or {}
        for _, weaponType in ipairs(weaponTypes(quest)) do add("weapons", weaponType) end
        if type(quest.level) == "number" and quest.level > 0 then add("levels", quest.level) end
        for _, monster in ipairs(entry.monsters or {}) do
            local label = monster.label
            if type(label) == "table" and type(label.emId) == "number" then
                add("species", label.emId)
                for _, variant in ipairs(VARIANTS) do
                    if hasVariant(label, variant) then seen.variants[variant] = true end
                end
            end
        end
    end
    table.sort(options.weapons)
    table.sort(options.levels, function(a, b) return a > b end)
    for _, variant in ipairs(VARIANTS) do
        if seen.variants[variant] then options.variants[#options.variants + 1] = variant end
    end
    return options
end

function HistoryFilter.matches(entry, selection)
    local quest = entry.quest or {}
    if selection.weapon ~= nil and not contains(weaponTypes(quest), selection.weapon) then return false end
    if selection.level ~= nil and (type(quest.level) ~= "number" or quest.level <= 0 or quest.level ~= selection.level) then
        return false
    end
    if selection.emId ~= nil or selection.variant ~= nil then
        for _, monster in ipairs(entry.monsters or {}) do
            local label = monster.label
            if type(label) == "table" and type(label.emId) == "number"
                and (selection.emId == nil or label.emId == selection.emId)
                and (selection.variant == nil or hasVariant(label, selection.variant)) then
                return true
            end
        end
        return false
    end
    return true
end

function HistoryFilter.apply(entries, selection)
    local filtered = {}
    for _, entry in ipairs(entries or {}) do
        if HistoryFilter.matches(entry, selection) then filtered[#filtered + 1] = entry end
    end
    return filtered
end

function HistoryFilter.prune(selection, options)
    local changed = false
    for axis, name in pairs(AXES) do
        if selection[axis] ~= nil and not contains(options[name], selection[axis]) then
            selection[axis] = nil
            changed = true
        end
    end
    return changed
end

return HistoryFilter
