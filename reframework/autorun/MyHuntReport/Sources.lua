local Sources = {}

Sources.KEYS = { "kinsect", "phial", "swordBoost", "shelling", "wyrmstake", "echoBubble" }

local SHELLING_ROOTS = { [1853117018] = true, [2642542453] = true, [543483591] = true }
local WYRMSTAKE_ROOTS = { [2914767066] = true, [2615429298] = true, [2449957206] = true }
local SWORD_BOOST_ROOT = 707418733
local ECHO_BUBBLE_ROOT = 2691864323

function Sources.classify(hit)
    if type(hit) ~= "table" then return nil end
    if hit.path == "kinsect" then return "kinsect" end
    if hit.shell ~= true then return nil end
    local weaponType, name, root = hit.weaponType, hit.objectName, hit.rootHash
    if weaponType == 8 and type(name) == "string" and name:find("^Wp08Shell") then return "phial" end
    if type(root) ~= "number" then return nil end
    if weaponType == 9 and type(name) == "string" and name:find("^Wp09Shell") then
        return root == SWORD_BOOST_ROOT and "swordBoost" or "phial"
    end
    if weaponType == 7 then
        if SHELLING_ROOTS[root] then return "shelling" end
        if WYRMSTAKE_ROOTS[root] then return "wyrmstake" end
    end
    if weaponType == 5 and root == ECHO_BUBBLE_ROOT then return "echoBubble" end
    return nil
end

function Sources.weaponTypeFor(source, weaponType)
    if source == "kinsect" then return 10 end
    return weaponType
end

return Sources
