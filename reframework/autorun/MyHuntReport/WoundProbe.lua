local Game = require("MyHuntReport.Game")
local Log = require("MyHuntReport.Log")

local WoundProbe = {}

WoundProbe.COUNTER_ORDER = { "external", "scar", "windows", "hpChanges", "hitsInWindow" }

local counters = {}
local owners = {}
local watches = {}
local installed = false

local function resetQuestState()
    for _, name in ipairs(WoundProbe.COUNTER_ORDER) do counters[name] = 0 end
    owners = {}
    watches = {}
end

resetQuestState()

function WoundProbe.formatValue(value)
    local kind = type(value)
    if kind == "nil" then return "nil" end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        if math.type(value) == "integer" then return tostring(value) end
        return string.format("%.1f", value)
    end
    return tostring(value)
end

local function readValue(read)
    local ok, value = pcall(read)
    if ok then return WoundProbe.formatValue(value) end
    return "?"
end

local function trace(text)
    Log.trace("wb " .. text)
end

local function bump(name)
    counters[name] = (counters[name] or 0) + 1
end

local function managedArg(args, index)
    local ok, object = pcall(function() return sdk.to_managed_object(args[index]) end)
    if ok then return object end
    return nil
end

function WoundProbe.summaryLine(values)
    local parts = {}
    for _, name in ipairs(WoundProbe.COUNTER_ORDER) do
        parts[#parts + 1] = name .. "=" .. tostring(values[name] or 0)
    end
    return "summary " .. table.concat(parts, " ")
end

function WoundProbe.counters()
    return counters
end

function WoundProbe.reset()
    resetQuestState()
end

function WoundProbe.owner(index)
    return owners[index]
end

function WoundProbe.watch(index)
    return watches[index]
end

local function onQuestStart()
    resetQuestState()
    if not Log.isDeveloperMode() then return end
    trace("state weapon=" .. readValue(function() return Game.masterHunter():get_WeaponType() end))
end

local function onResultPost()
    if not Log.isDeveloperMode() then return end
    trace(WoundProbe.summaryLine(counters))
end

local function onStockDamageDetailPre(args)
    if not Log.isDeveloperMode() then return end
    local hitInfo = managedArg(args, 3)
    if not hitInfo then return end
    local okOwner, owner = pcall(function() return hitInfo:get_DamageOwner() end)
    if not okOwner or owner == nil then return end
    local em = Game.enemyContext(owner)
    if not em then return end
    local okIndex, index = pcall(function() return em:get_UniqueIndex() end)
    if okIndex and index ~= nil then owners[index] = owner end
end

local function installFlowHooks()
    Game.hook("app.cQuestPlaying", "enter()", onQuestStart)
    Game.hook("app.cGUIQuestResultInfo", "execute()", nil, onResultPost)
end

local function installDamageHooks()
    Game.hook("app.cEnemyStockDamage", "stockDamageDetail(app.HitInfo)", onStockDamageDetailPre)
end

function WoundProbe.install()
    if installed then return end
    installed = true
    installFlowHooks()
    installDamageHooks()
end

return WoundProbe
