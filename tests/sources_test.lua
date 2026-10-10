local Sources = require("MyHuntReport.Sources")
local T = {}

function T.classifiesEveryApprovedSource()
    assert(Sources.classify({ path = "kinsect", weaponType = -1 }) == "kinsect")
    assert(Sources.weaponTypeFor("kinsect", -1) == 10)
    assert(Sources.weaponTypeFor("phial", 8) == 8)
    assert(Sources.weaponTypeFor("phial", 9) == 9)
    assert(Sources.weaponTypeFor(nil, nil) == nil)
    local cases = {
        { 8, "Wp08Shell", nil, "phial" },
        { 8, "Wp08Shell_Child", 2609706798, "phial" },
        { 9, "Wp09Shell", 707418733, "swordBoost" },
        { 9, "Wp09Shell_Child", 494429526, "phial" },
        { 7, "Wp07Shell", 1853117018, "shelling" },
        { 7, "Wp07Shell", 2642542453, "shelling" },
        { 7, "Wp07Shell", 543483591, "shelling" },
        { 7, "Wp07Shell", 2914767066, "wyrmstake" },
        { 7, "Wp07Shell", 2615429298, "wyrmstake" },
        { 7, "Wp07Shell", 2449957206, "wyrmstake" },
        { 5, "Wp05Shell", 2691864323, "echoBubble" },
    }
    for _, case in ipairs(cases) do
        assert(Sources.classify({ shell = true, weaponType = case[1], objectName = case[2], rootHash = case[3] }) == case[4], case[4])
    end
end

function T.excludesUnapprovedRootsAndWeapons()
    for _, hash in ipairs({ 2642246429, 3040920022 }) do
        assert(Sources.classify({ shell = true, weaponType = 7, rootHash = hash }) == nil)
    end
    for _, hash in ipairs({ 4055548668, 2607229914, 824610146, 3655263309, 402912253 }) do
        assert(Sources.classify({ shell = true, weaponType = 5, rootHash = hash }) == nil)
    end
    for _, weaponType in ipairs({ -1, 0, 3, 5, 7, 9, 10, 11, 12, 13 }) do
        assert(Sources.classify({ shell = true, weaponType = weaponType, objectName = "Wp08Shell", rootHash = 2609706798 }) == nil)
    end
end

function T.weaponObjectsAndBareKeysNeverClassify()
    for _, case in ipairs({ { 7, "it0700_0027_0", 543483591 }, { 8, "it0800_0023_0", 2609706798 },
        { 9, "it0900_0025_0", 707418733 }, { 5, "it0500_test", 2691864323 } }) do
        assert(Sources.classify({ weaponType = case[1], objectName = case[2], rootHash = case[3],
            resource = 0, index = 6, shell = false }) == nil)
    end
    for _, name in ipairs({ "prefixWp08Shell", "wp08Shell", "it0800_0023_0" }) do
        assert(Sources.classify({ shell = true, weaponType = 8, objectName = name }) == nil)
    end
    assert(Sources.classify({ weaponType = 9, objectName = "Wp09Shell", rootHash = 707418733 }) == nil)
end

function T.missingFieldsDoNotInventSources()
    assert(Sources.classify(nil) == nil)
    assert(Sources.classify({}) == nil)
    for _, weaponType in ipairs({ 5, 7, 9 }) do
        assert(Sources.classify({ shell = true, weaponType = weaponType, objectName = "Wp09Shell" }) == nil)
    end
    assert(Sources.classify({ shell = true, objectName = "Wp08Shell" }) == nil)
    assert(Sources.classify({ shell = true, weaponType = 8 }) == nil)
    assert(Sources.classify({ shell = true, weaponType = 9, objectName = "Wp09Shell", rootHash = "?" }) == nil)
end

function T.keyOrderIsStable()
    assert(table.concat(Sources.KEYS, ",") == "kinsect,phial,swordBoost,shelling,wyrmstake,echoBubble")
end

return T
