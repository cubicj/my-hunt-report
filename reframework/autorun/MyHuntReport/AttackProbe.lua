local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local AttackProbe = {}

AttackProbe.FIELDS = {
    { "weapon", "get_WeaponAttackPower()" },
    { "current", "get_CurrentAttackPower()" },
    { "add", "get_CurrentAttackAdd()" },
    { "rate", "get_CurrentAttackRate()" },
}

AttackProbe.ON_HIT = { "app.cHunterAttackPower",
    "calcOnHitAttackPower(app.HitInfo, System.Single, app.HunterCharacter, System.Boolean, System.Boolean, System.Boolean)" }
AttackProbe.HIT_INFO = { "app.cEnemyStockDamage", "stockDamageDetail(app.HitInfo)" }
AttackProbe.CALC = { "app.cEnemyStockDamage",
    "calcStockDamage(app.cEnemyStockDamage.cCalcDamage, app.cEnemyStockDamage.cPreCalcDamage, app.cEnemyStockDamage.cDamageRate, System.Boolean)" }

local UP_TIMER = "get_AttackUpTimer()"
local STORAGE_KEY = "MyHuntReport.AttackProbe.onHit"

local installed = false
local previous = {}
local lastOnHit = nil
local onHitCalls = 0
local pendingHit = nil

local function trace(text)
    Log.trace("atk " .. text)
end

local function enabled()
    if Log.isDeveloperMode() then return true end
    lastOnHit = nil
    onHitCalls = 0
    pendingHit = nil
    return false
end

local function differs(a, b)
    if a ~= a and b ~= b then return false end
    return a ~= b
end

local function attackPower()
    local hunter = Game.masterHunter()
    if not hunter then return nil end
    local ok, power = pcall(function() return hunter:get_HunterStatus():get_AttackPower() end)
    if ok then return power end
    return nil
end

local function readGetter(power, signature)
    if not power then return "?" end
    local ok, value = pcall(function() return power:call(signature) end)
    if ok and value ~= nil then return value end
    return "?"
end

local function readField(object, name)
    local ok, value = pcall(function() return object[name] end)
    if ok and value ~= nil then return value end
    return "?"
end

function AttackProbe.snapshot()
    local power = attackPower()
    local snapshot = {}
    for _, field in ipairs(AttackProbe.FIELDS) do
        snapshot[field[1]] = readGetter(power, field[2])
    end
    return snapshot, power
end

local function derefObject(pointer)
    local ok, object = pcall(function()
        local slot = sdk.to_valuetype(pointer, "System.UInt64")
        local address = slot and slot:get_field("m_value") or nil
        if not address or address == 0 then return nil end
        return sdk.to_managed_object(address)
    end)
    if ok then return object end
    return nil
end

local function boolArg(value)
    local ok, flag = pcall(function() return (sdk.to_int64(value) & 0xFF) ~= 0 end)
    if ok then return flag and "T" or "F" end
    return "?"
end

local function isMasterHunter(pointer)
    local ok, same = pcall(function()
        local hunter = sdk.to_managed_object(pointer)
        local master = Game.masterHunter()
        return hunter ~= nil and master ~= nil and hunter:get_address() == master:get_address()
    end)
    return ok and same == true
end

local function beforeOnHit(args)
    if not enabled() then return end
    local okBase, base = pcall(sdk.to_float, args[4])
    local okHit, hitAddress = pcall(sdk.to_int64, args[3])
    thread.get_hook_storage()[STORAGE_KEY] = {
        master = isMasterHunter(args[5]),
        base = okBase and base or "?",
        flags = boolArg(args[6]) .. boolArg(args[7]) .. boolArg(args[8]),
        hit = okHit and hitAddress or nil,
    }
end

