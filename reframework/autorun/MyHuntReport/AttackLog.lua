local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local AttackLog = {}

AttackLog.FIELDS = {
    { "weapon", "get_WeaponAttackPower()" },
    { "current", "get_CurrentAttackPower()" },
    { "add", "get_CurrentAttackAdd()" },
    { "rate", "get_CurrentAttackRate()" },
}

local previous = {}

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

function AttackLog.update()
    if not Log.isDeveloperMode() then
        if next(previous) ~= nil then previous = {} end
        return
    end
    local power = attackPower()
    local snapshot = {}
    for _, field in ipairs(AttackLog.FIELDS) do
        snapshot[field[1]] = readGetter(power, field[2])
    end
    local now = nil
    for _, field in ipairs(AttackLog.FIELDS) do
        local name = field[1]
        if differs(snapshot[name], previous[name]) then
            now = now or tostring(Game.uptime())
            Log.trace("atk change " .. name .. " " .. tostring(previous[name]) .. " -> " .. tostring(snapshot[name]) .. " at " .. now)
        end
    end
    previous = snapshot
end

function AttackLog.resetForTests()
    previous = {}
end

return AttackLog
