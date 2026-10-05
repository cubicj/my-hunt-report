local HistoryFilter = {}

local VARIANTS = { "normal", "tempered", "arch", "frenzied" }
local AXES = { "weapons", "levels", "species", "variants" }

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
    local weapons, levels = selection.weapons or {}, selection.levels or {}
    local species, variants = selection.species or {}, selection.variants or {}
    if next(weapons) then
        local found = false
        for _, weaponType in ipairs(weaponTypes(quest)) do
            if weapons[weaponType] then found = true break end
        end
        if not found then return false end
    end
    if next(levels) and (type(quest.level) ~= "number" or quest.level <= 0 or not levels[quest.level]) then return false end
    if next(species) or next(variants) then
        for _, monster in ipairs(entry.monsters or {}) do
            local label = monster.label
            if type(label) == "table" and type(label.emId) == "number" and (not next(species) or species[label.emId]) then
                if not next(variants) then return true end
                for variant in pairs(variants) do
                    if hasVariant(label, variant) then return true end
                end
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
    for _, axis in ipairs(AXES) do
        for value in pairs(selection[axis] or {}) do
            if not contains(options[axis], value) then
                selection[axis][value] = nil
                changed = true
            end
        end
    end
    return changed
end

function HistoryFilter.isActive(selection)
    for _, axis in ipairs(AXES) do
        if next(selection[axis] or {}) then return true end
    end
    return false
end

function HistoryFilter.clear(selection, axis)
    local changed = false
    for _, name in ipairs(AXES) do
        if axis == nil or axis == name then
            for value in pairs(selection[name] or {}) do
                selection[name][value] = nil
                changed = true
            end
        end
    end
    return changed
end

return HistoryFilter
