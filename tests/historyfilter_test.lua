local HistoryFilter = require("MyHuntReport.HistoryFilter")

local T = {}

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
    assert(HistoryFilter.matches(record, { weapon = 10 }))
    assert(HistoryFilter.matches(record, { weapon = 3 }))
    assert(not HistoryFilter.matches(record, { weapon = 0 }))
end

function T.weaponFallsBackOnlyWhenTheListHasNoNumericType()
    for _, weapons in ipairs({ false, {}, { { name = "unknown" }, { type = "10" } } }) do
        local record = entry(weapons or nil, 5)
        record.quest.weapon = { type = 0 }
        assert(HistoryFilter.matches(record, { weapon = 0 }))
        assert(table.concat(HistoryFilter.options({ record }).weapons, ",") == "0")
    end
    local record = entry({ { type = 10 } }, 5)
    record.quest.weapon = { type = 3 }
    assert(not HistoryFilter.matches(record, { weapon = 3 }))
    assert(table.concat(HistoryFilter.options({ record }).weapons, ",") == "10")
end

function T.monsterContainsMatchesEverySpecies()
    local record = entry({}, 5, { { emId = 32 }, { emId = 33, legendaryId = 2 } })
    assert(HistoryFilter.matches(record, { emId = 32 }))
    assert(HistoryFilter.matches(record, { emId = 33 }))
    assert(HistoryFilter.matches(record, { variant = "arch" }))
    assert(not HistoryFilter.matches(record, { emId = 34 }))
end

function T.axesCombineWithAnd()
    local record = entry({ { type = 10 } }, 5, { { emId = 32, legendaryId = 1 } })
    local selection = { weapon = 10, level = 5, emId = 32, variant = "tempered" }
    assert(HistoryFilter.matches(record, selection))
    for axis, wrong in pairs({ weapon = 3, level = 10, emId = 33, variant = "arch" }) do
        local original = selection[axis]
        selection[axis] = wrong
        assert(not HistoryFilter.matches(record, selection), axis)
        selection[axis] = original
    end
end

function T.speciesAndVariantMustMatchTheSameMonster()
    local record = entry({}, 5, { { emId = 32 }, { emId = 33, legendaryId = 2 } })
    assert(not HistoryFilter.matches(record, { emId = 32, variant = "arch" }))
    assert(HistoryFilter.matches(record, { emId = 33, variant = "arch" }))
    assert(HistoryFilter.matches(record, { emId = 32, variant = "normal" }))
    assert(not HistoryFilter.matches(record, { emId = 33, variant = "normal" }))
end

function T.frenziedTemperedMatchesBothVariantsButNotNormalOrArch()
    local record = entry({}, 5, { { emId = 32, roleId = 3, legendaryId = 1 } })
    assert(HistoryFilter.matches(record, { variant = "tempered" }))
    assert(HistoryFilter.matches(record, { variant = "frenzied" }))
    assert(not HistoryFilter.matches(record, { variant = "normal" }))
    assert(not HistoryFilter.matches(record, { variant = "arch" }))
    assert(table.concat(HistoryFilter.options({ record }).variants, ",") == "tempered,frenzied")
end

function T.archAndFrenziedAlsoRemainIndependent()
    local record = entry({}, 5, { { emId = 32, roleId = 3, legendaryId = 2 } })
    assert(HistoryFilter.matches(record, { variant = "arch" }))
    assert(HistoryFilter.matches(record, { variant = "frenzied" }))
    assert(not HistoryFilter.matches(record, { variant = "tempered" }))
    assert(table.concat(HistoryFilter.options({ record }).variants, ",") == "arch,frenzied")
end

function T.missingVariantFieldsCountAsNormal()
    local record = entry({}, 5, { { emId = 32 } })
    assert(HistoryFilter.matches(record, { emId = 32, variant = "normal" }))
    assert(not HistoryFilter.matches(record, { variant = "frenzied" }))
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
        for _, selection in ipairs({ { weapon = 10 }, { level = 5 }, { emId = 32 }, { variant = "normal" }, { variant = "arch" } }) do
            assert(not HistoryFilter.matches(record, selection))
        end
    end
    local options = HistoryFilter.options(records)
    for _, values in pairs(options) do assert(#values == 0) end
    assert(not HistoryFilter.matches(records[4], { level = 0 }))
end

function T.applyPreservesOrderAndRecordIdentity()
    local first = entry({ { type = 10 } }, 5)
    local second = entry({ { type = 3 } }, 5)
    local third = entry({ { type = 10 } }, 10)
    local records = { first, second, third }
    local filtered = HistoryFilter.apply(records, { weapon = 10 })
    assert(#filtered == 2 and filtered[1] == first and filtered[2] == third)
    assert(#records == 3 and records[2] == second)
    assert(#HistoryFilter.apply(records, { weapon = 0 }) == 0)
    assert(#HistoryFilter.apply(records, {}) == 3)
end

function T.pruneClearsOnlyValuesWithoutOptions()
    local selection = { weapon = 10, level = 5, emId = 32, variant = "arch" }
    local options = { weapons = { 0, 10 }, levels = { 10 }, species = { 32 }, variants = { "normal" } }
    assert(HistoryFilter.prune(selection, options))
    assert(selection.weapon == 10 and selection.emId == 32)
    assert(selection.level == nil and selection.variant == nil)
    assert(not HistoryFilter.prune(selection, options))
    assert(HistoryFilter.prune(selection, HistoryFilter.options({})))
    assert(next(selection) == nil)
end

return T