local function afterOnHit(retval)
    if not enabled() then return end
    local storage = thread.get_hook_storage()
    local call = storage[STORAGE_KEY]
    storage[STORAGE_KEY] = nil
    if not call or not call.master then return end
    local ok, value = pcall(sdk.to_float, retval)
    lastOnHit = { value = ok and value or "?", base = call.base, flags = call.flags, hit = call.hit, at = Game.uptime() }
    onHitCalls = onHitCalls + 1
end

local function captureHit(args)
    if not enabled() then return end
    local ok, hit = pcall(function()
        local hitInfo = sdk.to_managed_object(args[3])
        if not hitInfo or not Game.isMasterGameObject(hitInfo:getActualAttackOwner()) then return nil end
        local attackData = hitInfo:get_AttackData()
        if not attackData then return nil end
        return {
            address = sdk.to_int64(args[3]),
            mv = readField(attackData, "_OriginalAttackAdjust"),
            crit = readField(attackData, "_CriticaType"),
            nocrit = readField(attackData, "_IsNoCritical"),
        }
    end)
    pendingHit = ok and hit or nil
end

local function logHit(args)
    if not enabled() then return end
    local hit = pendingHit
    if not hit then return end
    pendingHit = nil
    local preCalc = derefObject(args[4])
    local snapshot, power = AttackProbe.snapshot()
    local onHit = lastOnHit or {}
    local now = Game.uptime()
    local age, same = nil, nil
    if lastOnHit then
        age = now - lastOnHit.at
        same = (lastOnHit.hit ~= nil and lastOnHit.hit == hit.address) and "T" or "F"
    end
    local parts = {
        "hit at " .. tostring(now),
        "mv=" .. tostring(hit.mv),
        "crit=" .. tostring(hit.crit),
        "nocrit=" .. tostring(hit.nocrit),
        "action=" .. tostring(preCalc and readField(preCalc, "ActionType") or "?"),
        "preAttack=" .. tostring(preCalc and readField(preCalc, "Attack") or "?"),
        "fix=" .. tostring(preCalc and readField(preCalc, "FixAttack") or "?"),
        "abs=" .. tostring(preCalc and readField(preCalc, "AbsoluteAttack") or "?"),
    }
    for _, field in ipairs(AttackProbe.FIELDS) do
        parts[#parts + 1] = field[1] .. "=" .. tostring(snapshot[field[1]])
    end
    parts[#parts + 1] = "upTimer=" .. tostring(readGetter(power, UP_TIMER))
    parts[#parts + 1] = "onhit=" .. tostring(onHit.value)
    parts[#parts + 1] = "onhitBase=" .. tostring(onHit.base)
    parts[#parts + 1] = "onhitFlags=" .. tostring(onHit.flags)
    parts[#parts + 1] = "onhitCalls=" .. tostring(onHitCalls)
    parts[#parts + 1] = "onhitAge=" .. tostring(age)
    parts[#parts + 1] = "onhitSame=" .. tostring(same)
    trace(table.concat(parts, " "))
    lastOnHit = nil
    onHitCalls = 0
end

function AttackProbe.install()
    if installed then return end
    installed = true
    Game.hook(AttackProbe.ON_HIT[1], AttackProbe.ON_HIT[2], beforeOnHit, afterOnHit)
    Game.hook(AttackProbe.HIT_INFO[1], AttackProbe.HIT_INFO[2], captureHit)
    Game.hook(AttackProbe.CALC[1], AttackProbe.CALC[2], logHit)
end

function AttackProbe.update()
    if not enabled() then return end
    local snapshot = AttackProbe.snapshot()
    local now = nil
    for _, field in ipairs(AttackProbe.FIELDS) do
        local name = field[1]
        if differs(snapshot[name], previous[name]) then
            now = now or tostring(Game.uptime())
            trace("change " .. name .. " " .. tostring(previous[name]) .. " -> " .. tostring(snapshot[name]) .. " at " .. now)
        end
    end
    previous = snapshot
end

function AttackProbe.resetForTests()
    installed = false
    previous = {}
    lastOnHit = nil
    onHitCalls = 0
    pendingHit = nil
end

return AttackProbe
