local HistoryFilter = require("MyHuntReport.HistoryFilter")

local T = {}

local function selection(weapons, levels, species, variants)
    local result = { weapons = {}, levels = {}, species = {}, variants = {} }
    for index, axis in ipairs({ "weapons", "levels", "species", "variants" }) do
        for _, value in ipairs(({ weapons or {}, levels or {}, species or {}, variants or {} })[index]) do result[axis][value] = true end
    end
    return result
end

local function entry(weapons, level, labels)
    local monsters = {}
    for _, label in ipairs(labels or {}) do monsters[#monsters + 1] = { label = label } end
    return { quest = { weapons = weapons, level = level }, monsters = monsters }
end

function T.optionsDeduplicateAndOrderWeaponsLevelsAndVariants()
    local entries = {
        entry({ { type = 10 }, { type = 3 }, { type = 10 } }, 5, {
            { emId = 32, legendaryId = 2 }, { emId = 33, roleId = 3, legendaryId = 1 },
        }),
        entry({ { type = 0 }, { type = 3 } }, 10, { { emId = 32 }, { emId = 34 } }),
        entry({ { type = 10 } }, 5, { { emId = 34, legendaryId = 1 } }),
    }
    local options = HistoryFilter.options(entries)
    assert(table.concat(options.weapons, ",") == "0,3,10")
    assert(table.concat(options.levels, ",") == "10,5")
    assert(#options.species == 3)
    table.sort(options.species)
    assert(table.concat(options.species, ",") == "32,33,34")
    assert(table.concat(options.variants, ",") == "normal,tempered,arch,frenzied")
end

function T.optionsOnlyIncludePresentVariants()
    local options = HistoryFilter.options({ entry({}, 1, { { emId = 32, legendaryId = 2 } }) })
    assert(#options.weapons == 0 and #options.species == 1)
    assert(table.concat(options.variants, ",") == "arch")
end

function T.weaponContainsMatchesEveryUsedWeapon()
    local record = entry({ { type = 10 }, { type = 3 } }, 5)
    assert(HistoryFilter.matches(record, selection({ 10 })))
    assert(HistoryFilter.matches(record, selection({ 3 })))
    assert(not HistoryFilter.matches(record, selection({ 0 })))
end

function T.weaponFallsBackOnlyWhenTheListHasNoNumericType()
    for _, weapons in ipairs({ false, {}, { { name = "unknown" }, { type = "10" } } }) do
        local record = entry(weapons or nil, 5)
        record.quest.weapon = { type = 0 }
        assert(HistoryFilter.matches(record, selection({ 0 })))
        assert(table.concat(HistoryFilter.options({ record }).weapons, ",") == "0")
    end
    local record = entry({ { type = 10 } }, 5)
    record.quest.weapon = { type = 3 }
    assert(not HistoryFilter.matches(record, selection({ 3 })))
    assert(table.concat(HistoryFilter.options({ record }).weapons, ",") == "10")
end

function T.monsterContainsMatchesEverySpecies()
    local record = entry({}, 5, { { emId = 32 }, { emId = 33, legendaryId = 2 } })
    assert(HistoryFilter.matches(record, selection(nil, nil, { 32 })))
    assert(HistoryFilter.matches(record, selection(nil, nil, { 33 })))
    assert(HistoryFilter.matches(record, selection(nil, nil, nil, { "arch" })))
    assert(not HistoryFilter.matches(record, selection(nil, nil, { 34 })))
end

function T.axesCombineWithAnd()
    local record = entry({ { type = 10 } }, 5, { { emId = 32, legendaryId = 1 } })
    local chosen = selection({ 3, 10 }, { 5, 10 }, { 32, 33 }, { "normal", "tempered" })
    assert(HistoryFilter.matches(record, chosen))
    for axis, wrong in pairs({ weapons = { [0] = true }, levels = { [1] = true }, species = { [34] = true }, variants = { arch = true } }) do
        local original = chosen[axis]
        chosen[axis] = wrong
        assert(not HistoryFilter.matches(record, chosen), axis)
        chosen[axis] = original
    end
end

function T.multipleValuesInsideEveryAxisUseOr()
    local records = {
        entry({ { type = 3 } }, 5, { { emId = 32 } }),
        entry({ { type = 10 } }, 10, { { emId = 33, legendaryId = 2 } }),
        entry({ { type = 0 } }, 1, { { emId = 34, roleId = 3 } }),
    }
    for _, chosen in ipairs({
        selection({ 3, 10 }), selection(nil, { 5, 10 }),
        selection(nil, nil, { 32, 33 }), selection(nil, nil, nil, { "normal", "arch" }),
    }) do
        local result = HistoryFilter.apply(records, chosen)
        assert(#result == 2 and result[1] == records[1] and result[2] == records[2])
    end
end

function T.multipleSpeciesAndVariantsStillRequireOneMatchingMonster()
    local record = entry({ { type = 3 }, { type = 10 } }, 5, { { emId = 32 }, { emId = 33, legendaryId = 2 } })
    assert(not HistoryFilter.matches(record, selection({ 0, 10 }, nil, { 32, 34 }, { "arch", "tempered" })))
    assert(HistoryFilter.matches(record, selection({ 0, 10 }, nil, { 32, 33 }, { "arch", "tempered" })))
    assert(HistoryFilter.matches(record, selection(nil, nil, { 32, 34 }, { "normal", "tempered" })))
end

function T.speciesAndVariantMustMatchTheSameMonster()
    local record = entry({}, 5, { { emId = 32 }, { emId = 33, legendaryId = 2 } })
    assert(not HistoryFilter.matches(record, selection(nil, nil, { 32 }, { "arch" })))
    assert(HistoryFilter.matches(record, selection(nil, nil, { 33 }, { "arch" })))
    assert(HistoryFilter.matches(record, selection(nil, nil, { 32 }, { "normal" })))
    assert(not HistoryFilter.matches(record, selection(nil, nil, { 33 }, { "normal" })))
end

function T.frenziedTemperedMatchesBothVariantsButNotNormalOrArch()
    local record = entry({}, 5, { { emId = 32, roleId = 3, legendaryId = 1 } })
    assert(HistoryFilter.matches(record, selection(nil, nil, nil, { "tempered" })))
    assert(HistoryFilter.matches(record, selection(nil, nil, nil, { "frenzied" })))
    assert(not HistoryFilter.matches(record, selection(nil, nil, nil, { "normal" })))
    assert(not HistoryFilter.matches(record, selection(nil, nil, nil, { "arch" })))
    assert(table.concat(HistoryFilter.options({ record }).variants, ",") == "tempered,frenzied")
end

function T.archAndFrenziedAlsoRemainIndependent()
    local record = entry({}, 5, { { emId = 32, roleId = 3, legendaryId = 2 } })
    assert(HistoryFilter.matches(record, selection(nil, nil, nil, { "arch" })))
    assert(HistoryFilter.matches(record, selection(nil, nil, nil, { "frenzied" })))
    assert(not HistoryFilter.matches(record, selection(nil, nil, nil, { "tempered" })))
    assert(table.concat(HistoryFilter.options({ record }).variants, ",") == "arch,frenzied")
end

function T.missingVariantFieldsCountAsNormal()
    local record = entry({}, 5, { { emId = 32 } })
    assert(HistoryFilter.matches(record, selection(nil, nil, { 32 }, { "normal" })))
    assert(not HistoryFilter.matches(record, selection(nil, nil, nil, { "frenzied" })))
    assert(table.concat(HistoryFilter.options({ record }).variants, ",") == "normal")
end

function T.missingDataMatchesOnlyInactiveAxes()
    local records = {
        {},
        { quest = {}, monsters = { { id = 32, name = "legacy" } } },
        entry({ { type = "10" } }, "5", { { legendaryId = 2 }, { emId = "32" } }),
        entry({}, 0),
        entry({}, -1),
    }
    for _, record in ipairs(records) do
        assert(HistoryFilter.matches(record, {}))
        for _, selection in ipairs({ selection({ 10 }), selection(nil, { 5 }), selection(nil, nil, { 32 }), selection(nil, nil, nil, { "normal" }), selection(nil, nil, nil, { "arch" }) }) do
            assert(not HistoryFilter.matches(record, selection))
        end
    end
    local options = HistoryFilter.options(records)
    for _, values in pairs(options) do assert(#values == 0) end
    assert(not HistoryFilter.matches(records[4], selection(nil, { 0 })))
end

function T.applyPreservesOrderAndRecordIdentity()
    local first = entry({ { type = 10 } }, 5)
    local second = entry({ { type = 3 } }, 5)
    local third = entry({ { type = 10 } }, 10)
    local records = { first, second, third }
    local filtered = HistoryFilter.apply(records, selection({ 10 }))
    assert(#filtered == 2 and filtered[1] == first and filtered[2] == third)
    assert(#records == 3 and records[2] == second)
    assert(#HistoryFilter.apply(records, selection({ 0 })) == 0)
    assert(#HistoryFilter.apply(records, {}) == 3)
end

function T.pruneClearsOnlyValuesWithoutOptions()
    local chosen = selection({ 0, 10 }, { 5, 10 }, { 32, 33 }, { "normal", "arch" })
    local options = { weapons = { 0 }, levels = { 10 }, species = { 32 }, variants = { "normal" } }
    assert(HistoryFilter.prune(chosen, options))
    assert(chosen.weapons[0] and not chosen.weapons[10])
    assert(chosen.levels[10] and not chosen.levels[5])
    assert(chosen.species[32] and not chosen.species[33])
    assert(chosen.variants.normal and not chosen.variants.arch)
    assert(not HistoryFilter.prune(chosen, options))
    assert(HistoryFilter.prune(chosen, HistoryFilter.options({})))
    assert(not HistoryFilter.isActive(chosen))
end

function T.isActiveAndClearKeepTheSelectionAndSetsOwnedByTheCaller()
    local chosen = selection()
    assert(not HistoryFilter.isActive(chosen) and not HistoryFilter.clear(chosen))
    for _, axis in ipairs({ "weapons", "levels", "species", "variants" }) do
        chosen[axis][1] = true
        assert(HistoryFilter.isActive(chosen))
        assert(HistoryFilter.clear(chosen, axis))
        assert(not HistoryFilter.isActive(chosen))
    end
    chosen = selection({ 3, 10 }, { 5 }, { 32 }, { "normal", "tempered" })
    local weapons, levels = chosen.weapons, chosen.levels
    assert(HistoryFilter.clear(chosen, "weapons"))
    assert(chosen.weapons == weapons and next(weapons) == nil)
    assert(chosen.levels == levels and levels[5] and chosen.species[32] and chosen.variants.tempered)
    assert(HistoryFilter.isActive(chosen))
    assert(HistoryFilter.clear(chosen))
    assert(not HistoryFilter.isActive(chosen) and not HistoryFilter.clear(chosen))
    assert(chosen.weapons == weapons and chosen.levels == levels)
end

return T
