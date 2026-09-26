local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local SkillExtras = {}

local TUPLE_TYPE = "System.ValueTuple`2<System.Single,System.Single>"

local pendingByKind = {}
local insideMaster = false
local installed = false

function SkillExtras.reset()
    pendingByKind = {}
    insideMaster = false
end

function SkillExtras.enter(isMaster)
    insideMaster = isMaster == true
end

function SkillExtras.leave()
    insideMaster = false
end

function SkillExtras.record(kind, damage)
    if not insideMaster then return false end
    local amount = tonumber(damage) or 0
    if not (amount > 0) then return false end
    pendingByKind[kind] = amount
    Log.debug("skill extra " .. tostring(kind) .. " value=" .. tostring(amount), "extra:" .. tostring(kind))
    return true
end

function SkillExtras.take()
    local list = {}
    for kind, damage in pairs(pendingByKind) do
        list[#list + 1] = { kind = kind, damage = damage }
    end
    pendingByKind = {}
    table.sort(list, function(a, b) return a.kind < b.kind end)
    return list
end

function SkillExtras.pendingCount()
    local count = 0
    for _ in pairs(pendingByKind) do count = count + 1 end
    return count
end

local function onCalcAdditional(args)
    local hunter = sdk.to_managed_object(args[5])
    local ok, gameObject = pcall(function() return hunter:get_GameObject() end)
    SkillExtras.enter(ok and Game.isMasterGameObject(gameObject))
end

local function onCalcAdditionalDone()
    SkillExtras.leave()
end

local function onRyukiExplosion(retval)
    local ok, tuple = pcall(sdk.to_valuetype, retval, TUPLE_TYPE)
    if not ok or not tuple then return end
    local okItem, value = pcall(function() return tuple.Item1 end)
    if okItem then SkillExtras.record("ryukiExplosion", value) end
end

function SkillExtras.install()
    if installed then return end
    installed = true
    Game.hook("app.cHunterSkill",
        "calcSkillAdditionalDamage(app.cEnemyContextHolder, app.HitInfo, app.HunterCharacter)",
        onCalcAdditional, onCalcAdditionalDone)
    Game.hook("app.cHunterSkill", "getSkillRyukiExplosionAddDamage(System.Boolean)", nil, onRyukiExplosion)
end

return SkillExtras
